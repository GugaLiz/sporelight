extends "res://tests/native_symbiosis_capture.gd"
## Completed-memory fixture for UI rendering, not a claim of full-route play.
var layouts: Array = []
func _click(button: Button) -> void:
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center(); event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		outer.push_input(event,true); await process_frame
	for unused in 8: await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer); app.view._resize()
	app.set_meta("scripted_gpu_capture",true); app.set_process_input(true)
	app.hud.menu_requested.connect(app._show_menu)
	app.hud.level_requested.connect(app._enter_level)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if fixture.name == "authored/3-4":
			app.repository.data.mainline.memories["3-4"] = fixture.steps.back().snapshot.duplicate(true)
	app._enter_level("3-4",true); await _drain()
	var saved: Dictionary = app.repository.data.duplicate(true)
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(1672,941),Vector2i(844,390),Vector2i(390,844)]:
		dimensions = extent; outer.size = extent; app.view._resize()
		branch = "ending"
		app._show_ending()
		var page: Control = app.hud._journey_ending
		for moment: float in [0.0,.85,1.05,1.25,1.45,1.65,5.79,5.81,12.0]:
			page.elapsed = moment
			page._update_farewell()
			_check(page.hero_sprite.position.is_equal_approx(page.hero_foot),"whole-pose animation stays centered " + str(moment)+str(extent))
		page.elapsed = 0.0
		page._process(0)
		for unused in 20: await RenderingServer.frame_post_draw
		await _capture("arrival")
		_check(page.paragraphs[0].modulate.a >= page.paragraphs.back().modulate.a and page.paragraphs.back().modulate.a == 0,"letter starts in reading order, final line hidden " + str(extent))
		var before := outer.get_texture().get_image()
		for unused in 70: await process_frame
		await _capture("drifting")
		_check(before.get_data() != outer.get_texture().get_image().get_data(),"ending particles/breath change real GPU frames")
		if extent in [Vector2i(1280,720),Vector2i(390,844)]:
			for moment: float in [0.0,.85,1.05,1.25,1.45,1.65]:
				page.elapsed = moment
				page._process(0)
				page.set_process(false)
				await _capture("farewell-" + str(moment))
				_check(page.hero_sprite.material == null,"whole-frame art has no limb cutout shader " + str(moment))
			page.set_process(true)
		page.elapsed = 1.05
		page._process(0)
		_check(page.wave_frame == 2 and page.hero_sprite.texture == page.wave_frames[2],"painted outward wave frame is active " + str(extent))
		page.elapsed = 18.0
		page._process(0)
		_check(page.paragraphs.all(func(line: Label) -> bool: return line.modulate.a == 1.0),"all lines finish revealing " + str(extent))
		var body: Rect2 = page.scroll.get_global_rect()
		var actions: Rect2 = page.footer.get_global_rect()
		_check(body.end.y <= actions.position.y,"letter scroll and buttons do not overlap " + str(extent))
		for button: Button in page.buttons:
			_check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(button.get_global_rect()),"ending button stays within viewport " + str(extent))
		page.scroll.scroll_vertical = 10000
		for unused in 8: await process_frame
		await _capture("letter-end")
		var last: Label = page.paragraphs.back()
		_check(last.get_global_rect().end.y <= body.end.y+2,"final blessing is reachable without clipped text " + str(extent))
		layouts.append({"size":str(extent),"body":str(body),"buttons":str(actions),"lastParagraph":str(last.get_global_rect())})
		page.apply_settings({"lowMotion":true,"particles":false})
		await _capture("quiet")
		var time: float = page.elapsed
		for unused in 8: await process_frame
		_check(page.elapsed == time,"reduced motion freezes ending clock")
		_check(page.hero_sprite.position.is_equal_approx(page.hero_foot) and page.wave_frame == 0,"reduced motion shows the centered relaxed pose")
		_check(page.paragraphs.all(func(line: Label) -> bool: return line.modulate.a == 1.0),"reduced motion shows complete letter immediately")
		page.apply_settings({"lowMotion":false,"particles":true})
		page.elapsed = 0.0
		page._process(0)
		for down: bool in [true,false]:
			var reveal := InputEventMouseButton.new()
			reveal.position = page.scroll.get_global_rect().get_center()
			reveal.global_position = reveal.position
			reveal.button_index = MOUSE_BUTTON_LEFT
			reveal.pressed = down
			outer.push_input(reveal,true)
			await process_frame
		_check(page.letter_complete and page.paragraphs.back().modulate.a == 1,"real click reveals full letter " + str(extent))
		await _click(page.buttons[1])
		_check(app.strolling and not app.paused and not app.hud.is_modal_open(),"actual stay click resumes completed garden " + str(extent))
		app._on_command("ending")
		for unused in 8: await process_frame
		await _click(app.hud._journey_ending.buttons[0])
		_check(app.hud._chapter_map.selected_id == "3-4","actual map click selects final garden " + str(extent))
		app.hud.close_overlay()
	_check(saved == app.repository.data,"ending rendering and resizing never rewrite progress")
	app._show_ending()
	for unused in 8: await process_frame
	await _click(app.hud._journey_ending.buttons[2])
	_check(app.home_active and app.hud._page_kind == "home","actual home click opens home")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":source_sha,"passed":failures.is_empty(),"checks":checks,"failures":failures,"layouts":layouts,"images":images,"scope":"Completed-memory UI fixture, four sizes and actual GPU animation; no claim of a complete 3-4 route."},"  "))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
