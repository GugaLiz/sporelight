extends "res://tests/native_route_test.gd"
const LeverWorld = preload("res://core/garden_world.gd")
const LeverSnapshot = preload("res://contracts/snapshot_data.gd")

func _fresh(held := false, buddy := "f:-2:0") -> void:
	# Each case starts fresh in this harness's in-memory repository only.
	app.repository.data.mainline.runs.erase("1-4")
	app._enter_level("1-4")
	app.session.world.state.actors.buddy = buddy
	if held: app.session.world.state.flags.append("hold")
	app.view.set_world(app.session.world)
	app.native_movement.restore()
	await _tick()
	await _tick()

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	app.input_router.handle_key(event)

func _run() -> void:
	_setup()
	await _fresh()
	var hero: CharacterBody3D = app.view.get_actor_body("luvie")
	var sprite: AnimatedSprite3D = hero.get_node("Visual/Art")
	_check(not app.session.world.act("release:hold").ok,"release not available when untouched")
	app._on_command("use:hold")
	_check(await _drain(),"actual initial pull settles")
	_check(app.session.world.lever_held(),"lever opens only after approach and pull")
	_check(str(sprite.animation)=="hold_lever","sustained action is upright, not the pickup crouch")
	_check(hero.position.distance_to(app.view.actor_rest_position(app.session.world.point_for("f:-3:0"),"luvie"))<.08,"body really arrives at lever station")
	var revision: int = app.session.revision
	app._on_command("use:hold")
	_check(app.motion.is_empty() and app.session.revision==revision,"repeated hold is idempotent, not a toggle")
	app._on_command("switch")
	_check(app.session.world.actor()=="buddy" and app.session.world.lever_held(),"switch leaves hero holding and buddy free")
	app._on_command("switch")
	var before: Vector3 = hero.position
	var old_support: String = str(app.session.world.state.actors.luvie)
	_key(KEY_LEFT,true)
	await _tick()
	_key(KEY_LEFT,false)
	_check(hero.position.distance_to(before)>.015 and app.session.world.state.actors.luvie==old_support,"move is real but still within the original tile")
	_check(not app.session.world.flag("hold") and app.session.world.point_for("f:0:0").is_empty(),"first within-tile step releases and retracts bridge")
	app._on_command("undo")
	_check(app.session.world.lever_held(),"one undo restores hold before continuous move")
	_check(hero.position.distance_to(before)<.03,"undo restores physical pose as well as bridge")
	# The partner is on a bridge cell: neither explicit release nor the first
	# sub-tile movement may retract their actual support.
	await _fresh(true,"f:0:0")
	hero = app.view.get_actor_body("luvie")
	before = hero.position
	var held_state: Dictionary = app.session.world.snapshot()
	app._on_command("release:hold")
	_check(app.motion.is_empty() and LeverSnapshot.equivalent(held_state,app.session.world.snapshot()),"explicit release rolls back when passenger stands on bridge")
	_key(KEY_LEFT,true)
	await _tick()
	_key(KEY_LEFT,false)
	_check(Vector2(hero.position.x-before.x,hero.position.z-before.z).length()<.001,"blocked release also rolls back native body")
	_check(app.session.world.lever_held() and not app.session.world.point_for("f:0:0").is_empty(),"passenger bridge remains solid")
	app._on_command("undo")
	_check(app.session.world.lever_held(),"blocked attempt adds no walking checkpoint")
	# Bridge-edge capsule protection still applies before the partner changes ID.
	await _fresh(true,"f:2:0")
	var partner: CharacterBody3D = app.view.get_actor_body("buddy")
	partner.position.x = 1.66
	app.native_movement.capture()
	hero = app.view.get_actor_body("luvie")
	before = hero.position
	_key(KEY_LEFT,true); await _tick(); _key(KEY_LEFT,false)
	_check(app.session.world.lever_held() and Vector2(hero.position.x-before.x,hero.position.z-before.z).length()<.001,"shore edge protection blocks release without weakening the guard")
	partner.position.x = 2.0
	app.native_movement.capture()
	_key(KEY_LEFT,true); await _tick(); _key(KEY_LEFT,false)
	_check(not app.session.world.flag("hold"),"after passenger clears shore edge the same move can release")
	# Domain compatibility: latch ends temporary work, old flags are harmless,
	# buddy capability and legacy following cannot leave a ghost holder.
	var world := LeverWorld.new("1-4")
	world.state.active = "buddy"
	_check(not world.act("use:hold",true).ok,"buddy cannot force heavy-lever command")
	world.state.active = "luvie"; world.state.flags=["hold","latch"]
	var restored := LeverWorld.new("1-4",world.snapshot())
	_check(not restored.flag("hold") and not restored.commands().any(func(c:Dictionary)->bool:return c.id=="use:hold"),"old permanent-latch save drops obsolete hold and does not reoffer it")
	_check(not restored.act("use:hold",true).ok,"permanent latch cannot rearm temporary hold")
	# Native approach is cancellable and cannot carry a ball/crouch pose into
	# sustained two-handed work, even after switching a rolling companion.
	await _fresh()
	app._on_command("mode")
	_check(app.rolling,"setup starts in ball mode")
	app._on_command("use:hold");await _drain()
	hero = app.view.get_actor_body("luvie");sprite = hero.get_node("Visual/Art")
	_check(not app.rolling and not app.native_movement.rolling and str(sprite.animation)=="hold_lever","pulling from ball mode stands up before holding")
	app._on_command("switch");app._on_command("mode");app._on_command("switch")
	_check(not app.rolling and str(sprite.animation)=="hold_lever","switching back from rolling buddy retains upright holder")
	var saved_hold: Dictionary = app.session.world.snapshot()
	app.session = preload("res://application/game_session.gd").new("1-4",saved_hold)
	app.view.set_world(app.session.world);app.native_movement.setup(app.session,app.view,app.input_router)
	await _tick()
	_check(app.session.world.lever_held() and str(sprite.animation)=="hold_lever","held save restores logical and visual state")
	app.settings.lowMotion = true;app.view.set_settings(app.settings)
	_check(app.session.world.lever_held(),"reduced motion leaves mechanism state intact")
	app.settings.lowMotion = false;app.view.set_settings(app.settings)
	await _fresh()
	_check(await _walk_to("f:-4:0","approach cancellation setup"),"walk adjacent to handle")
	app._on_command("use:hold")
	_check(app._approaching_heavy_lever and not app.session.world.flag("hold"),"automatic approach does not open bridge early")
	app._go("f:-3:0")
	_check(await _drain() and not app._approaching_heavy_lever and not app.session.world.flag("hold"),"a new click cancels queued pulling even at the same destination")
	_check(await _walk_to("f:-4:0","keyboard cancellation setup"),"return beside handle")
	app._on_command("use:hold");app._step("up",true)
	_check(not app._approaching_heavy_lever,"manual directional input cancels queued pulling")
	await _drain()
	_check(await _walk_to("f:-4:0","natural approach retry"),"walk beside lever before real approach")
	var adjacent: Vector3 = app.view.get_actor_body("luvie").position
	app._on_command("use:hold")
	for frame in range(180):
		await _tick()
		if app.session.world.lever_held() and app.motion.is_empty() and not app._approaching_heavy_lever: break
	_check(app.session.world.lever_held() and app.session.world.state.actors.luvie=="f:-3:0","approach walks onto original handle support before committing hold")
	_check(app.view.get_actor_body("luvie").position.distance_to(adjacent)>.5,"approach changes physical position instead of teleporting the drawing")
	world = LeverWorld.new("1-4")
	world.state.flags=["hold"];world.state.active="buddy";world.state.follow=true
	world.state.actors.buddy="f:-3:0";world.state.actors.luvie="f:-4:0"
	_check(world.move("f:-3:-1").ok and not world.flag("hold"),"legacy followed hero also releases when it actually moves")
	# Replay the original cooperative puzzle through the application and real
	# physics, rather than replacing its fixture with this implementation.
	app.repository.data.mainline.runs.erase("1-4")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if str(fixture.name)=="authored/1-4": await _replay("1-4",fixture.steps,fixture.initial.snapshot)
	print(JSON.stringify({"suite":"native-heavy-lever","checks":checks,"passed":failures.is_empty(),"failures":failures,"routes":routes,"samples":samples,"scope":"same-tile physical release, occupancy rollback, explicit release, switch, undo, old permanent state and original 1-4 route"}))
	app.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
