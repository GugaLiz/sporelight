extends "res://tests/native_pond_feedback_capture.gd"
## Existing pond puzzle with actual bodies, pointer actions and gauge animation.
var motion_label := ""
var gauges: Array = []

func _drain(limit: int = 240) -> bool:
	if not motion_label.is_empty() and app != null and not app.motion.is_empty():
		var label := motion_label
		motion_label = ""
		await _capture(label + "-start")
		for unused in 120:
			if app.motion.is_empty() or float(app.motion.elapsed) / float(app.motion.duration) >= .45: break
			await _tick()
		await _capture(label + "-middle")
	return await super._drain(limit)

func _capture(label: String) -> void:
	await super._capture(label)
	if str(app.session.world.level.id) == "2-1":
		var prop: Node3D = app.view._props_nodes["mark:water"]
		gauges.append({"label":label,"size":str(dimensions),"step":prop.get_meta("height_step"),"pointer":str(prop.get_node("HeightPointer").position),"water":app.session.world.state.water,"actors":app.session.world.state.actors.duplicate(true)})

func _cycle(fixture: Dictionary) -> void:
	branch = "water-control"
	app.repository.data = Repository.empty_store(); app._enter_level("2-1"); await _drain()
	for index in 10:
		var command: Dictionary = fixture.steps[index].command
		var ok := await _walk_to(str(command.value),"original pickup and dew return") if command.kind == "move" else await _menu_action(str(command.value))
		if not ok: return
	await _capture("low")
	for step in [1,2,0]:
		motion_label = "water-" + str(step)
		if not await _menu_action("valve:water"): return
		_check(int(app.session.world.state.water) == step,"original three-level water cycle reaches " + str(step))
		_check(is_equal_approx(float(app.view._props_nodes["mark:water"].get_meta("height_step")),float(step)),"settled gauge follows actual water")
		await _capture("water-" + str(step) + "-settled")
	motion_label = "undo"
	await _key_input(KEY_Z); await _drain(900)
	# Undo may restore immediately, with no motion to capture. Never let its
	# label leak into the next level's walk animation.
	motion_label = ""
	_check(int(app.session.world.state.water) == 2,"undo restores high water")
	await _capture("undo-high")
	app._enter_level("2-1"); await _drain()
	_check(int(app.session.world.state.water) == 2 and float(app.view._props_nodes["mark:water"].get_meta("height_step")) == 2,"reload preserves actual high water and indicator")
	await _capture("reload-high")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer); app.view._resize()
	app.set_meta("scripted_gpu_capture",true); app.set_process_input(true)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary
	for entry: Dictionary in reference.cases:
		if entry.name == "authored/2-1": fixture = entry
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions = extent; outer.size = extent; app.view._resize()
		await _cycle(fixture)
	dimensions = Vector2i(1280,720); outer.size = dimensions; app.view._resize()
	await _route_menu(fixture)
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":source_sha,"passed":failures.is_empty(),"checks":checks,"failures":failures,"routes":routes,"clicks":clicks,"gauges":gauges,"images":images,"scope":"Actual pointer menus, three water levels with start/middle/end, undo/reload, original 16 intentions through physical bodies. GPU pictures, not browser/audio/performance validation."},"  "))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"routes":routes,"failures":failures}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
