class_name RunState
extends RefCounted
## Состояние текущего забега: всё, что обнуляется новым забегом и сгорает со смертью (монеты, опыт, дерево навыков,
## счётчики). Только данные и простая арифметика над ними; эффекты (звук, сообщения, пересчёт здоровья) — в `Game`.
## Параметры забега (сложность, переключатели) — отдельно, `Game.run` / `RunConfig`; то, что переживает забег, — `Profile`.

var zone_level: int = 1
var kills: int = 0
var run_time: float = 0.0
var hero_level: int = 1
var tree: Dictionary = {}    # дерево навыков этого забега: id узла -> уровень (LevelTree)
var xp: float = 0.0          # накоплено к следующему уровню (остаток после повышения переносится; может быть < 0)
var xp_total: float = 0.0    # за весь забег, для статистики и калибровки
var guns_found: int = 0
var best_gun: Gun = null
var biome_offset: int = 0
var bosses: int = 0          # боссов убито за забег
var coins: float = 0.0       # монеты забега (тратятся в городе, после смерти сгорают)
var meta_run: int = 0        # древних монет подобрано за этот забег (для экрана смерти)
var in_town := false         # сейчас в городе между этапами
var town_name := ""
var new_rating_record := false   # для экрана смерти
var seed_value: int = 0      # фактический сид забега
var quests: Array = []       # взятые задания Гильдии (Quests): словари {type, need, have, reward...}


## Начать забег с нуля. rng — общий ГСЧ игры, уже засеянный сидом (биом берётся первым же броском).
func reset(rng: RandomNumberGenerator) -> void:
	zone_level = 1
	kills = 0
	run_time = 0.0
	hero_level = 1
	xp = 0.0
	xp_total = 0.0
	tree = {}
	guns_found = 0
	best_gun = null
	bosses = 0
	coins = RunConfig.START_COINS
	meta_run = 0
	in_town = false
	town_name = ""
	new_rating_record = false
	quests = []
	biome_offset = rng.randi_range(0, 10)


## Состояние забега словарём (для сейва, `RunSave`). Лучшая пушка забега (best_gun) — тоже словарём.
func to_dict() -> Dictionary:
	var d := {}
	for pr in get_property_list():
		if (int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(pr["name"])
		var v: Variant = get(n)
		if n == "best_gun":
			d[n] = (v as Gun).to_dict() if v != null else null
		elif v is Array or v is Dictionary:
			d[n] = v.duplicate(true)
		else:
			d[n] = v
	return d


## Вернуть состояние из словаря `to_dict` (неизвестные поля пропускаются, недостающие остаются как после `reset`).
func from_dict(d: Dictionary) -> void:
	var valid := {}
	for pr in get_property_list():
		if (int(pr["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			valid[str(pr["name"])] = true
	for k in d:
		var n := str(k)
		if not valid.has(n):
			continue
		var v: Variant = d[k]
		if n == "best_gun":
			best_gun = Gun.from_dict(v) if v is Dictionary else null
		elif v is Array or v is Dictionary:
			set(n, v.duplicate(true))
		else:
			set(n, v)


func add_coins(n: float) -> void:
	coins = clampf(coins + n, 0.0, Balance.MONEY_MAX)


func note_gun(g: Gun) -> void:
	guns_found += 1
	if best_gun == null or g.rarity > best_gun.rarity or (g.rarity == best_gun.rarity and g.dps() > best_gun.dps()):
		best_gun = g


## Начислить XP (уже с множителем рейтинга) и повысить уровень (может несколько раз подряд).
## Возвращает, на сколько уровней вырос герой.
func gain_xp(amount: float) -> int:
	xp += amount
	xp_total += amount
	var ups := 0
	while xp >= Balance.xp_need(hero_level):
		xp -= Balance.xp_need(hero_level)
		hero_level += 1
		ups += 1
	return ups


## Очки забега до умножения на рейтинг.
func points() -> int:
	return RunConfig.points(zone_level, kills, bosses)


## Рейтинг забега при параметрах cfg.
func rating(cfg: Dictionary) -> int:
	return roundi(float(points()) * RunConfig.rating_mult(cfg))
