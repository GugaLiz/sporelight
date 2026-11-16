extends "res://tests/native_guardian_return_capture.gd"
## Prepared phase views use the normal follow camera. Physical return is a
## separate suite; the transition probes here use original E/undo commands.
const FlowGuidance = preload("res://application/guardian_flow_guidance.gd")
const FlowJourney = preload("res://application/journey_view.gd")
var flow_cases: Array = []
var restore_cases: Array = []

func _node_evidence(node: Node) -> Array:
	var result: Array = []
	if node == null: return result
	var entry := {"name":str(node.name),"type":node.get_class(),"meta":{}}
	if node is Node3D:
		entry.position = [node.global_position.x,node.global_position.y,node.global_position.z]
		entry.visible = node.is_visible_in_tree()
	for key: StringName in node.get_meta_list(): entry.meta[str(key)] = node.get_meta(key)
	result.append(entry)
	for child: Node in node.get_children(): result.append_array(_node_evidence(child))
	return result

func _actor_evidence() -> Dictionary:
	var result := {}
	for who: String in ["luvie","buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		var screen: Vector2 = app.view.world_to_screen(body.global_position)
		result[who] = {"support":app.session.world.state.actors[who],"body":[body.global_position.x,body.global_position.y,body.global_position.z],"screenFoot":[screen.x,screen.y],"visual":_node_evidence(app.view.actor_visual_root(who))}
	return result

func _capture(label: String) -> void:
	await super._capture(label)
	print("FLOW EVIDENCE START "+label)
	var scene: Dictionary = {}
	for id: String in ["mark:lift","mark:core"]:
		scene[id] = _node_evidence(app.view._props_nodes.get(id))
	images.back().flow = FlowGuidance.describe(app.session.world)
	images.back().goalText = app.hud._rule.text
	images.back().goalVisible = app.hud._rule.is_visible_in_tree()
	images.back().messageText = app.hud._message.text
	images.back().scene = scene
	images.back().actors = _actor_evidence()
	images.back().camera = "Existing normal follow camera and safe area; no QA camera override"
	print("FLOW EVIDENCE END "+label)

func _inspect_flow(label: String, expected: Dictionary = {}) -> Dictionary:
	print("FLOW INSPECT START "+label)
	var world: RefCounted = app.session.world
	var snapshot: Dictionary = world.snapshot().duplicate(true)
	var commands: Array = world.commands().duplicate(true)
	var tiles: Array = world.tiles().duplicate(true)
	var rays: Array = world.rays().duplicate(true)
	var flow: Dictionary = FlowGuidance.describe(world)
	var journey: Dictionary = FlowJourney.describe(world)
	_check(world.snapshot()==snapshot and world.commands()==commands and world.tiles()==tiles and world.rays()==rays,label+" presentation reads preserve state, actions, topology and rays")
	_check(not app.view.overview,label+" uses ordinary follow view")
	_check(str(flow.get("goal",""))==str(journey.get("goal","")) and app.hud._rule.text==str(journey.get("goal","")),label+" actual HUD uses the current flow goal")
	_check(app.hud._rule.is_visible_in_tree() and app.hud._heading.get_global_rect().grow(1).encloses(app.hud._rule.get_global_rect()),label+" current goal is visible inside heading at this viewport")
	_check(not str(flow.get("goal","")).is_empty(),label+" phase has a concrete current goal")
	for key: String in expected:
		_check(flow.get(key)==expected[key],label+" expected "+key+"="+str(expected[key])+", actual="+str(flow.get(key)))
	_check(bool(flow.get("water_current"))==(int(world.state.turns.water)==1),label+" water feedback uses current direction")
	_check(bool(flow.get("light_current"))==world.beam_hits(-4,0),label+" light feedback uses current ray")
	_check(bool(flow.get("inner_current"))==(int(world.state.turns.inner)==1),label+" inner feedback uses current direction")
	_check(bool(flow.get("lift_raised"))==(int(world.state.turns.lift)%2==1),label+" lift feedback uses current level")
	_check(bool(flow.get("near_core_luvie"))==world.near("f:-4:0","luvie",tiles) and bool(flow.get("near_core_buddy"))==world.near("f:-4:0","buddy",tiles),label+" home feedback describes actual actor locations")
	_check(bool(flow.get("together"))==world.together(tiles) and bool(flow.get("ready"))==world.ready(tiles),label+" readiness does not substitute a milestone for current requirements")
	var lift: Node3D = app.view._props_nodes["mark:lift"]
	var frame: Node3D = lift.get_node_or_null("GuardianLiftFrame")
	_check(frame!=null,label+" lift has a visible physical platform frame")
	if frame!=null:
		_check(frame.find_children("*","CollisionObject3D",true,false).is_empty(),label+" lift identification adds no support or collision")
	var core: Node3D = app.view._props_nodes["mark:core"]
	_check(bool(core.get_node("GuardianReceivingShoot").get_meta("receiver_powered"))==world.beam_hits(-4,0),label+" receiving shoot reflects actual current light")
	flow_cases.append({"label":label,"viewport":[dimensions.x,dimensions.y],"prepared":true,"flow":flow,"expected":expected,"actors":_actor_evidence()})
	print("FLOW INSPECT END "+label)
	return flow

func _prepared_phase(index: int, label: String, expected: Dictionary = {}) -> bool:
	print("FLOW PREPARE "+label)
	if not await _prepared_state(original.steps[index].snapshot,label): return false
	_inspect_flow(label,expected)
	return true

func _negative_current_conditions() -> void:
	for condition: String in ["inner","water","light"]:
		var saved: Dictionary = original.steps[94].snapshot.duplicate(true)
		saved.turns[condition] = 0
		var label := "causal-current-"+condition+"-turned-away"
		if not await _prepared_state(saved,label): return
		var world: RefCounted = app.session.world
		_check(world.flag("root") and world.flag("rain") and world.flag("star") and world.flag("moon"),label+" keeps all original historical milestones")
		var required := condition == "light"
		var flow := _inspect_flow(label,{condition+"_current":false,"ready":not required,"completed":false})
		_check(str(flow.get("phase",""))==("restore_light" if required else "care"),label+" only actual light is a live planting requirement")
		var before: Dictionary = world.snapshot().duplicate(true)
		var result: Dictionary = world.act("repair")
		_check((not result.ok and world.snapshot()==before) if required else (result.ok and world.state.completed),label+" user-requested cultivation contract")

func _actual_lift_restore() -> bool:
	if not await _prepared_phase(54,"raised-lift-before-real-lower",{"lift_raised":true}): return false
	var raised: Dictionary = app.session.world.snapshot().duplicate(true)
	if not await _e_action("valve:lift","actual-lower"): return false
	await _capture("actual-lower-settled")
	_inspect_flow("actual-lower-settled",{"lift_raised":false})
	app._on_command("undo")
	if not _check(await _drain(700),"actual undo of descent settles"): return false
	await _capture("actual-lower-undone")
	_inspect_flow("actual-lower-undone",{"lift_raised":true})
	_check(app.session.world.state.turns==raised.turns and app.session.world.state.actors==raised.actors,"undo restores original rider supports and platform state")
	if not await _e_action("valve:lift","actual-lower-redo"): return false
	await _capture("actual-lower-redone")
	var before: Dictionary = app.session.world.snapshot().duplicate(true)
	var before_flow: Dictionary = FlowGuidance.describe(app.session.world)
	# MemoryRepository is the actual application repository adapter used by
	# this harness; the saved runtime includes real bodies after E/undo/E.
	app._save()
	app._enter_level("3-4")
	if not _check(await _drain(700),"actual saved lowered state reload settles"): return false
	await _capture("actual-lower-reloaded")
	_inspect_flow("actual-lower-reloaded",{"lift_raised":false})
	_check(app.session.world.state.turns==before.turns and app.session.world.state.actors==before.actors,"reload retains actual lift and actor support state")
	_check(FlowGuidance.describe(app.session.world)==before_flow,"reload produces identical current flow feedback")
	restore_cases.append({"viewport":[dimensions.x,dimensions.y],"input":"actual E descent, app undo, actual E descent, repository save and level reentry","flow":before_flow})
	return true

func _actual_care() -> bool:
	if not await _prepared_phase(94,"both-home-ready-for-care",{"phase":"care","target":"core","ready":true,"completed":false,"near_core_luvie":true,"near_core_buddy":true}): return false
	if not await _e_action("repair","actual-care"): return false
	_check(app.session.world.state.completed,"actual E care completes original puzzle")
	var stay:=_find_stay(app.hud)
	if stay!=null: stay.pressed.emit()
	await _capture("actual-care-complete")
	_inspect_flow("actual-care-complete",{"phase":"complete","target":"","completed":true})
	return true

func _hashes() -> Dictionary:
	var result: Dictionary = super._hashes()
	for path: String in ["tests/native_guardian_flow_capture.gd","application/guardian_flow_guidance.gd","presentation/native/guardian_lift_frame.gd","presentation/native/native_prop_obstacles.gd"]:
		result[path] = FileAccess.get_sha256("res://"+path)
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("Explicit output and actual GPU required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before:=_hashes()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if str(entry.name)=="authored/3-4": original=entry
	current_level="3-4"
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions=size; branch="guardian-flow"
		if await _start():
			await _capture("cold-original-start")
			_inspect_flow("cold-original-start",{"phase":"root","target":"root","root_fixed":false,"water_current":false,"light_current":false,"completed":false})
			await _prepared_phase(11,"root-bridge-connected",{"phase":"water","target":"water","root_fixed":true,"water_current":false})
			await _prepared_phase(34,"water-currently-connected",{"phase":"mirror","target":"highslot","water_current":true,"lift_raised":false})
			await _prepared_phase(36,"lift-raised-before-light",{"phase":"mirror","target":"highslot","water_current":true,"lift_raised":true,"light_current":false})
			await _prepared_phase(48,"six-of-eight-screenshot-high-bank",{"phase":"return_lift","target":"lift","light_current":true,"lift_raised":true,"ready":false})
			await _prepared_phase(55,"returned-low-lift",{"phase":"reunion","target":"core","light_current":true,"lift_raised":false,"inner_current":false})
			await _prepared_phase(68,"inner-reconnected",{"phase":"reunion","target":"core","light_current":true,"inner_current":true})
			await _prepared_phase(80,"hero-home-waiting-for-companion",{"phase":"reunion","target":"core","near_core_luvie":true,"near_core_buddy":false,"ready":false})
			await _actual_care()
			await _negative_current_conditions()
			await _actual_lift_restore()
			await _dispose()
	var after:=_hashes()
	_check(before==after,"guardian flow source files stable")
	failures.append_array(logger.captured_errors())
	var report: Dictionary={"suite":"guardian-flow-capture","passed":failures.is_empty(),"checks":checks,"failures":failures,"sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"cases":flow_cases,"restoreCases":restore_cases,"images":images,"events":events,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"scope":"Two native sizes with existing ordinary follow camera. Explicit prepared original phase snapshots and wrong-current/historical-milestone negatives; actual E care plus E descent/undo/E/reload. Not a complete cold journey, browser, audio or performance proof. Separate actual return suite covers physical route."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures,"cases":flow_cases.size(),"restoreCases":restore_cases,"images":images.size()}))
	quit(0 if report.passed else 1)
