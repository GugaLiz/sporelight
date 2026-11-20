extends "res://tests/native_route_test.gd"
## Real 3-2 body movement and E/menu actions, both retained modes.
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var dimensions := Vector2i(1280, 720)
var outer: SubViewport
var images: Array = []
var events: Array = []
var branch := "sun-first"
var logger := ErrorLogger.new()
var finished := false

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(900).timeout.connect(func() -> void:
		if not finished: push_error("Shadow GPU capture timed out"); quit(2))
	_run.call_deferred()

func _start() -> bool:
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	app.repository.data = Repository.empty_store()
	app._enter_level("3-2")
	return _check(await _drain(), "3-2 cold entry settles from empty MemoryRepository")

func _dispose() -> void:
	app.queue_free()
	app = null
	outer.queue_free()
	await process_frame

func _e_action(id: String, label: String) -> bool:
	app.hud.close_context_choices()
	var revision: int = app.session.revision
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = pressed
		app._input(event)
	await RenderingServer.frame_post_draw
	var menu: bool = app.hud.is_context_open()
	if menu:
		var selected: Button
		for node: Node in app.hud._commands.get_children():
			if node is Button and str(node.get_meta("command_id", "")) == id: selected = node
		if not _check(selected != null and not selected.disabled, label + " original command offered by actual E menu: " + id): return false
		await _capture(label + "-menu")
		selected.pressed.emit()
	var settled := await _drain(700)
	var accepted: bool = app.session.revision > revision or bool(app.session.world.state.completed)
	events.append({"branch": branch, "label": label, "command": id, "viewport": [dimensions.x, dimensions.y], "accepted": accepted, "settled": settled, "status": app.status_message, "input": "application E press/release and actual menu Button signal"})
	return _check(settled and accepted, label + " succeeds through actual E/menu")

func _capture(label: String) -> void:
	app._update_layout()
	app.view._fit_camera(true)
	for unused in range(8): await RenderingServer.frame_post_draw
	var pixels := outer.get_texture().get_image()
	var file := "%s-%s-%dx%d.png" % [branch, label, dimensions.x, dimensions.y]
	_check(pixels != null and pixels.save_png(output.path_join(file)) == OK, "GPU original " + file)
	var roles := []
	for node: Node in app.view._props.get_children():
		if not node.has_meta("shadow_role"): continue
		roles.append({"role": node.get_meta("shadow_role"), "mode": node.get_meta("shadow_mode", -1), "tile": node.get_meta("tile_id", ""), "retained": node.get_meta("shadow_retained", false)})
	var snapshot: Dictionary = app.session.world.snapshot()
	images.append({"file": file, "branch": branch, "viewport": [dimensions.x, dimensions.y], "snapshot": snapshot, "roles": roles, "status": app.status_message, "menuOpen": app.hud.is_context_open(), "captureExcludesAppTicks": true})
	print("CAPTURE " + file)

func _route(fixture: Dictionary, moon_first: bool) -> bool:
	await _capture("cold")
	var executed := 0
	for index: int in fixture.steps.size():
		app.hud.close_context_choices()
		# Both branches arrange the same real pillars. The second branch keeps
		# moonlight first using original legal commands, never injecting state.
		if moon_first and index == 24:
			if not await _e_action("valve:mode", "moon-before-memory"): return false
			await _capture("moon-before-memory")
		var command: Dictionary = fixture.steps[index].command
		var success := false
		if str(command.kind) == "move": success = await _walk_to(str(command.value), branch + " step " + str(index))
		elif str(command.kind) == "act": success = await _e_action(str(command.value), "step-" + str(index) + "-" + str(command.value).replace(":", "-"))
		if not success: return false
		executed += 1
		_check(app.session.world.normalize_saved(app.session.world.snapshot()).get("ok", false), "3-2 step " + str(index) + " remains valid save")
		if index in [2, 5, 9, 17, 24, 26, 31]: await _capture("step-" + str(index))
		if index == 24:
			_check(int(app.session.world.state.frozen) == (1 if moon_first else 0), "actual memory retains intended sun/moon branch")
		if index == 26:
			_check(int(app.session.world.state.mode) != int(app.session.world.state.frozen), "current light differs from retained memory")
	var completed: bool = app.session.world.state.completed
	_check(completed and executed == 36, branch + " completes the original destination and reunion through real bodies")
	routes.append({"branch": branch, "viewport": [dimensions.x, dimensions.y], "steps": executed, "extraModeSwitch": moon_first, "completed": completed})
	if completed:
		app._on_command("stay")
		await _capture("completed")
	return completed

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["core/garden_world.gd", "application/main.gd", "application/native_movement.gd", "application/native_interaction.gd", "presentation/native/shadow_dressing.gd", "presentation/native/native_garden_stage.gd", "presentation/native/original_carry_art.gd", "tests/native_shadow_capture.gd", "tests/native_route_test.gd", "tests/fixtures/reference.json"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Actual GPU and explicit shadow output required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var before := _hashes()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture := {}
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/3-2": fixture = entry
	_check(not fixture.is_empty() and fixture.steps.size() == 36, "original 3-2 fixture has 36 intentions")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		dimensions = size
		for moon_first: bool in [false, true]:
			branch = "moon-first" if moon_first else "sun-first"
			if await _start(): await _route(fixture, moon_first)
			await _dispose()
	var after := _hashes()
	_check(before == after, "shadow production and capture sources stable")
	failures.append_array(logger.captured_errors())
	var report := {"suite": "native-shadow-real-app-gpu", "sourceSha256": source_sha, "sourceFilesStable": before == after, "initialSources": before, "finalSources": after, "routes": routes, "images": images, "events": events, "checks": checks, "failures": failures, "passed": failures.is_empty(), "samples": samples, "maxBodySurfaceGap": max_body_surface_gap, "maxVisualContactError": max_visual_penetration, "adapter": RenderingServer.get_video_adapter_name(), "scope": "Original 36 intentions and moon-first variant at two sizes using native body movement, E input and actual menu signals. No state injection. AudioStub; not OS/browser input, Web performance or audio validation."}
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	finished = true
	print(JSON.stringify({"checks": checks, "images": images.size(), "routes": routes, "passed": report.passed, "failures": failures}))
	quit(0 if report.passed else 1)
