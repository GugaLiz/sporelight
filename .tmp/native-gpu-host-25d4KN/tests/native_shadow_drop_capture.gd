extends "res://tests/native_shadow_capture.gd"
## Regression for immediately re-placing a moon pillar after its first placement.

func _drop_diagnostics(label: String) -> Dictionary:
	var stage: Node = app.view
	var world: RefCounted = app.session.world
	var tile: Dictionary = world.point_for(str(world.state.actors.luvie))
	var body: CharacterBody3D = stage.get_actor_body("luvie")
	var predicted: Array = stage._prop_obstacles.duplicate()
	var pending: Dictionary = stage.PropObstacles.placement_entry("moonPost", stage.tile_position(world.point_for("f:3:-1")), "3-2")
	predicted.append(pending)
	var preferred := body.position
	preferred.y = stage.tile_position(tile).y
	var safe: Dictionary = stage.PropObstacles.waypoint(stage, tile, "luvie", preferred, predicted)
	var report := {"label":label,"actor":str(world.state.actors.luvie),"position":body.position,"buddy":stage.get_actor_body("buddy").position,"safe":safe,"stance":stage.prop_drop_stance("f:3:-1","luvie","moonPost"),"obstacles":stage._prop_obstacles}
	report.buddyClearExisting = stage.prop_point_clear(stage.get_actor_body("buddy").position,"buddy")
	report.buddyClearPending = stage.PropObstacles.clear(stage.get_actor_body("buddy").position,stage._prop_actor_radius("buddy"),[pending],stage._prop_actor_height("buddy"))
	if not safe.is_empty():
		report.direct = stage.prop_segment_clear(body.position,safe.point,"luvie")
		report.localRoute = stage.prop_local_route(tile,"luvie",body.position,safe.point)
	print("DROP_DIAGNOSTIC " + JSON.stringify(report))
	return report

