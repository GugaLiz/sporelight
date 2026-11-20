extends "res://tests/native_symbiosis_capture.gd"
## UI-only feedback: no puzzle solver, user saves or changes to world state.
func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(100).timeout.connect(func() -> void: if not finished: quit(2))
	_run.call_deferred()

func _press(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		outer.push_input(event,true)
	for unused in 6: await process_frame

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	for size: Vector2i in [Vector2i(1910,938),Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		dimensions = size
		outer.size = size
		for level: String in ["1-2","1-4"]:
			app.repository.data = Repository.empty_store()
			branch = level
			app._enter_level(level)
			_check(await _drain(),level+" cold settles / "+str(size))
			await _capture("follow")
			var overview: Button = app.hud._overview
			var navigation: Control = app.hud._nav
			_check(overview.position.x > size.x-200 and is_equal_approx(overview.position.y,navigation.position.y),"overview stays at top right next to pause/map / "+str(size))
			_check(overview.get_global_rect().end.x < navigation.get_global_rect().position.x,"top controls do not overlap / "+str(size))
			var before := JSON.stringify(app.session.world.state)
			await _press(overview)
			_check(app.view.overview and overview.text == "跟随","actual top-right click enters overview / "+str(size))
			_check(JSON.stringify(app.session.world.state)==before,"overview leaves puzzle state intact / "+str(size))
			if level == "1-2": await _capture("overview")
			await _press(overview)
			_check(not app.view.overview and overview.text == "全景","actual top-right click restores follow / "+str(size))
			_check(JSON.stringify(app.session.world.state)==before,"follow leaves puzzle state intact / "+str(size))
	failures.append_array(logger.captured_errors())
	var report := {"sourceSha256":source_sha,"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images,"scope":"Four GPU sizes, single/dual-player toolbar; real SubViewport pointer at overview/follow. In-memory saves, AudioStub; no browser/OS input or performance claim."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"checks":checks,"images":images.size(),"passed":failures.is_empty(),"failures":failures}))
	await _dispose()
	finished = true
	quit(0 if failures.is_empty() else 1)
