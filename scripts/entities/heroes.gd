class_name Heroes
extends RefCounted
## Герои: у каждого свой активный навык (кнопка «Навык», по умолчанию ПКМ / LT).
## Выбираются у Вербовщика в стартовом городе, открываются за древние монеты (Game.unlock_hero).
## Урон навыков фиксированный — не растёт с глубиной, в отличие от пушек.
##  skill: grenade — граната в точку прицела (dmg, r — радиус взрыва, range — дальность броска);
##         bless — следующий выстрел наносит +dmg (делится между дробинами);
##         slash — удар перед собой (dmg, r — дальность, arc — ширина дуги в градусах,
##                 time — сколько длится удар, slow — замедление героя на это время).

const DEFAULT := "pioneer"
const ORDER := ["pioneer", "sheriff", "assassin"]
const LIST := {
	"pioneer": {"name": "Pioneer", "price": 0, "color": Color(0.35, 0.85, 1.0),
		"skill": "grenade", "skill_name": "Hand grenade", "cd": 6.0, "dmg": 35.0, "r": 60.0, "range": 420.0,
		"desc": "Throws a grenade at the aim point: %d damage in radius %d. Cooldown %s s."},
	"sheriff": {"name": "Sheriff", "price": 25, "color": Color(1.0, 0.45, 0.3),
		"skill": "bless", "skill_name": "Blessing", "cd": 6.0, "dmg": 40.0,
		"desc": "Blesses the next shot: +%d damage. Cooldown %s s."},
	"assassin": {"name": "Assassin", "price": 30, "color": Color(0.72, 0.5, 1.0),
		"skill": "slash", "skill_name": "Slash", "cd": 0.7, "dmg": 15.0, "r": 95.0, "arc": 130.0,
		"time": 0.25, "slow": 0.5,
		"desc": "A cleaving melee strike in front of you: %d damage. Cooldown %s s, you are slowed by %d%% while striking."},
}


## Перки навыков — берутся у Мистика за монеты, на один забег (Player.run_perks).
##  heroes — у кого перк бывает ([] — у всех), max — сколько раз можно взять (0 — сколько угодно).
##  desc — первое взятие, more — каждое следующее. name_<навык> — своё имя для навыка (Ядовитый разрез).
## Как работают — Player (_use_skill, skill_dmg_mult, ...) и Skills (попадание навыком).
const PERKS := {
	"split": {"name": "Split", "heroes": ["pioneer", "sheriff"], "max": 0,
		"desc": "The skill fires ×3 projectiles and deals +20% total damage, split evenly between them.",
		"more": "+3 projectiles, +20% damage."},
	"wounds": {"name": "Grievous Wounds", "heroes": [], "max": 1,
		"desc": "Skill hits slow the target by 10% for good, up to 30%. Elites need 2 hits for each step, bosses 3."},
	"poison": {"name": "Poison Shell", "name_slash": "Poison Cut", "heroes": ["pioneer", "sheriff", "assassin"], "max": 0,
		"desc": "Skill damage lands 5 s later, but is 30% higher.", "more": "+2 s delay, +30% damage."},
	"heavy": {"name": "Heavy Shell", "heroes": ["pioneer", "sheriff"], "max": 0,
		"desc": "+1 s skill cooldown, +20% damage, the hit stuns for 0.7 s.", "more": "+1 s cooldown, +20% damage, +0.4 s stun."},
	"parry": {"name": "Parry", "heroes": ["assassin"], "max": 0,
		"desc": "Every 4 s your next strike reflects enemy projectiles back.", "more": "Reflected projectiles deal +30% damage."},
	"hand": {"name": "Extra Hand", "heroes": [], "max": 0,
		"desc": "+1 skill charge.", "more": "+1 skill charge."},
	"vandal": {"name": "Vandalism", "heroes": ["assassin"], "max": 1,
		"desc": "The strike knocks enemies far away, but deals 50% less damage."},
	"element": {"name": "Element", "heroes": [], "max": 1,
		"desc": "The skill gets an element of your choice."},
	"trophies": {"name": "Trophies", "heroes": ["assassin"], "max": 0,
		"desc": "A kill with the skill gives 1 coin and +0.2% skill damage until the end of the run.",
		"more": "+0.05% skill damage per kill."},
	"smoke": {"name": "Smoke Grenade", "heroes": ["pioneer"], "max": 0,
		"desc": "The grenade turns into smoke of radius 300: 30% of its damage every second for 4 s.",
		"more": "The smoke lasts 1 s longer."},
	"precise": {"name": "Precise Shot", "heroes": ["sheriff"], "max": 0,
		"desc": "The blessed shot homes in, flies 20% farther and deals 10% more damage.",
		"more": "+20% range, +10% damage."},
	"ready": {"name": "Readiness", "heroes": ["assassin", "sheriff"], "max": 1,
		"desc": "Dealing damage with the skill takes 1 s off the dodge cooldown."},
}
## Стихии, которые даёт перк «Стихия» (U.EL_*).
const ELEMENTS := [0, 1, 2, 3, 4]


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
	return LIST.get(id, LIST[DEFAULT])


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
	return d
