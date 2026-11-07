class_name DebugLog
extends RefCounted
## Журнал для отладчика модов: предупреждения загрузчика, проверки данных, ошибки скриптов модов.
## Пишется всегда (это дёшево), а показывается консолью (F8), только если отладчик включён
## в меню «Моды» (настройка mod_debug, применяется после перезапуска).
## Одинаковые сообщения не копятся — у записи растёт счётчик.
## Может вызываться из других потоков (Logger движка) — поэтому мьютекс.

const MAX := 2000

static var enabled := false          # отладчик включён (на этот запуск)
static var logger_active := false    # движковый Logger перехватывает push_warning/ошибки
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


## Копия записей для отрисовки (без гонок с другими потоками).
static func snapshot() -> Array:
	_mx.lock()
	var out := entries.duplicate()
	_mx.unlock()
	return out
