extends "res://tests/rule_application.gd"
## Intent buffering and contiguous segments through the real controller; no user storage or renderer.

func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func _frames(app: Node, count: int) -> void:
	for unused: int in range(count): app._process(0.05)

func _router_cases() -> void:
	var router = Router.new()
	router.handle_key(_key(KEY_LEFT))
	router.buffer("left")
	router.advance(0.08)
	router.handle_key(_key(KEY_LEFT, false))
	_check(router.take_next() == "left", "A released deliberate tap survives until the next step even with continuous walking off")
	_check(router.take_next().is_empty(), "One buffered tap produces only one continuation")
	router.buffer("up")
	router.buffer("right")
	_check(router.take_next() == "right", "The newest deliberate direction replaces the previous intent")
	router.buffer("left")
	router.advance(0.10)
	router.handle_key(_key(KEY_LEFT, true, true))
	router.advance(0.07)
	_check(router.take_next().is_empty(), "OS repeat cannot refresh or replace an expired tap buffer")
	router.clear()
	router.handle_key(_key(KEY_LEFT, true, true))
	_check(router.held.is_empty() and router.take_next().is_empty(), "Echo cannot recreate held input after focus or pause clears it")
	router.continuous = true
	router.handle_key(_key(KEY_LEFT))
	router.handle_key(_key(KEY_A))
	router.handle_key(_key(KEY_LEFT, false))
	_check(router.take_next() == "left", "Releasing one alias does not release another physically held key")
	router.suppress_held("left")
	_check(router.take_next().is_empty(), "A blocked held direction remains quiet")
	router.world_changed()
	_check(router.take_next() == "left", "A changed world allows a blocked held direction to be checked again")
	router.handle_key(_key(KEY_A, false))
	_check(router.take_next().is_empty(), "Releasing the last alias stops held movement")

func _controller_cases() -> void:
	var app: Node = _app()
	app._step("left")
	_frames(app, 2)
	app._input(_key(KEY_LEFT))
	app._input(_key(KEY_LEFT, false))
	_frames(app, 2)
	app._process(0.01)
	_check(app.session.world.state.actors.luvie == "f:-1:0", "The first tap commits at its original grid destination")
	_check(not app.motion.is_empty() and app.motion.after.actors.luvie == "f:-2:0", "A late press-release starts its next move in the completing frame")
	_check(app.view.clear_calls == 0, "Contiguous walking never clears motion between the two segments")
	_check(app.motion.duration == 0.205 and app.motion.elapsed == 0.0, "Continuation preserves the 205ms duration and begins at progress zero")
	_drain(app, "tap/released-continuation")
	_check(app.session.revision == 2 and app.repository.commits == 2, "Two taps cause exactly two moves and saves")
	_check(app.view.clear_calls == 1, "Motion clears once after the final segment")
	app.free()

	app = _app()
	app._go("f:-2:0")
	app._process(0.0)
	_frames(app, 4)
	app._process(0.01)
	_check(app.session.world.state.actors.luvie == "f:-1:0" and not app.motion.is_empty(), "A click route starts its next tile in the previous tile's completion frame")
	_check(app.motion.after.actors.luvie == "f:-2:0" and app.view.clear_calls == 0, "Click-route continuation does not insert an idle or stop transition")
	_drain(app, "route/contiguous")
	app.free()

	app = _app()
	app._step("left")
	app.route = ["f:-2:0"]
	_frames(app, 2)
	app._input(_key(KEY_LEFT))
	app._input(_key(KEY_LEFT, false))
	app._input(_key(KEY_UP))
	app._input(_key(KEY_UP, false))
	_frames(app, 2)
	app._process(0.01)
	_check(app.route.is_empty() and app.motion.after.actors.luvie == "f:-1:-1", "The latest manual intent supersedes both an older tap and an automatic route")
	_drain(app, "tap/latest-turn")
	app.free()

	app = _app()
	app._on_command("grow:root:right")
	_frames(app, 2)
	app._input(_key(KEY_LEFT))
	app._input(_key(KEY_LEFT, false))
	_frames(app, 15)
	_check(app.session.world.state.actors.luvie == "f:0:0" and app.motion.is_empty(), "An early tap expires during a long mechanism animation rather than moving later")
	_check(app.session.revision == 1 and app.input_router.buffered_direction.is_empty(), "Expired intent adds no command, save or retained queue")
	app.free()

	app = _app()
	app.input_router.continuous = true
	app._input(_key(KEY_LEFT))
	_frames(app, 14)
	var starts: int = app.audio.starts
	var stable: Dictionary = app.session.world.snapshot()
	_frames(app, 80)
	_check(app.audio.starts == starts and app.session.world.snapshot() == stable, "Held input at a boundary does not retry movement or audio every frame")
	_check(app.input_router.take_next().is_empty(), "Blocked hold stays suppressed until a new intent or world change")
	app._input(_key(KEY_LEFT, false))
	app.free()

	app = _app()
	app.input_router.continuous = true
	app._input(_key(KEY_LEFT))
	var modified_release := _key(KEY_LEFT, false)
	modified_release.ctrl_pressed = true
	app._input(modified_release)
	_check(app.input_router.held.is_empty(), "Releasing a movement key while Ctrl is held still ends the hold")
	_drain(app, "keyboard/modified-release")
	app.free()

	for boundary: String in ["pause", "focus", "level"]:
		app = _app()
		app._step("left")
		_frames(app, 2)
		app._input(_key(KEY_LEFT))
		if boundary == "pause":
			app._on_command("pause")
			_frames(app, 10)
			app._on_command("resume")
		elif boundary == "focus": app._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else: app._enter_level("1-3")
		_check(app.input_router.held.is_empty() and app.input_router.buffered_direction.is_empty(), boundary + "/clears-held-and-buffered-intent")
		_drain(app, boundary + "/finish-only-current-segment")
		if boundary != "level": _check(app.session.world.state.actors.luvie == "f:-1:0", boundary + "/does-not-replay-an-old-tap")
		app.free()

	app = _app()
	app._input(_key(KEY_E))
	_drain(app, "interaction/first-keydown")
	var after_interaction: Dictionary = app.session.world.snapshot()
	app._input(_key(KEY_E, true, true))
	_frames(app, 20)
	_check(app.session.world.snapshot() == after_interaction and app.session.revision == 1, "Held E repeat never queues or repeats a resource-changing interaction")
	app.free()

func _run() -> void:
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	_levels = content.levels
	_router_cases()
	_controller_cases()
	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite": "garden-natural-input", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)
