class_name EnemyData
extends RefCounted
## Типы врагов, аффиксы элиток, генерация паков и имён.

## res — врождённое сопротивление стихии (U.EL_*): эффект этой стихии на нём слабее на INNATE_RESIST.
## sides: 0 — круг, иначе число сторон. lvl — с какой зоны появляется.
const TYPES := {
	"runner": {"n": "Runner", "hp": 32.0, "dmg": 12.0, "speed": 185.0, "r": 13.0, "col": Color(0.92, 0.32, 0.3),
		"lvl": 1, "sides": 3, "star": false, "w": 10.0, "res": U.EL_ACID},
	"gunner": {"n": "Gunner", "hp": 38.0, "dmg": 10.0, "speed": 120.0, "r": 14.0, "col": Color(0.95, 0.75, 0.25),
		"lvl": 1, "sides": 4, "star": false, "w": 7.0, "res": U.EL_SHOCK},
	"brute": {"n": "Brute", "hp": 150.0, "dmg": 28.0, "speed": 95.0, "r": 22.0, "col": Color(0.62, 0.36, 0.82),
		"lvl": 2, "sides": 6, "star": false, "w": 4.0, "res": U.EL_CRYO},
	"bomber": {"n": "Kamikaze", "hp": 22.0, "dmg": 38.0, "speed": 220.0, "r": 12.0, "col": Color(1.0, 0.52, 0.12),
		"lvl": 2, "sides": 0, "star": false, "w": 5.0, "res": U.EL_FIRE},
	"spreader": {"n": "Spreader", "hp": 60.0, "dmg": 9.0, "speed": 105.0, "r": 16.0, "col": Color(0.3, 0.82, 0.5),
		"lvl": 3, "sides": 5, "star": false, "w": 5.0, "res": U.EL_SHOCK},
	"charger": {"n": "Charger", "hp": 95.0, "dmg": 30.0, "speed": 125.0, "r": 18.0, "col": Color(0.88, 0.22, 0.56),
		"lvl": 4, "sides": 4, "star": true, "w": 4.0, "res": U.EL_ACID},
	"mortar": {"n": "Mortarman", "hp": 50.0, "dmg": 32.0, "speed": 90.0, "r": 15.0, "col": Color(0.5, 0.62, 0.95),
		"lvl": 6, "sides": 8, "star": false, "w": 3.0, "res": U.EL_SHOCK},
	"summoner": {"n": "Shaman", "hp": 75.0, "dmg": 8.0, "speed": 110.0, "r": 15.0, "col": Color(0.4, 0.95, 0.9),
		"lvl": 8, "sides": 5, "star": true, "w": 2.0, "res": U.EL_CURSE},
}

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
static func roll_pack(level: int, rng: RandomNumberGenerator) -> Dictionary:
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
	var tn := str(TYPES[etype]["n"])
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
