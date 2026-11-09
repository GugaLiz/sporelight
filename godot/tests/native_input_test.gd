extends "res://tests/native_application_test.gd"
## Integration routing through Input.parse_input_event, not direct button calls.
func _run() -> void:
	var app := Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	app.input_router = Router.new()
	Router.install_native_actions()
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
	app.hud.set_repository(app.repository)
	app.native_enabled = true
	app._enter_level("1-1")
	await process_frame
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	Input.parse_input_event(key)
	await process_frame
	_check(app.hud.is_context_open(), "real E event opens local choices")
	var before: Vector3 = app.view.get_actor_body("luvie").position
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	await process_frame
	app._physics_process(1.0 / 60.0)
	_check(app.view.get_actor_body("luvie").position == before, "context consumes stick without moving the actor")
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	_check(not app.hud.is_context_open() and not app.motion.is_empty(), "real A confirms one local action")
	accept.pressed = false
	Input.parse_input_event(accept)
	await _drain(app)
	_check(app.session.world.state.growth.root.size() == 1, "one A cannot plant and execute world primary again")
	app._on_command("settings")
	await process_frame
	var resume: BaseButton = _find_button(app.hud, "resume")
	_check(resume != null, "pause has a real focusable resume control")
	if resume != null:
		resume.grab_focus()
		accept.pressed = true
		Input.parse_input_event(accept)
		await process_frame
		accept.pressed = false
		Input.parse_input_event(accept)
		await process_frame
		_check(not app.paused and not app.hud.is_modal_open(), "A activates focused GUI resume before world input")
		_check(not app.hud.is_context_open() and app.session.world.state.growth.root.size() == 1, "GUI A never leaks into another world action")
	app._show_menu()
	app._on_command("settings")
	await process_frame
	var cancel := InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await process_frame
	_check(app.paused and app.hud.is_modal_open(), "B from map settings returns to map without resuming the world")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	Input.parse_input_event(start)
	await process_frame
	_check(not app.paused, "Start on the map returns to the previous gameplay source")
	app.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS native input routing: %d checks" % checks)
		quit(0)
	else:
		quit(1)

func _find_button(node: Node, action: String) -> BaseButton:
	if node is BaseButton and node.is_visible_in_tree() and str(node.get_meta("action", "")) == action:
		return node
	for child: Node in node.get_children():
		var found := _find_button(child, action)
		if found != null:
			return found
	return null
