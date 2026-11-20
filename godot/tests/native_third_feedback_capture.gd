extends "res://tests/native_pond_feedback_capture.gd"
## Report 124: real body travel, native keyboard and pointer menu input.
var probes: Array = []

func _fresh(level_id: String) -> void:
	app.hud.close_context_choices()
	app.repository.data = Repository.empty_store()
	app._enter_level(level_id)
	await _drain()

func _lamp_transfer(tile: String, reload_save: bool) -> void:
	branch = "lamp-" + tile.replace(":", "-") + ("-reload" if reload_save else "")
	await _fresh("3-1")
	if not await _menu_action("take:lamp"): return
	if not await _walk_to(tile, "hero carries lamp to drop location"): return
	if not await _menu_action("drop:lamp:" + tile): return
	_check(app.session.world.state.items.lamp.get("holder", "").is_empty() and app.session.world.state.items.lamp.tile == tile, "lamp actually placed, independent of collectible count")
	if reload_save:
		app._enter_level("3-1")
		await _drain()
		_check(app.session.world.state.items.lamp.tile == tile and app.session.world.state.items.lamp.get("holder", "").is_empty(), "saved ground lamp restored")
	if not await _menu_action("switch"): return
	if not await _walk_to(tile, "buddy physically approaches dropped lamp"): return
	probes.append({"branch":branch,"context":app._native_interaction_context(),"lamp":app.session.world.state.items.lamp.duplicate(true)})
	if not await _menu_action("take:lamp"): return
	_check(app.session.world.state.items.lamp.get("holder", "") == "buddy", "buddy picks up hero's dropped lamp via E/pointer")
	await _capture("buddy-holds-lamp")

func _hints() -> void:
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions = extent; outer.size = extent; app.view._resize()
		branch = "3-4-hint"
		await _fresh("3-4")
		await _key_input(KEY_H)
		for tier in 3:
			if tier > 0:
				var rect: Rect2 = app.hud._hint_button.get_global_rect()
				for down: bool in [true,false]:
					var event := InputEventMouseButton.new()
					event.position = rect.get_center(); event.global_position = event.position
					event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
					outer.push_input(event,true)
					await process_frame
			await _capture("tier-" + str(tier+1))
			var label: Label = app.hud._hint_label
			var font: Font = label.get_theme_font("font")
			var missing := []
			for character in label.text:
				if character.unicode_at(0) > 127 and not font.has_char(character.unicode_at(0)): missing.append(character)
			_check(missing.is_empty(), "hint font covers all Chinese glyphs")
			_check(label.get_line_count() == label.get_visible_line_count(), "hint lines fit actual label")
			probes.append({"branch":branch,"viewport":str(extent),"tier":tier,"text":label.text,"missingGlyphs":missing,"rect":str(label.get_global_rect())})

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer); app.view._resize()
	app.set_meta("scripted_gpu_capture", true); app.set_process_input(true)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	for tile: String in ["f:-3:0","f:-2:0"]:
		await _lamp_transfer(tile,false)
	await _lamp_transfer("f:-2:0",true)
	branch = "3-2-posts"
	for tile: String in ["f:-2:0","f:-2:1"]:
		await _fresh("3-2")
		if await _walk_to(tile,"physically reach shadow post"):
			await _menu_action("take:sunPost" if tile == "f:-2:0" else "take:moonPost")
			_check(app.session.world.state.items["sunPost" if tile == "f:-2:0" else "moonPost"].get("holder", "") == "luvie", "actual post picked up through pointer menu")
	await _hints()
	dimensions = Vector2i(1280,720); outer.size = dimensions; app.view._resize()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if str(fixture.name).begins_with("authored/") and str(fixture.levelId) in ["3-1","3-2","3-3","3-4"]:
			branch = str(fixture.levelId)
			app.hud.close_context_choices(); app.hud.hide_hint()
			app.repository.data = Repository.empty_store()
			if branch in ["3-1","3-2"]:
				await _route_menu(fixture)
			else:
				await _replay(branch,fixture.steps,fixture.initial.snapshot)
			await _capture("complete-route")
			app._on_command("stay")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"source":source_sha,"passed":failures.is_empty(),"checks":checks,"failures":failures,"routes":routes,"clicks":clicks,"probes":probes,"images":images,"scope":"Targeted native viewport keyboard/pointer pickup and hint probes; four original routes use application commands and actual physical bodies. Not browser/performance tests."},"  "))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"routes":routes,"failures":failures}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
