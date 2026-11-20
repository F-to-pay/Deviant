class_name EnemyData
extends RefCounted
## Типы врагов, аффиксы элиток, генерация паков и имён.

## Типы врагов — data/enemies.json (слои игры и модов, по id): name, hp, dmg, speed, r, color, lvl (с какой зоны), sides (0 — круг),
## star, w (вес выпадения), res (врождённое сопротивление стихии: "fire", "shock", "acid", "cryo", "curse" или ""), ai (поведение из кода,
## по умолчанию — id типа). Здоровье и урон — на 1-й зоне, дальше растут (Balance.enemy_hp_mult / enemy_dmg_mult).
static var TYPES: Dictionary = {}

## Поведения, реализованные в коде (`Enemy._behave`): их можно указать в поле "ai" своего типа врага.
const AI_IDS := ["runner", "gunner", "brute", "bomber", "spreader", "charger", "mortar", "summoner"]

## Насколько врождённое сопротивление режет стихию: накопление кислоты/холода/проклятия, силу поджога,
## длину оглушения шока, удар проклятия. Элитки и боссы с их status_resist — поверх этого.
const INNATE_RESIST := 0.5

const AFFIXES := {
	"fast": "Fast",
	"tough": "Tough",
	"explosive": "Explosive",
	"teleport": "Teleporter",
	"multishot": "Multishot",
	"shielded": "Shielded",
	"regen": "Regeneration",
	"frost": "Frost Aura",
	"orbit": "Orbitals",
}

## Списки имён — из data/names.json (игра + моды): elite_prefixes, rare_first_names, rare_last_names,
## boss_titles, boss_names. Порядок слов — шаблоны языка "elite", "rare", "boss".
static var ELITE_PREFIX: Array = ["Vicious"]
static var RARE_FIRST: Array = ["Grisha"]
static var RARE_LAST: Array = ["the Breaker"]
static var BOSS_TITLES: Array = ["Great"]
static var BOSS_NAMES: Array = ["General Eggplant"]


static func load_data() -> void:
	_load_types()
	var n := GunData.merge_names()
	for pair in [["elite_prefixes", "ELITE_PREFIX"], ["rare_first_names", "RARE_FIRST"], ["rare_last_names", "RARE_LAST"],
			["boss_titles", "BOSS_TITLES"], ["boss_names", "BOSS_NAMES"]]:
		var v: Variant = n.get(pair[0], [])
		if v is Array and not (v as Array).is_empty():
			match str(pair[1]):
				"ELITE_PREFIX": ELITE_PREFIX = v
				"RARE_FIRST": RARE_FIRST = v
				"RARE_LAST": RARE_LAST = v
				"BOSS_TITLES": BOSS_TITLES = v
				"BOSS_NAMES": BOSS_NAMES = v


## Таблица типов из data/enemies.json: числа, цвет и стихия -> то, что ждёт код (недостающие поля — по умолчанию).
static func _load_types() -> void:
	TYPES = GunData.merge_dict("data/enemies.json")
	var defaults := {"hp": 10.0, "dmg": 5.0, "speed": 100.0, "r": 14.0, "w": 1.0}
	for k in TYPES.keys():
		var d: Dictionary = TYPES[k]
		d["name"] = str(d.get("name", str(k).capitalize()))
		d["color"] = GunData.to_color(d.get("color", [1.0, 1.0, 1.0]))
		for f in defaults:
			d[f] = float(d.get(f, defaults[f]))
		d["lvl"] = int(d.get("lvl", 1))
		d["sides"] = int(d.get("sides", 0))
		d["star"] = bool(d.get("star", false))
		d["res"] = U.el_id(d.get("res", ""))


