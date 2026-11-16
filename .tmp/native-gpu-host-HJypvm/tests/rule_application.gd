extends SceneTree
## Full application replay: frozen JS fixtures -> real controller/session -> memory repository.
## Rendering/audio/file I/O are replaced; rules, coordination, HUD decisions and save assembly remain real.
const Session = preload("res://application/game_session.gd")
const Command = preload("res://contracts/game_command.gd")
const Router = preload("res://application/input_router.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const Repository = preload("res://services/save_repository.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")

class Harness:
	extends "res://application/main.gd"
	func _ready() -> void:
		pass

class QuietView:
	extends Node2D
	var hint_visible: bool = false
	var overview: bool = false
	var current_world: RefCounted
	var motion_calls: int = 0
	var clear_calls: int = 0
	func clear_motion(_smooth_stop: bool = true) -> void:
		clear_calls += 1
	func set_motion(_before: Dictionary, _after: Dictionary, _progress: float, _kind: String) -> void:
		motion_calls += 1
	func set_world(value: RefCounted) -> void:
		current_world = value
	func set_layout(_rect: Rect2) -> void:
		pass
	func set_paused(_value: bool) -> void:
		pass
	func set_settings(_value: Dictionary) -> void:
		pass
	func set_visual_time(_value: float) -> void:
		pass
	func resume_visual_time() -> void:
		pass

class QuietAudio:
	extends Node
	var events: Array = []
	var starts: int = 0
	func start() -> void:
		starts += 1
	func play(kind: String) -> void:
		events.append(kind)
	func pause(_value: bool) -> void:
		pass
	func configure(_value: Dictionary) -> void:
		pass

class MemoryRepository:
	extends "res://services/save_repository.gd"
	var commits: int = 0
	var fail_writes: bool = false
	var persisted: Dictionary = {}
	func persist(candidate: Dictionary = {}) -> Dictionary:
		commits += 1
		var next: Dictionary = data.duplicate(true) if candidate.is_empty() else candidate.duplicate(true)
		var checked: Dictionary = _validate_store(next)
		if not checked.ok: return checked
		if fail_writes: return {"ok": false, "error": "injected_write_failure"}
		persisted = JSON.parse_string(JSON.stringify(next))
		data = next
		return {"ok": true, "data": data.duplicate(true)}

class QuietHUD:
	extends Control
	signal command_requested(id: String)
	var ending_visible: bool = false
	var ended_count: int = 0
	var last_journey: Dictionary = {}
	var locked: bool = false
	func update_state(_world: RefCounted, value: bool, _message: String) -> void:
		locked = value
	func set_action_label(_id: String, _label: String) -> void:
		pass
	func set_message(_message: String) -> void:
		pass
	func set_journey(value: Dictionary) -> void:
		last_journey = value
	func set_overview(_value: bool) -> void:
		pass
	func set_action_feedback(_primary: String, _states: Dictionary) -> void:
		pass
	func safe_world_rect() -> Rect2:
		return Rect2()
	func show_ending(_level: Dictionary, _snapshot: Dictionary) -> void:
		ending_visible = true
		ended_count += 1
		command_requested.emit("pause")
	func close_overlay() -> void:
		ending_visible = false
		command_requested.emit("resume")
	func show_settings(_settings: Dictionary) -> void:
		command_requested.emit("pause")
	func show_menu(_levels: Array, _progress: Dictionary) -> void:
		command_requested.emit("pause")
	func show_journal(_levels: Array, _progress: Dictionary) -> void:
		command_requested.emit("pause")

var _checks: int = 0
var _commands: int = 0
var _cases: int = 0
var _failures: Array = []
var _levels: Array
var _reference: Dictionary
var _logger = ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(_logger)
	call_deferred("_run")

func _app(id: String = "1-1", saved: Dictionary = {}, low_motion: bool = false) -> Node:
	var app = Harness.new()
	app.levels = _levels
	app.session = Session.new(id, saved)
	app.view = QuietView.new()
	app.hud = QuietHUD.new()
	app.audio = QuietAudio.new()
	app.repository = MemoryRepository.new()
	app.repository.configure_levels(_levels)
	app.repository.snapshot_validator = app._normalize_snapshot
	app.input_router = Router.new()
	app.settings = Repository.default_settings()
	app.settings.lowMotion = low_motion
	app.add_child(app.view)
	app.add_child(app.hud)
	app.add_child(app.audio)
	app.hud.command_requested.connect(app._on_command)
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	return app

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error(label)

func _same(expected: Variant, actual: Variant, label: String) -> void:
	_check(_equal(expected, actual), label)

func _canonical(value: Variant, field: String = "") -> Variant:
	if field == "trial" and value is String:
		return _canonical(JSON.parse_string(value))
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[key] = _canonical(value[key], str(key))
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_canonical(item))
		return result
	return value

