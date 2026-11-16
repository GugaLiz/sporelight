extends "res://tests/native_growth_frontier_capture.gd"
## New authored journey has no water-wheel detour; historical fixture is immutable.
const FinalWorld = preload("res://core/garden_world.gd")
var prepared_boundaries: Array = []
var descent_probed := false

func _walk_to(id: String, label: String) -> bool:
	var success: bool=await super._walk_to(id,label)
	if success and id=="f:0:3":
		_check(app.session.world.point_for(id).get("kind","fixed")=="fixed","occupied south shore remains permanent fixed geometry")
		await _capture("south-fixed-shore-water"+str(app.session.world.state.turns.water))
	return success

func _new_route(original: Dictionary) -> Dictionary:
	var result: Dictionary=original.duplicate(true)
	var steps: Array=[]
	for index: int in range(39): steps.append(original.steps[index].duplicate(true))
	# Follow the existing roots back to the north lift entry with water still 0.
	for index: int in range(13,20): steps.append(original.steps[index].duplicate(true))
	steps.append(original.steps[49].duplicate(true))
	for index: int in range(50,59): steps.append(original.steps[index].duplicate(true))
	result.steps=steps
	_check(steps.size()==56,"new route has 56 intentions without changing historical fixture")
	_check(not steps.any(func(s: Dictionary) -> bool: return str(s.command.value)=="turn:water"),"new route contains no water-wheel turn")
	return result

func _e_action(id: String, label: String) -> bool:
	var success: bool=await super._e_action(id,label)
	if not success: return false
	if branch.begins_with("new-") and id=="valve:lift" and app.session.world.flag("root") and app.session.world.state.turns.lift==1 and not descent_probed:
		descent_probed=true
		_check(app.session.world.state.turns.water==0 and app.session.world.symbiosis_final_route_open() and app.session.world.ready(),"stable root plus high lift opens final route immediately at water0")
		await _capture("stable-high-immediate-route")
		if not await super._e_action("valve:lift","safe-descent-probe"): return false
		_check(not app.session.world.symbiosis_final_route_open(),"actual safe descent closes final route")
		await _capture("stable-low-route-closed")
		app._on_command("undo")
		_check(await _drain(700) and app.session.world.symbiosis_final_route_open(),"actual undo restores high lift and final route")
		await _capture("stable-high-descent-undone")
	return true

func _prepared_overlap(original: Dictionary, water: int) -> bool:
	var saved: Dictionary=original.steps[49].snapshot.duplicate(true)
	saved.turns.water=water
	saved.actors={"luvie":"m:lift:0:0","buddy":"m:water:0:0"}
	saved.active="luvie"
	saved.follow=false
	saved.erase("runtime")
	_check(bool(app._normalize_snapshot(saved).get("ok",false)),"prepared stacked high/low save is legal water%d" % water)
	app.repository.data.mainline.runs["3-3"]=saved
	app._enter_level("3-3")
	if not _check(await _drain(700),"prepared layered scene settles"): return false
	await _capture("prepared-high-low-start")
	for target: String in ["m:lift:-1:0","m:lift:-1:1","f:3:2","f:2:2","f:1:2","f:0:2"]:
		if not await _walk_to(target,"upper water%d %s" % [water,target]): return false
		_check(is_equal_approx(float(app.session.world.point_for(str(app.session.world.state.actors.luvie)).h),2.0),"upper body stays on high support "+target)
	await _capture("upper-over-lower-corridor")
	if not await _walk_to("f:0:3","high route joins permanent south shore water%d" % water): return false
	if not await _walk_to("f:0:2","return above lower branch for overlap check"): return false
	var upper_before: Vector3=app.view.get_actor_body("luvie").position
	app._on_command("switch")
	await _drain(700)
	var lower_path: Array=["m:water:0:-1","m:water:0:-2"] if water==2 else ["m:water:-1:0","m:water:-2:0"]
	for target: String in lower_path:
		if not await _walk_to(target,"lower water%d %s" % [water,target]): return false
		_check(is_equal_approx(float(app.session.world.point_for(str(app.session.world.state.actors.buddy)).h),0.0),"lower body stays on ground support "+target)
	var lower_body: Vector3=app.view.get_actor_body("buddy").position
	_check(str(app.session.world.state.actors.luvie)=="f:0:2" and upper_before.distance_to(app.view.get_actor_body("luvie").position)<.02,"moving below never steals upper support")
	_check(upper_before.y-lower_body.y>.5,"upper and lower actual body heights remain distinct")
	await _capture("both-bodies-at-stacked-supports")
	if not await _walk_to("m:water:0:0","return lower operator to water wheel"): return false
	if not await _e_action("turn:water","rotate-below-upper-route"): return false
	_check(app.session.world.symbiosis_final_route_open() and str(app.session.world.state.actors.luvie)=="f:0:2","rotating lower platform preserves upper road and passenger")
	_check(upper_before.distance_to(app.view.get_actor_body("luvie").position)<.02,"lower rotation does not move upper body")
	await _capture("lower-rotation-settled-upper-retained")
	prepared_boundaries.append({"initialWater":water,"finalWater":app.session.world.state.turns.water,"viewport":[dimensions.x,dimensions.y],"upper":"f:0:2","lowerEndpoint":lower_path.back(),"upperY":upper_before.y,"lowerY":lower_body.y,"preparedSave":true,"actualTravelAndRotation":true})
	return true

func _hashes() -> Dictionary:
	var result: Dictionary=super._hashes()
	for path: String in ["content/levels.json","application/journey_view.gd","tests/native_symbiosis_final_route_capture.gd","tests/native_symbiosis_final_route_test.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "absent"
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("Actual GPU and output required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before:=_hashes()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var original: Dictionary={}
	for entry: Dictionary in data.cases:
		if str(entry.name)=="authored/3-3": original=entry
	_check(original.steps.size()==59,"immutable original route retains 59 intentions")
	current_level="3-3"
	for config: Array in [["new-water0",1280,720],["new-water0",844,390],["old-water1",1280,720]]:
		branch=str(config[0]); dimensions=Vector2i(config[1],config[2]); descent_probed=false
		if await _start():
			await _route(_new_route(original) if branch.begins_with("new-") else original)
			if branch.begins_with("new-"): _check(app.session.world.state.turns.water==0,"new completed journey never turns water")
		await _dispose()
	for water: int in [2,3]:
		branch="prepared-overlap-water"+str(water); dimensions=Vector2i(1280,720)
		if await _start(): await _prepared_overlap(original,water)
		await _dispose()
	var after:=_hashes()
	_check(before==after,"final route production and test sources stable")
	failures.append_array(logger.captured_errors())
	var report: Dictionary={"suite":"symbiosis-final-route-gpu","sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"passed":failures.is_empty(),"checks":checks,"failures":failures,"routes":routes,"preparedBoundaries":prepared_boundaries,"images":images,"events":events,"extraWalks":extra_walks,"growthInputs":growth_inputs,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"scope":"New no-wheel route at two sizes plus original wheel route: actual E/menu and scene plus, physical frontier walks, lift descent and undo. Water2/3 stacked cases explicitly use legal prepared saves, followed by actual upper/lower walks and lower rotation. AudioStub; not Web, performance or audio acceptance."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures,"routes":routes,"preparedBoundaries":prepared_boundaries,"images":images.size()}))
	quit(0 if report.passed else 1)
