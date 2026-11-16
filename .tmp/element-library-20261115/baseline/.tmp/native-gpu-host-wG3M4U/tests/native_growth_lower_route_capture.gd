extends "res://tests/native_growth_frontier_capture.gd"
## The alternative 1-2 route uses real bodies and the unchanged four sockets.
var body_paths: Array = []
var _walk_label := ""
var _walk_origin := Vector3.ZERO
var _walk_captured := false

func _walk_to(id: String, label: String) -> bool:
	_walk_label = label.replace("/", "-").replace(" ", "-")
	_walk_origin = app.view.get_actor_body(app.session.world.actor()).position
	_walk_captured = false
	var reached := await super._walk_to(id, label)
	_walk_label = ""
	return reached

func _tick() -> void:
	await super._tick()
	if _walk_label.is_empty(): return
	var body: CharacterBody3D = app.view.get_actor_body(app.session.world.actor())
	body_paths.append({"walk":_walk_label,"support":str(app.session.world.state.actors[app.session.world.actor()]),"position":[body.position.x,body.position.y,body.position.z]})
	if not _walk_captured and body.position.distance_to(_walk_origin) > 0.3:
		_walk_captured = true
		await _capture(_walk_label + "-body-in-transit")

func _lower_route() -> bool:
	await _capture("cold")
	if not await _walk_to("f:1:1", "seedbed-approach"): return false
	var directions := ["down", "right", "right", "up"]
	for index in range(directions.size()):
		if not await _build("grow:root:" + directions[index], "section-" + str(index + 1)): return false
		_check(app.session.world.normalize_saved(app.session.world.snapshot()).get("ok",false), "lower route section remains a valid save")
	if not await _walk_to("g:root:3:1", "fourth-board-landing"): return false
	await _capture("fourth-board-standing")
	if not await _walk_to("f:4:1", "shore-approach"): return false
	await _capture("shore-standing")
	if not await _e_action("repair", "shore-flower"): return false
	var completed: bool = app.session.world.state.completed
	_check(completed and app.session.world.state.growth.root == ["g:root:1:2","g:root:2:2","g:root:3:2","g:root:3:1"], "lower four-board route reaches the flower and completes")
	if completed:
		var stay := _find_stay(app.hud)
		if not _check(stay != null, "completed lower route offers stay"): return false
		stay.pressed.emit()
		await _capture("completed")
	return completed

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": push_error("Actual GPU and output required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	current_level = "1-2"
	branch = "1-2-lower"
	dimensions = Vector2i(1280,720)
	var before := _hashes()
	before["tests/native_growth_lower_route_capture.gd"] = FileAccess.get_sha256("res://tests/native_growth_lower_route_capture.gd")
	var completed := false
	if await _start(): completed = await _lower_route()
	await _dispose()
	var after := _hashes()
	after["tests/native_growth_lower_route_capture.gd"] = FileAccess.get_sha256("res://tests/native_growth_lower_route_capture.gd")
	_check(before == after, "lower route production and capture sources stable")
	failures.append_array(logger.captured_errors())
	var report := {"suite":"growth-lower-route-real-input-gpu","sourceSha256":source_sha,"sourceFilesStable":before == after,"initialSources":before,"finalSources":after,"passed":failures.is_empty() and completed,"checks":checks,"failures":failures,"completed":completed,"images":images,"events":events,"extraWalks":extra_walks,"growthInputs":growth_inputs,"bodyPaths":body_paths,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"adapter":RenderingServer.get_video_adapter_name(),"scope":"1-2 lower four-board branch with actual native bodies, E/menu and scene mouse plus; no state injection or historical fixture edits. AudioStub; not browser input or performance acceptance."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ") + "\n")
	finished = true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures,"completed":completed,"images":images.size()}))
	quit(0 if report.passed else 1)
