extends "res://tests/native_symbiosis_capture.gd"
## UI capture: completed fixture in memory; actual pointer input on the new sheet.
func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(100).timeout.connect(func() -> void: if not finished: quit(2))
	_run.call_deferred()

func _button(caption: String, node: Node) -> Button:
	if node is Button and node.text == caption: return node
	for child: Node in node.get_children():
		var found := _button(caption,child)
		if found != null: return found
	return null

func _press(button: Button) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		outer.push_input(event,true)
	for unused in 8: await process_frame

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.hud.menu_requested.connect(app._show_menu)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if fixture.name != "authored/1-1": continue
		app.repository.data.mainline.memories["1-1"] = fixture.steps.back().snapshot.duplicate(true)
		app._enter_level("1-1",true)
	for size: Vector2i in [Vector2i(1280,720),Vector2i(627,637),Vector2i(844,390),Vector2i(390,844),Vector2i(568,320),Vector2i(320,568)]:
		dimensions = size
		outer.size = size
		app._enter_level("1-1",true)
		branch = "completion"
		app._show_ending()
		await _capture("sheet")
		var paper: Rect2 = app.hud._overlay_paper.get_global_rect()
		_check(not app.hud._overlay_scroll.get_v_scroll_bar().is_visible_in_tree() and app.hud._overlay_scroll.scroll_vertical == 0,"all ending content visible without auto-scroll / "+str(size))
		_check(paper.size.x <= 433 and paper.size.y < 360,"completion sheet stays compact / "+str(size))
		_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(paper),"completion paper stays inside viewport / "+str(size))
		for caption: String in ["去下一片微光 ↗","留下看看","返回地图"]:
			var button := _button(caption,app.hud._overlay)
			_check(button != null and paper.encloses(button.get_global_rect()) and button.size.y >= 44 and button.size.y < 50,"all compact real buttons visible / "+caption+" / "+str(size))
		await _press(_button("留下看看",app.hud._overlay))
		_check(not app.hud.is_modal_open() and app.strolling and not app.paused,"real stay click resumes stroll / "+str(size))
		app._show_ending()
		for unused in 8: await RenderingServer.frame_post_draw
		await _press(_button("返回地图",app.hud._overlay))
		_check(app.hud._page_kind == "map" and app.hud.is_modal_open(),"real map click navigates / "+str(size))
		app.hud.close_overlay(false)
		app._show_ending()
		for unused in 8: await RenderingServer.frame_post_draw
		await _press(_button("去下一片微光 ↗",app.hud._overlay))
		_check(app.session.world.level.id == "1-2" and not app.hud.is_modal_open() and not app.paused,"real next click enters next garden / "+str(size))
	for id: String in ["1-2","cloud-3"]:
		var level: Dictionary = {}
		for value: Dictionary in app.levels:
			if value.id == id: level = value.duplicate(true)
		level["has_next_garden"] = id != "cloud-3"
		for size: Vector2i in [Vector2i(627,637),Vector2i(320,568),Vector2i(568,320)]:
			dimensions = size
			outer.size = size
			branch = id+"-copy"
			app.hud.show_ending(level,{"collected":3,"total":3})
			await _capture("sheet")
			var paper: Rect2 = app.hud._overlay_paper.get_global_rect()
			_check(not app.hud._overlay_scroll.get_v_scroll_bar().is_visible_in_tree() and app.hud._overlay_scroll.scroll_vertical == 0,"authored long text remains fully visible / "+id+" / "+str(size))
			_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(paper),"authored text sheet fits viewport / "+id+" / "+str(size))
			var caption := "看看一路的纪事 ↗" if id == "cloud-3" else "去下一片微光 ↗"
			_check(paper.encloses(_button(caption,app.hud._overlay).get_global_rect()),"next / final journal caption remains visible / "+id+" / "+str(size))
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"sourceSha256":source_sha,"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images,"scope":"Six GPU sizes, completed 1-1 fixture in memory; real SubViewport button pointers. No user saves, browser input, audio or performance claim."},"  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images.size()}))
	await _dispose()
	finished = true
	quit(0 if failures.is_empty() else 1)