func _cycle(fixture: Dictionary) -> bool:
	for index: int in range(18):
		var command: Dictionary = fixture.steps[index].command
		var ok := await _walk_to(str(command.value), "arrange " + str(index)) if command.kind == "move" else await _e_action(str(command.value), "arrange-" + str(index))
		if not ok: return false
		if index == 5:
			app._on_command("follow")
			await _drain(700)
			_check(not app.session.world.state.follow,"buddy waits on original start island")
		if index == 16: _drop_diagnostics("before first moon placement with waiting buddy")
	await _capture("moon-first-placement")
	app._on_command("switch")
	await _drain(700)
	_check(app.native_movement.request_local_target(Vector3(-.10,0,.30)),"buddy can approach existing day base")
	await _drain(700)
	for code: Key in [KEY_W]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = true
		app._input(event)
	for unused in range(12): await _tick()
	for code: Key in [KEY_W]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = false
		app._input(event)
	await _drain(700)
	app._on_command("switch")
	await _drain(700)
	if not await _e_action("take:moonPost", "moon-immediate-retake"): return false
	_drop_diagnostics("immediate-retake")
	await _capture("moon-retaken")
	var buddy_before: Vector3 = app.view.get_actor_body("buddy").position
	_check(not app.view.prop_point_clear(buddy_before,"buddy") and app.view.prop_physical_point_clear(buddy_before,"buddy"),"waiting buddy is a real physical contact inside extra planner margin")
	if not await _e_action("drop:moonPost:f:3:-1", "moon-immediate-replace"): return false
	_check(app.view.get_actor_body("buddy").position.distance_to(buddy_before)<.01,"unrelated waiting buddy stays at its original contact")
	await _capture("moon-replaced")
	if not await _e_action("take:moonPost", "moon-retake-before-offsets"): return false
	for support: String in ["f:3:-1","f:2:-1","f:3:0"]:
		if not await _walk_to(support,"adjacent slot support "+support): return false
		var exercised := 0
		for offset: Vector3 in [Vector3(-.30,0,-.30),Vector3.ZERO,Vector3(.30,0,.30)]:
			var point: Vector3 = app.view.tile_position(app.session.world.point_for(support)) + offset
			if not app.native_movement.request_local_target(point): continue
			if not _check(await _drain(700),"real offset walk settles "+str(point)): return false
			var label := support.replace(":","-")+"-"+str(exercised)
			_drop_diagnostics("offset "+label)
			if not await _e_action("drop:moonPost:f:3:-1","offset-drop-"+label): return false
			_check(str(app.session.world.state.items.moonPost.tile)=="f:3:-1","nearby drop never rewrites original slot target")
			if not await _e_action("take:moonPost","offset-retake-"+label): return false
			exercised += 1
		_check(exercised>=2,"at least two actual clear offset approaches tested on "+support)
	if not await _walk_to("f:3:-1","return to moon support for cancel"): return false
	var center: Vector3 = app.view.tile_position(app.session.world.point_for("f:3:-1"))
	_check(app.native_movement.request_local_target(center),"walk into empty moon base before cancellation")
	await _drain(700)
	if not await _choose_drop_without_drain(): return false
	_check(not app._pending_prop_drop.is_empty(),"drop starts a real safety approach before commitment")
	_key(KEY_A,true)
	await _tick()
	_key(KEY_A,false)
	await _drain(700)
	_check(app._pending_prop_drop.is_empty() and app.session.world.state.items.moonPost.get("holder","")=="luvie","manual movement cancels pending drop and preserves held moon")
	_check(app.view.prop_physical_point_clear(center,"buddy"),"cancelled placement creates no moon hard base")
	if not await _e_action("drop:moonPost:f:3:-1","drop-before-undo"): return false
	_check(not app.view.prop_physical_point_clear(center,"buddy"),"successful placement creates real moon hard base")
	_key(KEY_Z,true)
	_key(KEY_Z,false)
	await _drain(700)
	_check(app.session.world.state.items.moonPost.get("holder","")=="luvie" and app.view.prop_physical_point_clear(center,"buddy"),"actual undo key restores held moon and removes hard base")
	if not await _walk_to("f:2:-1","primary approaches old lantern beside moon slot"): return false
	_check(app.native_movement.request_local_target(Vector3(2.26,0,-.82)),"primary walks to old lantern contact approach")
	await _drain(700)
	_key(KEY_S,true)
	for unused in range(12): await _tick()
	_key(KEY_S,false)
	await _drain(700)
	var primary_contact: Vector3 = app.view.get_actor_body("luvie").position
	_check(not app.view.prop_point_clear(primary_contact,"luvie") and app.view.prop_physical_point_clear(primary_contact,"luvie"),"stationary primary is legally touching old lantern within extra planner margin")
	app._on_command("switch")
	await _drain(700)
	if not await _walk_to("f:3:-1","buddy physically walks to empty new moon base"): return false
	_check(app.native_movement.request_local_target(center),"buddy approaches empty moon center")
	await _drain(700)
	app._on_command("switch")
	await _drain(700)
	var occupied: Vector3 = app.view.get_actor_body("buddy").position
	var needed: Dictionary = app.view.prop_drop_stance("f:3:-1","luvie","moonPost")
	_check(needed.get("companions",{}).has("buddy"),"only buddy actually occupying pending moon base needs moving")
	if not await _e_action("drop:moonPost:f:3:-1","drop-with-buddy-on-new-base"): return false
	_check(app.view.get_actor_body("buddy").position.distance_to(occupied)>.10,"affected buddy physically moves aside before placing")
	_check(app.view.get_actor_body("luvie").position.distance_to(primary_contact)<.01,"unaffected primary retains legal old-lantern contact while buddy moves")
	_check(app.view.prop_physical_point_clear(app.view.get_actor_body("buddy").position,"buddy") and app.view.prop_physical_point_clear(app.view.get_actor_body("luvie").position,"luvie"),"both real bodies clear new moon hard base")
	await _capture("buddy-clears-new-base")
	return true

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	app._input(event)

func _choose_drop_without_drain() -> bool:
	app.hud.close_context_choices()
	_key(KEY_E,true)
	_key(KEY_E,false)
	await RenderingServer.frame_post_draw
	if app.hud.is_context_open():
		for node: Node in app.hud._commands.get_children():
			if node is Button and str(node.get_meta("command_id",""))=="drop:moonPost:f:3:-1" and not node.disabled:
				node.pressed.emit()
				return true
		return _check(false,"moon drop offered in actual cancellation menu")
	return true

func _hashes() -> Dictionary:
	var result := super._hashes()
	for path: String in ["tests/native_shadow_drop_capture.gd","presentation/native/native_prop_obstacles.gd"]:
		result[path] = FileAccess.get_sha256("res://"+path)
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before := _hashes()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture := {}
	for entry: Dictionary in reference.cases:
		if entry.name == "authored/3-2": fixture = entry
	branch = "replace"
	var success := true
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions = size
		if await _start(): success = await _cycle(fixture) and success
		else: success = false
		await _dispose()
	var after := _hashes()
	_check(before==after,"production and regression test sources stable throughout both sizes")
	failures.append_array(logger.captured_errors())
	var report := {"suite":"native-shadow-drop-gpu","passed":success and failures.is_empty(),"checks":checks,"images":images,"events":events,"failures":failures,"sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"scope":"Native real body movement and actual E/menu, movement cancellation and Z undo at two viewports. No state/body injection. AudioStub; no browser, audio or performance claim."}
	var file := FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	finished = true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures}))
	quit(0 if report.passed else 1)
