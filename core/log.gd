extends Node
## Structured logging to stdout and to a per-process file under user://logs. Autoload `Log`.
##
## Every line carries the level, the current network tick, the local peer id and a module tag,
## so logs from several instances can be lined up by tick.

enum Level { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

const LEVEL_NAMES := ["TRC", "DBG", "INF", "WRN", "ERR"]

var level: int = Level.INFO
var log_path: String = ""

var _file: FileAccess
var _module_levels: Dictionary = {}
var _lines_since_flush: int = 0


func _ready() -> void:
	var dir := "user://logs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	log_path = "%s/bomba_%d.log" % [dir, OS.get_process_id()]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_warning("Log: could not open %s" % log_path)
	info("log", "Logging to %s" % ProjectSettings.globalize_path(log_path))


func set_module_level(module: String, lvl: int) -> void:
	_module_levels[module] = lvl


func trace(module: String, msg: String, args: Array = []) -> void:
	_log(Level.TRACE, module, msg, args)


func debug(module: String, msg: String, args: Array = []) -> void:
	_log(Level.DEBUG, module, msg, args)


func info(module: String, msg: String, args: Array = []) -> void:
	_log(Level.INFO, module, msg, args)


func warn(module: String, msg: String, args: Array = []) -> void:
	_log(Level.WARN, module, msg, args)


func error(module: String, msg: String, args: Array = []) -> void:
	_log(Level.ERROR, module, msg, args)


func flush() -> void:
	if _file:
		_file.flush()
	_lines_since_flush = 0


func _log(lvl: int, module: String, msg: String, args: Array) -> void:
	var min_level: int = _module_levels.get(module, level)
	if lvl < min_level:
		return
	var text := msg
	if not args.is_empty():
		text = msg % args
	var peer := 0
	if multiplayer != null and multiplayer.has_multiplayer_peer() \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer = multiplayer.get_unique_id()
	var line := "[%s][@%d][#%d][%s] %s" % [LEVEL_NAMES[lvl], NetworkTime.tick, peer, module, text]
	print(line)
	if lvl == Level.ERROR:
		push_error(text)
	if _file:
		_file.store_line(line)
		_lines_since_flush += 1
		if lvl >= Level.WARN or _lines_since_flush >= 64:
			flush()


func _exit_tree() -> void:
	flush()
