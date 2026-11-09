extends SceneTree
const Session = preload("res://application/game_session.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Movement = preload("res://application/native_movement.gd")
const Router = preload("res://application/input_router.gd")
const Command = preload("res://contracts/game_command.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var session: RefCounted
var movement: RefCounted
var router: RefCounted
var maximum_floor_error := 0.0
var floor_samples := 0
var worst_contact: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _setup(id: String) -> void:
	if stage != null:
		stage.queue_free()
		await process_frame
	session = Session.new(id)
	stage = Stage.new()
	root.add_child(stage)
	stage.set_world(session.world)
	router = Router.new()
	movement = Movement.new()
	movement.setup(session, stage, router)
	await physics_frame
	await physics_frame

func _frames(count: int) -> void:
	for unused in range(count):
		await physics_frame
		movement.tick(1.0 / 60.0)
		for who: String in ["luvie", "buddy"]:
			var body: CharacterBody3D = stage.get_actor_body(who)
			var height: float = stage.support_height(body.position, str(session.world.state.actors[who]), who)
			var contact_error := absf(body.position.y - height)
			if contact_error > maximum_floor_error:
				worst_contact = {"actor": who, "position": str(body.position), "support": session.world.state.actors[who], "height": height, "onFloor": body.is_on_floor()}
			maximum_floor_error = maxf(maximum_floor_error, contact_error)
			floor_samples += 1

func _key(code: int, down: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = down
	router.handle_key(key)

func _action(id: String) -> void:
	movement.stop()
	var result: RefCounted = session.apply(Command.interact(id))
	_check(result.accepted, "prepare test action " + id)
	stage.refresh_world(session.world, true)
	movement.capture()
	await _frames(3)

func _run() -> void:
	await _setup("1-1")
	var hero: CharacterBody3D = stage.get_actor_body("luvie")
	_key(KEY_D, true)
	await _frames(50)
	_key(KEY_D, false)
	await _frames(2)
	_check(session.world.state.actors.luvie == "f:0:0", "unplanted road cannot be crossed")
	_check(hero.position.x <= 0.325, "exterior edge guarded by character radius")
	var stopped := hero.position
	await _frames(8)
	_check(hero.position.distance_to(stopped) < 0.003, "release stops immediately without cell-center drift")
	_key(KEY_D, true)
	_key(KEY_W, true)
	await _frames(36)
	_key(KEY_D, false)
	_key(KEY_W, false)
	await _frames(3)
	_check(hero.position.x <= 0.325 and hero.position.z >= -1.325, "diagonal input cannot cut across missing cells or descend an exterior edge")
	_check(session.world.point_for(str(session.world.state.actors.luvie)).h == 0, "diagonal input cannot jump to the high terrace")
	await _action("grow:root:right")
	movement.request_path(session.world.path_to("f:4:0"))
	await _frames(140)
	_check(session.world.state.actors.luvie == "f:4:0", "native body climbs the grown route and first ramp")
	_check(Vector2(hero.position.x - 4, hero.position.z).length() < 0.09, "click movement reaches requested support center")
	_key(KEY_W, true)
	await _frames(7)
	_key(KEY_W, false)
	await _frames(2)
	var mid_slope := hero.position
	_check(mid_slope.z < -0.22 and mid_slope.z > -0.5, "walking may stop partway up a ramp without forced step completion")
	await _frames(6)
	_check(Vector2(hero.position.x - mid_slope.x, hero.position.z - mid_slope.z).length() < 0.01, "ramp stop remains steady without sliding or recentering")
	_key(KEY_S, true)
	await _frames(7)
	_key(KEY_S, false)
	await _frames(2)
	_check(hero.position.z > mid_slope.z + 0.15, "direction can reverse midway through a ramp")
	movement.request_path(session.world.path_to("f:4:-1"))
	await _frames(45)
	_check(session.world.state.actors.luvie == "f:4:-1", "native body climbs second high terrace")
	movement.request_path(session.world.path_to("f:4:0"))
	await _frames(45)
	_check(session.world.state.actors.luvie == "f:4:0", "slope can be reversed and descended")
	_check(session.world.together(), "partner follows through actual legal supports")
	var recorded: Dictionary = session.world.snapshot()
	var pose_before := hero.position
	var normalized: Dictionary = session.world.normalize_saved(recorded)
	_check(normalized.ok, "continuous pose can be saved and normalized after slopes")
	var clone := Session.new("1-1", recorded)
	movement.setup(clone, stage, router)
	_check(hero.position.distance_to(pose_before) < 0.03, "reload restores local pose without recentering")
	var ids := ["1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4", "cloud-1", "cloud-2", "cloud-3"]
	for id: String in ids:
		await _setup(id)
		var current := str(session.world.state.actors.luvie)
		var neighbors: Array = session.world.neighbors(current, "luvie")
		if neighbors.is_empty():
			continue
		var target := str(neighbors[0].id)
		movement.request_path([target])
		await _frames(60)
		_check(session.world.state.actors.luvie == target, id + " uses shared physical motor on a legal edge")
		_check(session.world.normalize_saved(session.world.snapshot()).ok, id + " native pose is saveable")
	_check(maximum_floor_error < 0.2, "physical foot remains on the authored support surface (max %.4f)" % maximum_floor_error)
	print("Native floor samples: %d, maximum contact error %.5f" % [floor_samples, maximum_floor_error])
	if stage != null:
		stage.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS native movement: %d checks" % checks)
		quit(0)
	else:
		print("FAIL native movement: %d failures / %d checks" % [failures.size(), checks])
		quit(1)
