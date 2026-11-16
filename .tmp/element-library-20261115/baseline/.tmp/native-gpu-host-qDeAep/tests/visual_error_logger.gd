extends Logger

var errors: Array[String] = []
var _mutex := Mutex.new()

func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	var message := "%s:%d %s %s" % [file, line, code, rationale]
	if not message in errors:
		errors.append(message)
	_mutex.unlock()

func captured_errors() -> Array[String]:
	_mutex.lock()
	var result: Array[String] = errors.duplicate()
	_mutex.unlock()
	return result
