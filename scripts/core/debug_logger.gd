extends Logger
## Перехват сообщений движка (Godot 4.5+) для отладчика модов: ошибки и предупреждения скриптов
## модов, push_warning/push_error и print() попадают в DebugLog.
## Грузится динамически и только при включённом отладчике (см. Game._start_debugger),
## поэтому на старых версиях Godot без класса Logger игра просто работает без перехвата.


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var lvl := "warn" if error_type == ERROR_TYPE_WARNING else "error"
	var text := rationale if rationale != "" else code
	var where := ""
	if file != "":
		where = "  (%s:%d)" % [file.get_file(), line]
	DebugLog.add(lvl, text + where, "engine")


func _log_message(message: String, error: bool) -> void:
	var m := message.strip_edges()
	if m == "":
		return
	DebugLog.add("error" if error else "print", m, "engine")
