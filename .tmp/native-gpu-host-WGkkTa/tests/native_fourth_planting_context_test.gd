extends "res://tests/native_route_test.gd"
## Buddy-led bedside flow through real E input, unchanged switch/follow and repair.
const FourthGuidance := preload("res://ui/fourth_garden_guidance.gd")
var observations: Array = []
var capture_output := ""

func _press_e() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame

func _confirm_context() -> void:
	await _press_e()
	if app.hud.is_context_open(): await _press_e()

func _choice(id: String) -> Dictionary:
	for choice: Dictionary in app._native_interaction_context().get("choices", []):
		if str(choice.id) == id: return choice
	return {}

func _capture(name_value: String) -> void:
	if capture_output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_output)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_output.path_join(name_value + ".png"))

func _observe(phase: String) -> void:
	var active_body: CharacterBody3D = app.view.get_actor_body(app.session.world.actor())
	observations.append({"phase":phase,"state":app.session.world.snapshot(),"context":app._native_interaction_context(),"native":app.native_movement.qa_state(),"bedsideHint":app.view.core_bedside_target(active_body.position),"coreBase":app.view._prop_obstacles.filter(func(entry:Dictionary)->bool:return str(entry.get("id",""))=="mark:core")})

func _run() -> void:
	root.unfocusable = true
	root.size = Vector2i(1280,720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-output="): capture_output = argument.trim_prefix("--capture-output=")
	_setup()
	Router.install_native_actions()
	app.set_process_input(true)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var snapshot: Dictionary = {}
	for fixture: Dictionary in reference.cases:
		if str(fixture.name) == "authored/1-4": snapshot = fixture.steps[-2].snapshot.duplicate(true)
	# The fixture supplies solved permanent mechanisms only. Both travellers
	# begin at the home, then the buddy leads them along the actual motor route.
	snapshot.active = "buddy"
	snapshot.follow = true
	snapshot.actors = {"luvie":"f:-4:0","buddy":"f:-4:0"}
	snapshot.erase("runtime")
	_check(app.repository.stage_run(snapshot).ok, "buddy-led home snapshot remains valid")
	app._enter_level("1-4")
	await _tick(); await _tick()
	_check(await _walk_to("f:-8:1", "buddy leads to visible flowerbed"), "buddy physically reaches visible bedside")
	_check(app.session.world.actor() == "buddy" and app.session.world.state.follow, "buddy remains active and following remains on during travel")
	_check(not app.session.world.near("f:-9:0"), "visible bedside still does not grant expanded repair range")
	var before_query: Dictionary = app.session.world.snapshot()
	var switch_choice := _choice("switch")
	_check(str(switch_choice.get("label", "")) == "切换露薇来播种" and not bool(switch_choice.get("disabled", true)), "buddy's E context explicitly exposes the ordinary role switch")
	_check(_choice("repair").is_empty() and _choice("approach:core").is_empty(), "buddy is never offered luvie's planting or approach ability")
	_check(app.session.world.snapshot() == before_query, "role guidance query does not switch or summon anyone")
	var denied: Dictionary = app.session.world.fork(before_query).act("repair")
	_check(not bool(denied.get("ok", true)), "buddy still cannot invoke repair through the domain")
	var body: CharacterBody3D = app.view.get_actor_body("buddy")
	_check(app.view.core_bedside_target(body.position - Vector3.UP * .65).is_empty(), "lower layer has no bedside role hint")
	_check(app.view.core_bedside_target(body.position + Vector3.RIGHT * 4).is_empty(), "far away body has no bedside role hint")
	var hidden_bed: Node3D = app.view._props_nodes["mark:core"]
	hidden_bed.hide()
	_check(app.view.core_bedside_target(body.position).is_empty(), "hidden flowerbed does not offer role guidance")
	hidden_bed.show()
	_check(FourthGuidance.hint(app.session.world,0).contains("露薇") and FourthGuidance.hint(app.session.world,2).contains("同行"), "buddy's existing hint explains the required role and following")
	_observe("buddy-bedside")
	await _capture("01-buddy-switch-context")
	await _confirm_context()
	_check(await _drain(), "real E role switch settles")
	_check(app.session.world.actor() == "luvie" and not app.session.world.state.follow, "E uses original switch semantics and leaves buddy waiting")
	_check(app.session.world.state.actors == before_query.actors, "role switch does not teleport either traveller")
	var approach_choice := _choice("approach:core")
	_check(not approach_choice.is_empty() and not bool(approach_choice.disabled), "luvie now discovers the existing legal approach")
	var before_walk: Vector3 = app.view.get_actor_body("luvie").position
	await _confirm_context()
	_check(app.view.get_actor_body("luvie").position.distance_to(before_walk) < .2, "approach begins with real travel rather than teleportation")
	_check(await _drain(900), "luvie's E approach physically settles")
	_check(app.session.world.near("f:-9:0"), "luvie reaches unchanged domain repair range")
	_check(not app.session.world.together() and not app.session.world.state.follow, "original switch leaves the companion at the bedside")
	var repair_choice := _choice("repair")
	var follow_choice := _choice("follow")
	_check(not repair_choice.is_empty() and bool(repair_choice.disabled), "original repair remains visible but blocked while partner is absent")
	_check(str(follow_choice.get("label", "")) == "叫上伙伴同行" and not bool(follow_choice.get("disabled", true)), "the same E context offers the existing follow command clearly")
	_check(str(app._native_interaction_context().choices[0].id) == "follow", "available follow action precedes blocked planting and optional observations")
	_observe("luvie-awaits-companion")
	await _capture("02-call-companion-context")
	await _confirm_context()
	_check(await _drain(900), "E-enabled following physically brings buddy along the permanent path")
	_check(app.session.world.state.follow and app.session.world.together(), "explicit follow reaches real reunion")
	_check(not app.session.world.state.completed, "reunion does not auto-complete the puzzle")
	_check(_choice("follow").is_empty(), "call-companion hint disappears after reunion")
	_check(not _choice("repair").is_empty() and not bool(_choice("repair").disabled), "unchanged original repair becomes available")
	_observe("together-ready")
	await _capture("03-original-planting-ready")
	await _confirm_context()
	_check(await _drain(), "explicit E planting settles")
	_check(app.session.world.state.completed, "buddy-led flow can complete through explicit role, follow and planting actions")
	_check(_choice("switch").is_empty(), "completed garden no longer has planting role guidance")
	_observe("completed")
	await _capture("04-completed")
	var output := capture_output if not capture_output.is_empty() else ProjectSettings.globalize_path("res://../docs/qa-godot-native/fourth-buddy-context-20261117")
	DirAccess.make_dir_recursive_absolute(output)
	var report := {"suite":"native-fourth-planting-context","checks":checks,"passed":failures.is_empty(),"failures":failures,"observations":observations,"scope":"Native controller/HUD, real E Input.parse_input_event, physics motor and in-memory progress. Optional GPU images are separate from browser pointer verification."}
	FileAccess.open(output.path_join("observations.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print(JSON.stringify({"suite":report.suite,"checks":checks,"passed":report.passed,"failures":failures,"scope":report.scope}))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
