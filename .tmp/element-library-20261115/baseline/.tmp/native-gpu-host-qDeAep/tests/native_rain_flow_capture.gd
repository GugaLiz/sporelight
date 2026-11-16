extends "res://tests/native_rain_song_capture.gd"
## Additional native input/recovery flows. The inherited authored replay still
## executes all 27 original intentions at both sizes without installing states.
const RainNotation = preload("res://application/rain_song_guidance.gd")
var flow_cases: Array = []
var recovery_probes: Array = []
var pose_restores: Array = []

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(1200).timeout.connect(func() -> void:
		if not finished:
			push_error("Rain-flow actual application capture timed out")
			quit(2))
	_run.call_deferred()

func _start_flow() -> bool:
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	app.repository.data = Repository.empty_store()
	app._enter_level("2-3")
	return _check(await _drain(), "fresh flow enters through an empty MemoryRepository")

func _dispose_flow() -> void:
	app.queue_free()
	app = null
	outer.queue_free()
	await process_frame

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	app._input(event)

func _e_menu(label: String) -> bool:
	app.hud.close_context_choices()
	_key(KEY_E, true)
	_key(KEY_E, false)
	await RenderingServer.frame_post_draw
	events.append({"label": label, "input": "E key press/release through application _input", "viewport": [dimensions.x, dimensions.y], "opened": app.hud.is_context_open(), "status": app.status_message})
	return _check(app.hud.is_context_open(), label + " opens through the real E input handler")

func _button(id: String) -> Button:
	for child: Node in app.hud._commands.get_children():
		if child is Button and str(child.get_meta("command_id", "")) == id:
			return child
	return null

