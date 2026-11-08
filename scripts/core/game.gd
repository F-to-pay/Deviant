extends Node
## Глобальное состояние забега. Автозагрузка "Game" (без class_name — иначе конфликт имён).

signal message(text: String, color: Color)
signal settings_changed(key: String)

const SAVE_PATH := "user://deviant.cfg"
## Настройки по умолчанию. Хранятся в deviant.cfg, секция [settings].
const DEFAULTS := {
	"master": 1.0, "music_volume": 0.6, "music_muted": false, "sfx_volume": 0.8, "ui_volume": 0.7,
	"fullscreen": true, "vsync": true, "shake": 1.0, "damage_numbers": true, "show_fps": false,
	"language": "",   # "" — как в системе, иначе код языка ("en", "ru", ...)
	"mod_states": "",  # JSON {имя мода: вкл/выкл}, см. Mods
	"mod_debug": false,  # отладчик модов (F8); применяется после перезапуска
	"auto_aim": false,   # автоприцел на геймпаде и сенсоре (Controls)
	"binds": "",         # переназначенные кнопки, JSON (InputSetup)
	"touch_controls": "auto",  # экранные кнопки: auto (когда играешь пальцем) / on / off
	"touch_scale": 1.0,  # размер экранных кнопок
	"touch_static": false,    # неподвижные стики (иначе — где коснулся, там и стик)
	"touch_tap_fire": false,  # стрельба по тапу в точку вместо правого стика
	"auto_fire": false,       # автоогонь по видимым врагам (геймпад и сенсор)
	"touch_layout": "",       # расположение и размер экранных кнопок, JSON (TouchControls)
	"ui_scale": 1.0,          # размер интерфейса (UiFit)
	"ui_margin_x": 0.0,       # отступ интерфейса от краёв экрана по бокам
	"ui_margin_y": 0.0,       # ... сверху и снизу
	"gun_card": "right",      # карточка пушки на земле: right / left / above (над пушкой)
	"ui_safe_area": true,     # на телефоне — ещё и безопасная зона системы (вырез, скругления)
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
var coins: int = 0                  # монеты забега (тратятся в городе, после смерти сгорают)
var meta_coins: int = 0             # древние монеты — мета-прогрессия, копятся между забегами (deviant.cfg)
var meta_run: int = 0               # древних монет подобрано за этот забег (для экрана смерти)
var hero := Heroes.DEFAULT          # выбранный герой (Heroes), сохраняется
var heroes_open: Array = [Heroes.DEFAULT]   # открытые герои, сохраняются
var in_town := false                # сейчас в городе между этапами
var town_name := ""
var new_rating_record := false      # для экрана смерти
var debug: bool = false
var settings: Dictionary = DEFAULTS.duplicate()

## Параметры забега («Настраиваемый старт»). Обычная «Новая игра» = RUN_DEFAULTS.
##  hp/dmg — множители здоровья и урона врагов; arch/maker — стартовая пушка ("" — по умолчанию,
##  "random" — случайно); seed — текст сида ("" — случайный).
const RUN_DEFAULTS := {
	"hp": 1.0, "dmg": 1.0, "zone_heal": false, "no_normals": false, "chests": true,
	"no_heal": false, "chaos": false, "arch": "", "maker": "", "seed": "", "towns": true,
}
## Этап = TOWN_EVERY зон (последняя — с боссом). Перед каждым этапом, и в начале забега, — город.
const TOWN_EVERY := 5
const START_COINS := 100
const DIFFICULTY := [
	{"n": "Easy", "hp": 0.8, "dmg": 0.5},
	{"n": "Normal", "hp": 1.0, "dmg": 1.0},
	{"n": "Hard", "hp": 1.2, "dmg": 1.2},
]
var run: Dictionary = RUN_DEFAULTS.duplicate()        # текущий забег
var custom: Dictionary = RUN_DEFAULTS.duplicate()     # последний «настраиваемый старт» (сохраняется)
var seed_value: int = 0                               # фактический сид забега

## Рейтинг = очки × множитель. Множитель = здоровье врагов × урон врагов × (1 + сумма бонусов).
## Бонус даётся, когда параметр забега равен указанному значению.
const RATING_BONUS := [
	["no_heal", true, 1.0, "hardcore"],
	["no_normals", true, 0.5, "elites only"],
	["chaos", true, 0.25, "chaos"],
	["chests", false, 0.25, "no chests"],
	["zone_heal", true, -0.5, "heal between zones"],
]
const POINTS_ZONE := 100     # за каждую пройденную зону
const POINTS_KILL := 1
const POINTS_BOSS := 250


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.setup()
	rng.randomize()
	_load()
	# отладчик модов включается только при запуске, чтобы просто так ничего не грузить
	if bool(setting("mod_debug")):
		_start_debugger()
	load_content()
	for k in settings:
		_apply_setting(str(k))


var debug_console: DebugConsole = null


func _start_debugger() -> void:
	DebugLog.enabled = true
	# ошибки движка (скрипты модов, push_warning, print) — читаем из файла журнала Godot.
	# Не через Logger (Godot 4.5+): на 4.7 свой Logger на GDScript ронял игру без следа в журнале.
	DebugLog.start_engine_log()
	debug_console = DebugConsole.new()
	add_child.call_deferred(debug_console)
	# полная проверка — когда поднимется main (нужны загруженные звуки)
	(func() -> void: Mods.validate()).call_deferred()


## Перезапуск игры (нужен, чтобы включить/выключить отладчик модов).
func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


## Данные игры и модов: таблицы пушек, имена, переводы. Повторный вызов — «применить моды».
func load_content() -> void:
	Mods.scan()
	Mods.clear_cache()
	GunData.load_data()
	EnemyData.load_data()
	Codex.load_data()
	I18n.load_all()
	I18n.apply(str(setting("language")))


## Перечитать всё после включения/выключения модов: данные, переводы, звуки, музыку —
## и прогреть заново под экраном загрузки (новые пушки, перки, буквы из модов).
func reload_content() -> void:
	load_content()
	if main != null:
		main.sfx.rescan()
		main.music.rescan()
		main.warmup()


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
	coins = START_COINS
	meta_run = 0
	in_town = false
	town_name = ""
	new_rating_record = false
	biome_offset = rng.randi_range(0, 10)


# --- Кривые сложности -------------------------------------------------------
# Здоровье врагов растёт чуть быстрее урона пушек: старые стволы постепенно
# устаревают, и приходится лутаться. Урон врагов растёт линейно — у игрока
# нет уровней, вся его сила — в пушках.

func is_boss_zone(level: int) -> bool:
	return level % 5 == 0


## Город перед этой зоной? — в начале забега и после каждого этапа (зоны 1, 6, 11...).
func town_before(level: int) -> bool:
	return bool(run.get("towns", true)) and (level - 1) % TOWN_EVERY == 0


# --- Монеты ---------------------------------------------------------------------

## Сколько стоит одна монетка, выпавшая в зоне level: глубже — дороже (цены в городе будут расти так же).
func coin_value(level: int) -> int:
	return 1 + maxi(0, level - 1) / 3


func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)


