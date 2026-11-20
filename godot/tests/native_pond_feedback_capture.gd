extends "res://tests/native_symbiosis_capture.gd"
## Feedback 121–123: route intentions use real bodies; menu actions use actual
## viewport mouse press/release, never Button.pressed.emit or world.apply.
var clicks: Array = []
var observation_contexts: Array = []

func _key_input(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = down
		outer.push_input(event, true)
		await process_frame

func _menu_action(id: String) -> bool:
	if id == "switch":
		await _key_input(KEY_T)
		return await _drain()
	app.hud.close_context_choices()
	var revision: int = app.session.revision
	await _key_input(KEY_E)
	for unused in 6: await RenderingServer.frame_post_draw
	if app.hud.is_context_open():
		var button: Button
		for child: Node in app.hud._commands.get_children():
			if child is Button and str(child.get_meta("command_id", "")) == id: button = child
		if not _check(button != null and not button.disabled, branch + " E offers " + id): return false
		app.hud._context_scroll.ensure_control_visible(button)
		for unused in 6: await RenderingServer.frame_post_draw
		var rect := button.get_global_rect()
		await _capture(id.replace(":", "-") + "-menu")
		for down: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = rect.get_center(); event.global_position = event.position
			event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
			outer.push_input(event, true)
			await process_frame
		clicks.append({"level":branch,"id":id,"rect":str(rect),"viewport":str(dimensions)})
	var settled := await _drain(900)
	return _check(settled and app.hud._page_kind != "settings" and (app.session.revision > revision or app.session.world.state.completed), branch + " pointer/primary accepted " + id + " without opening settings: " + app.status_message)

func _recovery_probe() -> void:
	branch = "2-3-recovery"
	app.repository.data = Repository.empty_store(); app._enter_level("2-3"); await _drain()
	await _menu_action("beat"); await _menu_action("beat"); await _menu_action("beat")
	_check(app.session.world.flag("raised") and str(app.session.world.state.actors.luvie) == "f:-4:0", "empty stage rises while traveller stays on low bank")
	await _menu_action("resetSong")
	_check(not app.session.world.flag("raised") and int(app.session.world.state.beat) == 0, "pointer reset restores empty stage, no restart needed")
	await _key_input(KEY_E)
	var before: Dictionary = app.session.world.snapshot()
	var location: Vector3 = app.view.get_actor_body("luvie").position
	var target := -1
	for index in app.hud._context_choices.size():
		if app.hud._context_choices[index].id == "beat": target = index
	for unused in app.hud._context_choices.size():
		if app.hud._context_index == target: break
		await _key_input(KEY_DOWN)
	_check(app.view.get_actor_body("luvie").position == location and before == app.session.world.snapshot(), "menu arrow navigation never moves actors or changes puzzle")
	await _key_input(KEY_ENTER); await _drain()
	_check(int(app.session.world.state.beat) == 1, "Enter confirms the selected beat once")
	await _key_input(KEY_E); await _key_input(KEY_ESCAPE)
	_check(not app.hud.is_context_open() and not app.hud.is_modal_open(), "Esc closes context without opening settings")
	await _capture("keyboard-recovery")

func _route_menu(fixture: Dictionary) -> void:
	branch = str(fixture.levelId)
	app.repository.data = Repository.empty_store()
	app._enter_level(branch); await _drain()
	var expected: Dictionary = fixture.initial.snapshot
	var executed := 0
	for step: Dictionary in fixture.steps:
		var command: Dictionary = step.command
		if command.kind == "move":
			if not await _walk_to(str(command.value), branch + " original route"): break
			if branch == "2-1" and str(command.value) in ["f:0:2", "m:float:0:0"]:
				observation_contexts.append({"tile":command.value,"context":app._native_interaction_context(),"held":app.session.world.state.items.dew})
		else:
			var who: String = app.session.world.actor()
			var intended := str(expected.get("actors", {}).get(who, expected.get("tile", "")))
			if not intended.is_empty() and intended != str(app.session.world.state.actors[who]):
				if not await _walk_to(intended, branch + " original action approach"): break
			if not await _menu_action(str(command.value)): break
		expected = step.snapshot
		executed += 1
	_check(app.session.world.state.completed and executed == fixture.steps.size(), branch + " completes original route with pointer menus")
	routes.append({"level":branch,"steps":executed,"expected":fixture.steps.size(),"completed":app.session.world.state.completed})
	await _capture("route-end")
	app._on_command("stay")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer); app.view._resize()
	app.set_meta("scripted_gpu_capture", true); app.set_process_input(true)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if str(fixture.name).begins_with("authored/") and str(fixture.levelId) in ["2-1", "2-2", "2-3", "2-4"]:
			await _route_menu(fixture)
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions = extent; outer.size = extent; app.view._resize()
		await _recovery_probe()
		branch = "2-4-small-menu"
		app.repository.data = Repository.empty_store(); app._enter_level("2-4"); await _drain()
		if await _walk_to("m:boat:0:0", "2-4 real walk to boat"):
			await _menu_action("use:plant")
			_check(app.session.world.flag("plant"), "boat menu plant changes its real flag")
			var memories: Dictionary = app.repository.data.mainline.memories.duplicate(true)
			await _key_input(KEY_R); await _drain()
			_check(not app.session.world.flag("plant") and app.hud._page_kind != "settings", "R restarts current level, never settings")
			_check(app.repository.data.mainline.memories == memories, "R keeps permanent memories")
			await _capture("restarted")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify({"source":source_sha,"passed":failures.is_empty(),"checks":checks,"failures":failures,"routes":routes,"clicks":clicks,"observationContexts":observation_contexts,"images":images,"scope":"Actual motor routes and native viewport E / pointer menus, memory-only saves; not browser input or performance."}, "  "))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"routes":routes,"failures":failures}))
	await _dispose(); finished = true; quit(0 if failures.is_empty() else 1)