func _bodies_supported(label: String) -> bool:
	var valid := true
	for who: String in ["luvie", "buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		var support := str(app.session.world.state.actors[who])
		var floor_height: float = app.view.support_height(body.position, support, who)
		valid = _check(not app.session.world.point_for(support).is_empty() and absf(body.position.y - floor_height) <= .08 and app.view.prop_physical_point_clear(body.position, who), label + " " + who + " has a real clear grounded support") and valid
	return valid

func _trial_poses_restored(trial: Dictionary, label: String) -> bool:
	var valid := true
	var expected_poses: Dictionary = trial.get("runtime", {}).get("poses", {})
	var actual_poses: Dictionary = app.session.world.state.get("runtime", {}).get("poses", {})
	var bodies: Dictionary = app.native_movement.qa_state()
	var deltas := {}
	for who: String in ["luvie", "buddy"]:
		var pose: Dictionary = expected_poses.get(who, {})
		var offset: Array = pose.get("offset", [])
		var support := str(trial.actors[who])
		if not _check(str(pose.get("support", "")) == support and offset.size() == 3, label + " records the original " + who + " trial pose"):
			valid = false
			continue
		var tile: Dictionary = app.session.world.point_for(support)
		if not _check(not tile.is_empty() and str(app.session.world.state.actors[who]) == support, label + " returns " + who + " to the trial support"):
			valid = false
			continue
		var center: Vector3 = app.view.logical_position(app.view.tile_position(tile))
		var expected: Vector3 = app.view.physical_position(center + Vector3(float(offset[0]), float(offset[1]), float(offset[2])))
		var body: CharacterBody3D = app.view.get_actor_body(who)
		var horizontal := Vector2(body.position.x - expected.x, body.position.z - expected.z).length()
		var vertical := absf(body.position.y - expected.y)
		var facing := str(bodies.actors[who].facing)
		var restored_pose: Dictionary = actual_poses.get(who, {})
		var restored_offset: Array = restored_pose.get("offset", [])
		var runtime_matches := restored_offset.size() == 3 and str(restored_pose.get("support", "")) == support and str(restored_pose.get("facing", "")) == str(pose.get("facing", ""))
		if runtime_matches:
			runtime_matches = Vector2(float(restored_offset[0]) - float(offset[0]), float(restored_offset[2]) - float(offset[2])).length() <= .01 and absf(float(restored_offset[1]) - float(offset[1])) <= .03
		deltas[who] = {"expectedPosition": [expected.x, expected.y, expected.z], "actualPosition": [body.position.x, body.position.y, body.position.z], "horizontalError": horizontal, "verticalError": vertical, "expectedFacing": str(pose.get("facing", "")), "actualFacing": facing, "runtimeMatches": runtime_matches}
		valid = _check(horizontal <= .01 and vertical <= .03 and facing == str(pose.get("facing", "")) and runtime_matches, label + " restores " + who + " original trial footpoint/runtime/facing (XZ <= 1cm, floor solver <= 3cm)") and valid
	pose_restores.append({"label": label, "viewport": [dimensions.x, dimensions.y], "passed": valid, "expectedRuntime": trial.get("runtime", {}).duplicate(true), "actualRuntime": app.session.world.state.get("runtime", {}).duplicate(true), "deltas": deltas, "actualBodies": bodies})
	return valid

func _wait_for_beat(target: int, label: String) -> bool:
	for unused in range(900):
		await _tick()
		if app.motion.is_empty() and int(app.session.world.state.beat) >= target:
			return _check(true, label + " reaches committed beat " + str(target))
	return _check(false, label + " automatic playback failed to advance: " + app.status_message)

func _reverse_division() -> bool:
	if not await _act("swap:1", "reverse arrange turn/rest/rise"): return false
	if not await _act("switch", "reverse choose buddy passenger"): return false
	if not await _walk_to("m:stage:0:0", "reverse buddy walks onto stage"): return false
	if not await _act("switch", "reverse return to pianist"): return false
	for beat in range(3):
		if not await _act("beat", "reverse single beat " + str(beat + 1)): return false
	var trial: Dictionary = JSON.parse_string(str(app.session.world.state.trial))
	_check(app.session.world.state.song == ["turn", "rest", "rise"] and app.session.world.state.actors.buddy == "m:stage:0:0" and app.session.world.state.actors.luvie == "f:-4:0", "user division remains legal without automatic reassignment")
	await _capture("flow-reverse-user-state")
	if not await _act("switch", "reverse select distant buddy"): return false
	if not await _e_menu("reverse distant recovery"): return false
	await _capture("flow-reverse-remote-menu")
	if not await _press("resetSong", "reverse remote reset button"): return false
	_check(app.session.world.actor() == "luvie" and app.session.world.state.actors.buddy == "m:stage:0:0" and not app.session.world.flag("raised") and int(app.session.world.state.beat) == 0, "reverse reset restores the original trial division rather than choosing another solution")
	var supported := _bodies_supported("reverse reset")
	supported = _trial_poses_restored(trial, "reverse reset") and supported
	await _capture("flow-reverse-restored")
	return supported

func _two_passenger_reload() -> bool:
	for id: String in ["swap:0", "swap:1", "swap:0"]:
		if not await _act(id, "two-passenger arrange " + id): return false
	if not await _act("switch", "two-passenger select buddy"): return false
	if not await _walk_to("m:stage:0:1", "two-passenger buddy distinct platform support"): return false
	if not await _act("switch", "two-passenger select pianist"): return false
	if not await _act("beat", "two-passenger first rest"): return false
	var trial: Dictionary = JSON.parse_string(str(app.session.world.state.trial))
	if not await _walk_to("f:-5:0", "two-passenger discovers a shore spore after trial starts"): return false
	if not await _act("observe:rest", "two-passenger makes an original optional observation after trial starts"): return false
	if not await _walk_to("m:stage:0:0", "two-passenger pianist legally joins the platform"): return false
	_check(app.session.world.state.collected.size() > trial.collected.size(), "a real post-trial collection makes discovery retention non-vacuous")
	_check(app.session.world.state.observations.size() > trial.observations.size(), "a real post-trial observation makes observation retention non-vacuous")
	if not await _e_menu("two-passenger remote playback"): return false
	if not await _press("play", "two-passenger original remote play button"): return false
	if not await _wait_for_beat(3, "two-passenger phrase"): return false
	_check(app.session.world.state.song == ["rest", "rise", "turn"] and int(app.session.world.state.turns.stage) == 0 and app.session.world.flag("raised") and not app.session.world.state.playing, "original raised turn consumes its beat without rotating")
	for who: String in ["luvie", "buddy"]:
		_check(not app.session.world.has_path_to("f:-4:0", who) and not app.session.world.has_path_to("f:0:-4", who), "two-passenger " + who + " has no walking route to either shore")
	_bodies_supported("two-passenger before reload")
	await _capture("flow-two-passenger-raised")
	var before: Dictionary = app.session.world.snapshot()
	var repository_id: int = app.repository.get_instance_id()
	var positions := {}
	for who: String in ["luvie", "buddy"]: positions[who] = app.view.get_actor_body(who).position
	app._save()
	_check(app.repository.data.mainline.runs.has("2-3"), "real application save stages the legal high-platform run")
	app._enter_level("2-3")
	if not _check(await _drain(), "same-repository continuation settles"): return false
	_check(app.repository.get_instance_id() == repository_id and not app.session.world.can_undo(), "same MemoryRepository continuation restores the run without undo history")
	_check(app.session.world.state.actors == before.actors and app.session.world.state.song == before.song and app.session.world.state.collected == before.collected and app.session.world.state.observations == before.observations, "continuation retains positions, arrangement and actual discoveries")
	for who: String in ["luvie", "buddy"]:
		_check(app.view.get_actor_body(who).position.distance_to(positions[who]) < .08, "continuation restores the actual " + who + " pose")
	_bodies_supported("two-passenger continuation")
	await _capture("flow-two-passenger-reloaded")
	if not await _e_menu("two-passenger continued recovery"): return false
	await _capture("flow-two-passenger-reload-menu")
	if not await _press("resetSong", "two-passenger continued reset button"): return false
	_check(app.session.world.state.actors == trial.actors and app.session.world.actor() == str(trial.active) and not app.session.world.flag("raised") and int(app.session.world.state.beat) == 0, "continued reset returns both actors to the original trial supports")
	for collected: String in before.collected:
		_check(collected in app.session.world.state.collected, "continued reset retains actual collection " + collected)
	_check(app.session.world.state.observations == before.observations, "continued reset retains original observation semantics")
	var supported := _bodies_supported("two-passenger restored")
	supported = _trial_poses_restored(trial, "two-passenger restored") and supported
	await _capture("flow-two-passenger-restored")
	return supported

func _automatic_menu() -> bool:
	if not await _act("play", "automatic phrase starts"): return false
	if not await _e_menu("automatic running menu"): return false
	var reset := _button("resetSong")
	if not _check(reset != null, "automatic menu includes original reset button"): return false
	reset.grab_focus()
	app.hud._context_scroll.scroll_vertical = int(app.hud._context_scroll.get_v_scroll_bar().max_value)
	for unused in range(3): await RenderingServer.frame_post_draw
	var scroll: int = app.hud._context_scroll.scroll_vertical
	await _capture("flow-automatic-menu-start")
	for beat in range(1, 4):
		if not await _wait_for_beat(beat, "automatic open-menu phrase"): return false
		for unused in range(3): await RenderingServer.frame_post_draw
		_check(app.hud.is_context_open() and app.hud._rain_summary.text == RainNotation.summary(app.session.world), "automatic menu reports committed sequence/progress/effect at beat " + str(beat))
		var play := _button("play")
		var offered: Array = app.session.world.commands().filter(func(row: Dictionary) -> bool: return str(row.id) == "play")
		_check(play != null and not offered.is_empty() and play.text == str(offered[0].label), "automatic menu retains current original play label at beat " + str(beat))
		_check(bool(app.session.world.state.playing) == (beat < 3), "open menu does not pause the original clock at beat " + str(beat))
		var bar: VScrollBar = app.hud._context_scroll.get_v_scroll_bar()
		_check(outer.gui_get_focus_owner() == _button("resetSong") and app.hud._context_scroll.scroll_vertical == mini(scroll, maxi(0, int(bar.max_value - bar.page))), "automatic menu preserves reset focus and legal scrolling at beat " + str(beat))
		await _capture("flow-automatic-menu-beat-" + str(beat))
	return await _press("resetSong", "automatic final menu reset button")

func _default_high_passenger() -> bool:
	if not await _walk_to("m:stage:0:0", "probe passenger boards"): return false
	if not await _act("switch", "probe pianist takes control"): return false
	if not await _walk_to("f:-4:0", "probe pianist reaches piano"): return false
	if not await _act("beat", "probe original turn"): return false
	if not await _act("beat", "probe original rise"): return false
	return await _act("switch", "probe passenger takes control")

func _walk_to_edge(code: Key, axis: Vector2, label: String) -> bool:
	app.hud.close_context_choices()
	var support := str(app.session.world.state.actors[app.session.world.actor()])
	var tile: Dictionary = app.session.world.point_for(support)
	var reached := false
	_key(code, true)
	for unused in range(90):
		await _tick()
		var body: CharacterBody3D = app.view.get_actor_body(app.session.world.actor())
		var logical: Vector3 = app.view.logical_position(body.position)
		var projection := Vector2(logical.x - float(tile.x), logical.z - float(tile.z)).dot(axis)
		if str(app.session.world.state.actors[app.session.world.actor()]) != support: break
		if projection >= .34:
			reached = true
			break
	_key(code, false)
	await _drain()
	return _check(reached, label + " reaches the real connected edge through held directional input")

func _reset_probe(label: String) -> bool:
	if not await _e_menu(label + " recovery menu"): return false
	await _capture(label + "-menu")
	var button := _button("resetSong")
	if not _check(button != null and not button.disabled, label + " has an original available reset button"): return false
	var before: Dictionary = app.session.world.snapshot()
	var trial: Dictionary = JSON.parse_string(str(before.trial))
	var bodies: Dictionary = app.native_movement.qa_state()
	var revision: int = app.session.revision
	button.pressed.emit()
	var settled := await _drain(700)
	var accepted: bool = app.session.revision > revision and int(app.session.world.state.beat) == 0 and str(app.session.world.state.get("trial", "")).is_empty()
	recovery_probes.append({"label": label, "viewport": [dimensions.x, dimensions.y], "accepted": accepted, "settled": settled, "status": app.status_message, "before": before, "beforeBodies": bodies, "after": app.session.world.snapshot(), "afterBodies": app.native_movement.qa_state()})
	_check(settled and accepted, label + " original reset restores the trial from a real edge/stair: " + app.status_message)
	var poses_restored := false
	if accepted:
		poses_restored = _bodies_supported(label + " restored")
		poses_restored = _trial_poses_restored(trial, label + " restored") and poses_restored
	await _capture(label + ("-restored" if accepted else "-refused"))
	return settled and accepted and poses_restored

func _edge_recovery() -> bool:
	if not await _default_high_passenger(): return false
	if not await _walk_to("m:stage:-2:0", "edge probe north-facing stage endpoint"): return false
	if not await _walk_to_edge(KEY_W, Vector2(0, -1), "stage edge probe"): return false
	return await _reset_probe("flow-stage-edge-reset")

func _stair_recovery() -> bool:
	if not await _default_high_passenger(): return false
	if not await _walk_to("f:0:-4", "stair probe reaches real latch"): return false
	if not await _act("use:latch", "stair probe fixes original reunion path"): return false
	await _capture("flow-stair-latch-fixed")
	if not await _walk_to("f:-4:-2", "stair probe passenger walks onto reunion stair"): return false
	if not await _walk_to_edge(KEY_S, Vector2(0, 1), "reunion stair probe"): return false
	if not await _act("switch", "stair probe pianist selects existing piano reset"): return false
	return await _reset_probe("flow-reunion-stair-reset")

func _run_flow_size() -> void:
	for entry: Array in [["reverse-division", _reverse_division], ["two-passenger-continuation", _two_passenger_reload], ["automatic-open-menu", _automatic_menu], ["stage-edge-reset", _edge_recovery], ["reunion-stair-reset", _stair_recovery]]:
		var started := Time.get_ticks_msec()
		var success := false
		if await _start_flow(): success = await entry[1].call()
		flow_cases.append({"id": entry[0], "viewport": [dimensions.x, dimensions.y], "success": success, "elapsedMs": Time.get_ticks_msec() - started})
		await _dispose_flow()

func _hashes() -> Dictionary:
	var hashes: Dictionary = super._hashes()
	for path: String in ["tests/native_rain_flow_capture.gd", "services/save_repository.gd", "application/game_session.gd", "application/input_router.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes

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
	_check(not fixture.is_empty() and fixture.steps.size() == 27, "frozen original rain route retains 27 atomic intentions")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		dimensions = size
		await _run_flow_size()
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		dimensions = size
		await super._run_size(fixture)
	var sources_after := _hashes()
	_check(sources_before == sources_after, "flow production and capture sources remain stable during the batch")
	failures.append_array(logger.captured_errors())
	var report := {"suite": "native-rain-flow-real-app-gpu", "sourceSha256": source_sha, "testSha256": FileAccess.get_sha256("res://tests/native_rain_flow_capture.gd"), "sourceFilesStable": sources_before == sources_after, "initialSources": sources_before, "finalSources": sources_after, "flowCases": flow_cases, "recoveryProbes": recovery_probes, "trialPoseRestores": pose_restores, "images": images, "detailCrops": details, "events": events, "originalRoutes": routes, "checks": checks, "failures": failures, "passed": failures.is_empty(), "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "scope": "Native real body walking; app commands, synthetic E press/release through the real application input handler and actual menu Button signals. Legal reverse division, two passengers at distinct supports, same MemoryRepository save/continuation without history, open-menu automatic beats and real stage-edge/reunion-stair reset probes. Each reverse/two-passenger/edge/stair reset compares bodies, runtime poses and facing with the original trial (XZ <= 1cm; floor solver Y <= 3cm). Original 27-intention fixture replayed unchanged at 1280x720 and 844x390. No actor/snapshot injection or teleport; no fixed screenshot total. AudioStub retained, so this suite does not validate audio, OS-level touch, browser input or Web performance. Screenshots wait actual GPU draws without advancing application ticks."}
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	finished = true
	print(JSON.stringify({"checks": checks, "images": images.size(), "flowCases": flow_cases, "passed": report.passed, "failures": failures}))
	quit(0 if report.passed else 1)