## Герой открыт (бесплатный — всегда).
func hero_unlocked(id: String) -> bool:
	return id in heroes_open or int(Heroes.get_hero(id).get("price", 0)) <= 0


## Открыть героя за древние монеты. free — без оплаты (команда отладчика). true — открыт.
func unlock_hero(id: String, free: bool = false) -> bool:
	if not Heroes.LIST.has(id) or hero_unlocked(id):
		return Heroes.LIST.has(id)
	var price := int(Heroes.LIST[id]["price"])
	if not free:
		if meta_coins < price:
			return false
		meta_coins -= price
	heroes_open.append(id)
	_save()
	return true


## Выбрать героя (только открытого). Текущий забег подхватывает сразу — см. Player.set_hero.
func select_hero(id: String) -> bool:
	if not hero_unlocked(id):
		return false
	hero = id
	_save()
	if main != null and main.player != null:
		main.player.set_hero(id)
	return true


## Древние монеты сохраняются сразу при подборе — их не теряешь ни при смерти, ни при вылете.
func add_meta(n: int) -> void:
	meta_coins = maxi(0, meta_coins + n)
	if n > 0:
		meta_run += n
	_save()


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
		"binds":
			InputSetup.apply_setting(str(setting("binds")))
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
		meta_coins = int(cf.get_value("meta", "coins", 0))
		hero = str(cf.get_value("meta", "hero", Heroes.DEFAULT))
		if not Heroes.LIST.has(hero):
			hero = Heroes.DEFAULT
		for h in str(cf.get_value("meta", "heroes", "")).split(",", false):
			if Heroes.LIST.has(h) and not (h in heroes_open):
				heroes_open.append(h)
		if not hero_unlocked(hero):
			hero = Heroes.DEFAULT
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
	cf.set_value("meta", "coins", meta_coins)
	cf.set_value("meta", "hero", hero)
	cf.set_value("meta", "heroes", ",".join(PackedStringArray(heroes_open)))
	for k in settings:
		cf.set_value("settings", str(k), settings[k])
	for k in custom:
		cf.set_value("custom", str(k), custom[k])
	cf.save(SAVE_PATH)


func save_custom() -> void:
	_save()
