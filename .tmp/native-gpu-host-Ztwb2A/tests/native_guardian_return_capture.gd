extends "res://tests/native_guardian_capture.gd"
## Reproduce the reported 6/8 high-bank state, then use actual screen picking
## and physical paths. Prepared saves are explicit, not a full cold journey.
var click_inputs: Array = []
var return_cases: Array = []

func _scene_click(id: String, label: String) -> bool:
	app.hud.close_context_choices()
	app._update_layout()
	app.view._fit_camera(true)
	for unused in range(5): await RenderingServer.frame_post_draw
	var tile: Dictionary = app.session.world.point_for(id)
	if not _check(not tile.is_empty(), label+" target is an existing logical support"): return false
	var screen := Vector2.ZERO
	var found := false
	var center: Vector3 = app.view.tile_position(tile)
	for offset: Vector2 in [Vector2.ZERO,Vector2(.25,0),Vector2(-.25,0),Vector2(0,.25),Vector2(0,-.25),Vector2(.25,.25),Vector2(-.25,-.25)]:
		var candidate: Vector2 = app.view.world_to_screen(center+Vector3(offset.x,0,offset.y))
		if not Rect2(Vector2.ZERO,Vector2(dimensions)).has_point(candidate): continue
		var covered := false
		for region: Rect2 in app.view._regions:
			if region.has_point(candidate): covered=true
		if not covered and app.view.hit_test(candidate)==id and app.view.command_hit_test(candidate).is_empty():
			screen=candidate; found=true; break
	if not _check(found,label+" has an unoccluded real screen target"): return false
	var before: String=app.session.world.state.actors[app.session.world.actor()]
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=screen
	app.view._unhandled_input(event)
	var planned: int=app.native_movement.click_path.size()
	var settled:=await _drain(maxi(700,planned*120))
	var reached: String=app.session.world.state.actors[app.session.world.actor()]
	click_inputs.append({"label":label,"target":id,"from":before,"reached":reached,"screen":[screen.x,screen.y],"plannedSupports":planned,"settled":settled,"status":app.status_message,"viewport":[dimensions.x,dimensions.y],"input":"actual native scene mouse picking and tile_selected"})
	if not _check(settled and reached==id,label+" real screen click reaches requested support"):
		print("RETURN CLICK DIAGNOSTIC "+JSON.stringify({"target":id,"status":app.status_message,"movement":app.native_movement.qa_state(),"path":app.session.world.path_to(id)}))
		await _capture(label+"-failed")
		return false
	return true

func _prepare_return() -> bool:
	if not await _prepared_state(original.steps[46].snapshot,"prepared-six-of-eight"): return false
	_check(app.session.world.flag("star") and not app.session.world.flag("moon"),"prepared state is light-connected before reunion")
	_check(app.session.world.state.collected.size()==6,"prepared state has original six gifts")
	return true

func _return_by_click() -> bool:
	if not await _prepare_return(): return false
	if not await _scene_click("f:8:2","walk-to-screenshot-high-bank"): return false
	await _capture("screenshot-high-bank")
	if not await _scene_click("m:lift:0:0","direct-click-back-to-lift"): return false
	await _capture("back-on-high-lift")
	if not await _e_action("valve:lift","lower-for-return"): return false
	await _capture("lowered-return-platform")
	if not await _scene_click("f:4:-3","click-north-bank-after-lowering"): return false
	if not await _walk_to("m:inner:0:0","actual path from root bank to inner controller"): return false
	if not await _e_action("turn:inner","align-inner-for-return"): return false
	if not await _walk_to("f:-4:0","hero actual west-bank return"): return false
	await _capture("hero-at-planter-before-reunion")
	app._on_command("switch")
	if not _check(await _drain(700),"switch to waiting companion settles"): return false
	if not await _walk_to("f:-4:0","companion actual south-west return"): return false
	_check(app.session.world.flag("moon") and app.session.world.state.collected.size()==8,"actual reunion awards remaining two gifts")
	app._on_command("switch")
	if not _check(await _drain(700),"switch back to hero settles"): return false
	await _capture("both-at-planter-ready")
	if not await _e_action("repair","actual-final-care"): return false
	_check(app.session.world.state.completed,"prepared 6/8 state completes by actual return and care")
	var stay:=_find_stay(app.hud)
	if stay!=null: stay.pressed.emit()
	await _capture("completed-small-planter")
	return true

