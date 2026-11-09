extends SceneTree
const Session = preload("res://application/game_session.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Movement = preload("res://application/native_movement.gd")
const Router = preload("res://application/input_router.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var session: RefCounted
var movement: RefCounted
var router: RefCounted
var base: Dictionary = {}
var before_corner: Dictionary = {}
var maximum_body_gap := 0.0
var maximum_visual_error := 0.0
var maximum_step := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _setup(lateral: float, saved: Dictionary = {}) -> void:
	if stage != null:
		stage.queue_free()
		await process_frame
	session = Session.new("1-2", base if saved.is_empty() else saved)
	stage = Stage.new()
	root.add_child(stage)
	stage.set_world(session.world)
	router = Router.new()
	movement = Movement.new()
	movement.setup(session, stage, router)
	var body: CharacterBody3D = stage.get_actor_body("luvie")
	body.position = stage.tile_position(session.world.point()) + Vector3(0, 0.018, lateral)
	movement.capture()
	await physics_frame
	await physics_frame

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	router.handle_key(event)

func _tick() -> void:
	await physics_frame
	var body: CharacterBody3D = stage.get_actor_body("luvie")
	var before := body.position
	movement.tick(1.0 / 60.0)
	maximum_step = maxf(maximum_step, Vector2(body.position.x - before.x, body.position.z - before.z).length())
	var floor_height: float = stage.support_height(body.position, str(session.world.state.actors.luvie), "luvie")
	maximum_body_gap = maxf(maximum_body_gap, absf(body.position.y - floor_height))
	var visual: Node3D = stage.actor_visual_root("luvie")
	maximum_visual_error = maxf(maximum_visual_error, absf(body.position.y + visual.position.y - floor_height))

func _run() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in fixtures.cases:
		if fixture.name == "authored/1-2":
			base = fixture.steps[8].snapshot
			before_corner = fixture.steps[7].snapshot
	for lateral: float in [0.1, -0.1, 0.14, -0.14, 0.25, -0.25]:
		await _setup(lateral)
		_key(KEY_D, true)
		var entered_while_unsafe := false
		for index in range(85):
			await _tick()
			var body: CharacterBody3D = stage.get_actor_body("luvie")
			if body.position.x > 3.205 and body.position.x < 3.79 and absf(body.position.z - 1.0) > 0.145:
				entered_while_unsafe = true
			if body.position.x > 3.95:
				break
		_key(KEY_D, false)
		await _tick()
		var body: CharacterBody3D = stage.get_actor_body("luvie")
		_check(session.world.state.actors.luvie == "f:4:1" and body.position.x > 3.9, "offset %.2f can cross the real ramp by continuous movement" % lateral)
		_check(not entered_while_unsafe, "offset %.2f stays inside capsule-safe slope volume" % lateral)
		_check(absf(body.position.z - 1.0) < 0.145, "offset %.2f is inside the physical lane after crossing" % lateral)
	# Reproduce the browser click->key corner: walk from the grown north road
	# into f:3:1, then press diagonally toward the east shoulder.
	await _setup(0, before_corner)
	var body: CharacterBody3D = stage.get_actor_body("luvie")
	movement.request_path(["f:3:1"])
	for index in range(45):
		await _tick()
		if session.world.state.actors.luvie == "f:3:1":
			break
	_check(session.world.state.actors.luvie == "f:3:1", "click route physically enters the corner before keyboard takes over")
	_key(KEY_D, true)
	_key(KEY_S, true)
	for index in range(35):
		await _tick()
	_key(KEY_D, false)
	_key(KEY_S, false)
	for index in range(8):
		await _tick()
	# Exact pose from the real browser failure: the actor is on the east
	# slope's northern safety edge and asks to turn north. It must walk back
	# through the landing, rather than remain locked by two profile clamps.
	await _setup(0)
	body = stage.get_actor_body("luvie")
	body.position = Vector3(3.48902654647827, 0.388920783996582, 0.860034167766571)
	var partner: CharacterBody3D = stage.get_actor_body("buddy")
	partner.position = Vector3(3.28693604469299, 0.155906915664673, 1.09874439239502)
	movement.capture()
	var before_turn := body.position
	_key(KEY_W, true)
	for index in range(85):
		await _tick()
		if session.world.state.actors.luvie == "g:root:3:0" and body.position.z < 0.2:
			break
	_key(KEY_W, false)
	await _tick()
	_check(session.world.state.actors.luvie == "g:root:3:0", "exact browser corner pose can turn north through the real landing")
	_check(body.position.x < before_turn.x - 0.2 and body.position.z < 0.3, "turning uses continuous backward and northward travel instead of a teleport")
	_check(maximum_body_gap < 0.15, "capsule never perches on a ramp shoulder (max %.4f)" % maximum_body_gap)
	_check(maximum_visual_error < 0.005, "visible foot remains on its own support")
	_check(maximum_step < 0.075, "alignment never jumps coordinates (max %.4f)" % maximum_step)
	var profiles: Array = stage.traversal_profiles("f:3:1")
	_check(not profiles.is_empty(), "volume profile comes from actual native surface geometry")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-volume-clearance", "passed": failures.is_empty(), "checks": checks, "maxBodySurfaceGap": maximum_body_gap, "maxVisualError": maximum_visual_error, "maxHorizontalStep": maximum_step, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
