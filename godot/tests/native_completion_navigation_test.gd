extends "res://tests/native_input_test.gd"
## Native controller/HUD regression for completion -> stroll -> continuation.
## Uses actual input events; this headless suite does not certify GPU pixels.
const CloudWorld := preload("res://core/cloud_garden_world.gd")

func _find_text(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption and node.is_visible_in_tree():
		return node
	for child: Node in node.get_children():
		var found := _find_text(child, caption)
		if found != null:
			return found
	return null

func _press_text(app: Node, caption: String) -> void:
	var button := _find_text(app.hud, caption)
	_check(button != null and not button.disabled, "visible enabled control: " + caption)
	if button != null and not button.disabled:
		button.pressed.emit()

func _press_e() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	Input.parse_input_event(key)
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	Router.install_native_actions()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var cloud: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for sample: Dictionary in [{"id": "1-1", "next": "1-2"}, {"id": "3-4", "next": ""}, {"id": "cloud-1", "next": "cloud-2"}, {"id": "cloud-3", "next": ""}]:
		var id := str(sample.id)
		var before: Dictionary = {}
		if id.begins_with("cloud-"):
			for fixture: Dictionary in cloud.levels:
				if fixture.id == id:
					before = CloudWorld.new(id, fixture.steps[-2].snapshot).snapshot()
		else:
			for fixture: Dictionary in reference.cases:
				if fixture.name == "authored/" + id:
					before = fixture.steps[-2].snapshot.duplicate(true)
			# The frozen first-garden oracle predates the upper landing. Prepare
			# its same solved mechanism beside today's authored repair support.
			if id == "1-1":
				before.actors.luvie = "f:3:-2"
				before.actors.buddy = "f:3:-2"
		var app := Harness.new()
		root.add_child(app)
		app.set_process(false)
		app.set_physics_process(false)
		app.levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
		app.levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
		app.input_router = Router.new()
		app.repository = MemoryRepository.new()
		app.repository.configure_levels(app.levels)
		app.repository.snapshot_validator = app._normalize_snapshot
		app.audio = AudioStub.new()
		app.add_child(app.audio)
		app.settings = Repository.default_settings()
		app.view = Stage.new()
		app.add_child(app.view)
		app.hud = HUD.new()
		app.add_child(app.hud)
		app.hud.command_requested.connect(app._on_command)
		app.hud.menu_requested.connect(app._show_menu)
		app.hud.set_repository(app.repository)
		app.native_enabled = true
		_check(app.repository.stage_run(before).ok, id + " precompletion fixture is valid")
		app._enter_level(id)
		await process_frame
		app._on_command("repair")
		await _drain(app)
		_check(app.session.world.state.completed and app.hud.is_modal_open(), id + " explicit repair shows completion")
		if not app.session.world.state.completed:
			print("COMPLETION PREPARATION ", id, " ", app.status_message, " ", app.session.world.state.actors)
			app.queue_free()
			await process_frame
			continue
		var saved: Dictionary = app.repository.data.mainline.duplicate(true)
		_press_text(app, "留下看看")
		await process_frame
		_check(app.strolling and not app.paused and not app.hud.is_modal_open(), id + " stay resumes native movement")
		var context: Dictionary = app._native_interaction_context()
		_check(context.choices.any(func(choice: Dictionary) -> bool: return choice.id == "ending"), id + " continuation is present in the completed context")
		for observation: Dictionary in app._local_commands():
			_check(context.choices.any(func(choice: Dictionary) -> bool: return choice.id == observation.id), id + " keeps optional nearby observations")
		for touch: bool in [false, true]:
			app.hud.set_touch_mode(touch)
			app._sync_hud()
			var primary := _find_button(app.hud, "primary")
			_check(primary != null and not primary.disabled and (primary.text.contains("微光") or primary.text.contains("纪事") or primary.text.contains("继续旅程")), id + " continuation CTA is visible for touch=" + str(touch))
			if primary != null:
				_check(primary.text.ends_with(" · E") != touch, id + " shortcut caption matches the current input mode")
		app.hud.set_touch_mode(false)
		app._sync_hud()
		await _press_e()
		if app.hud.is_context_open():
			await _press_e()
		_check(app.paused and app.hud.is_modal_open(), id + " real E event reopens the completion sheet")
		_check(Repository.json_equivalent(saved, app.repository.data.mainline), id + " reopening does not change saves")
		_press_text(app, "留下看看")
		await process_frame
		var primary := _find_button(app.hud, "primary")
		_check(primary != null and not primary.disabled, id + " button remains usable after repeated stay")
		if primary != null:
			primary.pressed.emit()
			if app.hud.is_context_open():
				_press_text(app, app._ending_action_label())
		if id == "3-4":
			_check(app.hud._journey_ending != null and not app._has_next_garden(),"final mainline repair and repeated E open the dedicated farewell")
			_check(_find_text(app.hud,"去下一片微光 ↗") == null,"mainline farewell offers no cloud continuation")
			app._on_command("next")
			_check(str(app.session.world.level.id) == "3-4" and app.hud._journey_ending != null,"stale next command cannot enter cloud-1")
			_press_text(app,"返回花园地图")
			_check(app.hud._chapter_map.selected_id == "3-4","ending map action returns to the completed final node")
		else:
			_press_text(app, "去下一片微光 ↗" if not str(sample.next).is_empty() else "看看一路的纪事 ↗")
		await process_frame
		if not str(sample.next).is_empty():
			_check(app.session.world.level.id == sample.next and not app.paused and not app.strolling and not app.session.world.state.completed, id + " advances to the next real garden")
		elif id != "3-4":
			_check(app.session.world.level.id == id and app.paused and app.hud._page_kind == "journal", id + " final garden opens the journal")
		_check(Repository.json_equivalent(saved.memories[id], app.repository.data.mainline.memories[id]), id + " advancing preserves the completion memory")
		app.queue_free()
		await process_frame
	print(JSON.stringify({"suite": "native-completion-navigation", "passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "Headless real native stage/controller/HUD, Input.parse_input_event and emitted button signals; GPU pixels and browser pointer input require separate verification."}))
	quit(0 if failures.is_empty() else 1)
