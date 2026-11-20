extends "res://tests/native_route_test.gd"
## Real 3-3 body movement and E/menu actions through the unchanged 59-step route.
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var dimensions := Vector2i(1280, 720)
var outer: SubViewport
var images: Array = []
var events: Array = []
var branch := "authored"
var expect_wordless := false
var cold_only := false
var logger := ErrorLogger.new()
var finished := false

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
		elif argument == "--expect-wordless": expect_wordless = true
		elif argument == "--cold-only": cold_only = true
	create_timer(900).timeout.connect(func() -> void:
		if not finished: push_error("Symbiosis GPU capture timed out"); quit(2))
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
	app._enter_level("3-3")
	return _check(await _drain(), "3-3 cold entry settles from empty MemoryRepository")

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
	if id in ["valve:lift", "turn:water"] and not app.motion.is_empty():
		await _capture(label + "-motion-start")
		for unused in range(120):
			if app.motion.is_empty(): break
			if float(app.motion.elapsed) / float(app.motion.duration) >= 0.45: break
			await _tick()
		if not app.motion.is_empty(): await _capture(label + "-motion-middle")
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
	var words: Array = []
	_find_scene_words(app.view._props, words)
	if expect_wordless: _check(words.is_empty(), "3-3 scene uses natural props rather than Label3D: " + label)
	var snapshot: Dictionary = app.session.world.snapshot()
	images.append({"file": file, "branch": branch, "viewport": [dimensions.x, dimensions.y], "snapshot": snapshot, "sceneWords": words, "status": app.status_message, "menuOpen": app.hud.is_context_open(), "overview": app.view.overview, "motion": {} if app.motion.is_empty() else {"kind": app.motion.kind,"progress": float(app.motion.elapsed) / float(app.motion.duration)}, "captureExcludesAppTicks": true})
	print("CAPTURE " + file)

func _find_scene_words(node: Node, result: Array) -> void:
	if node is Label3D and node.visible and not str(node.text).strip_edges().is_empty():
		result.append({"name": str(node.get_path()), "text": str(node.text)})
	for child: Node in node.get_children(): _find_scene_words(child, result)

func _route(fixture: Dictionary) -> bool:
	await _capture("cold")
	app.hud._overview.pressed.emit()
	await _capture("cold-overview")
	app.hud._overview.pressed.emit()
	if cold_only: return true
	var executed := 0
	var expected_before: Dictionary = fixture.initial.snapshot
	for index: int in fixture.steps.size():
		app.hud.close_context_choices()
		var command: Dictionary = fixture.steps[index].command
		var success := false
		if str(command.kind) == "move": success = await _walk_to(str(command.value), "3-3 step " + str(index))
		elif str(command.kind) == "act":
			var actor: String = app.session.world.actor()
			var intended: String = str(expected_before.get("actors", {}).get(actor, expected_before.get("tile", "")))
			if not intended.is_empty() and intended != str(app.session.world.state.actors[actor]):
				if not await _walk_to(intended, "step " + str(index) + " approach"): return false
			success = await _e_action(str(command.value), "step-" + str(index) + "-" + str(command.value).replace(":", "-"))
		if not success: return false
		executed += 1
		expected_before = fixture.steps[index].snapshot
		_check(app.session.world.normalize_saved(app.session.world.snapshot()).get("ok", false), "3-3 step " + str(index) + " remains valid save")
		if index in [3, 8, 12, 19, 20, 24, 25, 30, 37, 38, 43, 44, 48, 49, 57]: await _capture("step-" + str(index))
		if index == 12: _check(not app.session.world.flag("root"), "four grown root segments do not auto-stabilize")
		if index == 25: _check(str(app.session.world.state.items.dew.get("holder", "")) == "luvie", "dew is actually carried after pickup")
		if index == 38: _check(app.session.world.flag("root"), "giving dew stabilizes root")
	var completed: bool = app.session.world.state.completed
	_check(completed and executed == 59, "3-3 completes original 59 intentions with actual bodies")
	routes.append({"branch": branch, "viewport": [dimensions.x, dimensions.y], "steps": executed, "completed": completed})
	if completed:
		app._on_command("stay")
		await _capture("completed")
	return completed

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["core/garden_world.gd", "application/main.gd", "application/native_movement.gd", "application/native_interaction.gd", "presentation/native/mechanism_props.gd", "presentation/native/symbiosis_dressing.gd", "presentation/native/original_prop_ratios.gd", "presentation/native/native_garden_stage.gd", "presentation/native/original_carry_art.gd", "tests/native_symbiosis_capture.gd", "tests/native_route_test.gd", "tests/fixtures/reference.json"]:
		result[path] = FileAccess.get_sha256("res://" + path) if FileAccess.file_exists("res://" + path) else "absent"
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Actual GPU and explicit symbiosis output required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var before := _hashes()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture := {}
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/3-3": fixture = entry
	_check(not fixture.is_empty() and fixture.steps.size() == 59, "original 3-3 fixture has 59 intentions")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		dimensions = size
		if await _start(): await _route(fixture)
		await _dispose()
	var after := _hashes()
	_check(before == after, "symbiosis production and capture sources stable")
	failures.append_array(logger.captured_errors())
	var report := {"suite": "native-symbiosis-real-app-gpu", "sourceSha256": source_sha, "sourceFilesStable": before == after, "initialSources": before, "finalSources": after, "routes": routes, "images": images, "events": events, "checks": checks, "failures": failures, "passed": failures.is_empty(), "samples": samples, "maxBodySurfaceGap": max_body_surface_gap, "maxVisualContactError": max_visual_penetration, "adapter": RenderingServer.get_video_adapter_name(), "scope": "Original 59 intentions at two sizes using native body movement, E input and actual menu signals. No state injection. AudioStub; not OS/browser input, Web performance or audio validation."}
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	finished = true
	print(JSON.stringify({"checks": checks, "images": images.size(), "routes": routes, "passed": report.passed, "failures": failures}))
	quit(0 if report.passed else 1)
