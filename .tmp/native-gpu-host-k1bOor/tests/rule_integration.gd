extends SceneTree
## Controller/session regression checks. No real user files or audio devices are used.
const Session = preload("res://application/game_session.gd")
const Command = preload("res://contracts/game_command.gd")
const Router = preload("res://application/input_router.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")

class Harness:
	extends "res://application/main.gd"
	func _ready() -> void:
		pass

class QuietView:
	extends Node2D
	var hint_visible: bool = false
	var overview: bool = false
	func clear_motion(_smooth_stop: bool = true) -> void:
		pass
	func set_motion(_before: Dictionary, _after: Dictionary, _progress: float, _kind: String) -> void:
		pass
	func set_layout(_rect: Rect2) -> void:
		pass
	func set_paused(_value: bool) -> void:
		pass

class QuietAudio:
	extends Node
	func start() -> void:
		pass
	func play(_kind: String) -> void:
		pass
	func pause(_value: bool) -> void:
		pass

class MemoryStore:
	extends RefCounted
	var commits: int = 0
	var latest: Dictionary = {}
	func commit_run(value: Dictionary) -> Dictionary:
		commits += 1
		latest = value.duplicate(true)
		return {"ok": true}

class QuietHUD:
	extends Control
	signal command_requested(id: String)
	var ending_visible: bool = false
	var action_labels: Dictionary = {}
	func update_state(_world: RefCounted, _locked: bool, _message: String) -> void:
		pass
	func set_action_label(id: String, label: String) -> void:
		action_labels[id] = label
	func set_message(_message: String) -> void:
		pass
	func set_journey(_value: Dictionary) -> void:
		pass
	func set_overview(_value: bool) -> void:
		pass
	func set_action_feedback(_primary: String, _states: Dictionary) -> void:
		pass
	func safe_world_rect() -> Rect2:
		return Rect2()
	func show_ending(_level: Dictionary, _snapshot: Dictionary) -> void:
		ending_visible = true
		command_requested.emit("pause")
	func close_overlay() -> void:
		ending_visible = false
		command_requested.emit("resume")

var _checks: int = 0
var _failures: Array = []
var _logger = ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(_logger)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error(label)

func _app(id: String = "1-1", saved: Dictionary = {}) -> Node:
	var app = Harness.new()
	app.session = Session.new(id, saved)
	app.view = QuietView.new()
	app.hud = QuietHUD.new()
	app.audio = QuietAudio.new()
	app.repository = MemoryStore.new()
	app.input_router = Router.new()
	app.settings = {"lowMotion": false}
	app.add_child(app.view)
	app.add_child(app.hud)
	app.add_child(app.audio)
	app.hud.command_requested.connect(app._on_command)
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	return app

func _completed(id: String) -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if entry.name == "authored/" + id:
			return entry.steps.back().snapshot
	return {}

func _advance(app: Node, frames: int) -> void:
	for unused: int in range(frames): app._process(0.05)

func _walk(app: Node, target: String) -> void:
	for id: String in app.session.world.path_to(target):
		app._execute(Command.move_to(id), "move")
		_advance(app, 6)

func _hint_and_mode_tests() -> void:
	var app: Node = _app("1-3")
	app._on_command("hint")
	_check(app.view.hint_visible, "Normal hint is visible immediately")
	_advance(app, 238)
	_check(app.view.hint_visible, "Normal hint remains visible before twelve seconds")
	var remaining: float = app._hint_remaining
	app._on_command("pause")
	_advance(app, 400)
	_check(app._hint_remaining == remaining and app.view.hint_visible, "Pausing does not consume the hint duration")
	app._on_command("resume")
	_advance(app, 4)
	_check(not app.view.hint_visible, "Normal hint expires after twelve active seconds")
	app._on_command("mode")
	_check(app.rolling and app.hud.action_labels.get("mode") == "滚动中", "Rolling mode immediately updates its button label")
	app._on_command("mode")
	_check(not app.rolling and app.hud.action_labels.get("mode") == "行走", "Walking mode immediately updates its button label")
	app.free()

	app = _app("2-2")
	app._on_command("hint")
	_advance(app, 241)
	_check(app.view.hint_visible, "Mirror guidance remains visible beyond the normal twelve-second duration")
	_advance(app, 160)
	_check(not app.view.hint_visible, "Mirror guidance expires after twenty active seconds")
	app.free()

	app = _app("1-2")
	_walk(app, "f:1:1")
	for direction: String in ["up", "right", "right"]:
		app._on_command("grow:root:" + direction)
		_advance(app, 16)
	_walk(app, "f:4:1")
	var before: Dictionary = app.session.world.snapshot()
	var writes: int = app.repository.commits
	app._on_command("repair")
	_check(app.view.hint_visible and app._growth_hint, "Refused planting in 1-2 reveals persistent root guidance")
	_check(app.session.world.snapshot() == before and app.repository.commits == writes, "Refused planting does not change or save the puzzle")
	_advance(app, 600)
	_check(app.view.hint_visible, "Incomplete-root guidance remains visible beyond thirty active seconds")
	_walk(app, "f:1:1")
	app._on_command("grow:root:down")
	_advance(app, 16)
	_check(app.session.world.connected() and not app.view.hint_visible, "Completing the root route clears persistent growth guidance")
	app.free()


