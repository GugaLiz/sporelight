extends "res://tests/native_hud_feedback_capture.gd"
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = Vector2i(1880,940)
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup(); app.reparent(outer)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	# Fresh camera and a real saved puzzle state near home, before any walk.
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var snapshot: Dictionary
	for route: Dictionary in reference.cases:
		if route.name != "authored/1-4": continue
		for step: Dictionary in route.steps:
			if str(step.command.get("value","")) == "use:home": snapshot = step.snapshot.duplicate(true); break
	snapshot.actors = {"luvie":"f:-4:0","buddy":"f:-4:0"}
	snapshot.active = "luvie"; snapshot.follow = true; snapshot.erase("runtime")
	for level: String in ["1-1","1-2","1-3"]: app.repository.data.mainline.records[level] = {"completed":true,"collected":3,"stars":3}
	app.repository.data.mainline.runs["1-4"] = snapshot
	app._enter_level("1-4")
	app._update_layout(); app.view._fit_camera(true)
	var resident: Sprite3D = app.view._props.get_node("MoleResident")
	var initial := resident.basis
	_check(absf(initial.x.dot(app.view._camera.global_basis.x)-1)<.001,"first entry resident width correct before app tick")
	await shot("fourth-before-movement")
	_check(await _walk_to("f:-4:-1","walk beside resident"),"actual walk beside resident")
	resident = app.view._props.get_node("MoleResident")
	_check(resident.basis.is_equal_approx(initial),"walking does not repair a previously wrong basis")
	await shot("fourth-after-movement")
	for extent: Vector2i in [Vector2i(1880,940),Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844),Vector2i(320,568)]:
		outer.size = extent
		app.hud.show_settings(app.settings)
		await shot("settings")
		var settings_page: Control = app.hud._settings_page
		for slider: HSlider in settings_page._sliders.values():
			_check(slider.get_global_rect().end.x <= settings_page.scroll.get_global_rect().end.x+.5,"settings slider fits horizontal viewport / %s / %s" % [extent,slider.name])
		app._show_menu()
		await shot("map")
		app.hud._chapter_map.show_overview()
		await shot("overview")
		_check(app.hud._chapter_map._overview.find_children("ChapterPreview_cloud","Button",true,false).is_empty(),"cloud absent from overview")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"images":images,"scope":"Fresh 1-4 stage with prepared memory save near home; initial projection and actual motor walking. Five UI sizes and mainline-only overview. No user-save or audible audio/performance claim."},"  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images.size()}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
func shot(label: String) -> void:
	for unused in 8: await RenderingServer.frame_post_draw
	var file := "%s-%dx%d.jpg" % [label,outer.size.x,outer.size.y]
	_check(outer.get_texture().get_image().save_jpg(output.path_join(file),.94)==OK,"GPU "+file)
	images.append(file)
