extends "res://tests/native_symbiosis_capture.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer)
	app.view._resize()
	app.set_meta("scripted_gpu_capture", true)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	app.repository.data = Repository.empty_store()
	for level: Dictionary in app.levels:
		branch = str(level.id)
		if branch.begins_with("cloud-"): continue
		app._enter_level(branch)
		_check(await _drain(), branch + " initial scene settles")
		await _capture("follow")
		_check(app.view._viewport.size == dimensions, branch + " 3D render matches capture viewport")
	for extent: Vector2i in [Vector2i(1880,940), Vector2i(844,390), Vector2i(390,844)]:
		dimensions = extent; outer.size = extent
		app.view._resize()
		for id: String in ["1-1", "2-1", "3-1"]:
			branch = id; app._enter_level(id)
			_check(await _drain(), id + " resized scene settles")
			await _capture("follow")
			if extent.x == 1880:
				app._on_command("overview")
				await _capture("overview")
				app._on_command("overview")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"source":source_sha,"images":images,"scope":"Native GPU initial views for all 12 mainline levels; three chapter representatives at wide, small landscape and portrait sizes. Wide overview toggle. Memory-only saves; no full-route or performance claim."}, "  "))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"images":images.size(),"failures":failures}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
