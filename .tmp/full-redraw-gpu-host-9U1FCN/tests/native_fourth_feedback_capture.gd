extends "res://tests/native_hud_feedback_capture.gd"
## Feedback 119 GPU checks: prepared phases, then real motor and HUD input.
var fourth: Dictionary

func _capture(label: String) -> void:
	app._update_layout(); app.view._fit_camera(true)
	for unused in 6: await RenderingServer.frame_post_draw
	var file := "%s-%dx%d.jpg" % [label, dimensions.x, dimensions.y]
	_check(outer.get_texture().get_image().save_jpg(output.path_join(file), .96) == OK, "GPU original " + file)
	images.append({"file":file,"viewport":[dimensions.x,dimensions.y],"message":app.status_message,"cooperation":app.hud._action_help.text,"state":app.session.world.snapshot()})
	print("CAPTURE " + file)

func _load(state: Dictionary) -> void:
	app.repository.data.mainline.runs["1-4"] = state.duplicate(true)
	app._enter_level("1-4"); await _tick(); await _tick()

func _switch() -> void:
	var button: Button
	for node: Button in app.hud._tool_buttons:
		if node.get_meta("action") == "switch": button = node
	var at := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		outer.push_input(event, true)
	await _drain()

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer)
	app.view.tile_selected.connect(app._go); app.view.command_selected.connect(app._on_command)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) == "authored/1-4": fourth = entry
	branch = "fourth-feedback"
	for size: Vector2i in [Vector2i(1280,720), Vector2i(844,390), Vector2i(390,844)]:
		dimensions = size; outer.size = size
		await _load(fourth.steps[0].snapshot)
		await _switch()
		_check(app.session.world.actor() == "buddy" and app.session.world.lever_held(), "HUD pointer switches while keeping heavy lever")
		_check(app.status_message.begins_with("当前控制：小苔灵"), "HUD pointer shows explicit role feedback")
		await _capture("switch-to-buddy")
		await _load(fourth.steps[11].snapshot)
		await _switch()
		_check(app.session.world.actor() == "luvie" and app.session.world.state.actors.buddy == "f:3:5", "switch keeps buddy on plate")
		_check(app.hud._action_help.text.contains("守住踏板"), "action card follows actual cooperation phase")
		await _capture("switch-to-latch")
		await _load(fourth.steps[20].snapshot)
		_check(await _walk_to("f:3:0", "middle bell drop"), "real motor reaches middle")
		await _e_action("drop:bell:f:3:0", "drop-bell")
		_check(app.session.world.state.items.bell.tile == "f:3:0", "E menu drops bell on middle")
		_check(app.status_message.contains("门铃已放"), "drop message states actual result")
		await _capture("bell-on-middle")
		await _e_action("take:bell", "take-bell")
		_key(KEY_DOWN, true)
		for unused in 70: await _tick()
		_key(KEY_DOWN, false)
		_check(app.session.world.state.actors.luvie == "f:3:0" and app.status_message.contains("低拱"), "held key identifies low arch without crossing")
		await _capture("low-arch-feedback")
		_check(await _walk_to("f:-4:0", "return middle bell"), "actual motor returns from middle")
		await _e_action("use:home", "deliver-bell")
		_check(app.session.world.flag("home") and not app.session.world.state.completed, "delivery opens original gate only")
		await _capture("returned-home")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify({"sourceSha256":source_sha,"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images,"scope":"Prepared puzzle phases followed by real native motor, SubViewport pointer switch, E/menu and held-key handlers. Three GPU sizes; memory saves and AudioStub. No browser/OS input or performance claim."}, "  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images.size()}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
