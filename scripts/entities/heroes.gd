class_name Heroes
extends RefCounted
## Герои: у каждого свой активный навык (кнопка «Навык», по умолчанию ПКМ / LT).
## Выбираются у Вербовщика в стартовом городе, открываются за древние монеты (Game.unlock_hero).
## Урон навыков фиксированный — не растёт с глубиной, в отличие от пушек.
##  aimed: true — на сенсоре у навыка свой стик прицела (кнопка навыка → тянешь, отпустил — бросок/удар;
##         тап без протяжки — как обычно, по прицелу ствола); без него навык срабатывает сразу при нажатии
##         (благословение Шерифа — у него нет направления).
##  skill: grenade — граната в точку прицела (dmg, r — радиус взрыва, range — дальность броска);
##         bless — следующий выстрел наносит +dmg (делится между дробинами);
##         turret — турель в точку прицела (range — дальность броска, r — размер метки; число турелей = заряды навыка);
##         slash — удар перед собой (dmg, r — дальность, arc — ширина дуги в градусах,
##                 time — сколько длится удар, slow — замедление героя на это время).

const DEFAULT := "pioneer"
## Навыки, реализованные в коде (`HeroSkill.use`): их можно указать в поле "skill" своего героя в data/heroes.json.
const SKILLS := ["grenade", "bless", "slash", "turret"]
## Герои — data/heroes.json (слои игры и модов, по id): name, price (древние монеты), color, skill, skill_name, cd, dmg и числа навыка,
## desc (с %d / %s, см. describe). Порядок записей = порядок в меню Вербовщика.
static var LIST: Dictionary = {}
static var ORDER: Array = []   # id героев в порядке LIST

## Перки навыков — берутся у Мистика за монеты, на один забег (Player.skill.run_perks).
##  heroes — у кого перк бывает ([] — у всех), max — сколько раз можно взять (0 — сколько угодно).
##  desc — первое взятие, more — каждое следующее. name_<навык> — своё имя для навыка (Ядовитый разрез).
## Как работают — HeroSkill (use, dmg_mult, ...) и Skills (попадание навыком).
## Данные — data/hero_perks.json (слои игры и модов, по id).
static var PERKS: Dictionary = {}
## Стихии, которые даёт перк «Стихия» (U.EL_*).
const ELEMENTS := [0, 1, 2, 3, 4]


## Загрузить героев и перки навыков из data/ (игра и включённые моды). Зовёт `Game.load_content`.
static func load_data() -> void:
	LIST = GunData.merge_dict("data/heroes.json")
	ORDER = []
	for id in LIST.keys():
		ORDER.append(str(id))
		var h: Dictionary = LIST[id]
		h["name"] = str(h.get("name", str(id).capitalize()))
		h["color"] = GunData.to_color(h.get("color", [1.0, 1.0, 1.0]))
		h["price"] = int(h.get("price", 0))
		h["skill"] = str(h.get("skill", ""))
		h["skill_name"] = str(h.get("skill_name", h["name"]))
		h["cd"] = float(h.get("cd", 6.0))
		h["dmg"] = float(h.get("dmg", 0.0))
		h["desc"] = str(h.get("desc", ""))
		if h.has("aimed"):
			h["aimed"] = bool(h["aimed"])
	PERKS = GunData.merge_dict("data/hero_perks.json")
	for id in PERKS.keys():
		var p: Dictionary = PERKS[id]
		p["name"] = str(p.get("name", str(id).capitalize()))
		p["max"] = int(p.get("max", 0))
		p["desc"] = str(p.get("desc", ""))
		if not (p.get("heroes") is Array):
			p["heroes"] = []


static func perk_fits(id: String, hero: String) -> bool:
	var hs: Array = PERKS.get(id, {}).get("heroes", [])
	return PERKS.has(id) and (hs.is_empty() or hero in hs)


## Можно ли взять перк ещё раз (have — сколько уже взято).
static func perk_open(id: String, hero: String, have: int) -> bool:
	var mx := int(PERKS.get(id, {}).get("max", 0))
	return perk_fits(id, hero) and (mx <= 0 or have < mx)


static func perk_name(id: String, hero: String) -> String:
	var pk: Dictionary = PERKS.get(id, {})
	var own := "name_" + str(get_hero(hero).get("skill", ""))
	return U.t(str(pk.get(own, pk.get("name", id))))


## Описание: для первого взятия — desc, для следующих — more.
static func perk_desc(id: String, have: int) -> String:
	var pk: Dictionary = PERKS.get(id, {})
	return U.t(str(pk.get("more", pk.get("desc", "")) if have > 0 else pk.get("desc", "")))


## n перков на выбор у Мистика для героя (без исчерпанных).
static func perk_offer(hero: String, owned: Dictionary, rng: RandomNumberGenerator, n: int) -> Array:
	var ids: Array = []
	for id in PERKS:
		if perk_open(str(id), hero, int(owned.get(id, 0))):
			ids.append(str(id))
	U.shuffle(ids, rng)
	return ids.slice(0, n)


static func get_hero(id: String) -> Dictionary:
	return LIST.get(id, LIST.get(DEFAULT, {}))


static func hero_name(id: String) -> String:
	return U.t(str(get_hero(id)["name"]))


static func color(id: String) -> Color:
	return get_hero(id)["color"]


## Описание навыка с числами (уже переведённое).
static func describe(id: String) -> String:
	var h := get_hero(id)
	var d := U.t(str(h["desc"]))
	var cd := U.fmt(float(h["cd"]))
	match str(h["skill"]):
		"grenade":
			return d % [roundi(float(h["dmg"])), roundi(float(h["r"])), cd]
		"bless":
			return d % [roundi(float(h["dmg"])), cd]
		"slash":
			return d % [roundi(float(h["dmg"])), cd, roundi(float(h["slow"]) * 100.0)]
		"turret":
			return d % [roundi(float(h["range"])), cd]
	return d
