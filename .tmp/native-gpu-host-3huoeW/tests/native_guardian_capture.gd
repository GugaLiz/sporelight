extends "res://tests/native_growth_frontier_capture.gd"
## Original guardian puzzle, physical frontier movement and natural prop/HUD QA.
const GuardianWorld = preload("res://core/garden_world.gd")
const GuardianSnapshot = preload("res://contracts/snapshot_data.gd")
var original: Dictionary = {}
var prepared_views: Array = []
var button_inputs: Array = []
var baseline_only := false
var domain_only := false
var prepared_only := false
var domain_checks := 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument=="--baseline-only": baseline_only=true
		if argument=="--domain-only": domain_only=true
		if argument=="--prepared-only": prepared_only=true
	super._initialize()

func _domain_walk(world: RefCounted, destination: String, label: String) -> bool:
	if str(world.state.actors[world.actor()])==destination: return true
	var path: Array=world.path_to(destination)
	if not _check(not path.is_empty(),label+" legal approach"): return false
	for target: String in path:
		if not _check(world.move(target).ok,label+" adjacent step "+target): return false
	return _check(str(world.state.actors[world.actor()])==destination,label+" reached")

func _domain_rules() -> void:
	var before_checks:=checks
	var world:=GuardianWorld.new("3-4")
	var expected_before: Dictionary=original.initial.snapshot
	_check(original.steps.size()==96,"original guardian fixture retains 96 intentions")
	for index: int in original.steps.size():
		var step: Dictionary=original.steps[index]
		var id:=str(step.command.value)
		var label: String="domain original step "+str(index)
		if str(step.command.kind)=="move":
			if not _domain_walk(world,id,label): return
		else:
			var station:=str(world.root_growth_station(world.level.roots[0]).id) if id.begins_with("grow:") else str(expected_before.actors[world.actor()])
			if not _domain_walk(world,station,label+" action station"): return
			if not _check(world.act(id).ok==bool(step.result.ok),label+" original acceptance"): return
		var actual: Dictionary=world.snapshot().duplicate(true)
		var expected: Dictionary=step.snapshot.duplicate(true)
		actual.erase("actors"); expected.erase("actors")
		_check(GuardianSnapshot.equivalent(actual,expected),label+" exact original non-position state")
		_check(world.ready()==bool(step.ready),label+" original simultaneous readiness")
		_check(bool(world.normalize_saved(world.snapshot()).get("ok",false)),label+" valid save")
		var reload:=GuardianWorld.new("3-4",world.snapshot())
		_check(GuardianSnapshot.equivalent(reload.snapshot(),world.snapshot()),label+" reload preserves progress and gifts")
		expected_before=step.snapshot
	_check(world.state.completed,"original guardian domain journey completes")
	var final: Dictionary=original.steps[94].snapshot.duplicate(true)
	for flag: String in ["root","rain","star","moon"]:
		var missing:=final.duplicate(true)
		missing.flags.erase(flag)
		var negative:=GuardianWorld.new("3-4",missing)
		var saved: Dictionary=negative.snapshot().duplicate(true)
		_check(not negative.ready() and not negative.act("repair").ok and negative.snapshot()==saved,"cannot finish with missing "+flag)
	# User-requested causal revision: road angle is not a planting lock and
	# water already stored in the lift tank remains available after rotation.
	for inner_turn: int in range(4):
		for water_turn: int in range(4):
			var aligned_home := final.duplicate(true)
			aligned_home.turns.inner=inner_turn
			aligned_home.turns.water=water_turn
			var home:=GuardianWorld.new("3-4",aligned_home)
			_check(home.ready() and home.act("repair").ok,"all remote road/water orientations permit actual home care after supply")
	for condition: String in ["light","together"]:
		var wrong:=final.duplicate(true)
		if condition=="together": wrong.actors.buddy="m:water:0:0"
		else: wrong.turns[condition]=0
		var negative:=GuardianWorld.new("3-4",wrong)
		var saved: Dictionary=negative.snapshot().duplicate(true)
		_check(not negative.ready() and not negative.act("repair").ok and negative.snapshot()==saved,"past milestones never bypass current "+condition)
		_check(negative.flag("star"),"past star remains recorded during wrong "+condition)
	var pre_water:=GuardianWorld.new("3-4",original.steps[19].snapshot)
	_check(not pre_water.act("valve:lift").ok,"unwatered load platform still cannot ascend")
	var companion:=GuardianWorld.new("3-4",original.steps[11].snapshot)
	companion.state.active="buddy"; companion.state.actors.buddy="f:1:-4"
	_check(not companion.act("take:mirror").ok,"companion cannot carry heavy mirror")
	var small:=GuardianWorld.new("3-4")
	_check(not small.path_to("m:water:0:0").size(),"hero still cannot enter small water platform")
	domain_checks=checks-before_checks

func _capture(label: String) -> void:
	await super._capture(label)
	if not baseline_only:
		_check(images.back().sceneWords.is_empty(),"guardian uses natural scene props without Label3D text: "+branch+"/"+label)

func _e_action(id: String,label: String) -> bool:
	if not id in ["turn:inner","turn:light","valve:water"]: return await super._e_action(id,label)
	app.hud.close_context_choices()
	var revision: int=app.session.revision
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=KEY_E; event.physical_keycode=KEY_E; event.pressed=pressed
		app._input(event)
	await RenderingServer.frame_post_draw
	if app.hud.is_context_open():
		var selected: Button
		for node: Node in app.hud._commands.get_children():
			if node is Button and str(node.get_meta("command_id",""))==id: selected=node
		if not _check(selected!=null and not selected.disabled,label+" actual menu retains original action"): return false
		await _capture(label+"-menu")
		selected.pressed.emit()
	if not app.motion.is_empty():
		await _capture(label+"-motion-start")
		for unused in range(160):
			if app.motion.is_empty() or float(app.motion.elapsed)/float(app.motion.duration)>=.45: break
			await _tick()
		if not app.motion.is_empty(): await _capture(label+"-motion-middle")
	var settled:=await _drain(700)
	events.append({"branch":branch,"command":id,"label":label,"viewport":[dimensions.x,dimensions.y],"accepted":app.session.revision>revision,"settled":settled,"input":"actual application E and menu button signal"})
	return _check(settled and app.session.revision>revision,label+" original mechanism moves and settles")

