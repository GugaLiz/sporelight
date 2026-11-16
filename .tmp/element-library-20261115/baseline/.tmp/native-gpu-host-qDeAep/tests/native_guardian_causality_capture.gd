extends "res://tests/native_guardian_return_capture.gd"
## Current 3-4 causal contract. Prepared starts are explicit; all changes
## between them use real movement and E/undo, never injected completion.
var causal_cases: Array = []

func _capture(label: String) -> void:
	await super._capture(label)
	var world: RefCounted = app.session.world
	images.back().currentGoal = app.hud._rule.text
	images.back().ray = world.rays()
	images.back().received = world.beam_hits(-4,0)
	images.back().stored = world.flag("rain")
	images.back().mole = app.view._props.has_node("MoleResident")
	_check(not app.view._props.has_node("MoleResident"),label+" final garden never spawns the bell-story resident")
	_check(app.view._water_links.is_empty(),label+" final garden does not use unsupported long water droplets")
	_check(app.view._effects.has_node("GuardianWaterworks"),label+" final garden has physical waterworks")

func _water_cycle() -> bool:
	if not await _prepared_state(original.steps[33].snapshot,"water-before-first-docking"): return false
	if not await _e_action("valve:water","water-dock-and-fill"): return false
	_check(app.session.world.flag("rain"),"actual first docking stores water")
	await _capture("water-docked-full")
	app._on_command("undo")
	if not _check(await _drain(700),"actual water undo settles"): return false
	_check(not app.session.world.flag("rain"),"undo before first fill clears stored water")
	await _capture("water-undone-empty")
	for turn in [1,2,3,0]:
		if not await _e_action("valve:water","water-actual-turn-"+str(turn)): return false
		_check(int(app.session.world.state.turns.water)==turn and app.session.world.flag("rain"),"water keeps first stored charge through actual turn "+str(turn))
		await _capture("water-turn-"+str(turn)+"-stored")
	app._on_command("switch")
	if not _check(await _drain(700),"switch back to lift passenger settles"): return false
	if not await _e_action("valve:lift","stored-water-powers-lift-after-undocking"): return false
	_check(app.session.world.state.turns.water==0 and app.session.world.state.turns.lift==1,"stored water powers real ascent without current sluice alignment")
	await _capture("lift-powered-by-stored-water")
	return true

func _light_cycle() -> bool:
	if not await _prepared_state(original.steps[45].snapshot,"lamp-west-before-turning"): return false
	for turn in [1,2,3,0]:
		if not await _e_action("turn:light","lamp-actual-turn-"+str(turn)): return false
		var ray: Array = app.session.world.rays()
		_check(ray.size()>1,"lamp casts a real ray in every settled direction")
		_check(app.session.world.beam_hits(-4,0)==(turn==1),"only real reflected alignment reaches receiving flower at turn "+str(turn))
		await _capture("lamp-turn-"+str(turn))
	return true

func _return_without_angle_lock() -> bool:
	if not await _prepare_return(): return false
	if not await _scene_click("f:8:2","new-contract-high-bank"): return false
	await _capture("light-received-before-return")
	if not await _scene_click("m:lift:0:0","new-contract-return-to-lift"): return false
	if not await _e_action("valve:lift","new-contract-lower"): return false
	if not await _walk_to("f:-4:0","actual permanent root route home without turning inner"): return false
	_check(app.session.world.state.turns.inner==0,"hero returns without artificial central-angle reset")
	await _capture("hero-home-inner-still-zero")
	app._on_command("switch")
	if not _check(await _drain(700),"switch to companion at sluice settles"): return false
	if not await _walk_to("m:water:0:0","companion actually approaches water control"): return false
	for turn in [2,3,0]:
		if not await _e_action("valve:water","companion-undocks-filled-sluice-"+str(turn)): return false
	if not await _walk_to("f:-4:0","companion actual south-west return with water at zero"): return false
	app._on_command("switch")
	if not _check(await _drain(700),"switch to hero for care settles"): return false
	_check(app.session.world.state.turns.inner==0 and app.session.world.state.turns.water==0 and app.session.world.ready(),"real reunion is ready regardless of both unrelated old angle locks")
	await _capture("both-home-no-angle-lock")
	if not await _e_action("repair","actual-care-with-both-angles-zero"): return false
	_check(app.session.world.state.completed,"actual E care completes the causally valid alternate route")
	var stay:=_find_stay(app.hud)
	if stay!=null: stay.pressed.emit()
	await _capture("bloom-without-unrelated-mole")
	app.view.overview=true
	await _capture("completed-overview-causal-objects")
	app.view.overview=false
	return true

func _hashes() -> Dictionary:
	var result: Dictionary = super._hashes()
	for path: String in ["tests/native_guardian_causality_capture.gd","application/guardian_flow_guidance.gd","presentation/native/guardian_optics.gd","presentation/native/guardian_waterworks.gd","presentation/native/guardian_dressing.gd","presentation/native/guardian_lift_frame.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("Explicit output and real GPU required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before:=_hashes()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if str(entry.name)=="authored/3-4": original=entry
	current_level="3-4"
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions=size; branch="guardian-causality"
		if await _start():
			app.view.tile_selected.connect(app._go)
			await _capture("cold-new-contract")
			var water_ok:=await _water_cycle()
			var light_ok:=await _light_cycle()
			var return_ok:=await _return_without_angle_lock()
			causal_cases.append({"viewport":[size.x,size.y],"waterCycle":water_ok,"lampCycle":light_ok,"alternateReturnAndCare":return_ok})
			await _dispose()
	var after:=_hashes()
	_check(before==after,"causal scene source files stable")
	failures.append_array(logger.captured_errors())
	var report: Dictionary={"suite":"guardian-causality-capture","passed":failures.is_empty(),"checks":checks,"failures":failures,"sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"cases":causal_cases,"images":images,"events":events,"clickInputs":click_inputs,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"scope":"Explicit original33/45/46 starts, actual E water rotation/undo/ascent, four real lamp rotations, physical high-bank return without inner turn, actual companion undocking and home/care with inner=water=0. Native GPU, not browser/audio/performance."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures,"cases":causal_cases,"images":images.size()}))
	quit(0 if report.passed else 1)
