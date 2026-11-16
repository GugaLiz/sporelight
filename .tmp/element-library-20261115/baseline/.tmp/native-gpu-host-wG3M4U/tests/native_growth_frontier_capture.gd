extends "res://tests/native_symbiosis_capture.gd"
## Original puzzle intentions plus explicit physical walks to each new frontier.
## No actor injection; historical fixtures remain immutable and are not rebaselined.
const Interaction = preload("res://application/native_interaction.gd")
var current_level := "3-3"
var extra_walks: Array = []
var growth_inputs: Array = []
var selected_level := ""

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
		elif argument.begins_with("--level="): selected_level = argument.trim_prefix("--level=")
	create_timer(1200).timeout.connect(func() -> void:
		if not finished: push_error("Frontier GPU capture timed out"); quit(2))
	_run.call_deferred()

func _start() -> bool:
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.command_selected.connect(app._on_command)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	app.repository.data = Repository.empty_store()
	app._enter_level(current_level)
	return _check(await _drain(), current_level + " cold entry settles")

func _frontier() -> String:
	var path: Array = app.session.world.state.growth.root
	if path.is_empty(): return str(app.session.world.level.roots[0].at)
	var split := str(path.back()).split(":")
	for tile: Dictionary in app.session.world.tiles():
		if is_equal_approx(float(tile.x), float(split[2])) and is_equal_approx(float(tile.z), float(split[3])) and is_equal_approx(float(tile.h), float(app.session.world.level.roots[0].h)): return str(tile.id)
	return ""

func _build(id: String, label: String) -> bool:
	var before_count: int = app.session.world.state.growth.root.size()
	if before_count > 0:
		var old_revision: int = app.session.revision
		var old: Dictionary = app.session.world.snapshot().duplicate(true)
		# The last build leaves the hero on the previous support. Old buttons
		# and direct command dispatch must not silently construct farther away.
		_check(not app.session.world.commands().any(func(c: Dictionary) -> bool: return str(c.id).begins_with("grow:")), label + " previous support offers no remote build")
		app._on_command(id)
		await _drain()
		_check(app.session.revision == old_revision and app.session.world.state.growth == old.growth, label + " stale command does not spend bud or extend")
		var destination := _frontier()
		var from := str(app.session.world.state.actors.luvie)
		if not await _walk_to(destination, label + " real frontier approach"): return false
		extra_walks.append({"level":current_level,"viewport":[dimensions.x,dimensions.y],"from":from,"to":destination,"beforeSection":before_count + 1})
		await _capture(label + "-on-frontier")
	var offered: Array = app.session.world.commands().filter(func(c: Dictionary) -> bool: return str(c.id) == id)
	if not _check(offered.size() == 1, label + " next original direction offered at frontier"): return false
	var anchor := Interaction.command_tile(app.session.world, offered[0])
	if not _check(str(anchor.id) == _frontier(), label + " menu focuses existing frontier"): return false
	app._update_layout()
	app.view._fit_camera(true)
	for unused in range(5): await RenderingServer.frame_post_draw
	var choice: Dictionary = {}
	for value: Dictionary in app.view.growth_choice_layout():
		if str(value.id) == id: choice = value
	var revision: int = app.session.revision
	var input := "E/menu"
	var success := false
	if not choice.is_empty() and before_count % 2 == 1:
		var position := Vector2(float(choice.x), float(choice.y))
		_check(app.view.command_hit_test(position) == id, label + " visible plus shares actual hit target")
		if dimensions.x < 1000:
			var touch := InputEventScreenTouch.new()
			touch.position = position; touch.pressed = true
			app.view._unhandled_input(touch)
			input = "scene touch plus"
		else:
			var click := InputEventMouseButton.new()
			click.position = position; click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
			app.view._unhandled_input(click)
			input = "scene mouse plus"
		success = await _drain(700)
		success = _check(success and app.session.revision > revision, label + " scene plus builds through application") and success
	else:
		success = await _e_action(id, label)
	if not success: return false
	_check(app.session.world.state.growth.root.size() == before_count + 1, label + " exactly one section built")
	growth_inputs.append({"level":current_level,"viewport":[dimensions.x,dimensions.y],"section":before_count + 1,"input":input,"support":str(app.session.world.state.actors.luvie),"path":app.session.world.state.growth.root.duplicate()})
	await _capture(label + "-built")
	if before_count == 0:
		app._on_command("undo")
		_check(await _drain(700) and app.session.world.state.growth.root.is_empty(), label + " application undo restores empty road")
		await _capture(label + "-undone")
		if not await _e_action(id, label + "-rebuild"): return false
	return true

