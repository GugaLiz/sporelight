extends "res://tests/native_route_test.gd"
## Native application commands and physical walking, not injected play states.
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var dimensions := Vector2i(1280, 720)
var outer: SubViewport
var images: Array = []
var details: Array = []
var events: Array = []
var logger := ErrorLogger.new()
var sources_before: Dictionary = {}
var finished := false
var motion_capture := ""
var captured_midpoints: Array[String] = []

func _tick() -> void:
	await super._tick()
	if motion_capture.is_empty() or captured_midpoints.has(motion_capture) or app.motion.is_empty(): return
	var progress: float = float(app.motion.elapsed) / float(app.motion.duration)
	if progress >= 0.45 and progress < 0.85:
		captured_midpoints.append(motion_capture)
		_check(not app.motion.is_empty() and progress < 1.0, motion_capture + " comes from actual running mechanism motion")
		await _capture(motion_capture)

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(600).timeout.connect(func() -> void:
		if not finished:
			push_error("Rain-song actual application capture timed out")
			quit(2))
	_run.call_deferred()

func _act(id: String, label: String) -> bool:
	app.hud.close_context_choices()
	var before: Dictionary = app.session.world.snapshot()
	var revision: int = app.session.revision
	app._on_command(id)
	var settled := await _drain(700)
	var accepted: bool = app.session.revision > revision or bool(app.session.world.state.completed)
	events.append({"label": label, "id": id, "viewport": [dimensions.x, dimensions.y], "accepted": accepted, "settled": settled, "beforeBeat": before.beat, "afterBeat": app.session.world.state.beat, "status": app.status_message})
	return _check(settled and accepted, label + " actual application transaction settles: " + app.status_message)

func _menu(label: String) -> bool:
	app.hud.close_context_choices()
	app._on_command("primary")
	await RenderingServer.frame_post_draw
	return _check(app.hud.is_context_open(), label + " opens through the actual primary action")

func _press(id: String, label: String) -> bool:
	var choices: Array = app.hud._context_choices
	var at := -1
	for index in choices.size():
		if str(choices[index].id) == id: at = index
	if not _check(at >= 0 and not bool(choices[at].get("disabled", false)), label + " has a real available menu choice"): return false
	var buttons: Array = []
	for child: Node in app.hud._commands.get_children():
		if child is Button: buttons.append(child)
	if not _check(at < buttons.size(), label + " is represented by a real button"): return false
	var revision: int = app.session.revision
	buttons[at].pressed.emit()
	return _check(await _drain(700) and app.session.revision > revision, label + " button signal applies the transaction")

