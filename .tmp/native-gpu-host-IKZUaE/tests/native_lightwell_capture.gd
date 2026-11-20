extends "res://tests/native_route_test.gd"
## Real native 3-1 intentions and legal discovery/recovery variants.
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var dimensions := Vector2i(1280, 720)
var outer: SubViewport
var images: Array = []
var events: Array = []
var variants: Array = []
var sources_before: Dictionary = {}
var logger := ErrorLogger.new()
var finished := false

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(900).timeout.connect(func() -> void:
		if not finished:
			push_error("Lightwell native GPU capture timed out")
			quit(2))
	_run.call_deferred()

func _start() -> bool:
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	app.repository.data = Repository.empty_store()
	app._enter_level("3-1")
	return _check(await _drain(), "lightwell cold entry settles from an empty MemoryRepository")

func _dispose() -> void:
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

func _button(id: String) -> Button:
	for node: Node in app.hud._commands.get_children():
		if node is Button and str(node.get_meta("command_id", "")) == id: return node
	return null

func _act(id: String, label: String) -> bool:
	app.hud.close_context_choices()
	var revision: int = app.session.revision
	app._on_command(id)
	var settled := await _drain(700)
	var accepted: bool = app.session.revision > revision or bool(app.session.world.state.completed)
	events.append({"label": label, "command": id, "input": "application command", "viewport": [dimensions.x, dimensions.y], "accepted": accepted, "settled": settled, "status": app.status_message})
	return _check(settled and accepted, label + " accepted through the actual application")

func _e_action(id: String, label: String) -> bool:
	app.hud.close_context_choices()
	var revision: int = app.session.revision
	_key(KEY_E, true)
	_key(KEY_E, false)
	await RenderingServer.frame_post_draw
	var menu: bool = app.hud.is_context_open()
	if menu:
		var button := _button(id)
		if not _check(button != null and not button.disabled, label + " has an actual available menu button"): return false
		await _capture(label + "-menu")
		button.pressed.emit()
	var settled := await _drain(700)
	var accepted: bool = app.session.revision > revision or bool(app.session.world.state.completed)
	events.append({"label": label, "command": id, "input": "E press/release through application _input, then actual Button signal when the original menu has choices", "viewport": [dimensions.x, dimensions.y], "menuOpened": menu, "accepted": accepted, "settled": settled, "status": app.status_message})
	return _check(settled and accepted, label + " executes through E and the original direct/menu semantics")

