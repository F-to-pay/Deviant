class_name RunConfig
extends RefCounted
## Правила и параметры забега: «Настраиваемый старт», структура этапов, рейтинг. Только константы и чистые
## статические функции над словарём параметров `cfg` (текущий забег — `Game.run`, последний пользовательский — `Game.profile.custom`).

## Параметры забега («Настраиваемый старт»). Обычная «Новая игра» = DEFAULTS. keep_save — сейв забега остаётся после смерти
## (рейтинг, а с ним и опыт, −50%).
##  hp/dmg — множители здоровья и урона врагов; arch/maker — стартовая пушка ("" — по умолчанию,
##  "random" — случайно); seed — текст сида ("" — случайный).
const DEFAULTS := {
	"hp": 1.0, "dmg": 1.0, "zone_heal": false, "no_normals": false, "chests": false,
	"no_heal": false, "chaos": false, "arch": "", "maker": "", "seed": "", "towns": true, "keep_save": false,
}
## Параметры, из-за которых забег не идёт в рекорды (сложность и переключатели; стартовая пушка и сид не в счёт).
const RECORD_KEYS := ["hp", "dmg", "zone_heal", "no_normals", "chests", "no_heal", "chaos", "keep_save"]

## Этап = TOWN_EVERY зон (последняя — с боссом). Перед каждым этапом, и в начале забега, — город.
const TOWN_EVERY := 5
const START_COINS := 120
const DIFFICULTY := [
	{"n": "Easy", "hp": 0.8, "dmg": 0.5},
	{"n": "Normal", "hp": 1.0, "dmg": 1.0},
	{"n": "Hard", "hp": 1.2, "dmg": 1.2},
]

## Рейтинг = очки × множитель. Множитель = здоровье врагов × урон врагов × (1 + сумма бонусов).
## Бонус даётся, когда параметр забега равен указанному значению.
const RATING_BONUS := [
	["no_heal", true, 1.0, "hardcore"],
	["no_normals", true, 0.5, "elites only"],
	["chaos", true, 0.25, "chaos"],
	["chests", true, -0.2, "chests"],
	["zone_heal", true, -0.5, "heal between zones"],
	["keep_save", true, -0.5, "keeping the save after death"],
]
const POINTS_ZONE := 100     # за каждую пройденную зону
const POINTS_KILL := 1
const POINTS_BOSS := 250


static func is_boss_zone(level: int) -> bool:
	return level % TOWN_EVERY == 0


## Город перед этой зоной? — в начале забега и после каждого этапа (зоны 1, 6, 11...).
static func town_before(cfg: Dictionary, level: int) -> bool:
	return bool(cfg.get("towns", true)) and (level - 1) % TOWN_EVERY == 0


## Рекорд засчитывается, только если сложность и переключатели — как в обычной игре.
static func counts_for_records(cfg: Dictionary) -> bool:
	for k in RECORD_KEYS:
		if cfg[k] != DEFAULTS[k]:
			return false
	return true


static func rating_mult(cfg: Dictionary) -> float:
	var bonus := 0.0
	for b in RATING_BONUS:
		if cfg.get(b[0]) == b[1]:
			bonus += float(b[2])
	return maxf(0.0, float(cfg["hp"]) * float(cfg["dmg"]) * (1.0 + bonus))


## Очки забега до умножения на рейтинг.
static func points(zone_level: int, kills: int, bosses: int) -> int:
	return (zone_level - 1) * POINTS_ZONE + kills * POINTS_KILL + bosses * POINTS_BOSS


## Сид из текста: число — как есть, любой другой текст — хэш. Пусто — случайный.
static func seed_from(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return randi() % 1000000000
	if t.is_valid_int():
		return t.to_int()
	return hash(t)
