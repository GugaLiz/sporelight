extends "res://tests/native_hud_feedback_capture.gd"
## Feedback 120: exact reported corridor, both actors, rendered bridge and click.
var observations: Array = []
var fourth: Dictionary

func _capture(label: String) -> void:
	app._update_layout(); app.view._fit_camera(true)
	for unused in 6: await RenderingServer.frame_post_draw
	var file := label + ".jpg"
	_check(outer.get_texture().get_image().save_jpg(output.path_join(file), .96) == OK, "GPU " + file)
	images.append(file)
	observations.append({"label":label,"state":app.session.world.snapshot(),"movement":app.native_movement.qa_state(),"message":app.status_message})

func _load(state: Dictionary) -> void:
	app.repository.data.mainline.runs["1-4"] = state.duplicate(true)
	app._enter_level("1-4"); await _tick(); await _tick()

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	dimensions = Vector2i(1600,900)
	outer = SubViewport.new(); outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(outer)
	_setup(); app.reparent(outer)
	app.view.tile_selected.connect(app._go); app.view.command_selected.connect(app._on_command)
	app.view.set_settings(app.settings); app.hud.apply_settings(app.settings)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) == "authored/1-4": fourth = entry
	await _load(fourth.steps[20].snapshot)
	_check(app.session.world.flag("latch") and app.hud._fourth_journey.steps[0].done, "latch flag and visible milestone agree")
	# Check the actual derived board, not only fixed JSON tiles.
	for tile: Dictionary in app.session.world.tiles():
		if bool(tile.get("solid",false)) or float(tile.x) < -4: continue
		for who: String in ["luvie","buddy"]:
			if who == "luvie" and bool(tile.get("small",false)): continue
			# The southeast island belongs to buddy's low-arch route. Luvie
			# cannot enter it in play; do not fabricate a reachable placement.
			if who == "luvie" and float(tile.x) >= 2 and float(tile.z) >= 4:
				_check(not app.session.world.has_path_to(str(tile.id), who), "luvie cannot enter buddy-only southeast island " + str(tile.id))
				continue
			var saved: Dictionary = app.session.world.snapshot()
			saved.erase("runtime"); saved.active = who; saved.actors[who] = str(tile.id)
			var test_world := preload("res://core/garden_world.gd").new("1-4", saved)
			_check(test_world.has_path_to("f:-4:0", who), "latched graph reaches home " + who + "/" + str(tile.id))
	for z in [1,2,3,4]:
		var id := "f:3:" + str(z)
		_check(bool(app.session.world.point_for(id).small), "reported corridor remains buddy-only " + id)
		var invalid: Dictionary = app.session.world.snapshot()
		invalid.actors.luvie = id; invalid.erase("runtime")
		_check(not app.session.world.normalize_saved(invalid).ok, "saved luvie inside low arch is rejected " + id)
	_check(not app.session.world.has_path_to("f:3:3", "luvie"), "normal luvie route cannot enter reported f:3:3")
	# Observe the actual latch and drop first, not a UI-only done flag.
	_check(await _walk_to("f:3:0", "luvie reaches middle"), "middle reached")
	await _e_action("drop:bell:f:3:0", "middle-drop")
	_check(app.session.world.flag("latch") and app.session.world.state.items.bell.tile == "f:3:0", "drop preserves actual latch")
	app._on_command("switch"); await _drain()
	_check(await _walk_to("f:3:3", "buddy corridor before delivery"), "buddy enters exact reported corridor before home opens")
	_key(KEY_UP, true)
	for unused in 240:
		await _tick()
		if str(app.session.world.state.actors.buddy) == "f:3:0": break
	_key(KEY_UP, false)
	_check(app.session.world.state.actors.buddy == "f:3:0" and not app.session.world.flag("home"), "held UP crosses z3 z2 z1 z0 before delivery")
	_check(await _walk_to("f:-4:0", "buddy home before delivery"), "buddy reaches home after leaving plate while bell is dropped")
	app._on_command("switch"); await _drain()
	app._on_command("overview"); await _capture("01-latched-bridges-overview")
	var home_point: Vector2 = app.view.project(app.session.world.point_for("f:-4:0"))
	var hit: String = app.view.hit_test(home_point)
	_check(hit == "f:-4:0", "visible home target hit maps to home support")
	_tap(home_point)
	_check(await _drain(1000) and app.session.world.state.actors.luvie == "f:-4:0", "actual pointer returns luvie home while bell stays dropped")
	_check(app.session.world.state.items.bell.tile == "f:3:0" and not app.session.world.flag("home"), "empty-handed arrival does not pretend bell delivered")
	await _capture("02-clicked-home-empty-handed")
	_check(await _walk_to("f:3:0", "return to dropped bell"), "middle still reachable from home")
	await _e_action("take:bell", "recover-bell")
	_check(await _walk_to("f:-4:0", "carry recovered bell home"), "bell can be carried home")
	await _e_action("use:home", "deliver-bell")
	_check(app.session.world.flag("home") and not app.session.world.state.completed, "bell opens gate without completion")
	app._on_command("switch"); await _drain()
	_check(await _walk_to("f:3:3", "buddy exact reported corridor"), "buddy physically enters reported f:3:3")
	await _capture("03-buddy-in-reported-corridor")
	_check(await _walk_to("f:3:0", "buddy corridor to upper platform"), "real traversal across z3 z2 z1 z0 succeeds")
	_check(await _walk_to("f:-4:0", "buddy over fixed bridge"), "buddy returns home after leaving plate")
	app._on_command("switch"); await _drain()
	app._on_command("follow"); await _drain()
	_check(await _walk_to("f:-9:0", "both to final bed"), "legal route enters sanctuary")
	_check(await _drain(1000), "companion settles beside bed")
	await _e_action("repair", "plant-together")
	_check(app.session.world.state.completed, "alternative drop and exact corridor route completes")
	await _capture("04-completed-after-corridor-return")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify({"sourceSha256":source_sha,"passed":failures.is_empty(),"checks":checks,"samples":samples,"failures":failures,"images":images,"observations":observations,"scope":"1600x900 GPU; prepared legal post-latch snapshot then real motor, actual home pointer hit, E/menu drop/pickup/delivery, buddy f:3:3 corridor traversal and explicit completion. Read-only graph and illegal-save checks. Memory saves, AudioStub; not a browser replay or original reporter save."},"  "))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"samples":samples,"failures":failures,"images":images.size()}))
	await _dispose(); finished=true; quit(0 if failures.is_empty() else 1)
