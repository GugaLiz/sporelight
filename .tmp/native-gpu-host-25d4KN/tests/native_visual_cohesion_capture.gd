extends "res://tests/native_hud_feedback_capture.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = Vector2i(1280,720)
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer)
	app.set_meta("scripted_gpu_capture",true)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary
	for route: Dictionary in reference.cases:
		if route.name == "authored/3-1": fixture = route
	for extent: Vector2i in [Vector2i(1880,940),Vector2i(1280,720),Vector2i(844,390)]:
		outer.size = extent; dimensions = extent
		app.repository.data = Repository.empty_store()
		app._enter_level("1-3")
		await _capture("wheel-cold")
		_check(await _walk_to("m:garden:0:0","walk to new wooden wheel"),"actual wheel approach")
		await _capture("wheel-beside")
		var previous: Dictionary = app.session.world.snapshot()
		await _e_action("turn:garden","wooden-wheel-turn")
		_check(previous.turns != app.session.world.state.turns,"same wheel action rotates garden")
		await _capture("wheel-turned")
		for tile: String in ["m:garden:-1:0","m:garden:-2:0","f:0:-3","f:0:-4"]:
			_check(await _walk_to(tile,"north-bank "+tile),"new wheel retains route")
		await _e_action("repair","wheel-route-plant")
		_check(bool(app.session.world.state.completed),"1-3 complete with natural wheel")
		app._on_command("stay")
		for index: int in [-1,1,5,13,21]:
			if index >= 0: app.repository.data.mainline.runs["3-1"] = fixture.steps[index].snapshot.duplicate(true)
			else: app.repository.data.mainline.runs.erase("3-1")
			app._enter_level("3-1")
			await _capture("lamp-step-"+str(index))
			for ray: Node in app.view._effects.get_children():
				if str(ray.get_meta("rule_path","")) != "lamp": continue
				_check(ray.has_node("LampInnerGlow") and ray.has_node("LampOuterGlow"),"lamp glow layers follow bound source")
		app._show_menu()
		app.hud._chapter_map.select_chapter("cave")
		await _capture("cave-map")
		app.hud._chapter_map.show_overview()
		await _capture("three-covers")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"images":images,"scope":"Three GPU sizes; actual 1-3 walking/turn/plant; prepared 3-1 optical phases and three chapter covers. In-memory saves, no user storage."},"  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images.size()}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
