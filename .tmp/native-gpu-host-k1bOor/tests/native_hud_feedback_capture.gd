extends "res://tests/native_symbiosis_capture.gd"
## Feedback 117: real bodies, pointer hits, E menus and GPU originals.
var lights: Array = []

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(180).timeout.connect(func() -> void: if not finished: quit(2))
	_run.call_deferred()

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	app._input(event)

func _tap(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	app.view._last_touch_ms = -1000
	app.view._unhandled_input(event)

func _garden() -> void:
	app._enter_level("1-3")
	await _drain()
	await _walk_to("f:-5:-1", "rest approach")
	await _e_action("observe:rest", "rest")
	var body: CharacterBody3D = app.view.get_actor_body("luvie")
	var start := body.position
	_key(KEY_DOWN,true)
	for unused in 24: await _tick()
	_key(KEY_DOWN,false)
	_check(await _drain() and body.position.distance_to(start) > .15, "1-3 direction key physically leaves rest without modal/pause")
	await _capture("after-rest")
	await _walk_to("f:-3:0", "return to connected entrance")
	if dimensions.y < 430:
		await _walk_to("m:garden:-2:0", "small-screen enter connected garden arm")
		await _walk_to("m:garden:-1:0", "small-screen approach wheel in following camera")
		app.view._fit_camera(true)
	var wheel: Sprite3D = app.view._props_nodes["mark:turn"].get_node("NaturalWheel")
	var point: Vector2 = app.view.world_to_screen(wheel.global_position + app.view._camera.global_basis.y * .69)
	_check(app.view.hit_test(point) == "m:garden:0:0", "pointer on wheel rim maps to mechanism support, not background floor")
	_tap(point)
	_check(await _drain(800), "clicking the physical wheel walks existing connected paving")
	_check(str(app.session.world.state.actors.luvie) == "m:garden:0:0", "wheel click physically arrives at original rotating support")
	var context: Dictionary = app._native_interaction_context()
	_check(context.get("choices",[]).any(func(c: Dictionary) -> bool: return c.id == "turn:garden" and not c.disabled), "original turn available beside wheel after real approach")
	await _capture("at-wheel")
	await _e_action("turn:garden", "rotate")
	await _capture("rotated")
	for support: String in ["m:garden:-1:0", "m:garden:-2:0", "f:0:-3", "f:0:-4"]:
		if not await _walk_to(support,"north-bank "+support): return
	await _e_action("repair","plant")
	_check(bool(app.session.world.state.completed), "1-3 completes after rest, pointer approach, rotation and planting")
	app._on_command("stay")
	await _capture("completed")

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.command_selected.connect(app._on_command)
	app.view.tile_selected.connect(app._go)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	for level: Dictionary in app.levels:
		branch = str(level.id)
		app._enter_level(branch)
		await _drain()
		await _capture("initial")
		var fx: Node3D = app.view._garden_effects
		for entry: Dictionary in fx.collectibles.values():
			_check(entry.sprite.texture.resource_path == "res://assets/images/scene-redraw-20261116/spore.png", branch+" active light uses shared redraw")
			_check(not entry.sprite.no_depth_test and entry.sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED, branch+" light has normal occlusion and no opaque prepass")
			lights.append({"level":branch,"tile":entry.tile,"offset":str(entry.offset)})
		app.view.visual_time += 550
		fx.update()
		app._on_command("overview")
		await _capture("overview-phase2")
		app._on_command("overview")
	for size: Vector2i in [Vector2i(1600,900),Vector2i(1280,720),Vector2i(844,390)]:
		app.repository.data = Repository.empty_store()
		dimensions = size
		outer.size = size
		branch = "input-1-3"
		await _garden()
		app._enter_level("1-1")
		await _drain()
		branch = "hud"
		await _capture("first-garden")
		var visible_buttons := 0
		for button: Button in app.hud._tool_buttons:
			if not button.visible: continue
			visible_buttons += 1
			_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()), "toolbar button within "+str(size)+" / "+str(button.get_meta("action")))
		_check(visible_buttons == 7, "first garden seven real tools without a fake switch")
		app._enter_level("1-2")
		await _drain()
		await _capture("second-garden")
		app.view.set_process(false)
		app.view._camera.size *= .65
		for unused in 8: await RenderingServer.frame_post_draw
		outer.get_texture().get_image().save_png(output.path_join("lights-close-%dx%d.png" % [size.x,size.y]))
		app.view.set_process(true)
		app.view._fit_camera(true)
		var light: Dictionary = app.view._garden_effects.collectibles["spore-1"]
		var at: Vector2 = app.view.world_to_screen(light.sprite.global_position)
		_check(app.view.hit_test(at) == str(light.tile), "shifted 1-2 light visible body selects original support / "+str(size))
		_tap(at)
		_check(await _drain(800) and "spore-1" in app.session.world.state.collected, "real pointer walks and collects shifted 1-2 light / "+str(size))
		await _capture("light-collected")
	failures.append_array(logger.captured_errors())
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty(),"images":images,"events":events,"lights":lights,"scope":"15 cold native gardens/two visual phases; real 1-3 rest, direction input, wheel pointer, E menu, rotation and planting at three sizes. AudioStub; not OS/browser input or performance measurement."}
	report["sourceSha256"] = source_sha
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"checks":checks,"images":images.size(),"passed":failures.is_empty(),"failures":failures}))
	await _dispose()
	finished = true
	quit(0 if failures.is_empty() else 1)