func _undo_input_tests() -> void:
	var app: Node = _app()
	var initial: Dictionary = app.session.world.snapshot()
	app._execute(Command.move_to("f:-1:0"), "move")
	app._on_command("undo")
	_check(not app.motion.is_empty() and app.session.revision == 0 and app.session.world.snapshot() == initial, "Undo remains disabled while an uncommitted move is animating")
	_advance(app, 6)
	var held := InputEventKey.new()
	held.keycode = KEY_LEFT
	held.physical_keycode = KEY_LEFT
	held.pressed = true
	app.input_router.handle_key(held)
	app.input_router.buffer("up")
	app._on_command("undo")
	_check(app.input_router.held.is_empty() and app.input_router.buffered_direction.is_empty(), "Undo clears both held movement and a pending deliberate tap")
	_check(app.session.world.snapshot() == initial and app.motion.is_empty(), "Undo restores the stable state without replaying the cleared movement intent")
	app.free()

func _run() -> void:
	# The UI used to preview no-ops before committing; repeated observations must not eat Undo.
	var session = Session.new("1-1")
	var rest: Dictionary = {}
	for mark: Dictionary in session.world.level.marks:
		if mark.kind == "rest": rest = mark
	for tile: String in session.world.path_to(str(rest.tile)):
		session.apply(Command.move_to(tile))
	var before_observation: Dictionary = session.world.snapshot()
	session.apply(Command.interact("observe:" + str(rest.id)))
	var repeated = session.apply(Command.interact("observe:" + str(rest.id)))
	_check(repeated.accepted and not repeated.changed, "Repeated observation is an accepted no-op")
	session.apply(Command.undo_action())
	_check(session.world.snapshot() == before_observation, "An accepted no-op must not create an empty Undo step")

	var song = Session.new("2-3")
	song.apply(Command.interact("play"))
	song.apply(Command.interact("beat"))
	song.apply(Command.undo_action())
	_check(not song.world.state.playing, "Undo pauses rehearsal rather than resuming an earlier playing state")

	# Animation must not save a future state while the player still sees its starting pose.
	var app = _app()
	var before: Dictionary = app.session.world.snapshot()
	app._execute(Command.move_to("f:-1:0"), "move")
	_check(app.session.world.snapshot() == before, "Rules remain at the stable state until motion completes")
	_check(app.repository.commits == 0, "A pending animated command is not persisted")
	for unused: int in range(6): app._process(0.05)
	_check(app.session.world.state.actors.luvie == "f:-1:0", "Completed motion commits its intended move")
	_check(app.repository.commits == 1, "A completed animated command is persisted exactly once")
	app.free()

	var completed: Dictionary = _completed("1-2")
	var garden = _app("1-2", completed)
	garden._on_command("stay")
	# Add a valid stroll so the raw core has an Undo state while the controller must protect completion.
	garden._execute(Command.move_to("f:5:1"), "move")
	for unused: int in range(6): garden._process(0.05)
	var after_stroll: Dictionary = garden.session.world.snapshot()
	garden._on_command("undo")
	_check(garden.session.world.snapshot() == after_stroll, "Completed garden stroll cannot invoke structural/session Undo")
	garden.free()

	var ending = _app("1-2", completed)
	ending.hud.show_ending(ending.session.world.level, completed)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	ending._input(escape)
	_check(ending.hud.ending_visible or ending.strolling, "Escape cannot dismiss completion into a locked garden with no ending actions")
	ending.free()
	_hint_and_mode_tests()
	_undo_input_tests()

	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite": "garden-session-controller", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)
