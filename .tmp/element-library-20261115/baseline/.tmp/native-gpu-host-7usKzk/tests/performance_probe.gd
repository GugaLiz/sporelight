extends SceneTree
## Native CPU probe only: no renderer, audio, browser QA or disk persistence.
## Inclusive nested timings overlap. Never add fork+restore or prepare+fork together.
const World = preload("res://core/garden_world.gd")
const Command = preload("res://contracts/game_command.gd")
const Router = preload("res://application/input_router.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const AppSuite = preload("res://tests/rule_application.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")

class Counts:
	extends RefCounted
	static var values: Dictionary = {}
	static func add(key: String, elapsed: int) -> void:
		var value: Dictionary = values.get(key, {"calls": 0, "usec": 0})
		value.calls += 1
		value.usec += elapsed
		values[key] = value
	static func reset() -> void:
		values = {}
	static func report(samples: int) -> Dictionary:
		var result: Dictionary = {}
		for key: String in values:
			result[key] = {"callsPerSample": float(values[key].calls) / samples, "inclusiveMsPerSample": float(values[key].usec) / samples / 1000.0}
		return result

class TrackedWorld:
	extends "res://core/garden_world.gd"
	func tiles() -> Array:
		var start: int = Time.get_ticks_usec()
		var result: Array = super.tiles()
		Counts.add("world.tiles", Time.get_ticks_usec() - start)
		return result
	func commands() -> Array:
		var start: int = Time.get_ticks_usec()
		var result: Array = super.commands()
		Counts.add("world.commands", Time.get_ticks_usec() - start)
		return result
	func act(id: String, quiet: bool = false) -> Dictionary:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = super.act(id, quiet)
		Counts.add("world.act", Time.get_ticks_usec() - start)
		return result
	func _transaction(change: Callable) -> Dictionary:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = super._transaction(change)
		Counts.add("world.transaction", Time.get_ticks_usec() - start)
		return result
	func fork(saved: Dictionary) -> RefCounted:
		var start: int = Time.get_ticks_usec()
		var result: RefCounted = super.fork(saved)
		Counts.add("world.fork", Time.get_ticks_usec() - start)
		return result
	func _restore(saved: Dictionary, initial: Dictionary) -> bool:
		var start: int = Time.get_ticks_usec()
		var result: bool = super._restore(saved, initial)
		Counts.add("world._restore", Time.get_ticks_usec() - start)
		return result

class TrackedSession:
	extends "res://application/game_session.gd"
	func _init(id: String = "1-1", saved: Dictionary = {}) -> void:
		super(id, saved)
		world = TrackedWorld.new(id, saved)
	func prepare(command: GardenCommand) -> GardenCommandResult:
		var start: int = Time.get_ticks_usec()
		var result: GardenCommandResult = super.prepare(command)
		Counts.add("session.prepare", Time.get_ticks_usec() - start)
		return result
	func commit(prepared: GardenCommandResult) -> GardenCommandResult:
		var start: int = Time.get_ticks_usec()
		var result: GardenCommandResult = super.commit(prepared)
		Counts.add("session.commit", Time.get_ticks_usec() - start)
		return result

class Harness:
	extends "res://application/main.gd"
	func _ready() -> void:
		pass
	func _command_states() -> Dictionary:
		var hit: bool = _command_cache_session == session.get_instance_id() and _command_cache_revision == session.revision
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = super._command_states()
		Counts.add("main.command_states.hit" if hit else "main.command_states.miss", Time.get_ticks_usec() - start)
		return result
	func _normalize_snapshot(saved: Dictionary) -> Dictionary:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = super._normalize_snapshot(saved)
		Counts.add("main.normalize_snapshot", Time.get_ticks_usec() - start)
		return result

var _logger = ErrorLogger.new()
var _levels: Array = []
var _samples: int = 100
var _report: Dictionary = {}
var _failures: Array = []

func _initialize() -> void:
	OS.add_logger(_logger)
	call_deferred("_run")

func _stats(durations: Array) -> Dictionary:
	var ordered: Array = durations.duplicate()
	ordered.sort()
	var total: float = 0.0
	for value: float in durations: total += value
	return {"samples": durations.size(), "meanMs": total / durations.size() / 1000.0,
		"p50Ms": float(ordered[int(floor((ordered.size() - 1) * 0.50))]) / 1000.0,
		"p95Ms": float(ordered[int(ceil((ordered.size() - 1) * 0.95))]) / 1000.0,
		"maxMs": float(ordered.back()) / 1000.0}

func _measure(label: String, operation: Callable) -> Dictionary:
	for i: int in range(15): operation.call(i)
	Counts.reset()
	var durations: Array = []
	for i: int in range(_samples):
		var start: int = Time.get_ticks_usec()
		operation.call(i)
		durations.append(Time.get_ticks_usec() - start)
	var result: Dictionary = _stats(durations)
	result.inclusiveProfile = Counts.report(_samples)
	_report.measurements[label] = result
	return result

func _app(transition: Dictionary, warm_cache: bool) -> Node:
	var app = Harness.new()
	app.levels = _levels
	app.session = TrackedSession.new(str(transition.before.levelId), transition.before)
	app.view = AppSuite.QuietView.new()
	app.hud = AppSuite.QuietHUD.new()
	app.audio = AppSuite.QuietAudio.new()
	app.repository = AppSuite.MemoryRepository.new()
	app.repository.configure_levels(_levels)
	app.repository.snapshot_validator = app._normalize_snapshot
	app.input_router = Router.new()
	app.settings = {"lowMotion": false}
	app.add_child(app.view)
	app.add_child(app.hud)
	app.add_child(app.audio)
	app.hud.command_requested.connect(app._on_command)
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	if warm_cache: app._sync_hud()
	return app

func _controller_measure(id: String, transitions: Array, warm_cache: bool) -> void:
	var durations: Array = []
	var cumulative: Dictionary = {}
	for i: int in range(_samples + 10):
		var transition: Dictionary = transitions[i % transitions.size()]
		var app: Node = _app(transition, warm_cache)
		Counts.reset()
		var start: int = Time.get_ticks_usec()
		app._execute(Command.move_to(str(transition.target)), "move")
		for unused: int in range(5): app._process(0.05)
		var elapsed: int = Time.get_ticks_usec() - start
		if not Snapshot.equivalent(app.session.world.snapshot(), transition.after):
			_failures.append(id + "/controller probe changed rules")
		if app.repository.commits != 1 or app.session.revision != 1:
			_failures.append(id + "/controller probe commit count")
		if i >= 10:
			durations.append(elapsed)
			for key: String in Counts.values:
				var total: Dictionary = cumulative.get(key, {"calls": 0, "usec": 0})
				total.calls += Counts.values[key].calls
				total.usec += Counts.values[key].usec
				cumulative[key] = total
		app.free()
	Counts.values = cumulative
	var result: Dictionary = _stats(durations)
	result.inclusiveProfile = Counts.report(_samples)
	result.initialCommandCache = "warm (normal consecutive walk)" if warm_cache else "cold"
	result.excludes = ["renderer/presentation forks", "real HUD drawing", "file I/O", "browser/WebAssembly cost"]
	result.persistence = "real stage_run and validation, memory persist (one extra store validation and JSON roundtrip)"
	_report.measurements[id + "/controller-step-" + ("warm" if warm_cache else "cold")] = result

func _run() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--samples="): _samples = maxi(10, int(arg.trim_prefix("--samples=")))
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	_levels = content.levels
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	_report = {"probe": "native-rule-copy-validation", "engine": Engine.get_version_info().string,
		"processor": OS.get_processor_name(), "cpuCount": OS.get_processor_count(),
		"referenceCommit": fixture.referenceCommit, "measurements": {}, "fixturePositions": {}, "notes": [
			"Microsecond wall-clock CPU measurements on native GDScript, not Chrome frame timing.",
			"Nested inclusive profiles overlap: restore is inside fork, fork is inside prepare/command_states.",
			"Only test subclasses count calls; normalize_snapshot is timed as a whole because its internal validator uses the production World class.",
			"Every controller sample starts from a real authored move fixture; setup occurs outside timing, and expected outcome/single commit are checked.",
			"Warm command cache models normal walking; cold cache is reported separately to avoid exaggerating feedback probing.",
			"No GPU, browser, audio or disk I/O is present; this cannot prove a 60FPS budget or directly quantify a Web frame's percentage."
		]}
	for id: String in ["1-1", "2-2"]:
		var entry: Dictionary = {}
		for candidate: Dictionary in fixture.cases:
			if candidate.name == "authored/" + id: entry = candidate
		var transitions: Array = []
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if step.command.kind == "move" and transitions.size() < 6:
				transitions.append({"before": before, "target": step.command.value, "after": step.snapshot})
			before = step.snapshot
		var worlds: Array = []
		var fresh: Array = []
		var sessions: Array = []
		var apps: Array = []
		var descriptions: Array = []
		for transition: Dictionary in transitions:
			worlds.append(TrackedWorld.new(id, transition.before))
			fresh.append(TrackedWorld.new(id))
			sessions.append(TrackedSession.new(id, transition.before))
			apps.append(_app(transition, false))
			descriptions.append({"tile": transition.before.actors.luvie, "target": transition.target, "commandCount": worlds.back().commands().size()})
		_report.fixturePositions[id] = descriptions
		_measure(id + "/new-world-without-save", func(i: int) -> void:
			var unused: RefCounted = TrackedWorld.new(id))
		_measure(id + "/restore-existing-world", func(i: int) -> void:
			var n: int = i % transitions.size()
			fresh[n]._restore(transitions[n].before, fresh[n].snapshot()))
		_measure(id + "/fork-saved-state", func(i: int) -> void:
			var n: int = i % transitions.size()
			var unused: RefCounted = worlds[n].fork(transitions[n].before))
		_measure(id + "/prepare-move", func(i: int) -> void:
			var n: int = i % transitions.size()
			sessions[n].prepare(Command.move_to(str(transitions[n].target))))
		_measure(id + "/available-command-list", func(i: int) -> void:
			worlds[i % worlds.size()].commands())
		_measure(id + "/command-cache-miss", func(i: int) -> void:
			var n: int = i % transitions.size()
			apps[n].session.revision += 1
			apps[n]._command_states())
		for app: Node in apps: app._command_states()
		_measure(id + "/command-cache-hit", func(i: int) -> void:
			apps[i % apps.size()]._command_states())
		_measure(id + "/normalize-valid-state", func(i: int) -> void:
			var n: int = i % transitions.size()
			apps[n]._normalize_snapshot(transitions[n].before))
		_controller_measure(id, transitions, true)
		_controller_measure(id, transitions, false)
		for app: Node in apps: app.free()
	_failures.append_array(_logger.captured_errors())
	_report.failures = _failures
	_report.completedWithoutErrors = _failures.is_empty()
	if not output.is_empty():
		var absolute: String = ProjectSettings.globalize_path(output)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var file: FileAccess = FileAccess.open(absolute, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_report, "\t"))
			file.close()
		else:
			_failures.append("Could not write probe report")
	print(JSON.stringify(_report))
	quit(0 if _failures.is_empty() else 1)
