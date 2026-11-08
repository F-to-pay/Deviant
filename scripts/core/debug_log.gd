class_name DebugLog
extends RefCounted
## Журнал для отладчика модов: предупреждения загрузчика, проверки данных, ошибки скриптов модов.
## Пишется всегда (это дёшево), а показывается консолью (F8), только если отладчик включён
## в меню «Моды» (настройка mod_debug, применяется после перезапуска).
## Одинаковые сообщения не копятся — у записи растёт счётчик.
## Сообщения движка (ошибки скриптов модов, push_warning, print) берутся из файла журнала Godot
## (user://logs/godot.log, на ПК пишется по умолчанию): poll_engine_log() дочитывает новые строки.
## На всякий случай add() потокобезопасна — мьютекс.

const MAX := 2000

static var enabled := false          # отладчик включён (на этот запуск)
static var logger_active := false    # журнал движка читается — push_warning из warn()/error() вернётся оттуда
static var _log_path := ""           # файл журнала Godot
static var _log_pos := 0             # сколько байт уже прочитано
static var _pending := {}            # запись, ждущая строки "at: ..." с местом ошибки
static var entries: Array = []       # [{level, text, src, n}]
static var version := 0              # растёт при каждом изменении — консоль перерисовывается
static var warns := 0
static var errors := 0
static var missing_tr := {}          # язык -> {строка: true} — строки без перевода, встреченные в игре
static var _index := {}              # level|text|src -> запись
static var _mx := Mutex.new()


static func add(level: String, text: String, src: String = "") -> void:
	_mx.lock()
	var key := level + "|" + text + "|" + src
	if _index.has(key):
		_index[key]["n"] += 1
	else:
		var e := {"level": level, "text": text, "src": src, "n": 1}
		entries.append(e)
		_index[key] = e
		if level == "warn":
			warns += 1
		elif level == "error":
			errors += 1
		if entries.size() > MAX:
			var old: Dictionary = entries.pop_front()
			_index.erase(str(old["level"]) + "|" + str(old["text"]) + "|" + str(old["src"]))
	version += 1
	_mx.unlock()


static func info(text: String, src: String = "") -> void:
	add("info", text, src)


## Предупреждение: в журнал и (если Logger движка не установлен) в консоль Godot.
static func warn(text: String, src: String = "") -> void:
	add("warn", text, src)
	if not logger_active:
		push_warning(("[%s] " % src if src != "" else "") + text)


static func error(text: String, src: String = "") -> void:
	add("error", text, src)
	if not logger_active:
		push_error(("[%s] " % src if src != "" else "") + text)


## Строка без перевода (вызывается из I18n, только при включённом отладчике).
static func missing(lang: String, s: String) -> void:
	_mx.lock()
	if not missing_tr.has(lang):
		missing_tr[lang] = {}
	var d: Dictionary = missing_tr[lang]
	var fresh := not d.has(s)
	d[s] = true
	_mx.unlock()
	if fresh:
		add("tr", "[%s] no translation: \"%s\"" % [lang, s], "i18n")


static func clear() -> void:
	_mx.lock()
	entries.clear()
	_index.clear()
	warns = 0
	errors = 0
	version += 1
	_mx.unlock()


# --- Журнал движка ------------------------------------------------------------------

## Начать читать файл журнала Godot (если он ведётся). Читаем с начала — ошибки запуска тоже нужны.
static func start_engine_log() -> void:
	if not bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging", false)) and \
			not bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging.pc", false)):
		info("Godot file logging is off — engine errors are not captured", "debug")
		return
	_log_path = str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	_log_pos = 0
	logger_active = true


## Дочитать новые целые строки журнала и разобрать. Зовётся консолью несколько раз в секунду.
static func poll_engine_log() -> void:
	if _log_path == "":
		return
	var f := FileAccess.open(_log_path, FileAccess.READ)
	if f == null:
		return
	var n := f.get_length()
	if n < _log_pos:          # файл начат заново
		_log_pos = 0
	if n <= _log_pos:
		_flush_pending()
		return
	f.seek(_log_pos)
	var buf := f.get_buffer(mini(n - _log_pos, 1 << 20))
	f.close()
	var cut := buf.rfind(10)  # только до последнего перевода строки
	if cut < 0:
		return
	_log_pos += cut + 1
	for line in buf.slice(0, cut).get_string_from_utf8().split("\n"):
		_engine_line(line.trim_suffix("\r"))
	_flush_pending()


## Строка журнала Godot: "ERROR: ...", "WARNING: ...", "SCRIPT ERROR: ...", "USER WARNING: ...",
## за ней — "   at: функция (файл:строка)". Остальное — print().
static func _engine_line(line: String) -> void:
	var t := line.strip_edges()
	if t == "":
		return
	if t.begins_with("at: "):
		if not _pending.is_empty():
			_pending["at"] = t.substr(4)
			_flush_pending()
		return
	var bt := t.length() > 1 and t[0] == "[" and t[1].is_valid_int()   # строки бэктрейса "[0] ..."
	if bt or t.begins_with("GDScript backtrace") or line.begins_with("Godot Engine v") \
			or t.begins_with("Vulkan ") or t.begins_with("OpenGL "):
		return
	_flush_pending()
	for p in [["SCRIPT ERROR: ", "error"], ["USER ERROR: ", "error"], ["ERROR: ", "error"],
			["SCRIPT WARNING: ", "warn"], ["USER WARNING: ", "warn"], ["WARNING: ", "warn"]]:
		if t.begins_with(str(p[0])):
			_pending = {"level": str(p[1]), "text": t.substr(str(p[0]).length()), "at": ""}
			return
	add("print", t, "engine")


static func _flush_pending() -> void:
	if _pending.is_empty():
		return
	var e := _pending
	_pending = {}
	var at := str(e["at"])
	# предупреждения по скриптам самой игры (не модов) — не дело моддера, за ними не видно главного
	if e["level"] == "warn" and at.contains("res://") and not at.contains("/Mods/"):
		return
	var where := ""
	var o := at.rfind("(")
	if o >= 0:
		where = "  (" + at.substr(o + 1).trim_suffix(")").get_file() + ")"
	add(str(e["level"]), str(e["text"]) + where, "engine")


## Копия записей для отрисовки (без гонок с другими потоками).
static func snapshot() -> Array:
	_mx.lock()
	var out := entries.duplicate()
	_mx.unlock()
	return out
