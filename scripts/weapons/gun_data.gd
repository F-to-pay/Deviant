class_name GunData
extends RefCounted
## Таблицы для генератора пушек. Сами данные — в data/*.json (игра) и Mods/<мод>/data/*.json:
##   archetypes.json  — основы (пистолет, дробовик...)        -> ARCH
##   makers.json      — марки                                    -> MAKERS
##   perks.json       — моды пушек (перки)                       -> MODS
##   legendaries.json — легендарки                               -> LEGENDARIES
##   rarities.json    — редкости (ровно 6, по порядку)           -> RARITIES
##   names.json       — прозвища, флейвор, имена врагов           -> NICKNAMES, ABSURD_FLAVOR (+ EnemyData)
## Правила слияния слоёв (игра, потом моды по алфавиту):
##   словари по id (archetypes, makers): та же запись — поля дописываются/заменяются, новая — добавляется;
##   списки по "id" (perks, legendaries): так же по полю id; {"remove": "id"} — убрать запись;
##   в словарях ключ "_remove": ["id", ...] — убрать записи; rarities — правка по индексу;
##   names.json: списки дописываются (или "replace": true — заменить целиком).
## Описание полей и операций — в Mods/README.md.

# Типы снарядов (дублируются в Projectiles).
const K_BULLET := 0
const K_PELLET := 1
const K_ROCKET := 2
const K_GRENADE := 3
const K_ORB := 4
const K_SHELL := 8     # мина: летит по дуге в точку и взрывается через SHELL_TIME
const SHELL_TIME := 1.0

const R_COMMON := 0
const R_UNCOMMON := 1
const R_RARE := 2
const R_EPIC := 3
const R_LEGENDARY := 4
const R_ABSURD := 5

## Патроны: общий запас на тип = RESERVE_MAGS базовых магазинов этого типа.
const RESERVE_MAGS := 4
const LOOT_GUN_LOADED := false   # новые пушки с пола/из сундуков приходят с пустым магазином

## Спецфишки легендарок, реализованные в коде (projectiles/player), которые что-то взрывают.
const EXPLOSIVE_SPECIALS := ["nuke10"]

static var ARCH: Dictionary = {}
static var MAKERS: Dictionary = {}
static var MODS: Array = []
static var LEGENDARIES: Array = []
static var RARITIES: Array = []
static var NICKNAMES: Array = []
static var ABSURD_FLAVOR: Array = []
static var _mod_index: Dictionary = {}   # id перка -> запись


static func ammo_cap(t: String) -> int:
	return base_mag(t) * RESERVE_MAGS


static func base_mag(t: String) -> int:
	return int(ARCH.get(t, {}).get("mag", 10))


static func ammo_color(t: String) -> Color:
	var c: Variant = ARCH.get(t, {}).get("ammo_color")
	return c if c is Color else Color(0.85, 0.85, 0.85)


## Название патронов (переведённое, строчная форма).
static func ammo_label(t: String) -> String:
	var a: Dictionary = ARCH.get(t, {})
	return I18n.word(str(a.get("ammo_name", a.get("name", t))), "lower")


static func perk(id: String) -> Dictionary:
	return _mod_index.get(id, {})


static func perk_has_tag(id: String, tag: String) -> bool:
	var tags: Variant = perk(id).get("tags", [])
	return tags is Array and (tags as Array).has(tag)


# --- Загрузка ---------------------------------------------------------------------

static func load_data() -> void:
	ARCH = _merge_dict("data/archetypes.json")
	MAKERS = _merge_dict("data/makers.json")
	MODS = _merge_list("data/perks.json")
	LEGENDARIES = _merge_list("data/legendaries.json")
	RARITIES = _merge_indexed("data/rarities.json")
	var names := merge_names()
	NICKNAMES = names.get("nicknames", [])
	ABSURD_FLAVOR = names.get("absurd_flavor", [])
	if NICKNAMES.is_empty():
		NICKNAMES = ["Nameless"]
	if ABSURD_FLAVOR.is_empty():
		ABSURD_FLAVOR = [""]
	_normalize()