func _equal(expected: Variant, actual: Variant) -> bool:
	# The old JS and Godot serialize trial's nested object keys differently.
	# Decode that one schema field; all numeric values, types and array order stay exact.
	return Snapshot.equivalent(_canonical(expected), _canonical(actual))

func _drain(app: Node, label: String, frames: int = 40) -> void:
	for unused: int in range(frames):
		if app.motion.is_empty() and app.route.is_empty() and not app.waiting_repair: break
		app._process(0.05)
	_check(app.motion.is_empty() and app.route.is_empty() and not app.waiting_repair, label + "/animation-and-route-finish")

func _fixture(name: String) -> Dictionary:
	for entry: Dictionary in _reference.cases:
		if entry.name == name: return entry
	return {}

func _restore(app: Node) -> Node:
	return _app(str(app.session.world.level.id), JSON.parse_string(JSON.stringify(app.session.world.snapshot())), bool(app.settings.lowMotion))

func _replay(entry: Dictionary, low_motion: bool) -> void:
	var app: Node = _app(str(entry.levelId), entry.get("saved", {}), low_motion)
	var prefix: String = str(entry.name) + ("/low-motion" if low_motion else "/animated")
	_same(entry.initial.snapshot, app.session.world.snapshot(), prefix + "/initial")
	for index: int in range(entry.steps.size()):
		if not _failures.is_empty(): break
		var step: Dictionary = entry.steps[index]
		var before: Dictionary = app.session.world.snapshot()
		var writes: int = app.repository.commits
		var revision: int = app.session.revision
		var kind: String = str(step.command.kind)
		var value: String = str(step.command.value)
		var label: String = "%s/%d/%s/%s" % [prefix, index, kind, value]
		if kind == "move": app._execute(Command.move_to(value), "move")
		elif kind == "act": app._on_command(value)
		else:
			_check(false, label + "/unexpected-fixture-command")
			break
		if not app.motion.is_empty():
			_same(before, app.session.world.snapshot(), label + "/pending-does-not-mutate-rules")
			_check(app.repository.commits == writes, label + "/pending-does-not-save")
			_check(app.session.revision == revision, label + "/pending-does-not-advance-revision")
		_drain(app, label)
		_same(step.snapshot, app.session.world.snapshot(), label + "/JS-oracle")
		var changed: bool = not _equal(before, step.snapshot)
		_check(app.repository.commits == writes + (1 if changed else 0), label + "/exactly-one-save-per-change")
		_check(app.session.revision == revision + (1 if changed else 0), label + "/exactly-one-rule-revision-per-change")
		if changed:
			_same(step.snapshot, app.repository.persisted.mainline.runs[entry.levelId], label + "/persisted-state")
		var restored: Node = _restore(app)
		_same(step.snapshot, restored.session.world.snapshot(), label + "/real-JSON-reload")
		_check(not restored.session.world.can_undo(), label + "/reload-has-no-session-history")
		restored.free()
		_commands += 1
	if not _failures.is_empty():
		app.free()
		_cases += 1
		return
	_check(app.session.world.state.completed, prefix + "/explicit-planting-completes")
	_check(app.hud.ending_visible and app.paused, prefix + "/completion-modal-pauses-input")
	_check(app.hud.ended_count == 1, prefix + "/completion-modal-once")
	if str(entry.name).begins_with("all-collections/"):
		var record: Dictionary = app.repository.data.mainline.records[entry.levelId]
		_check(record.collected == app.session.world.level.total and record.stars == 3, prefix + "/full-collection-record")
	var saved_completion: Dictionary = app.repository.data.mainline.memories[entry.levelId].duplicate(true)
	app.hud.close_overlay()
	app._on_command("stay")
	var choices: Array = app.session.world.neighbors(str(app.session.world.point().id))
	if not choices.is_empty():
		app._execute(Command.move_to(str(choices[0].id)), "move")
		_drain(app, prefix + "/completed-stroll")
	_same(saved_completion, app.repository.data.mainline.memories[entry.levelId], prefix + "/stroll-preserves-completion-memory")
	var stroll: Dictionary = app.session.world.snapshot()
	app._on_command("undo")
	_same(stroll, app.session.world.snapshot(), prefix + "/completed-stroll-rejects-undo")
	app.free()
	_cases += 1

