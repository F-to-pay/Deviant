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
const ORDER := ["pioneer", "cultist", "assassin"]
const LIST := {
	"pioneer": {"name": "Pioneer", "price": 0, "color": Color(0.35, 0.85, 1.0),
		"skill": "grenade", "skill_name": "Hand grenade", "cd": 6.0, "dmg": 35.0, "r": 60.0, "range": 420.0,
		"desc": "Throws a grenade at the aim point: %d damage in radius %d. Cooldown %s s."},
	"cultist": {"name": "Cultist of Strength", "price": 25, "color": Color(1.0, 0.45, 0.3),
		"skill": "bless", "skill_name": "Blessing", "cd": 6.0, "dmg": 40.0,
		"desc": "Blesses the next shot: +%d damage. Cooldown %s s."},
	"assassin": {"name": "Assassin", "price": 30, "color": Color(0.72, 0.5, 1.0),
		"skill": "slash", "skill_name": "Slash", "cd": 0.7, "dmg": 15.0, "r": 75.0, "arc": 130.0,
		"time": 0.25, "slow": 0.5,
		"desc": "A cleaving melee strike in front of you: %d damage. Cooldown %s s, you are slowed by %d%% while striking."},
}


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
