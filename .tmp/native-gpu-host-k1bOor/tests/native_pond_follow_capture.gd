extends "res://tests/native_hud_feedback_capture.gd"
var framing: Array = []

func _capture(label: String) -> void:
	for unused in 8: await RenderingServer.frame_post_draw
	var filename := "%s-%s-%dx%d.jpg" % [branch,label,outer.size.x,outer.size.y]
	_check(outer.get_texture().get_image().save_jpg(output.path_join(filename),.94)==OK,"GPU "+filename)
	images.append(filename)

func _framing(label: String) -> void:
	app._update_layout(); app.view._fit_camera(true)
	var safe: Rect2 = app._camera_safe_rect()
	var focus: Vector2 = app.view.world_to_screen(app.view._target_focus)
	_check(focus.distance_to(safe.get_center())<1.0,label+" focus centred in stable play area")
	if outer.size.x >= 1050:
		_check(absf(focus.x-outer.size.x*.5)<1,label+" horizontal screen centre")
		_check(focus.y<outer.size.y*.5 and focus.y>outer.size.y*.35,label+" focus above toolbar, not below sidebars")
	framing.append({"label":label,"size":str(outer.size),"focus":str(focus),"safe":str(safe),"cameraSize":app.view._camera.size})

func _pond_route(who: String) -> bool:
	branch = "pond-"+who
	app._enter_level("2-1"); await _drain()
	if who == "buddy":
		app._on_command("switch"); await _drain()
		app._on_command("follow"); await _drain()
	_framing(branch)
	_key(KEY_E,true); _key(KEY_E,false)
	await _capture("initial-denial")
	app.hud.close_context_choices()
	if not await _walk_to("f:0:4","walk low path to dew"): return false
	await _capture("at-dew")
	if who == "buddy":
		var context: Dictionary = app._native_interaction_context()
		_check(context.choices.any(func(c: Dictionary) -> bool: return c.id == "switch" and c.label == "切换露薇接清露"),"buddy beside dew sees original role switch")
		if not await _e_action("switch","switch-to-dew-carrier"): return false
		app._on_command("follow"); await _drain()
		if not await _walk_to("f:0:4","carrier walks to dew after switching"): return false
	if not await _e_action("take:dew","take-dew"): return false
	if not await _walk_to("m:float:0:0","return to floating platform"): return false
	if not await _e_action("use:care","give-dew"): return false
	if not await _e_action("valve:water","middle-water"): return false
	await _capture("east-landing")
	if not await _walk_to("f:4:0","walk opened east landing"): return false
	if not await _e_action("repair","plant-together"): return false
	_check(app.session.world.state.completed,who+" completes pond with real motor and E actions")
	app._on_command("stay")
	await _capture("complete")
	return true

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = Vector2i(1887,912)
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer); _setup(); app.reparent(outer)
	# This scripted offscreen viewport must not have its injected route cancelled
	# when the automation host takes OS focus. Browser input is verified separately.
	app.set_meta("scripted_gpu_capture",true)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	await _pond_route("buddy")
	outer.size = Vector2i(1280,720)
	app.repository.data = Repository.empty_store()
	await _pond_route("luvie")
	for extent: Vector2i in [Vector2i(1887,912),Vector2i(1280,720),Vector2i(844,390)]:
		outer.size = extent
		for id: String in ["1-1","1-4","2-1","3-4"]:
			branch = "framing-"+id
			app.repository.data = Repository.empty_store()
			app._enter_level(id); await _drain()
			_framing(branch)
			await _capture("follow")
			var before: float = app.view._camera.size
			app._on_command("overview")
			await _capture("overview")
			app._on_command("overview"); app.view._fit_camera(true)
			_check(is_equal_approx(before,app.view._camera.size),branch+" overview returns to same follow scale")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"images":images,"framing":framing,"samples":samples,"scope":"Fresh 2-1 native real motor/E/menu routes with each actor leading; 4 representative gardens, 3 sizes, follow/overview/return. In-memory saves only; no Web/performance/audio claim."},"  "))
	print(JSON.stringify({"checks":checks,"images":images.size(),"passed":failures.is_empty(),"failures":failures}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
