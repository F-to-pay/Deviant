class_name Mods
extends RefCounted
## Моды. Собранная игра читает папку Mods/ рядом с exe; в редакторе — Mods/ в корне проекта
## (там лежит .gdignore, чтобы Godot не импортировал и не компилировал содержимое модов).
##
## Мод — это папка Mods/<Имя>/, повторяющая корень игры:
##   mod.json            — необязательно: {"name", "author", "version", "description", "enabled": true}
##   data/*.json         — archetypes, makers, perks, legendaries, rarities, names (дополняют/правят базовые)
##   lang/<код>.json     — переводы (дополняют существующий язык или добавляют новый)
##   sfx/..., music/...  — звуки и музыка (те же папки-банки, что у игры: sfx/guns/pistol/*.wav и т.д.)
##   *.gd                — скрипты перков/марок/легендарок (поле "script" в data/*.json, путь от корня мода)
## Порядок слоёв: сначала игра (res://), потом моды по алфавиту — поздний слой переопределяет ранний.

const AUDIO_EXTS := ["wav", "ogg", "mp3"]

static var list: Array = []        # [{id, name, path, enabled, info}]
static var _scripts := {}          # абсолютный путь -> экземпляр скрипта (или null, если не собрался)


## Папка с модами (может не существовать).
static func root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://Mods")
	return OS.get_executable_path().get_base_dir().path_join("Mods")


## Найти моды и прочитать, какие включены. Вызывается при старте и при «Применить» в меню модов.
static func scan() -> void:
	list.clear()
	var r := root()
	var dir := DirAccess.open(r)
	if dir == null:
		return
	var names := Array(dir.get_directories())
	names.sort()
	var states := _states()
	for n in names:
		var id := str(n)
		if id.begins_with(".") or id.begins_with("_"):
			continue
		var path := r.path_join(id)
		var info: Variant = read_json(path.path_join("mod.json"))
		if not (info is Dictionary):
			info = {}
		var on := bool(info.get("enabled", true))
		if states.has(id):
			on = bool(states[id])
		list.append({"id": id, "name": str(info.get("name", id)), "path": path, "enabled": on, "info": info})


## Включение/выключение хранится в настройке mod_states (JSON-строка {id: bool}).
static func _states() -> Dictionary:
	var raw := str(Game.setting("mod_states"))
	var v: Variant = JSON.parse_string(raw) if raw != "" else {}
	return v if v is Dictionary else {}


static func set_enabled(id: String, on: bool) -> void:
	var st := _states()
	st[id] = on
	Game.set_setting("mod_states", JSON.stringify(st))
	for m in list:
		if m["id"] == id:
			m["enabled"] = on


## Корни слоёв: сначала игра, потом включённые моды.
static func layers() -> Array:
	var out: Array = ["res://"]
	for m in list:
		if bool(m["enabled"]):
			out.append(str(m["path"]))
	return out


# --- Файлы ----------------------------------------------------------------------

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var txt := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	if j.parse(txt) != OK:
		push_warning("Mods: ошибка в %s, строка %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


## Один и тот же файл (например "data/perks.json") из всех слоёв: [{data, root}].
static func json_layers(rel: String) -> Array:
	var out: Array = []
	for r in layers():
		var v: Variant = read_json(str(r).path_join(rel))
		if v != null:
			out.append({"data": v, "root": str(r)})
	return out


## Все файлы с нужными расширениями в папке rel_dir (рекурсивно) из всех слоёв.
## Возвращает [[путь внутри rel_dir, полный путь], ...].
## resources = true — для импортируемых ресурсов (звуки): в res:// их видит только ResourceLoader,
## потому что в собранной игре оригиналов нет, есть только импортированные копии.
static func files(rel_dir: String, exts: Array, resources: bool = false) -> Array:
	var out: Array = []
	for r in layers():
		var base := str(r).path_join(rel_dir)
		if not base.ends_with("/"):
			base += "/"
		_walk(base, "", exts, out, resources and str(r) == "res://")
	return out


static func _walk(base: String, sub: String, exts: Array, out: Array, via_loader: bool) -> void:
	var here := base + sub
	if via_loader:
		for n in ResourceLoader.list_directory(here):
			var fname := str(n)
			if fname.ends_with("/"):
				_walk(base, sub + fname, exts, out, via_loader)
			elif exts.has(fname.get_extension().to_lower()):
				out.append([sub + fname, here + fname])
		return
	var dir := DirAccess.open(here)
	if dir == null:
		return
	for d in dir.get_directories():
		if not str(d).begins_with("."):
			_walk(base, sub + str(d) + "/", exts, out, via_loader)
	for f in dir.get_files():
		var fname := str(f)
		if exts.has(fname.get_extension().to_lower()):
			out.append([sub + fname, here + fname])


## Звук из игры (res://) или из мода (обычный файл на диске).
static func load_audio(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return load(path) as AudioStream
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


# --- Скрипты модов ----------------------------------------------------------------

## Экземпляр скрипта мода. rel — путь от корня мода ("perks/laser.gd").
## Скрипт — обычный GDScript (extends RefCounted), игра вызывает в нём apply(gun, rng).
static func script_instance(mod_root: String, rel: String) -> Object:
	if rel == "":
		return null
	var path := rel if rel.begins_with("res://") else mod_root.path_join(rel)
	if _scripts.has(path):
		return _scripts[path]
	var inst: Object = null
	if FileAccess.file_exists(path):
		var s := GDScript.new()
		s.source_code = FileAccess.get_file_as_string(path)
		if s.reload() == OK:
			inst = s.new()
		else:
			push_warning("Mods: скрипт %s не собрался" % path)
	else:
		push_warning("Mods: нет скрипта %s" % path)
	_scripts[path] = inst
	return inst


## Вызвать apply(gun, rng) у скрипта записи (перк/марка/легендарка), если он указан.
static func run_entry_script(entry: Dictionary, g: Gun, rng: RandomNumberGenerator) -> void:
	var rel := str(entry.get("script", ""))
	if rel == "":
		return
	var inst := script_instance(str(entry.get("_root", "res://")), rel)
	if inst != null and inst.has_method("apply"):
		inst.call("apply", g, rng)


static func clear_cache() -> void:
	_scripts.clear()
