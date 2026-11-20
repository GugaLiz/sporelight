extends "res://tests/native_route_test.gd"
## Feedback 119: alternate drops, switch/restore, real motor and held input.
var observations: Array = []
var output := ProjectSettings.globalize_path("res://../docs/qa-godot-native/fourth-feedback-20261119")

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	app._input(event)

func _load(state: Dictionary) -> void:
	app.repository.data.mainline.runs["1-4"] = state.duplicate(true)
	app._enter_level("1-4")
	await _tick(); await _tick()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	_setup()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fourth: Dictionary
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/1-4": fourth = entry
	await _replay("1-4", fourth.steps, fourth.initial.snapshot)
	# f:2:0 is the bridge's root-kind endpoint and cannot accept a drop.
	for destination: String in ["f:2:-1", "f:3:0", "f:4:0"]:
		await _load(fourth.steps[20].snapshot)
		_check(await _walk_to(destination, "carry bell to middle " + destination), "middle platform reachable after latch")
		var before_flags: Array = app.session.world.state.flags.duplicate()
		app._on_command("drop:bell:" + destination)
		_check(await _drain(), "drop settles on middle " + destination)
		_check(app.session.world.state.items.bell.tile == destination and app.session.world.state.items.bell.get("holder", "") == "", "bell actually dropped " + destination)
		_check(not app.status_message.contains("光与道路") and app.status_message.contains("门铃"), "bell drop feedback describes item rather than road " + destination)
		_check(app.session.world.state.flags == before_flags, "bell drop never changes permanent roads")
		for unused in 2:
			app._on_command("switch"); await _drain()
			var actor_name := "露薇" if app.session.world.actor() == "luvie" else "小苔灵"
			_check(app.status_message.contains("当前控制：" + actor_name), "switch names current actor " + actor_name)
			_check(app.session.world.state.actors.buddy == "f:3:5" and app.session.world.flag("latch"), "switch preserves plate stance and permanent latch")
		if destination == "f:3:0":
			app._enter_level("1-4"); await _tick(); await _tick()
			_check(app.session.world.state.items.bell.tile == destination and app.session.world.flag("latch"), "reload preserves relocated middle bell and latch")
		app._on_command("take:bell"); await _drain()
		_check(app.session.world.state.items.bell.get("holder", "") == "luvie", "middle bell can be picked up again")
		_check(await _walk_to("f:-4:0", "return from middle " + destination), "real motor returns bell to home from middle")
		app._on_command("use:home"); await _drain()
		_check(app.session.world.flag("home") and not app.session.world.state.completed, "return opens gate without automatic completion")
		app._on_command("switch"); await _drain()
		_check(await _walk_to("f:-4:0", "buddy leaves plate after middle drop"), "buddy returns after leaving plate on fixed roads")
		observations.append({"case":destination,"state":app.session.world.snapshot(),"motor":app.native_movement.qa_state()})
	# Original negative constraints still apply; no permanent bypass is added.
	await _load(fourth.initial.snapshot)
	_check(not app.session.world.has_path_to("f:3:0"), "unsolved bridge remains closed")
	_check(not app.session.world.has_path_to("f:-3:5"), "unsolved south gate remains closed")
	_check(await _walk_to("f:-2:0", "approach unsolved gap"), "gap edge reachable")
	var notices: Array = []
	app.native_movement.blocked.connect(func(message: String) -> void: notices.append(message))
	_key(KEY_RIGHT, true)
	for unused in 80: await _tick()
	_key(KEY_RIGHT, false)
	_check(not notices.is_empty() and notices.size() <= 2, "held direction gives immediate throttled gap feedback")
	_check(app.session.world.state.actors.luvie == "f:-2:0", "held direction cannot cross unsolved gap")
	_check(app.status_message.contains("重杆"), "gap feedback explains current cooperation requirement")
	app._go("f:3:0")
	_check(app.status_message.contains("重杆"), "world click explains same cooperation requirement")
	app.native_movement._block_delay = 0
	app._step("right", false)
	_check(app.status_message.contains("重杆"), "touch direction nudge explains same cooperation requirement")
	observations.append({"case":"closed-gap-held-key","notices":notices,"message":app.status_message})
	await _load(fourth.steps[20].snapshot)
	_check(await _walk_to("f:3:0", "low arch approach"), "middle reaches arch entrance")
	app.native_movement._block_delay = 0
	_key(KEY_DOWN, true)
	for unused in 65: await _tick()
	_key(KEY_DOWN, false)
	_check(app.session.world.state.actors.luvie == "f:3:0", "luvie still cannot cross small arch after latch")
	_check(app.status_message.contains("低拱") and app.status_message.contains("小苔灵"), "keyboard arch feedback identifies character restriction")
	app._go("f:3:3")
	_check(app.status_message.contains("低拱"), "click arch feedback identifies same restriction")
	_check(app.session.world.has_path_to("f:-4:0"), "arch restriction does not disconnect middle from home")
	_check(await _walk_to("f:-4:0", "leave arch for home"), "blocked keyboard input leaves motor free to return home")
	app._sync_hud()
	_check(app.hud._action_help.text.contains("门铃"), "current action panel provides cooperation context")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"samples":samples,"routes":routes,"observations":observations,"scope":"Original 50 intentions plus three alternate middle-platform drops, repeated switch, restore, real motor return and native key handlers. Memory saves; no OS/browser input or pixel assertions."}, "  "))
	print(JSON.stringify({"suite":"fourth-feedback-119","checks":checks,"samples":samples,"passed":failures.is_empty(),"failures":failures}))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