static func pick_type(level: int, rng: RandomNumberGenerator, exclude: Array = []) -> String:
	var keys: Array = []
	var weights: Array = []
	var chaos := bool(Game.run["chaos"])
	for k in TYPES.keys():
		var d: Dictionary = TYPES[k]
		# Хаос: все типы с первой зоны и с равным шансом
		if (chaos or int(d["lvl"]) <= level) and not (k in exclude):
			keys.append(k)
			weights.append(1.0 if chaos else float(d["w"]))
	if keys.is_empty():
		return "runner"
	return keys[U.weighted(weights, rng)]


## Пак: состав, элитность (0/1 чемпионы/2 редкий вожак), число аффиксов.
## elite_mult > 1 — судья «любит элиток» (Director.ELITE_LOVE): шансы чемпионов и вожаков растут во столько раз, но не выше 45% и 32%.
static func roll_pack(level: int, rng: RandomNumberGenerator, elite_mult: float = 1.0) -> Dictionary:
	var size := rng.randi_range(4, 6 + mini(level / 3, 5))
	var t1 := pick_type(level, rng)
	var t2 := pick_type(level, rng)
	var elite := 0
	var n_aff := 0
	if bool(Game.run["chaos"]):
		# Хаос: обычные / чемпионы / вожак / босс — по 1/4
		var tier := rng.randi_range(0, 3)
		if tier == 3:
			return {"members": [], "elite": 3, "affixes": 0, "boss": true}
		elite = tier
		if tier == 1:
			n_aff = 1 + (1 if level >= 10 else 0)
			size = mini(size, 5)
		elif tier == 2:
			n_aff = 2 + (1 if level >= 15 else 0)
		var mm: Array = []
		for i in size:
			mm.append(t1 if rng.randf() < 0.6 else t2)
		return {"members": mm, "elite": elite, "affixes": n_aff}
	var r := rng.randf()
	var rare_chance := minf(0.07 + float(level) * 0.01, 0.25)
	var champ_chance := minf(0.14 + float(level) * 0.012, 0.35)
	if elite_mult > 1.0:
		rare_chance = minf(rare_chance * elite_mult, 0.32)
		champ_chance = minf(champ_chance * elite_mult, 0.45)
	if level >= 2 and r < rare_chance:
		elite = 2
		n_aff = 2 + (1 if level >= 15 else 0)
	elif r < rare_chance + champ_chance:
		elite = 1
		n_aff = 1 + (1 if level >= 10 else 0)
		size = mini(size, 5)
	var members: Array = []
	for i in size:
		members.append(t1 if rng.randf() < 0.6 else t2)
	return {"members": members, "elite": elite, "affixes": n_aff}


static func roll_affixes(n: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = AFFIXES.keys()
	U.shuffle(pool, rng)
	return pool.slice(0, mini(n, pool.size()))


static func elite_title(etype: String, elite: int, affixes: Array, rng: RandomNumberGenerator) -> String:
	var tn := str(TYPES[etype]["name"])
	var base := U.t(tn)
	var head := ""
	if elite == 1:
		var pre := str(ELITE_PREFIX[rng.randi() % ELITE_PREFIX.size()])
		head = I18n.tpl("elite", {"prefix": I18n.word(pre, "m"), "type": base, "type_l": I18n.word(tn, "lower")})
	elif elite == 2:
		head = I18n.tpl("rare", {"first": U.t(str(RARE_FIRST[rng.randi() % RARE_FIRST.size()])),
			"last": U.t(str(RARE_LAST[rng.randi() % RARE_LAST.size()]))})
	else:
		return base
	var names: Array = []
	for a in affixes:
		names.append(U.t(AFFIXES.get(a, str(a))))
	if names.is_empty():
		return head
	return head + " — " + ", ".join(PackedStringArray(names))


static func boss_name(rng: RandomNumberGenerator) -> String:
	var t1 := U.t(str(BOSS_TITLES[rng.randi() % BOSS_TITLES.size()]))
	var n1 := U.t(str(BOSS_NAMES[rng.randi() % BOSS_NAMES.size()]))
	return I18n.tpl("boss", {"title": t1, "name": n1})