func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button]=[]
	for child: Node in node.get_children():
		if child is Button: result.append(child)
		result.append_array(_buttons(child))
	return result

func _pointer_button(button: Button,label: String) -> bool:
	var rect:=button.get_global_rect()
	var viewport_rect:=Rect2(Vector2.ZERO,Vector2(dimensions))
	if not _check(button.is_visible_in_tree() and not button.disabled and viewport_rect.has_point(rect.get_center()),label+" enabled button center is inside viewport"): return false
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=rect.get_center()
		outer.push_input(event,true)
		await process_frame
	return true

func _prepared_state(snapshot: Dictionary,label: String) -> bool:
	app.repository.data.mainline.runs["3-4"]=snapshot.duplicate(true)
	app._enter_level("3-4")
	if not _check(await _drain(700),label+" prepared state settles"): return false
	await _capture(label)
	prepared_views.append({"label":label,"viewport":[dimensions.x,dimensions.y],"preparedSnapshot":true,"completeJourney":false})
	return true

func _prepared_menu() -> bool:
	var before: Dictionary=app.session.world.snapshot().duplicate(true)
	var primary: Button
	for button: Button in app.hud._tool_buttons:
		if str(button.get_meta("action",""))=="primary": primary=button
	if not _check(primary!=null,"prepared carrying state retains primary control"): return false
	if not await _pointer_button(primary,"pointer primary"): return false
	for unused in range(8): await RenderingServer.frame_post_draw
	if not _check(app.hud.is_context_open(),"actual pointer opens carrying action choices"): return false
	await _capture("prepared-carry-menu")
	var choices: Array[Button]=[]
	for node: Node in app.hud._commands.get_children():
		if node is Button and not node.disabled: choices.append(node)
	if not _check(not choices.is_empty(),"carrying menu retains an enabled action"): return false
	var chosen: Button=choices.back()
	app.hud._context_scroll.ensure_control_visible(chosen)
	for unused in range(8): await RenderingServer.frame_post_draw
	var id:=str(chosen.get_meta("command_id",""))
	var revision: int=app.session.revision
	await _capture("prepared-carry-menu-scrolled")
	if not await _pointer_button(chosen,"pointer chosen action "+id): return false
	var settled:=await _drain(700)
	_check(settled and not app.hud.is_context_open() and app.session.revision>revision,"actual pointer executes original selected action "+id)
	button_inputs.append({"viewport":[dimensions.x,dimensions.y],"command":id,"revisionChanged":app.session.revision>revision,"settled":settled,"input":"SubViewport mouse press/release to actual Control","prepared":true})
	await _capture("prepared-carry-action-result")
	return settled

func _hashes() -> Dictionary:
	var result: Dictionary=super._hashes()
	for path: String in ["presentation/native/mechanism_props.gd","presentation/native/guardian_dressing.gd","presentation/native/rule_ray_presentation.gd","presentation/native/symbiosis_dressing.gd","ui/garden_hud.gd","application/journey_view.gd","content/levels.json","tests/native_guardian_capture.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "absent"
	return result

func _run() -> void:
	if output.is_empty() or (DisplayServer.get_name()=="headless" and not domain_only): push_error("Output and actual GPU required except explicit domain-only mode"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before:=_hashes()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if str(entry.name)=="authored/3-4": original=entry
	if not baseline_only: _domain_rules()
	current_level="3-4"
	if not domain_only:
		if not baseline_only and not prepared_only:
			for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
				branch="guardian-full"; dimensions=size
				var prior_walks:=extra_walks.size()
				if await _start():
					await _route(original)
					if not routes.is_empty(): routes.back().addedFrontierWalks=extra_walks.size()-prior_walks
				await _dispose()
		for size: Vector2i in ([Vector2i(1280,720),Vector2i(844,390)] if baseline_only else [Vector2i(1460,720),Vector2i(568,320)]):
			branch="guardian-prepared"; dimensions=size
			if await _start():
				await _capture("cold")
				if await _prepared_state(original.steps[12].snapshot,"carrying-heavy-mirror") and not baseline_only: await _prepared_menu()
				await _prepared_state(original.steps[46].snapshot,"star-lit-current-beam")
			await _dispose()
	var after:=_hashes()
	_check(before==after,"guardian production and capture sources stable")
	failures.append_array(logger.captured_errors())
	var report: Dictionary={"suite":"guardian-natural-capture","sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"passed":failures.is_empty(),"checks":checks,"domainChecks":domain_checks,"failures":failures,"routes":routes,"preparedViews":prepared_views,"buttonInputs":button_inputs,"images":images,"events":events,"extraWalks":extra_walks,"growthInputs":growth_inputs,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"baselineOnly":baseline_only,"domainOnly":domain_only,"scope":"Immutable 96 intentions plus two physical frontier walks at 1280/844. 1460/568 use prepared cold/carry/star states and actual pointer button input, not complete journeys. Exact rule replay and negative simultaneous conditions are separate domain checks. AudioStub; not Web, audio or performance acceptance."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"domainChecks":domain_checks,"failures":failures,"routes":routes,"preparedViews":prepared_views,"images":images.size()}))
	quit(0 if report.passed else 1)
