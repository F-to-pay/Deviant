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
		DebugLog.error("JSON error in %s, line %d: %s" % [path, j.get_error_line(), j.get_error_message()], source_of(path))
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
			DebugLog.error("script failed to compile: %s" % path, source_of(path))
	else:
		DebugLog.error("script not found: %s" % path, source_of(path))
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


# --- Отладчик модов: откуда запись и проверка данных ------------------------------

## Имя мода (или "game") по пути файла или корню слоя.
static func source_of(path: String) -> String:
	if path.begins_with("res://"):
		return "game"
	for m in list:
		if path.begins_with(str(m["path"])):
			return str(m["id"])
	return "?"


static func _src(entry: Dictionary) -> String:
	return source_of(str(entry.get("_root", "res://")))


const KNOWN_TAGS := ["proc", "explosive", "heal", "no_shell"]
const KNOWN_SPECIALS := ["", "ring", "nuke10", "chaos", "expert", "singularity"]
const KNOWN_TEMPLATES := ["gun_plain", "gun_adj", "gun_nick", "gun_nick2", "gun_legendary", "type_hybrid", "elite", "rare", "boss"]


## Полная проверка загруженных данных. Пишет в DebugLog; вызывается отладчиком при старте
## и командой validate. Ничего не меняет.
static func validate() -> void:
	DebugLog.info("--- validate: mods folder %s" % root(), "mods")
	if list.is_empty():
		DebugLog.info("no mods found", "mods")
	for m in list:
		var info: Dictionary = m["info"]
		DebugLog.info("%s %s %s" % ["[on] " if bool(m["enabled"]) else "[off]", str(m["name"]),
			("v" + str(info["version"])) if info.has("version") else ""], str(m["id"]))
		if not FileAccess.file_exists(str(m["path"]).path_join("mod.json")):
			DebugLog.info("no mod.json (optional)", str(m["id"]))
	DebugLog.info("loaded: %d archetypes, %d makers, %d perks, %d legendaries, %d nicknames; languages: %s" % [
		GunData.ARCH.size(), GunData.MAKERS.size(), GunData.MODS.size(), GunData.LEGENDARIES.size(),
		GunData.NICKNAMES.size(), ", ".join(PackedStringArray(I18n.available()))], "mods")
	var banks: Dictionary = {}
	if Game.main != null and Game.main.sfx != null:
		banks = Game.main.sfx.banks
	for k in GunData.ARCH:
		var a: Dictionary = GunData.ARCH[k]
		var src := _src(a)
		for f in ["damage", "fire_rate", "mag", "reload", "speed", "lifetime"]:
			if not a.has(f):
				DebugLog.warn("archetype '%s' has no '%s' — default used" % [k, f], src)
		if not banks.is_empty() and not banks.has("guns/" + str(k)):
			DebugLog.info("archetype '%s' has no shot sounds (sfx/guns/%s/)" % [k, k], src)
		var snd: Dictionary = a.get("sound", {})
		for key in ["reload", "reload_done"]:
			if snd.has(key) and not banks.is_empty() and not banks.has(str(snd[key])):
				DebugLog.warn("archetype '%s': sound.%s '%s' — no such sound" % [k, key, str(snd[key])], src)
	for k in GunData.MAKERS:
		var mk: Dictionary = GunData.MAKERS[k]
		var src := _src(mk)
		_check_ops(mk, "maker '%s'" % k, src)
		for p in mk.get("perks", []):
			if GunData.perk(str(p)).is_empty():
				DebugLog.warn("maker '%s': unknown perk '%s'" % [k, str(p)], src)
		var pa := str(mk.get("projectile_arch", ""))
		if pa != "" and not GunData.ARCH.has(pa):
			DebugLog.warn("maker '%s': projectile_arch '%s' — no such archetype" % [k, pa], src)
	for p in GunData.MODS:
		var src := _src(p)
		var id := str(p.get("id", "?"))
		_check_ops(p, "perk '%s'" % id, src)
		for t in p.get("tags", []):
			if not (str(t) in KNOWN_TAGS):
				DebugLog.warn("perk '%s': unknown tag '%s' (known: %s)" % [id, str(t), ", ".join(PackedStringArray(KNOWN_TAGS))], src)
		for c in p.get("fits", []):
			for prob in GunOps.cond_problems(c):
				DebugLog.warn("perk '%s' fits: %s" % [id, prob], src)
	for l in GunData.LEGENDARIES:
		var src := _src(l)
		var id := str(l.get("id", "?"))
		_check_ops(l, "legendary '%s'" % id, src)
		for key in ["arch", "arch2"]:
			var a := str(l.get(key, ""))
			if a != "" and not GunData.ARCH.has(a):
				DebugLog.warn("legendary '%s': %s '%s' — no such archetype" % [id, key, a], src)
		for m in l.get("perks", []):
			if GunData.perk(str(m)).is_empty():
				DebugLog.warn("legendary '%s': unknown perk '%s'" % [id, str(m)], src)
		if not (str(l.get("special", "")) in KNOWN_SPECIALS):
			DebugLog.warn("legendary '%s': unknown special '%s' (known: %s)" % [id, str(l["special"]),
				", ".join(PackedStringArray(KNOWN_SPECIALS))], src)
	_check_translations()
	DebugLog.info("--- validate done: %d warnings, %d errors" % [DebugLog.warns, DebugLog.errors], "mods")


static func _check_ops(entry: Dictionary, what: String, src: String) -> void:
	for prob in GunOps.problems(entry.get("ops", [])):
		DebugLog.warn("%s: %s" % [what, prob], src)
	var rel := str(entry.get("script", ""))
	if rel != "":
		var inst := script_instance(str(entry.get("_root", "res://")), rel)
		if inst == null:
			DebugLog.error("%s: script '%s' not loaded" % [what, rel], src)
		elif not inst.has_method("apply"):
			DebugLog.warn("%s: script '%s' has no apply(gun, rng)" % [what, rel], src)


## Какие названия из данных не переведены в каждом языке.
static func _check_translations() -> void:
	var names: Array = []
	for k in GunData.ARCH:
		names.append(str(GunData.ARCH[k].get("name", k)))
		if GunData.ARCH[k].has("ammo_name"):
			names.append(str(GunData.ARCH[k]["ammo_name"]))
	for k in GunData.MAKERS:
		names.append(str(GunData.MAKERS[k].get("name", k)))
		names.append(str(GunData.MAKERS[k].get("motto", "")))
	for p in GunData.MODS:
		names.append(str(p.get("name", "")))
	for l in GunData.LEGENDARIES:
		names.append(str(l.get("name", "")))
		names.append(str(l.get("flavor", "")))
	names.append_array(GunData.NICKNAMES)
	for code in I18n.available():
		if code == "en":
			continue
		var st: Dictionary = I18n.langs[code]["strings"]
		var miss: Array = []
		for n in names:
			if str(n) != "" and not st.has(str(n)) and not miss.has(str(n)):
				miss.append(str(n))
		if not miss.is_empty():
			DebugLog.warn("[%s] %d data names untranslated: %s%s" % [code, miss.size(),
				", ".join(PackedStringArray(miss.slice(0, 12))), " ..." if miss.size() > 12 else ""], "i18n")
		for t in I18n.langs[code]["templates"]:
			if not (str(t) in KNOWN_TEMPLATES):
				DebugLog.warn("[%s] unknown template '%s'" % [code, str(t)], "i18n")