## Числа, цвета, имена снарядов из JSON -> то, что ждёт код.
static func _normalize() -> void:
	for k in ARCH.keys():
		var a: Dictionary = ARCH[k]
		a["kind"] = GunOps.kind_id(a.get("kind", "bullet"))
		a["ammo_color"] = _color(a.get("ammo_color", "#d9d9d9"))
		if not a.has("name"):
			a["name"] = str(k).capitalize()
		if not (a.get("icon") is Dictionary):
			a["icon"] = {}
		if not (a.get("sound") is Dictionary):
			a["sound"] = {}
	for k in MAKERS.keys():
		var m: Dictionary = MAKERS[k]
		m["color"] = _color(m.get("color", "#888888"))
		m["dark"] = _color(m.get("dark", "#333333"))
		m["projectile_color"] = _color(m.get("projectile_color", "#ffffff"))
		if not m.has("name"):
			m["name"] = str(k).capitalize()
	_mod_index = {}
	for p in MODS:
		_mod_index[str(p["id"])] = p
	for r in RARITIES:
		r["color"] = _color(r.get("color", "#ffffff"))
	while RARITIES.size() < 6:
		RARITIES.append({"name": "?", "color": Color.WHITE, "damage_mult": 1.0, "perks": 0, "weight": 0.0, "hybrid_chance": 0.0})
	# ракеты/гранаты/мины в патронах — у основы без своей полосы патронов
	for k in ARCH.keys():
		var am := str(ARCH[k].get("ammo", k))
		if not ARCH.has(am):
			ARCH[k]["ammo"] = k


static func _color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color.html(str(v)) if Color.html_is_valid(str(v)) else Color.WHITE


## Словари по id. Запоминаем корень слоя (_root) — от него ищется "script".
static func _merge_dict(rel: String) -> Dictionary:
	var out := {}
	for layer in Mods.json_layers(rel):
		var d: Variant = layer["data"]
		if not (d is Dictionary):
			continue
		for id in (d as Dictionary).get("_remove", []):
			out.erase(str(id))
		for k in d:
			if str(k).begins_with("_"):
				continue
			var v: Variant = d[k]
			if not (v is Dictionary):
				continue
			if out.has(k):
				(out[k] as Dictionary).merge(v, true)
			else:
				out[k] = (v as Dictionary).duplicate(true)
			out[k]["_root"] = layer["root"]
	return out


## Списки записей с "id".
static func _merge_list(rel: String) -> Array:
	var out: Array = []
	for layer in Mods.json_layers(rel):
		var d: Variant = layer["data"]
		if not (d is Array):
			continue
		for v in d:
			if not (v is Dictionary):
				continue
			var e: Dictionary = v
			if e.has("remove"):
				for i in range(out.size() - 1, -1, -1):
					if str(out[i].get("id")) == str(e["remove"]):
						out.remove_at(i)
				continue
			var id := str(e.get("id", ""))
			if id == "":
				continue
			var found := false
			for o in out:
				if str(o.get("id")) == id:
					(o as Dictionary).merge(e, true)
					o["_root"] = layer["root"]
					found = true
					break
			if not found:
				var c := e.duplicate(true)
				c["_root"] = layer["root"]
				out.append(c)
	return out


## Список, где важен порядок (редкости): правка по индексу.
static func _merge_indexed(rel: String) -> Array:
	var out: Array = []
	for layer in Mods.json_layers(rel):
		var d: Variant = layer["data"]
		if not (d is Array):
			continue
		for i in (d as Array).size():
			var v: Variant = d[i]
			if not (v is Dictionary):
				continue
			if i < out.size():
				(out[i] as Dictionary).merge(v, true)
			else:
				out.append((v as Dictionary).duplicate(true))
	return out


## names.json: словарь списков строк. Списки дописываются; "replace": true — заменяет.
static func merge_names() -> Dictionary:
	var out := {}
	for layer in Mods.json_layers("data/names.json"):
		var d: Variant = layer["data"]
		if not (d is Dictionary):
			continue
		var replace := bool((d as Dictionary).get("replace", false))
		for k in d:
			var v: Variant = d[k]
			if not (v is Array):
				continue
			if replace or not out.has(k):
				out[k] = (v as Array).duplicate()
			else:
				(out[k] as Array).append_array(v)
	return out