func _offset_return() -> bool:
	if not await _prepare_return(): return false
	if not await _scene_click("f:8:2","offset-start-high-bank"): return false
	var base: Vector3=app.view.tile_position(app.session.world.point_for("f:8:2"))
	var reached_offsets:=0
	for offset: Vector3 in [Vector3(.22,0,.22),Vector3(-.22,0,-.22)]:
		if not _check(app.native_movement.request_local_target(base+offset),"free same-cell approach accepted "+str(offset)): return false
		if not _check(await _drain(700),"free same-cell approach physically settles"): return false
		var actual: Vector3=app.view.get_actor_body("luvie").position
		_check(actual.distance_to(base+offset)<.04,"free same-cell body reaches requested offset")
		if not await _scene_click("m:lift:0:0","offset-click-return-"+str(reached_offsets)): return false
		reached_offsets+=1
		# Reset the next free-footpoint probe by actual walking. The target
		# bank may be outside the follow camera after reaching the lift.
		if reached_offsets<2 and not await _walk_to("f:8:2","physical walk back to prepare next offset"): return false
	await _capture("offset-return-settled")
	return reached_offsets==2

func _low_lift_rescue() -> bool:
	var snapshot: Dictionary=original.steps[48].snapshot.duplicate(true)
	snapshot.turns.lift=0
	var probe:=GuardianWorld.new("3-4")
	if not _check(bool(probe.normalize_saved(snapshot).get("ok",false)),"low lift rescue preparation is an original valid save"): return false
	if not await _prepared_state(snapshot,"prepared-high-hero-low-lift"): return false
	app._on_command("switch")
	if not _check(await _drain(700),"rescue switches to companion"): return false
	if not await _walk_to("m:lift:0:0","companion physically walks original west-north root route to low platform"): return false
	await _capture("companion-on-low-lift")
	if not await _e_action("valve:lift","companion-raises-lift-to-rescue"): return false
	app._on_command("switch")
	if not _check(await _drain(700),"rescue switches to high-bank hero"): return false
	if not await _scene_click("m:lift:0:0","rescued-hero-clicks-back-to-raised-platform"): return false
	if not await _e_action("valve:lift","both-descend-after-rescue"): return false
	_check(int(app.session.world.state.turns.lift)==0,"rescue ends with low platform")
	for who: String in ["luvie","buddy"]:
		_check(str(app.session.world.state.actors[who]).begins_with("m:lift:"),"rescue retains actual rider "+who)
	await _capture("both-rescued-low-platform")
	return true

func _hashes() -> Dictionary:
	var hashes: Dictionary=super._hashes()
	hashes["tests/native_guardian_return_capture.gd"]=FileAccess.get_sha256("res://tests/native_guardian_return_capture.gd")
	return hashes

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("Actual GPU and explicit absolute output required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before:=_hashes()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if str(entry.name)=="authored/3-4": original=entry
	current_level="3-4"
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions=size; branch="guardian-return"
		if await _start():
			app.view.tile_selected.connect(app._go)
			var complete:=await _return_by_click()
			return_cases.append({"viewport":[size.x,size.y],"preparedFrom":46,"completed":complete,"kind":"actual scene clicks then original return mechanisms"})
			if complete:
				branch="guardian-offset"
				return_cases.append({"viewport":[size.x,size.y],"preparedFrom":46,"completed":await _offset_return(),"kind":"free local offset then actual scene click"})
				if size.x==1280:
					branch="guardian-rescue"
					return_cases.append({"viewport":[size.x,size.y],"preparedFrom":"48 with lift low","completed":await _low_lift_rescue(),"kind":"companion original physical route and lift recovery"})
			await _dispose()
	var after:=_hashes()
	_check(before==after,"guardian return sources stable")
	failures.append_array(logger.captured_errors())
	var report: Dictionary={"suite":"guardian-return-capture","passed":failures.is_empty(),"checks":checks,"failures":failures,"sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"cases":return_cases,"clickInputs":click_inputs,"images":images,"events":events,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"scope":"Explicit prepared original step46 saves; actual scene mouse picking, physical free offset paths, E/menu mechanisms and final care. Not a cold-start complete journey, browser, audio or performance test."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures,"cases":return_cases,"images":images.size()}))
	quit(0 if report.passed else 1)
