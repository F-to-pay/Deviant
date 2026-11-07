extends Node
## Глобальное состояние забега. Автозагрузка "Game" (без class_name — иначе конфликт имён).

signal message(text: String, color: Color)
signal settings_changed(key: String)

const SAVE_PATH := "user://deviant.cfg"
## Настройки по умолчанию. Хранятся в deviant.cfg, секция [settings].
const DEFAULTS := {
	"master": 1.0, "music_volume": 0.6, "music_muted": false, "sfx_volume": 0.8, "ui_volume": 0.7,
	"fullscreen": true, "vsync": true, "shake": 1.0, "damage_numbers": true, "show_fps": false,
	"language": "",   # "" — как в системе, иначе "ru"/"en"
}

var rng := RandomNumberGenerator.new()
var main: Main = null
var zone_level: int = 1
var kills: int = 0
var run_time: float = 0.0
var guns_found: int = 0
var best_gun: Gun = null
var biome_offset: int = 0
var best_zone: int = 0
var best_kills: int = 0
var best_rating: int = 0
var bosses: int = 0                 # боссов убито за забег
var new_rating_record := false      # для экрана смерти
var debug: bool = false
var settings: Dictionary = DEFAULTS.duplicate()

## Параметры забега («Настраиваемый старт»). Обычная «Новая игра» = RUN_DEFAULTS.
##  hp/dmg — множители здоровья и урона врагов; arch/maker — стартовая пушка ("" — по умолчанию,
##  "random" — случайно); seed — текст сида ("" — случайный).
const RUN_DEFAULTS := {
	"hp": 1.0, "dmg": 1.0, "zone_heal": false, "no_normals": false, "chests": true,
	"no_heal": false, "chaos": false, "arch": "", "maker": "", "seed": "",
}
const DIFFICULTY := [
	{"n": "Легко", "hp": 0.8, "dmg": 0.5},
	{"n": "Нормально", "hp": 1.0, "dmg": 1.0},
	{"n": "Сложно", "hp": 1.2, "dmg": 1.2},
]
var run: Dictionary = RUN_DEFAULTS.duplicate()        # текущий забег
var custom: Dictionary = RUN_DEFAULTS.duplicate()     # последний «настраиваемый старт» (сохраняется)
var seed_value: int = 0                               # фактический сид забега

## Рейтинг = очки × множитель. Множитель = здоровье врагов × урон врагов × (1 + сумма бонусов).
## Бонус даётся, когда параметр забега равен указанному значению.
const RATING_BONUS := [
	["no_heal", true, 1.0, "хардкор"],
	["no_normals", true, 0.5, "только элита"],
	["chaos", true, 0.25, "хаос"],
	["chests", false, 0.25, "без сундуков"],
	["zone_heal", true, -0.5, "лечение между зонами"],
]
const POINTS_ZONE := 100     # за каждую пройденную зону
const POINTS_KILL := 1
const POINTS_BOSS := 250


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.setup()
	rng.randomize()
	_load()
	for k in settings:
		_apply_setting(str(k))


