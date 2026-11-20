extends "res://tests/native_visual_cohesion_capture.gd"

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
		for index: int in [-1,1,5,13,21]:
			if index >= 0: app.repository.data.mainline.runs["3-1"] = fixture.steps[index].snapshot.duplicate(true)
			else: app.repository.data.mainline.runs.erase("3-1")
			app._enter_level("3-1")
			await _capture("lamp-step-"+str(index))
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"images":images,"scope":"Final core radius .020, three GPU sizes, prepared cold/carried/passage/receiver/window states. Does not replace real route evidence."},"  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images.size()}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
