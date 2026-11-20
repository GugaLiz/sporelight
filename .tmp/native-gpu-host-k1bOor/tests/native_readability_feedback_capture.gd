extends "res://tests/native_symbiosis_capture.gd"
## Feedback 116: real art picking, E/menu routing, physical frontier walking,
## disposable plan pointer input and explicit confirmation. No user saves.
const Prototype := preload("res://prototypes/root_weaving.gd")
var feedback_output := ""

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Readability capture requires a real renderer for frame_post_draw and pointer pixels")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	_run.call_deferred()

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		app._input(event)

func _tap(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	app.view._last_touch_ms = -1000
	app.view._unhandled_input(event)

func _settle() -> bool:
	for unused in 2400:
		await _tick()
		if app.motion.is_empty() and not app.native_movement.is_moving() and (not app is Prototype or app.phase != "growing"): return true
	return false

func _capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await super._capture(label)

func _official() -> void:
	branch = "official"
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.command_selected.connect(app._on_command)
	app.view.tile_selected.connect(app._go)
	app._enter_level("1-1")
	await _settle()
	app.view._fit_camera(true)
	await process_frame
	var entry: Dictionary = app.view._garden_effects.collectibles["spore-1"]
	var at: Vector2 = app.view.world_to_screen(entry.sprite.global_position)
	_check(app.view.hit_test(at) == str(entry.tile), "click floating light centre selects its support, not the ground behind")
	if DisplayServer.get_name() != "headless":
		await _capture("light-before")
		_tap(at)
		_check(await _settle(), "clicking floating light follows an existing legal path")
		_check("spore-1" in app.session.world.state.collected, "floating body click really collects and updates state")
		await _capture("light-collected")
	app._enter_level("1-1")
	await _settle()
	_key(KEY_E)
	_check(app.hud.is_context_open() and app.session.world.state.growth.root.is_empty(), "E opens growth direction menu without committing")
	app.hud.close_context_choices()
	app._on_command("grow:root:right")
	await _settle()
	var before: Dictionary = app.session.world.snapshot()
	_key(KEY_E)
	_check(app.hud.is_context_open() and app.motion.is_empty() and app.session.world.snapshot() == before, "E after a single-section bridge does not immediately retract it")
	_check(app.hud._interaction_label != "收回根路", "retraction has an explicit secondary menu entry")
	_key(KEY_ESCAPE)
	_check(not app.hud.is_context_open() and not app.paused, "Escape leaves action selection and restores walking, without opening pause")
	_key(KEY_Z)
	await _settle()
	_check(app.session.world.state.growth.root.is_empty() and "撤销生长" in app.status_message, "Z independently undoes growth with a specific result")
	app._enter_level("1-2")
	await _settle()
	await _walk_to("f:-1:0", "rest-approach")
	app.hud.close_context_choices()
	var rest_revision: int = app.session.revision
	app._on_command("observe:rest")
	await _settle()
	_check(app.session.revision > rest_revision and not app.paused, "rest interaction is accepted and does not pause walking")
	var rest_body: CharacterBody3D = app.view.get_actor_body("luvie")
	var rest_position: Vector3 = rest_body.position
	var held := InputEventKey.new()
	held.keycode = KEY_RIGHT
	held.physical_keycode = KEY_RIGHT
	held.pressed = true
	app._input(held)
	for unused in 24: await _tick()
	held.pressed = false
	app._input(held)
	await _settle()
	_check(rest_body.position.distance_to(rest_position) > .15, "held direction input physically walks away after rest")
	await _walk_to("f:0:1", "return-from-rest")
	app._on_command("grow:root:up")
	await _settle()
	var context: Dictionary = app._native_interaction_context()
	_check(context.get("choices", []).any(func(c: Dictionary) -> bool: return c.id == "approach:root"), "one built segment offers an explicit frontier walk")
	_check("走到根路前端" in app.hud._interaction_label, "primary text explains why continuation requires walking")
	await _capture("one-section-frontier")
	app._on_command("approach:root")
	_check(await _settle(), "frontier navigation physically settles")
	_check(app.session.world.state.growth.root.size() == 1 and app.session.world.can_grow_root(app.session.world.level.roots[0]), "frontier walk never builds remotely and reaches the legal builder support")
	_check(not app.view.growth_choice_layout().is_empty(), "next plus is present after reaching the frontier")
	await _capture("next-plus")
	app._on_command("grow:root:right")
	await _settle()
	_check(app.session.world.state.growth.root.size() == 2, "the next section can actually grow")
	app._enter_level("1-1")
	await _settle()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if str(fixture.name) != "authored/1-1": continue
		for index in fixture.steps.size():
			var step: Dictionary = fixture.steps[index]
			var label := "first-%02d" % index
			if step.command.kind == "move": await _walk_to(str(step.command.value), label)
			else:
				# The authored flower moved uphill after the historical intention
				# fixture; follow the current marker, as native_route_test does.
				if str(step.command.value) == "repair":
					for mark: Dictionary in app.session.world.level.marks:
						if str(mark.kind) == "core": await _walk_to(str(mark.tile), label+"-current-flower")
				await _e_action(str(step.command.value), label)
	_check(app.session.world.state.completed, "original first garden route still completes with optional detour and explicit retract")
	await _capture("first-completed")
	await _dispose()

func _prototype() -> void:
	branch = "plan"
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	app = Prototype.new()
	outer.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.set_process_input(false)
	app.audio.free()
	app.audio = AudioStub.new()
	app.add_child(app.audio)
	await _settle()
	app.view._fit_camera(true)
	for directions: Array in [["up","right","right","down"],["down","right","right","up"]]:
		app._on_command("restart")
		app._on_command("primary")
		var baseline: Dictionary = app.session.world.snapshot()
		for i in 4:
			_check(app.view.draft.size() == i and not app.view.options.is_empty(), "draft %d/4 retains legal plus choices" % i)
			await _capture("%s-draft-%d" % [directions[0],i])
			var target := ""
			for choice: Dictionary in app.view.options:
				if str(choice.id).ends_with(":"+directions[i]): target = str(choice.target)
			if not _check(not target.is_empty(), "next authored pointer choice exists"): break
			_tap(app.view.target_position(target))
			_check(app.view.draft.size() == i+1 and app.session.world.snapshot() == baseline, "pointer adds visible draft without making walkable ground")
		_check(app.plan.ready() and app.hud._interaction_label == "确认生长根桥", "ready draft keeps its independent explicit confirmation label")
		await _capture("%s-ready" % directions[0])
		_key(KEY_E)
		_check(await _settle() and app.session.world.connected(), "E confirmation walks and grows the full route")
		await _capture("%s-grown" % directions[0])
	await _dispose()

func _run() -> void:
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions = size
		await _official()
		await _prototype()
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"images":images,"scope":"Application key events, actual stage pointer handlers, in-memory saves and physical body ticks; GPU images separately inspected. Audio stub, not audio or performance acceptance."}
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("feedback.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	finished = true
	quit(0 if failures.is_empty() else 1)
