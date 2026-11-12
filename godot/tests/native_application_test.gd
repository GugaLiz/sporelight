extends SceneTree
const Main = preload("res://application/main.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Router = preload("res://application/input_router.gd")
const Repository = preload("res://services/save_repository.gd")
const Command = preload("res://contracts/game_command.gd")
var checks := 0
var failures: Array[String] = []

class Harness:
	extends "res://application/main.gd"
	func _ready() -> void:
		pass

class AudioStub:
	extends Node
	func start() -> void: pass
	func play(_kind: String) -> void: pass
	func configure(_settings: Dictionary) -> void: pass
	func pause(_value: bool) -> void: pass

class MemoryRepository:
	extends "res://services/save_repository.gd"
	func persist(candidate: Dictionary = {}) -> Dictionary:
		var value := data if candidate.is_empty() else candidate
		var validation: Dictionary = _validate_store(value)
		if validation.ok:
			data = value.duplicate(true)
		return validation

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _drain(app: Node) -> void:
	for unused in range(24):
		if app.motion.is_empty():
			break
		app._process(0.05)
		await process_frame

func _run() -> void:
	var app := Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	app.set_physics_process(false)
	app.levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	app.input_router = Router.new()
	app.repository = MemoryRepository.new()
	app.repository.configure_levels(app.levels)
	app.repository.snapshot_validator = app._normalize_snapshot
	app.audio = AudioStub.new()
	app.add_child(app.audio)
	app.settings = Repository.default_settings()
	app.view = Stage.new()
	app.add_child(app.view)
	app.hud = HUD.new()
	app.add_child(app.hud)
	app.hud.command_requested.connect(app._on_command)
	app.hud.layout_changed.connect(app._on_hud_chrome_changed)
	app.hud.set_repository(app.repository)
	app.native_enabled = true
	app._enter_level("1-1")
	_check(app.session.world.tiles().size() == 19, "current first garden retains the expanded 19-tile layout")
	_check(app._native_command_tile({"id": "repair"}).id == "f:3:-2", "flowerbed remains on the upper landing")
	var root_context: Dictionary = app._native_interaction_context()
	_check(root_context.label == "选择生长方向" and root_context.choices.size() == 2, "root presents both routes without auto-selecting")
	_check(root_context.choices[0].label == "向东生长 · 1节" and root_context.choices[1].label == "向南生长 · 1节", "root direction wording stays explicit")
	_check(is_equal_approx(app._native_action_duration("grow:root:right"), 0.68), "normal growth keeps its high-to-low reveal duration")
	_check(is_equal_approx(app._native_action_duration("retract:root"), 0.44), "retraction keeps its transaction duration")
	_check(is_equal_approx(app._native_action_duration("repair"), 0.75), "planting completion retains its action duration")
	# Simulate a container whose old minimum height outlives initial text layout.
	# Let real deferred container signals settle without any movement/HUD refresh.
	app.hud._heading.custom_minimum_size.y = 140
	await process_frame
	await process_frame
	app.hud._heading.custom_minimum_size.y = 0
	for unused in range(5):
		await process_frame
	_check(app.hud._heading.size.y < 140, "HUD releases a stale minimum size before player input")
	_check(app.view._layout == app.hud.safe_world_rect(), "settled HUD geometry updates camera without player input")
	var entry_layout: Rect2 = app.view._layout
	var entry_scale: float = app.view.scale_factor
	app._sync_hud()
	_check(app.view._layout == entry_layout and is_equal_approx(app.view.scale_factor, entry_scale), "first movement HUD refresh cannot reframe the level")
	app._on_command("overview")
	_check(app.view.overview and app.hud._overview.button_pressed, "manual overview synchronizes camera and HUD")
	_check(app.view._layout == app.hud.overview_world_rect(), "manual overview avoids the visible journey message")
	app._on_command("overview")
	_check(not app.view.overview and app.view._layout == entry_layout, "manual overview exit restores the normal reference layout")
	_check(app._primary() == "context", "first root never chooses the right-hand solution for the player")
	var before: Dictionary = app.session.world.snapshot()
	app._on_command("hint")
	_check(app.hud.is_hint_visible() and app._hint_tier == 0 and not app.paused, "Hint button opens first inline hint")
	app._on_command("hint_next")
	_check(app.hud.is_hint_visible() and app._hint_tier == 1, "Hint text advances content")
	app._on_command("hint")
	_check(not app.hud.is_hint_visible() and app._hint_tier == 1, "Hint button hides without advancing")
	app._sync_hud()
	_check(not app.hud.is_hint_visible(), "HUD refresh does not reopen dismissed hint")
	app._on_command("hint")
	_check(app.hud.is_hint_visible() and app._hint_tier == 1, "Reopen preserves current hint")
	app._on_command("hint_next")
	_check(app._hint_tier == 2, "third hint remains available")
	app._on_command("hint_next")
	_check(app._hint_tier == 0 and not app.paused, "hint wraps without pausing gameplay")
	app._on_command("hint")
	app._on_command("primary")
	_check(app.hud.is_context_open(), "E opens explicit local root choice")
	_check(app.session.world.snapshot() == before, "opening root choices does not plant")
	var right := InputEventKey.new()
	right.physical_keycode = KEY_RIGHT
	right.keycode = KEY_RIGHT
	right.pressed = true
	app._input(right)
	_check(not app.hud.is_context_open(), "direction confirms a local choice and closes it")
	_check(not app.motion.is_empty(), "growth has an authored presentation transaction")
	_check(app.session.world.state.growth.root.is_empty(), "preview cannot be walked before commit")
	var elapsed: float = app.motion.elapsed
	app._set_portrait_blocked(true)
	app._process(0.3)
	app._physics_process(0.1)
	_check(is_equal_approx(app.motion.elapsed, elapsed) and app.session.world.state.growth.root.is_empty(), "portrait freezes uncommitted growth")
	app._set_portrait_blocked(false)
	_check(not app.paused and not app._portrait_blocked, "landscape restores gameplay without a new menu")
	await _drain(app)
	_check(app.session.world.state.growth.root == ["g:root:1:0"], "explicit chosen direction creates exactly one road")
	_check(app.view.get("world") == app.session.world, "presentation returns to live rules after growth")
	_check(app._validate_snapshot(app.session.world.snapshot()), "native application save remains valid after action")
	app._on_command("undo")
	_check(app.session.world.state.growth.root.is_empty(), "undo restores root budget and topology")
	_check(app.native_movement.is_stable(), "undo clears all pending motion ownership")
	app.settings.lowMotion = true
	app._execute(Command.interact("grow:root:down"), "grow:root:down")
	_check(not app.motion.is_empty() and is_equal_approx(app.motion.duration, 0.44), "reduce motion preserves action/input timing")
	app._show_home()
	_check(app.home_active and not app.view.visible, "return home actually leaves the level view")
	_check(app.session.world.state.growth.root.is_empty(), "return home cancels uncommitted growth")
	_check(app.native_movement.is_stable(), "return home cancels stale movement and callbacks")
	var home_snapshot: Dictionary = app.session.world.snapshot()
	var home_builds: Dictionary = app.view.render_statistics()
	app.view.prepare_initial_frame()
	_check(app.view._viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "startup prepares one hidden frame rather than deferring shaders until Continue")
	_check(app.paused and app.view._paused and app.native_movement.suspended and not app.view.visible, "preparing rendering never resumes gameplay at home")
	_check(Repository.json_equivalent(home_snapshot, app.session.world.snapshot()), "hidden first frame preserves saved gameplay")
	_check(app.view.render_statistics().meshRebuilds == home_builds.meshRebuilds, "first-frame preparation reuses constructed geometry")
	app.view._finish_initial_frame()
	_check(app.view._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "completed hidden frame releases rendering while home remains paused")
	app.view.prepare_initial_frame()
	app._on_command("continue")
	_check(not app.home_active and app.view.visible, "continue restores the level")
	_check(not app.native_movement.suspended, "continue resumes native input")
	_check(app.view._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "continue restores continuous rendering")
	app.view._finish_initial_frame()
	_check(app.view._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "pending frame callback cannot freeze a fast Continue")
	app.view.prepare_initial_frame()
	_check(app.view._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "late preparation cannot freeze active gameplay")
	app.settings.lowMotion = false
	app._on_command("primary")
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	_check(app._handle_native_pad_ui(accept), "local choice consumes gamepad confirmation before world input")
	_check(not app.motion.is_empty(), "gamepad confirmation begins exactly one selected action")
	await _drain(app)
	_check(app.session.world.state.growth.root.size() == 1, "gamepad confirmation never also reinterprets as another world primary")
	app._on_command("settings")
	_check(app.paused, "settings owns world input")
	app._set_portrait_blocked(true)
	app._set_portrait_blocked(false)
	_check(app.paused and app.view._paused, "rotation never resumes an existing settings pause")
	var cancel := InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B
	cancel.pressed = true
	_check(app._handle_native_pad_ui(cancel), "gamepad cancel is consumed by the current page")
	_check(not app.paused, "gamepad cancel returns from a gameplay pause to its source")
	app._enter_level("1-2")
	_check(is_equal_approx(app._native_action_duration("grow:root:right"), 0.44), "other levels retain their original growth timing")
	_check(app._hint_tier == 0 and not app.hud.is_hint_visible(), "entering a level resets and hides hints")
	app._execute(Command.interact("repair"), "repair")
	_check(not app.status_message.contains("上、右、右、下") and not app._growth_hint, "failed repair does not bypass the three-level hint system")
	for level_id: String in ["2-2", "3-4"]:
		app._enter_level(level_id)
		var goal: String = str(app.Journey.describe(app.session.world).goal)
		_check(app.status_message == goal, level_id + " native entry presents the natural goal")
		_check(app.status_message != str(app.session.world.hint().message), level_id + " native entry does not reveal the explicit solution")
		app._message("previous level text")
		app._qa_request([JSON.stringify({"type": "snapshot", "snapshot": app.session.world.snapshot()})])
		_check(app.status_message == goal, level_id + " QA preparation uses the same non-solution entry message")
	app.native_enabled = false
	_check(app._entry_message() == str(app.session.world.level.intro), "explicit legacy mode preserves its original introduction")
	app.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS native application: %d checks" % checks)
		quit(0)
	else:
		quit(1)