func _specials() -> void:
	var app: Node = _app()
	var initial: Dictionary = app.session.world.snapshot()
	app._execute(Command.move_to("f:-1:0"), "move")
	app._on_command("pause")
	for unused: int in range(30): app._process(0.05)
	_same(initial, app.session.world.snapshot(), "pause/pending-command-not-committed")
	_check(app.repository.commits == 0, "pause/no-save-during-paused-animation")
	app._on_command("resume")
	_drain(app, "pause/resume")
	_check(app.repository.commits == 1, "pause/resume-commits-once")
	app._execute(Command.move_to("f:0:0"), "move")
	app._enter_level("1-3")
	_check(app.motion.is_empty() and app.session.world.level.id == "1-3", "scene-change/discards-pending-old-command")
	_check(app.repository.commits == 1, "scene-change/does-not-save-abandoned-preview")
	app.free()

	app = _app()
	var completed: Dictionary = _fixture("authored/1-1").steps.back().snapshot
	app.repository.stage_run(completed)
	app._enter_level("1-1")
	_same(_fixture("authored/1-1").initial.snapshot, app.session.world.snapshot(), "replay/normal-entry-restarts-a-completed-run")
	_same(completed, app.repository.data.mainline.memories["1-1"], "replay/normal-entry-preserves-completion-memory")
	app._execute(Command.move_to("f:-1:0"), "move")
	_drain(app, "replay/active-run")
	var active_run: Dictionary = app.repository.data.mainline.runs["1-1"].duplicate(true)
	app._on_command("review:1-1")
	_check(app.reviewing and app.session.world.state.completed, "replay/review-loads-the-completed-memory")
	app.hud.close_overlay()
	app._on_command("stay")
	app._execute(Command.move_to("f:2:0"), "move")
	_drain(app, "replay/review-stroll")
	_same(active_run, app.repository.data.mainline.runs["1-1"], "replay/review-does-not-overwrite-active-run")
	_same(completed, app.repository.data.mainline.memories["1-1"], "replay/review-does-not-overwrite-completion-memory")
	app.free()

	app = _app()
	app.repository.fail_writes = true
	app._execute(Command.move_to("f:-1:0"), "move")
	_drain(app, "storage/first-failure")
	_check(not app.storage_ready, "storage/write-failure-enters-memory-mode")
	app._execute(Command.move_to("f:0:0"), "move")
	_drain(app, "storage/continue-in-memory")
	var exported: Dictionary = JSON.parse_string(app.repository.export_json())
	_same(app.session.world.snapshot(), exported.mainline.runs["1-1"], "storage/export-includes-progress-after-write-failure")
	_check(app.repository.commits == 1, "storage/failure-does-not-repeat-filesystem-writes")
	app.free()

	app = _app("2-3")
	app._on_command("play")
	_check(app.session.world.state.playing and app.motion.is_empty(), "song/play-is-immediate")
	app._on_command("jump")
	_check(app.motion.is_empty(), "song/jump-cannot-interrupt-playing")
	var playing: Dictionary = app.session.world.snapshot()
	app._step("up")
	_same(playing, app.session.world.snapshot(), "song/walking-rejected-during-playback")
	for unused: int in range(13): app._process(0.05)
	_check(not app.motion.is_empty(), "song/automatic-clock-prepares-first-beat")
	_drain(app, "song/first-auto-beat")
	_check(app.session.world.state.beat == 1, "song/automatic-beat-commits-once")
	app._on_command("play")
	_check(not app.session.world.state.playing, "song/play-toggles-pause")
	app._on_command("switch")
	_check(app.session.world.actor() == "buddy", "song/switch-is-immediate-and-keeps-trial")
	app._on_command("resetSong")
	_drain(app, "song/remote-reset")
	_check(app.session.world.state.beat == 0 and not app.session.world.state.playing, "song/reset-from-other-actor-restores-stable-state")
	app.free()

	app = _app()
	app._go("f:-2:-1")
	app._on_command("jump")
	_check(app.route.is_empty(), "jump/clears-previous-mouse-route")
	_drain(app, "jump/route-cancel")
	app.free()

	app = _app()
	var key := InputEventKey.new()
	key.keycode = KEY_LEFT
	key.physical_keycode = KEY_LEFT
	key.pressed = true
	app._input(key)
	_drain(app, "keyboard/first-step")
	var after_key: Dictionary = app.session.world.snapshot()
	key.echo = true
	app._input(key)
	_same(after_key, app.session.world.snapshot(), "keyboard/reference-mode-ignores-key-repeat")
	key.echo = false
	key.pressed = false
	app._input(key)
	app.free()

	app = _app()
	app.comfort_mode = true
	app.input_router.continuous = true
	key.pressed = true
	app._input(key)
	for unused: int in range(14): app._process(0.05)
	key.pressed = false
	app._input(key)
	_drain(app, "keyboard/comfort-release")
	var released: Dictionary = app.session.world.snapshot()
	for unused: int in range(20): app._process(0.05)
	_same(released, app.session.world.snapshot(), "keyboard/comfort-release-clears-held-direction")
	_check(app.session.world.state.actors.luvie == "f:-2:0", "keyboard/comfort-hold-can-traverse-two-valid-tiles")
	app.free()

func _run() -> void:
	_reference = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	_levels = content.levels
	for entry: Dictionary in _reference.cases:
		if not (str(entry.name).begins_with("authored/") or str(entry.name).begins_with("all-collections/")): continue
		for low_motion: bool in [false, true]:
			_replay(entry, low_motion)
			if not _failures.is_empty(): break
		if not _failures.is_empty(): break
	if _failures.is_empty(): _specials()
	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite": "garden-application-replay", "passed": _failures.is_empty(), "cases": _cases, "commands": _commands, "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)
