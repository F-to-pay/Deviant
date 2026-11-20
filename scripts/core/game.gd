extends Node
## Координатор игры. Автозагрузка "Game" (без class_name — иначе конфликт имён).
## Сам почти ничего не хранит: держит ссылки на части и склеивает их там, где нужны эффекты (звук, сообщения, мир).
##  · settings — настройки (`Settings`): `Game.settings.get_value("key")`, сигнал `Game.settings.changed`
##  · profile  — что переживает забег: древние монеты, герои, рекорды, последний пользовательский старт (`Profile`)
##  · state    — состояние текущего забега: монеты, опыт, дерево навыков, счётчики (`RunState`)
##  · run      — параметры текущего забега (`RunConfig.DEFAULTS` + что выбрал игрок)
## Числа баланса и кривые — `Balance`, правила забега и рейтинг — `RunConfig`, файл — `Save`.

signal message(text: String, color: Color)

var settings := Settings.new()
var profile := Profile.new()
var state := RunState.new()
var run: Dictionary = RunConfig.DEFAULTS.duplicate()   # параметры текущего забега

var rng := RandomNumberGenerator.new()
var main: Main = null
var debug: bool = false
var debug_console: DebugConsole = null
var controls := Controls.new()   # ввод игрока (kbm / геймпад / сенсор): режим, прицел, подписи кнопок
var debug_log := DebugLog.new()   # журнал отладчика модов (предупреждения загрузчика, ошибки скриптов, строки движка)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(controls)
	InputSetup.setup()
	rng.randomize()
	Save.read(profile, settings)
	profile.changed.connect(save)
	settings.changed.connect(func(_key: String) -> void: save())
	# отладчик модов включается только при запуске, чтобы просто так ничего не грузить
	if bool(settings.get_value("mod_debug")):
		_start_debugger()
	load_content()
	settings.apply_all()


func save() -> void:
	Save.write(profile, settings)


func _start_debugger() -> void:
	debug_log.enabled = true
	# ошибки движка (скрипты модов, push_warning, print) — читаем из файла журнала Godot.
	# Не через Logger (Godot 4.5+): на 4.7 свой Logger на GDScript ронял игру без следа в журнале.
	debug_log.start_engine_log()
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
	Heroes.load_data()
	LevelTree.load_data()
	Codex.load_data()
	I18n.load_all()
	I18n.apply(str(settings.get_value("language")))
	profile.validate_heroes()   # выбранный герой мог принадлежать выключенному моду


## Перечитать всё после включения/выключения модов: данные, переводы, звуки, музыку —
## и прогреть заново под экраном загрузки (новые пушки, перки, буквы из модов).
func reload_content() -> void:
	load_content()
	if main != null:
		main.sfx.rescan()
		main.music.rescan()
		main.warmup()


func say(text: String, color: Color = Color.WHITE) -> void:
	message.emit(text, color)


# --- Забег -----------------------------------------------------------------------

## Новый забег: ГСЧ от сида, обнулить состояние и дерево навыков.
func new_run() -> void:
	rng.seed = state.seed_value ^ 0x5eed
	state.reset(rng)
	LevelTree.recompute()


## Начисляет XP с множителем рейтинга забега (сложнее настройки — быстрее уровни, и наоборот) и повышает уровень.
## Каждый уровень — очки в дерево навыков (LevelTree), о чём сообщаем в углу экрана. Возвращает, на сколько уровней вырос.
func add_xp(amount: float) -> int:
	var ups := state.gain_xp(amount * RunConfig.rating_mult(run))
	if ups > 0:
		# корни дерева растут вместе с героем (per_hero): пересчитать бонусы и здоровье
		LevelTree.recompute()
		if main != null and main.player != null:
			main.player.on_tree_changed()
		say(U.t("LEVEL %d! Skill points: %d") % [state.hero_level, LevelTree.free_points()], Color(0.75, 1.0, 0.55))
		Sfx.ui("pickup/relic", -6.0, 1.3)
	return ups


## Уровень, под который подгоняются белые пушки (`Gun.sync_level`): текущая зона, а в городе — следующая
## (по ней же сделан товар Оружейной).
func white_level() -> int:
	if main != null and main.zone != null:
		return main.zone.level
	return state.zone_level


## Занести итог забега в профиль. Возвращает true, если поставлен рекорд по зонам (только обычная сложность).
## Рейтинг пишется для любого забега.
func record_death() -> bool:
	var res := profile.record_run(state.rating(run), state.zone_level, state.kills, RunConfig.counts_for_records(run))
	state.new_rating_record = bool(res["rating_record"])
	return bool(res["zone_record"])


# --- Герои и мета-монеты -----------------------------------------------------------

## Выбрать героя (только открытого). Текущий забег подхватывает сразу — см. Player.set_hero.
func select_hero(id: String) -> bool:
	if not profile.select_hero(id):
		return false
	if main != null and main.player != null:
		main.player.set_hero(id)
	return true


## Древние монеты: в профиль (сохраняется сразу) и в счёт «за этот забег».
func add_meta(n: int) -> void:
	if n > 0:
		state.meta_run += n
	profile.add_meta(n)
