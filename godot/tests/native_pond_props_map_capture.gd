extends "res://tests/native_pond_feedback_capture.gd"
## GPU scene review and original routes through actual pointer menus/bodies.
var action_number := 0

func _menu_action(id: String) -> bool:
	action_number += 1
	var ok := await super._menu_action(id)
	await _capture(str(action_number) + "-" + id.replace(":","-") + "-settled")
	return ok

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer); app.view._resize()
	# The route-only parent harness omits page navigation signals.
	app.hud.menu_requested.connect(app._show_menu)
	app.hud.level_requested.connect(app._enter_level)
	app.set_meta("scripted_gpu_capture",true); app.set_process_input(true)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions = extent; outer.size = extent; app.view._resize()
		for id: String in ["2-2","2-4","3-4"]:
			branch = id
			app.repository.data = Repository.empty_store(); app._enter_level(id); await _drain()
			await _capture("entry")
			if id.begins_with("2-"):
				app.view.visual_time = 6100
				app.view._original_pond.update(app.view)
				await _capture("blink")
	dimensions = Vector2i(1280,720); outer.size = dimensions; app.view._resize()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if str(fixture.name).begins_with("authored/") and str(fixture.levelId) in ["2-2","2-4"]:
			await _route_menu(fixture)
	branch = "map-return"
	app.repository.data = Repository.empty_store(); app.unlock_all_levels = true
	app._enter_level("3-2"); await _drain()
	app.repository.data.mainline.last_level = "3-4"
	var before: Dictionary = app.repository.data.duplicate(true)
	await _capture("3-2-play")
	var map_button: Button
	for node: Node in app.hud.find_children("*","Button",true,false):
		if node.text == "地图" and node.is_visible_in_tree(): map_button = node
	if _check(map_button != null,"actual map HUD button exists"):
		for down: bool in [true,false]:
			var event := InputEventMouseButton.new()
			event.position = map_button.get_global_rect().get_center(); event.global_position = event.position
			event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
			outer.push_input(event,true); await process_frame
		await _capture("3-2-selected")
		_check(app.hud._chapter_map != null and app.hud._chapter_map.selected_id == "3-2","pointer map return selects current 3-2")
		_check(before == app.repository.data,"opening map preserves saved progress")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":source_sha,"passed":failures.is_empty(),"checks":checks,"failures":failures,"routes":routes,"clicks":clicks,"images":images,"scope":"GPU pictures, actual bodies and pointer menus on original 2-2/2-4 routes; actual map button input with stale 3-4 save; memory-only repository."},"  "))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"routes":routes,"failures":failures}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
