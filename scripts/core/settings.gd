class_name Settings
extends RefCounted
## Настройки игры (меню «Настройки» и «Управление»). Хранятся в `user://deviant.cfg`, секция [settings].
## Чтение — `Game.settings.get_value("key")`, запись — `set_value` (применяет, сообщает `changed`, `Game` сохраняет файл).
## Громкость музыки и звуков читают Music и Sfx сами по сигналу `changed`.

signal changed(key: String)

## Настройки по умолчанию.
const DEFAULTS := {
	"master": 1.0, "music_volume": 0.6, "music_muted": false, "sfx_volume": 0.8, "ui_volume": 0.7,
	"fullscreen": true, "vsync": true, "shake": 1.0, "damage_numbers": true, "show_fps": false,
	"language": "",   # "" — как в системе, иначе код языка ("en", "ru", ...)
	"mod_states": "",  # JSON {имя мода: вкл/выкл}, см. Mods
	"mod_debug": false,  # отладчик модов (F8); применяется после перезапуска
	"autosave": true,   # контрольные точки пишутся на диск сами; выключено — только кнопкой «Сохранить» в паузе (RunSave)
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
	"touch_release_fire": "", # сенсор: какие типы пушек стреляют по отпусканию стика, JSON {id основы: true}
}

var values: Dictionary = DEFAULTS.duplicate()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	var old: Variant = values.get(key)
	if typeof(old) == typeof(value) and old == value:
		return
	values[key] = value
	apply(key)
	changed.emit(key)


## Применить все настройки (при старте, после чтения файла).
func apply_all() -> void:
	for k in values:
		apply(str(k))


## То, что применяется здесь же; громкость музыки/звуков читают Music и Sfx сами.
func apply(key: String) -> void:
	match key:
		"language":
			I18n.apply(str(get_value("language")))
		"binds":
			InputSetup.apply_setting(str(get_value("binds")))
		"master":
			var v := float(get_value("master"))
			AudioServer.set_bus_mute(0, v <= 0.001)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
		"fullscreen":
			var fs := bool(get_value("fullscreen"))
			var cur := DisplayServer.window_get_mode()
			var is_fs := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if fs and not is_fs:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			elif not fs and is_fs:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)


## Прочитать секцию [settings]; значения приводятся к типу значения по умолчанию.
func read(cf: ConfigFile) -> void:
	for k in DEFAULTS:
		values[k] = U.typed(DEFAULTS[k], cf.get_value("settings", str(k), DEFAULTS[k]))


func write(cf: ConfigFile) -> void:
	for k in values:
		cf.set_value("settings", str(k), values[k])