func _route(fixture: Dictionary) -> bool:
	await _capture("cold")
	var executed := 0
	var expected_before: Dictionary = fixture.initial.snapshot
	for index: int in fixture.steps.size():
		app.hud.close_context_choices()
		var command: Dictionary = fixture.steps[index].command
		var id := str(command.value)
		var label := "step-" + str(index) + "-" + id.replace(":", "-")
		var success := false
		if str(command.kind) == "move": success = await _walk_to(id, current_level + "/" + label)
		elif str(command.kind) == "act":
			if id.begins_with("grow:"):
				if app.session.world.state.growth.root.is_empty():
					var intended := str(expected_before.actors.get(app.session.world.actor(), ""))
					if not intended.is_empty() and not await _walk_to(intended, label + " seedbed approach"): return false
				success = await _build(id, label)
			else:
				var actor: String = app.session.world.actor()
				var intended := str(expected_before.actors.get(actor, ""))
				if not intended.is_empty() and intended != str(app.session.world.state.actors[actor]):
					if not await _walk_to(intended, label + " original interaction approach"): return false
				if id in ["switch", "follow"]:
					var revision: int = app.session.revision
					app._on_command(id)
					success = await _drain(700)
					success = _check(success and app.session.revision > revision, label + " original global action") and success
				else: success = await _e_action(id, label)
		if not success: return false
		executed += 1
		expected_before = fixture.steps[index].snapshot
		_check(app.session.world.normalize_saved(app.session.world.snapshot()).get("ok", false), label + " remains valid save")
		if command.kind == "act" and not id.begins_with("grow:"): await _capture(label + "-settled")
	var completed: bool = app.session.world.state.completed
	_check(completed and executed == fixture.steps.size(), current_level + " completes original intentions with added frontier walks")
	routes.append({"level":current_level,"viewport":[dimensions.x,dimensions.y],"originalIntentions":executed,"completed":completed,"addedFrontierWalks":extra_walks.filter(func(v: Dictionary) -> bool: return v.level == current_level and v.viewport == [dimensions.x,dimensions.y]).size()})
	if completed:
		var stay := _find_stay(app.hud)
		if not _check(stay != null, "actual completed overlay offers stay"): return false
		stay.pressed.emit()
		_check(bool(app.session.world.state.completed), "stay preserves completed bloom state")
		await _capture("completed")
	return completed

func _find_stay(node: Node) -> Button:
	if node is Button and node.text == "留下看看": return node
	for child: Node in node.get_children():
		var found := _find_stay(child)
		if found != null: return found
	return null

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["core/garden_world.gd","application/main.gd","application/native_movement.gd","application/native_interaction.gd","presentation/native/native_garden_stage.gd","presentation/native/original_prop_ratios.gd","presentation/native/native_prop_obstacles.gd","tests/native_growth_frontier_capture.gd","tests/native_route_test.gd","tests/native_symbiosis_capture.gd","tests/fixtures/reference.json"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": push_error("Actual GPU and output required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before := _hashes()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for configuration: Array in [["1-2",1280,720],["3-3",1280,720],["3-3",844,390],["3-4",1280,720]]:
		current_level = str(configuration[0]); dimensions = Vector2i(configuration[1],configuration[2]); branch = current_level
		if not selected_level.is_empty() and current_level != selected_level: continue
		var fixture: Dictionary = {}
		for entry: Dictionary in reference.cases:
			if str(entry.name) == "authored/" + current_level: fixture = entry
		if await _start(): await _route(fixture)
		await _dispose()
	var after := _hashes()
	_check(before == after,"frontier sources stable")
	failures.append_array(logger.captured_errors())
	var report := {"suite":"growth-frontier-real-input-gpu","sourceSha256":source_sha,"sourceFilesStable":before == after,"initialSources":before,"finalSources":after,"passed":failures.is_empty(),"checks":checks,"failures":failures,"routes":routes,"images":images,"events":events,"extraWalks":extra_walks,"growthInputs":growth_inputs,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"maxVisualContactError":max_visual_penetration,"scope":"Original intentions plus physically walked frontier approaches; E/menu and scene mouse/touch plus. No actor snapshot injection. AudioStub; not browser input, performance or audio acceptance."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ") + "\n")
	finished = true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures,"routes":routes,"images":images.size()}))
	quit(0 if report.passed else 1)
