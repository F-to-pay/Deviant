class_name Save
extends RefCounted
## Файл сохранения `user://deviant.cfg` (ConfigFile): профиль и настройки. Забег пока не сохраняется (см. TODO «Сейвы»).
## Разделы файла: [records] и [meta] (Profile.write_core), [settings] (Settings.write), [custom] (Profile.write_custom).

const PATH := "user://deviant.cfg"


## Прочитать файл в профиль и настройки (нет файла — остаются значения по умолчанию).
static func read(profile: Profile, settings: Settings, path: String = PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	profile.read(cf)
	settings.read(cf)


static func write(profile: Profile, settings: Settings, path: String = PATH) -> void:
	var cf := ConfigFile.new()
	profile.write_core(cf)
	settings.write(cf)
	profile.write_custom(cf)
	cf.save(path)