func _capture(label: String) -> void:
	app._update_layout()
	app.view._fit_camera(true)
	for unused in range(8): await RenderingServer.frame_post_draw
	var light_source: Node3D = app.view._lightwell_dressing._source
	var previous := Vector3.ZERO
	var axis := Vector3.ZERO
	var source_at := Vector3.ZERO
	var beam_count := 0
	for child: Node in app.view._effects.get_children():
		if not child is MeshInstance3D or str(child.get_meta("rule_path", "")) != "lamp" or not child.visible: continue
		var half: Vector3 = child.global_basis.y * child.mesh.height * .5
		var a: Vector3 = child.global_position - half
		var b: Vector3 = child.global_position + half
		if beam_count == 0:
			source_at = a
			axis = (b - a).normalized()
			_check(a.distance_to(light_source.global_position) < .001, label + " visible beam starts at real lamp")
		else:
			_check(a.distance_to(previous) < .001, label + " visible beam joins without gaps")
		_check((a - source_at).cross(axis).length() < .001 and (b - source_at).cross(axis).length() < .001, label + " visible beam stays straight")
		previous = b
		beam_count += 1
	var pixels := outer.get_texture().get_image()
	var file := "%s-%dx%d.png" % [label, dimensions.x, dimensions.y]
	_check(pixels != null and pixels.get_size() == dimensions and pixels.save_png(output.path_join(file)) == OK, "lightwell GPU original " + file)
	var bodies := {}
	for who: String in ["luvie", "buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		bodies[who] = {"position": [body.position.x, body.position.y, body.position.z], "support": app.session.world.state.actors[who], "clearOfHardProps": app.view.prop_physical_point_clear(body.position, who)}
	var labels: Array = []
	for node: Node in app.hud.find_children("*", "Label", true, false):
		if node.is_visible_in_tree() and not node.text.is_empty(): labels.append(node.text)
	images.append({"file": file, "viewport": [dimensions.x, dimensions.y], "snapshot": app.session.world.snapshot(), "bodies": bodies, "receiverLit": app.session.world.lamp_at_receiver(), "lampRay": app.session.world.lamp_ray(), "visibleHudLabels": labels, "menuOpen": app.hud.is_context_open(), "choices": app.hud._context_choices.duplicate(true) if app.hud.is_context_open() else [], "nativeContext": app._native_interaction_context(), "status": app.status_message, "motionEmpty": app.motion.is_empty(), "captureExcludesAppTicks": true})
	print("CAPTURE " + file)

func _original_route(fixture: Dictionary) -> bool:
	await _capture("cold")
	var executed := 0
	var success := true
	for index in fixture.steps.size():
		var command: Dictionary = fixture.steps[index].command
		app.hud.close_context_choices()
		if str(command.kind) == "move":
			success = await _walk_to(str(command.value), "original lightwell intention " + str(index))
		elif str(command.kind) == "act":
			if str(command.value) in ["take:lamp", "use:window", "repair"]:
				success = await _e_action(str(command.value), "original-" + str(index) + "-" + str(command.value).replace(":", "-"))
			else:
				success = await _act(str(command.value), "original lightwell intention " + str(index))
		else:
			success = _check(false, "unsupported original lightwell fixture command")
		if not success: break
		executed += 1
		_check(app.session.world.normalize_saved(app.session.world.snapshot()).get("ok", false), "original lightwell step " + str(index) + " is a valid saved journey")
		if index == 1: await _capture("buddy-holds-lamp")
		elif index == 5: await _capture("buddy-low-passage")
		elif index == 13:
			_check(app.session.world.lamp_at_receiver() and int(app.session.world.state.items.lamp.angle) == 0, "original default lamp direction lights the receiver without a forced rotation")
			await _capture("socket-receiver-lit")
		elif index == 17: await _capture("luvie-on-temporary-path")
		elif index == 21:
			_check(app.session.world.flag("window"), "original stone window opens through E/menu")
			await _capture("window-open")
		elif index == 30: await _capture("buddy-brings-lamp-back")
		elif index == 40: await _capture("reunion-with-lamp")
	var complete: bool = app.session.world.state.completed
	_check(success and executed == 43 and complete, "original 43 lightwell intentions complete through real bodies and original actions")
	routes.append({"level": "3-1", "viewport": [dimensions.x, dimensions.y], "steps": executed, "expectedSteps": 43, "success": success, "completed": complete})
	if complete:
		app._on_command("stay")
		await _capture("completed")
	return success and complete

func _walk_discovering(id: String, label: String) -> bool:
	# Cold hidden destinations are not clickable in the real interface. Follow
	# legal adjacent intentions so each next surface is discovered naturally.
	var path: Array = app.session.world.path_to(id)
	if not _check(not path.is_empty() or str(app.session.world.state.actors[app.session.world.actor()]) == id, label + " has an original rule route"): return false
	for tile: String in path:
		if not await _walk_to(tile, label + " / " + tile): return false
	return true

func _legal_variants() -> bool:
	if not await _act("switch", "unlit variant selects buddy without taking lamp"): return false
	if not await _walk_discovering("f:3:5", "unlit buddy reaches the actual socket through the low route"): return false
	_check(app.session.world.state.items.lamp.get("holder", "") != "buddy" and not app.session.world.lamp_at_receiver() and not app.session.world.has_path_to("f:3:0"), "unlit socket does not create a bridge when buddy has no lamp")
	app._go("f:3:0")
	await _capture("unlit-buddy-at-socket")
	if not await _walk_discovering("f:-2:0", "unlit buddy physically returns to the original lamp"): return false
	if not await _e_action("take:lamp", "recovered-take-lamp"): return false
	_check(app.session.world.state.items.lamp.get("holder", "") == "buddy", "actual E recovers the originally available lamp")
	await _capture("unlit-recovered-lamp")
	# These are extra legal control trials; no angle action is inserted into
	# the unchanged original 43-intention replay, whose default is valid.
	for turn in range(4):
		if not await _e_action("angle:lamp", "optional-lamp-turn-" + str(turn + 1)): return false
		if turn == 0: await _capture("optional-current-lamp-direction")
	_check(int(app.session.world.state.items.lamp.angle) == 0, "four optional original rotations restore the existing default direction")
	if not await _walk_discovering("f:3:5", "recovered lamp reaches socket"): return false
	if not await _e_action("drop:lamp:f:3:5", "socket-drop-lamp"): return false
	_check(app.session.world.lamp_at_receiver() and app.session.world.state.items.lamp.get("holder", "").is_empty(), "a lamp legally placed at the socket still supplies the original light path")
	await _capture("socket-ground-lamp-supplies-path")
	if not await _e_action("take:lamp", "socket-retake-lamp"): return false
	if not await _act("switch", "protected-path selects luvie"): return false
	if not await _walk_discovering("f:0:0", "luvie occupies the real temporary light path"): return false
	if not await _act("switch", "protected-path selects lamp carrier"): return false
	var before: Dictionary = app.session.world.snapshot()
	app._execute(Command.move_to("f:2:5"), "move")
	var settled := await _drain(300)
	var protected: bool = settled and app.session.world.state.actors.buddy == before.actors.buddy and app.session.world.state.actors.luvie == before.actors.luvie and app.session.world.lamp_at_receiver() and not app.session.world.point_for("f:0:0").is_empty()
	_check(protected, "original occupied-road protection refuses to carry the lamp away from a traveller on its temporary bridge")
	events.append({"label": "occupied-light-path-lamp-takeaway", "viewport": [dimensions.x, dimensions.y], "input": "real app path request and body crossing attempt", "protected": protected, "before": before, "after": app.session.world.snapshot(), "status": app.status_message, "nativeBodies": app.native_movement.qa_state()})
	await _capture("occupied-light-path-protected")
	if not protected: return false
	if not await _act("switch", "stable-path selects luvie"): return false
	if not await _walk_discovering("f:3:0", "luvie reaches the original stone-window control"): return false
	if not await _e_action("use:window", "variant-window-open"): return false
	if not await _act("switch", "stable-path selects lamp carrier"): return false
	if not await _walk_discovering("f:2:5", "lamp leaves socket after the original window is fixed"): return false
	_check(app.session.world.flag("window") and not app.session.world.lamp_at_receiver() and not app.session.world.point_for("f:0:0").is_empty(), "window keeps the original permanent path after the lamp moves away")
	await _capture("window-stable-after-lamp-leaves")
	return true

func _hashes() -> Dictionary:
	var hashes := {}
	for path: String in ["tests/native_lightwell_capture.gd", "tests/native_route_test.gd", "tests/fixtures/reference.json", "core/garden_world.gd", "application/main.gd", "application/native_movement.gd", "application/native_interaction.gd", "application/journey_view.gd", "ui/garden_hud.gd", "presentation/native/native_garden_stage.gd", "presentation/native/mechanism_props.gd", "presentation/native/original_carry_art.gd", "presentation/native/rule_ray_presentation.gd", "presentation/native/native_prop_obstacles.gd", "presentation/native/original_scenery_positions.gd", "content/levels.json"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	for path: String in ["presentation/native/lightwell_dressing.gd"]:
		if FileAccess.file_exists("res://" + path): hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes

func _hero_lamp_variant() -> bool:
	if not await _walk_discovering("f:-2:0", "hero approaches the original lamp"): return false
	if not await _e_action("take:lamp", "hero-takes-lamp"): return false
	_check(app.session.world.state.items.lamp.get("holder", "") == "luvie", "hero is the real lamp carrier")
	for turn in range(4):
		await _capture("hero-lamp-direction-" + str(turn))
		if not await _e_action("angle:lamp", "hero-turn-" + str(turn)): return false
	return true

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Actual GPU and explicit lightwell output required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	sources_before = _hashes()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary = {}
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/3-1": fixture = entry
	_check(not fixture.is_empty() and fixture.steps.size() == 43, "frozen original lightwell route has 43 atomic intentions")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		dimensions = size
		if await _start(): await _original_route(fixture)
		await _dispose()
		var success := false
		if await _start(): success = await _legal_variants()
		variants.append({"viewport": [dimensions.x, dimensions.y], "success": success})
		await _dispose()
		var hero_success := false
		if await _start(): hero_success = await _hero_lamp_variant()
		variants.append({"viewport": [dimensions.x, dimensions.y], "name": "hero four directions", "success": hero_success})
		await _dispose()
	var sources_after := _hashes()
	_check(sources_before == sources_after, "lightwell production and capture sources remain stable during the batch")
	failures.append_array(logger.captured_errors())
	var report := {"suite": "native-lightwell-real-app-gpu", "sourceSha256": source_sha, "testSha256": FileAccess.get_sha256("res://tests/native_lightwell_capture.gd"), "sourceFilesStable": sources_before == sources_after, "initialSources": sources_before, "finalSources": sources_after, "originalRoutes": routes, "variants": variants, "images": images, "events": events, "checks": checks, "failures": failures, "passed": failures.is_empty(), "samples": samples, "maxBodySurfaceGap": max_body_surface_gap, "maxVisualContactError": max_visual_penetration, "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "scope": "Original 43 lightwell intentions at 1280x720 and 844x390 through real native bodies; E events through application _input and actual menu Button signals preserve the original direct/single/multiple semantics. Independent legal variants cover an unlit buddy at the socket, real return/pickup, optional four lamp rotations, drop/retake supply, occupied temporary-path protection and permanent window response. No actor/snapshot injection, changed fixture or required new angle step. Screenshots wait actual GPU draws without app ticks; no fixed screenshot count. AudioStub retained: no audio, OS-level touch, browser input or Web performance validation."}
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	finished = true
	print(JSON.stringify({"checks": checks, "images": images.size(), "routes": routes, "variants": variants, "passed": report.passed, "failures": failures}))
	quit(0 if report.passed else 1)
