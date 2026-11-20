extends "res://tests/native_route_test.gd"
## Repeated bell pickup after legal drops and real motor travel to the final core.

var observations: Array = []
var capture_output := ""

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-output="):
			capture_output = argument.trim_prefix("--capture-output=")
	_setup()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fourth: Dictionary
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/1-4": fourth = entry
	app.repository.data.mainline.runs["1-4"] = fourth.steps[20].snapshot.duplicate(true)
	app._enter_level("1-4")
	await _tick(); await _tick()
	_check(not app._native_interaction_context().get("choices", []).any(func(choice: Dictionary) -> bool: return str(choice.id) == "approach:core"), "unreturned bell never offers remote core approach")
	var closed_position: Vector3 = app.view.get_actor_body("luvie").position
	app._on_command("approach:core")
	_check(app.view.get_actor_body("luvie").position == closed_position and app.native_movement.click_path.is_empty(), "unreturned bell cannot invoke the application approach remotely")
	for destination: String in ["f:-2:4", "f:-3:0", "f:-4:0"]:
		_check(await _walk_to(destination, "carry bell to " + destination), "bell reaches new drop cell " + destination)
		var dropped := "drop:bell:" + destination
		app._on_command(dropped)
		_check(await _drain(), "drop settles " + destination)
		_check(str(app.session.world.state.items.bell.tile) == destination, "bell saved on requested support " + destination)
		_check(str(app.session.world.state.items.bell.get("holder", "")).is_empty(), "drop releases holder " + destination)
		if destination == "f:-4:0":
			var progress_before: Array = app.session.world.state.flags.duplicate()
			app._enter_level("1-4")
			await _tick(); await _tick()
			_check(str(app.session.world.state.items.bell.tile) == destination and app.session.world.state.flags == progress_before, "reenter preserves relocated bell and permanent latch")
		var context: Dictionary = app._native_interaction_context()
		observations.append({"phase":"drop", "support":destination, "state":app.session.world.snapshot(), "context":context, "availability":app._command_states(), "message":app.status_message})
		_check(context.get("choices", []).any(func(choice: Dictionary) -> bool: return str(choice.id) == "take:bell" and not bool(choice.disabled)), "real context exposes pickup at relocated bell " + destination)
		app._on_command("primary")
		if app.hud.is_context_open():
			if destination == "f:-4:0": await _capture("01-bell-default-pickup")
			var confirm := InputEventKey.new()
			confirm.keycode = KEY_E
			confirm.physical_keycode = KEY_E
			confirm.pressed = true
			app.hud.handle_context_key(confirm)
		_check(await _drain(), "pickup settles " + destination)
		_check(str(app.session.world.state.items.bell.get("holder", "")) == "luvie", "relocated bell can be picked up through primary/E " + destination)
	app._on_command("use:home")
	_check(await _drain(), "return bell settles")
	_check(app.session.world.flag("home") and not app.session.world.state.completed, "bell delivery opens gate without completing")
	app._on_command("switch")
	_check(await _drain(), "switch to buddy settles")
	_check(await _walk_to("f:-4:0", "bring buddy back through permanent route"), "buddy walks to home on real supports")
	app._on_command("switch")
	_check(await _drain(), "switch to luvie settles")
	# Reproduce walking beside the displaced visible stone bed rather than
	# directly requesting the invisible old rule mark at (-9,0).
	_check(await _walk_to("f:-8:1", "walk beside visible flowerbed"), "real route reaches visible bed's side")
	_check(not app.session.world.near("f:-9:0"), "visible bedside remains outside unchanged rule repair radius")
	_check(not app.session.world.commands().any(func(choice: Dictionary) -> bool: return str(choice.id) == "repair"), "domain still rejects planting from the diagonal bedside")
	var bedside: Dictionary = app._native_interaction_context()
	observations.append({"phase":"visible-bedside", "state":app.session.world.snapshot(), "context":bedside, "movement":app.native_movement.qa_state()})
	_check(bedside.get("choices", []).any(func(choice: Dictionary) -> bool: return str(choice.id) == "approach:core" and not bool(choice.disabled)), "visible bedside offers legal approach through E")
	await _capture("02-visible-bedside-approach")
	var position_before: Vector3 = app.view.get_actor_body("luvie").position
	_check(app.view.core_approach_hint(position_before - Vector3.UP * .65).is_empty(), "lower-layer body cannot see the approach action")
	_check(app.view.core_approach_hint(position_before + Vector3.RIGHT * 4).is_empty(), "distant body cannot see the approach action")
	app._on_command("primary")
	if app.hud.is_context_open():
		var approach_key := InputEventKey.new()
		approach_key.keycode = KEY_E; approach_key.physical_keycode = KEY_E; approach_key.pressed = true
		app.hud.handle_context_key(approach_key)
	_check(app.view.get_actor_body("luvie").position == position_before, "approach input does not teleport the actor")
	_check(await _drain(), "bedside E approach physically settles")
	_check(app.session.world.near("f:-9:0"), "E approach reaches unchanged legal repair range")
	_check(not app.session.world.state.completed and not app.session.world.together(), "approach does not complete or summon the absent companion")
	var waiting_context: Dictionary = app._native_interaction_context()
	_check(waiting_context.get("choices", []).any(func(choice: Dictionary) -> bool: return str(choice.id) == "repair" and bool(choice.disabled)), "original planting appears with a blocked reason while companion is absent")
	await _capture("03-legal-stance-awaiting-companion")
	app._on_command("repair")
	_check(not app.session.world.state.completed, "absent companion still prevents repair")
	app._on_command("follow")
	_check(await _drain(900), "companion follows existing physical route to final bed")
	var at_core: Dictionary = app._native_interaction_context()
	observations.append({"phase":"core", "state":app.session.world.snapshot(), "context":at_core, "message":app.status_message, "movement":app.native_movement.qa_state()})
	_check(app.session.world.ready(), "full 1-4 final mechanism and reunion conditions satisfied")
	_check(at_core.get("choices", []).any(func(choice: Dictionary) -> bool: return str(choice.id) == "repair" and not bool(choice.disabled)), "final native context exposes together planting")
	await _capture("04-together-planting-available")
	app._on_command("primary")
	_check(await _drain(), "explicit repair settles")
	_check(app.session.world.state.completed, "real together route can explicitly complete 1-4")
	await _capture("05-completed")
	var output := capture_output if not capture_output.is_empty() else ProjectSettings.globalize_path("res://../docs/qa-godot-native/fourth-bell-recovery-20261117")
	DirAccess.make_dir_recursive_absolute(output)
	var report := FileAccess.open(output.path_join("native-recovery-observations.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"observations":observations},"  ")+"\n")
	print(JSON.stringify({"suite":"native-fourth-bell-recovery", "checks":checks, "passed":failures.is_empty(), "failures":failures, "scope":"Headless native controller/HUD handlers, real physics motor and memory saves. No GPU pixels or browser pointer verification."}))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func _capture(name: String) -> void:
	if capture_output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(capture_output)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_output.path_join(name + ".png"))