## Сид из текста: число — как есть, любой другой текст — хэш. Пусто — случайный.
func seed_from(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return randi() % 1000000000
	if t.is_valid_int():
		return t.to_int()
	return hash(t)


## Рекорд засчитывается, только если сложность и переключатели — как в обычной игре
## (стартовая пушка и сид не в счёт).
func counts_for_records() -> bool:
	for k in ["hp", "dmg", "zone_heal", "no_normals", "chests", "no_heal", "chaos"]:
		if run[k] != RUN_DEFAULTS[k]:
			return false
	return true


func new_run() -> void:
	rng.seed = seed_value ^ 0x5eed
	zone_level = 1
	kills = 0
	run_time = 0.0
	guns_found = 0
	best_gun = null
	bosses = 0
	new_rating_record = false
	biome_offset = rng.randi_range(0, 10)


# --- Кривые сложности -------------------------------------------------------
# Здоровье врагов растёт чуть быстрее урона пушек: старые стволы постепенно
# устаревают, и приходится лутаться. Урон врагов растёт линейно — у игрока
# нет уровней, вся его сила — в пушках.

func is_boss_zone(level: int) -> bool:
	return level % 5 == 0


func enemy_hp_mult(level: int) -> float:
	return pow(1.15, level - 1) * float(run["hp"])


func enemy_dmg_mult(level: int) -> float:
	return (1.0 + 0.1 * float(level - 1)) * float(run["dmg"])


func gun_dmg_mult(level: int) -> float:
	return pow(1.14, level - 1)


# --- Статистика ---------------------------------------------------------------

func note_gun(g: Gun) -> void:
	guns_found += 1
	if best_gun == null or g.rarity > best_gun.rarity or (g.rarity == best_gun.rarity and g.dps() > best_gun.dps()):
		best_gun = g


func say(text: String, color: Color = Color.WHITE) -> void:
	message.emit(text, color)


## Возвращает true, если поставлен рекорд.
# --- Рейтинг -------------------------------------------------------------------

func rating_mult(cfg: Dictionary = {}) -> float:
	var c := run if cfg.is_empty() else cfg
	var bonus := 0.0
	for b in RATING_BONUS:
		if c.get(b[0]) == b[1]:
			bonus += float(b[2])
	return maxf(0.0, float(c["hp"]) * float(c["dmg"]) * (1.0 + bonus))


func run_points() -> int:
	return (zone_level - 1) * POINTS_ZONE + kills * POINTS_KILL + bosses * POINTS_BOSS


func rating() -> int:
	return roundi(float(run_points()) * rating_mult())


## Возвращает true, если поставлен рекорд по зонам (только обычная сложность).
## Рейтинг пишется для любого забега.
func record_death() -> bool:
	var r := rating()
	new_rating_record = r > best_rating
	best_rating = maxi(best_rating, r)
	if not counts_for_records():
		_save()
		return false
	var rec := zone_level > best_zone
	best_zone = maxi(best_zone, zone_level)
	best_kills = maxi(best_kills, kills)
	_save()
	return rec


# --- Настройки -----------------------------------------------------------------

func setting(key: String) -> Variant:
	return settings.get(key, DEFAULTS.get(key))


func set_setting(key: String, value: Variant) -> void:
	var old: Variant = settings.get(key)
	if typeof(old) == typeof(value) and old == value:
		return
	settings[key] = value
	_apply_setting(key)
	_save()
	settings_changed.emit(key)


## То, что применяется здесь же; громкость музыки/звуков читают Music и Sfx сами.
func _apply_setting(key: String) -> void:
	match key:
		"language":
			I18n.apply(str(setting("language")))
		"master":
			var v := float(setting("master"))
			AudioServer.set_bus_mute(0, v <= 0.001)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
		"fullscreen":
			var fs := bool(setting("fullscreen"))
			var cur := DisplayServer.window_get_mode()
			var is_fs := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if fs and not is_fs:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			elif not fs and is_fs:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(setting("vsync")) else DisplayServer.VSYNC_DISABLED)


# --- Сохранение -----------------------------------------------------------------

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_zone = int(cf.get_value("records", "best_zone", 0))
		best_kills = int(cf.get_value("records", "best_kills", 0))
		best_rating = int(cf.get_value("records", "best_rating", 0))
		for k in DEFAULTS:
			settings[k] = _typed(DEFAULTS[k], cf.get_value("settings", str(k), DEFAULTS[k]))
		for k in RUN_DEFAULTS:
			custom[k] = _typed(RUN_DEFAULTS[k], cf.get_value("custom", str(k), RUN_DEFAULTS[k]))


## Значение из файла приводим к типу значения по умолчанию.
func _typed(d: Variant, v: Variant) -> Variant:
	if d is float:
		return float(v)
	if d is bool:
		return bool(v)
	return str(v)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("records", "best_zone", best_zone)
	cf.set_value("records", "best_kills", best_kills)
	cf.set_value("records", "best_rating", best_rating)
	for k in settings:
		cf.set_value("settings", str(k), settings[k])
	for k in custom:
		cf.set_value("custom", str(k), custom[k])
	cf.save(SAVE_PATH)


func save_custom() -> void:
	_save()