func _capture(label: String) -> void:
	app._update_layout()
	app.view._fit_camera(true)
	for unused in range(8): await RenderingServer.frame_post_draw
	var pixels := outer.get_texture().get_image()
	var file := "%s-%dx%d.png" % [label, dimensions.x, dimensions.y]
	_check(pixels != null and pixels.get_size() == dimensions and pixels.save_png(output.path_join(file)) == OK, "GPU original " + file)
	var bodies := {}
	for who: String in ["luvie", "buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		bodies[who] = {"position": [body.position.x, body.position.y, body.position.z], "support": app.session.world.state.actors[who], "clearOfHardProps": app.view.prop_physical_point_clear(body.position, who)}
	var labels: Array = []
	for node: Node in app.hud.find_children("*", "Label", true, false):
		if node.is_visible_in_tree() and not node.text.is_empty(): labels.append(node.text)
	var snapshot: Dictionary = app.session.world.snapshot()
	if label == "cold":
		# A 1:1 crop of this exact rendered frame, without a camera or asset edit.
		var instrument: MeshInstance3D = app.view._props_nodes["mark:song"].get_node("SongBase")
		var projected: Vector2 = app.view.world_to_screen(instrument.global_position + Vector3.UP * .18)
		var detail_size := Vector2i(260,200) if dimensions.x >= 1000 else Vector2i(200,150)
		var corner := Vector2i(projected) - detail_size / 2
		corner.x = clampi(corner.x,0,dimensions.x-detail_size.x)
		corner.y = clampi(corner.y,0,dimensions.y-detail_size.y)
		var detail_name := "instrument-detail-%dx%d.png" % [dimensions.x,dimensions.y]
		_check(pixels.get_region(Rect2i(corner,detail_size)).save_png(output.path_join(detail_name)) == OK, "unscaled instrument screenshot crop " + detail_name)
		details.append({"file":detail_name,"sourceFrame":file,"rect":[corner.x,corner.y,detail_size.x,detail_size.y],"unscaled":true})
	images.append({"file": file, "viewport": [dimensions.x, dimensions.y], "snapshot": snapshot, "bodies": bodies, "visibleHudLabels": labels, "menuOpen": app.hud.is_context_open(), "choices": app.hud._context_choices.duplicate(true) if app.hud.is_context_open() else [], "status": app.status_message, "nativeContext": app._native_interaction_context(), "motionEmpty": app.motion.is_empty(), "motion": {} if app.motion.is_empty() else {"kind": app.motion.kind, "progress": float(app.motion.elapsed) / float(app.motion.duration)}, "captureExcludesAppTicks": true})
	print("CAPTURE " + file)

func _intro_trials() -> bool:
	# Preserve the original zero-beat pause/edit/reset behavior.
	if not await _act("play", "zero-beat trial starts"): return false
	if not await _act("play", "zero-beat trial pauses"): return false
	if not await _act("swap:0", "original zero-beat pause remains editable"): return false
	_check(app.session.world.state.song == ["rise", "turn", "rest"], "zero-beat editing is not truncated by a new trial restriction")
	if not await _menu("zero-beat menu"): return false
	await _capture("zero-beat-paused")
	if not await _press("resetSong", "zero-beat restore"): return false
	_check(app.session.world.state.song == ["turn", "rise", "rest"], "reset retains the original pre-trial arrangement semantics")
	# A legal wrong-order phrase is observable and can safely return to its origin.
	if not await _act("swap:0", "arrange rise before turn"): return false
	if not await _act("beat", "wrong-order first rise"): return false
	if not await _act("beat", "wrong-order blocked turn"): return false
	_check("raised" in app.session.world.state.flags and int(app.session.world.state.turns.stage) == 0 and int(app.session.world.state.beat) == 2, "wrong-order turn consumes its beat while height limit preserves orientation")
	if not await _menu("wrong-order recovery menu"): return false
	await _capture("wrong-order-recovery")
	if not await _press("resetSong", "wrong-order restore"): return false
	_check(not "raised" in app.session.world.state.flags and int(app.session.world.state.beat) == 0, "actual reset returns the stage and performers to the rehearsal origin")
	if not await _act("swap:0", "restore default authored phrase"): return false
	return _check(app.session.world.state.song == ["turn", "rise", "rest"], "demos restore the original arrangement through offered exchanges")

func _run_size(fixture: Dictionary) -> void:
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	app.repository.data = Repository.empty_store()
	captured_midpoints.clear()
	app._enter_level("2-3")
	await _drain()
	_check(int(app.session.world.state.beat) == 0 and not app.session.world.state.playing and app.session.world.state.song == ["turn", "rise", "rest"], "cold native entry preserves the original valid default phrase")
	await _capture("cold")
	if not await _menu("initial piano menu"): return
	await _capture("piano-menu")
	var menu_scroll: ScrollContainer = app.hud.find_child("ContextChoicesScroll", true, false)
	menu_scroll.scroll_vertical = int(menu_scroll.get_v_scroll_bar().max_value)
	await _capture("piano-menu-actions")
	var buttons: Array = app.hud._commands.get_children().filter(func(child: Node) -> bool: return child is Button)
	_check(not buttons.is_empty() and menu_scroll.get_global_rect().intersects(buttons.back().get_global_rect()), "scroll reveals the final offered action without leaving the actual menu")
	menu_scroll.scroll_vertical = 0
	if not await _intro_trials(): return
	var executed := 0
	var success := true
	for index in fixture.steps.size():
		var step: Dictionary = fixture.steps[index]
		var command: Dictionary = step.command
		app.hud.close_context_choices()
		if str(command.kind) == "move":
			success = await _walk_to(str(command.value), "original rain intention %d" % index)
		elif str(command.kind) == "act":
			motion_capture = "turn-mid" if index == 6 else "rise-mid" if index == 7 else ""
			success = await _act(str(command.value), "original rain intention %d" % index)
			motion_capture = ""
		else:
			success = _check(false, "unexpected rain fixture command")
		if not success: break
		executed += 1
		_check(app.session.world.normalize_saved(app.session.world.snapshot()).get("ok", false), "original rain step %d remains a valid saved journey" % index)
		if index == 3: await _capture("passenger-ready")
		elif index == 5:
			if not await _menu("pianist ready"): break
			await _capture("pianist-ready-menu")
		elif index == 6:
			if not await _menu("after first beat"): break
			await _capture("turn-paused-menu")
		elif index == 7: await _capture("stage-raised")
		elif index == 8:
			_check(app.session.world.commands().any(func(entry: Dictionary) -> bool: return str(entry.id) == "play") and app.session.world.commands().any(func(entry: Dictionary) -> bool: return str(entry.id) == "beat"), "original end-of-phrase controls remain offered without new truncation")
			if not await _menu("phrase completed"): break
			await _capture("phrase-ended-menu")
		elif index == 14: await _capture("latch-fixed")
	var complete: bool = app.session.world.state.completed
	_check(success and executed == 27 and complete, "original 27 rain intentions complete through real bodies and actions")
	_check(captured_midpoints.has("turn-mid") and captured_midpoints.has("rise-mid"), "original turn and rise both have real rendered midpoints")
	routes.append({"level": "2-3", "viewport": [dimensions.x, dimensions.y], "success": success, "completed": complete, "steps": executed, "expectedSteps": 27, "extraDemosReturnedThroughLegalCommands": true})
	if complete:
		for button: Node in app.hud.find_children("*", "Button", true, false):
			if button.text == "留下看看":
				button.pressed.emit()
				break
		await _capture("completed")
	app.queue_free()
	app = null
	outer.queue_free()
	await process_frame

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["tests/native_rain_song_capture.gd", "tests/native_route_test.gd", "tests/fixtures/reference.json", "core/garden_world.gd", "application/main.gd", "application/native_movement.gd", "application/native_interaction.gd", "application/journey_view.gd", "application/rain_song_guidance.gd", "ui/garden_hud.gd", "presentation/native/mechanism_props.gd", "presentation/native/native_garden_stage.gd", "content/levels.json"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Actual GPU and explicit output required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	sources_before = _hashes()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary = {}
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/2-3": fixture = entry
	_check(not fixture.is_empty() and fixture.steps.size() == 27, "frozen original rain route has 27 atomic intentions")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		dimensions = size
		await _run_size(fixture)
	var sources_after := _hashes()
	_check(sources_before == sources_after, "production and capture sources remain stable during the batch")
	_check(images.size() == 28, "two sizes include original controls, menu scrolling and real turn/rise motion frames")
	failures.append_array(logger.captured_errors())
	var report := {"suite": "native-rain-song-real-app-gpu", "sourceSha256": source_sha, "sourceFilesStable": sources_before == sources_after, "initialSources": sources_before, "finalSources": sources_after, "images": images, "events": events, "originalRoutes": routes, "checks": checks, "failures": failures, "passed": failures.is_empty(), "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "scope": "Native empty-memory entry, actual body walking and original 27 intentions plus original pause/edit/reset demonstrations; no expanded remote control or truncated terminal actions. Menus opened by primary and original restore by button signals. No play snapshot injection. Screenshots wait actual draws without app ticks; not browser input or Web performance evidence."}
	report["detailCrops"] = details
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	finished = true
	print(JSON.stringify({"checks": checks, "images": images.size(), "passed": report.passed, "failures": failures}))
	quit(0 if report.passed else 1)
