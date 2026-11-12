extends "res://tests/native_movement_test.gd"
var maximum_penetration := 0.0
var maximum_contact_surface_error := 0.0
var maximum_visual_violation := 0.0
var maximum_shadow_error := 0.0
var maximum_clearance_violation := 0.0
var actual_contacts := 0
var authored_root_states := 0
var authored_root_stair_edges := 0

func _frames(count: int) -> void:
	for unused in range(count):
		await super._frames(1)
		for who: String in ["luvie", "buddy"]:
			var body: CharacterBody3D = stage.get_actor_body(who)
			var id := str(session.world.state.actors[who])
			var ground: float = stage.support_height(body.position, id)
			var clearance: float = stage.stair_capsule_clearance(body, id)
			maximum_clearance_violation = maxf(maximum_clearance_violation, body.position.y - ground - clearance)
			stage.update_actor_visual(who, body.velocity)
			var sole: float = stage.actor_visual_root(who).global_position.y
			maximum_visual_violation = maxf(maximum_visual_violation, maxf(ground - sole, sole - ground - 0.1625))
			maximum_shadow_error = maxf(maximum_shadow_error, absf(body.get_node("Shadow").global_position.y - ground - 0.012))
			var contact := KinematicCollision3D.new()
			if not body.test_move(body.global_transform, Vector3.DOWN * 0.4, contact, 0.001, true):
				_check(false, "capsule retains a real support below its current stance")
				continue
			actual_contacts += 1
			maximum_penetration = maxf(maximum_penetration, contact.get_depth())
			var collider: Node3D = contact.get_collider()
			if collider == null or not collider.get_parent().has_method("sample_height") or contact.get_normal().y < 0.1: continue
			var surface: Node3D = collider.get_parent()
			var point: Vector3 = contact.get_position()
			var error := INF
			# At an exact nose the touching tread can be either adjacent region.
			for dx: float in [-0.001, 0.0, 0.001]:
				for dz: float in [-0.001, 0.0, 0.001]:
					error = minf(error, absf(point.y - surface.sample_height(point + Vector3(dx, 0, dz))))
			maximum_contact_surface_error = maxf(maximum_contact_surface_error, error)

func _run() -> void:
	for who: String in ["luvie", "buddy"]:
		for offset: float in [-0.10, 0.10]:
			await _setup("1-3")
			session.world.state.turns.garden = 1
			session.world.state.active = who
			session.world.state.follow = false
			session.world.state.actors[who] = "m:garden:-2:0"
			session.world.state.actors["buddy" if who == "luvie" else "luvie"] = "m:garden:0:0"
			session.world.state.erase("runtime")
			stage.set_world(session.world)
			movement.restore()
			var body: CharacterBody3D = stage.get_actor_body(who)
			body.position.x += offset
			await _frames(3)
			_key(KEY_W, true)
			await _frames(9)
			_key(KEY_W, false)
			await _frames(4)
			var stopped := body.position
			_check(stopped.z < -2.20 and stopped.z > -2.75, who + " reaches an actual middle tread")
			await _frames(6)
			_check(Vector2(body.position.x, body.position.z).distance_to(Vector2(stopped.x, stopped.z)) < 0.01, who + " stops on a tread without horizontal drift")
			var ground: float = stage.support_height(body.position, str(session.world.state.actors[who]))
			stage.update_actor_visual(who, Vector3.ZERO)
			_check(absf(stage.actor_visual_root(who).global_position.y - ground) < 0.001, who + " stopped sole returns to the real tread")
			_key(KEY_S, true)
			await _frames(9)
			_key(KEY_S, false)
			await _frames(3)
			_check(body.position.z > stopped.z + 0.10, who + " reverses mid-flight")
			movement.request_path(["f:0:-3"])
			await _frames(65)
			_check(session.world.state.actors[who] == "f:0:-3", who + " climbs the full four-step flight")
			movement.request_path(["m:garden:-2:0"])
			await _frames(65)
			_check(session.world.state.actors[who] == "m:garden:-2:0", who + " descends the full four-step flight")
	await _test_departure_occupancy()
	_audit_root_stair_edges()
	_check(maximum_penetration < 0.004, "actual capsule contacts have no material penetration: " + str(maximum_penetration))
	_check(maximum_contact_surface_error < 0.004, "physical contact points lie on actual treads: " + str(maximum_contact_surface_error))
	_check(maximum_clearance_violation < 0.001, "capsule-centre clearance stays within one step plus its own radius")
	_check(maximum_visual_violation < 0.001 and maximum_shadow_error < 0.001, "visible soles and shadows remain attached to actual treads")
	print(JSON.stringify({"suite": "native-generic-stair-movement", "checks": checks, "maxCentreHeightDifference": maximum_floor_error, "maxPenetration": maximum_penetration, "maxContactSurfaceError": maximum_contact_surface_error, "actualContacts": actual_contacts, "maxVisualViolation": maximum_visual_violation, "maxShadowError": maximum_shadow_error, "authoredRootStates": authored_root_states, "authoredRootStairEdges": authored_root_stair_edges, "worstCentreDifference": worst_contact, "failures": failures, "passed": failures.is_empty()}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_departure_occupancy() -> void:
	await _setup("1-3")
	session.world.state.turns.garden = 1
	session.world.state.actors = {"luvie": "m:garden:0:0", "buddy": "m:garden:-2:0"}
	session.world.state.follow = false
	session.world.state.erase("runtime")
	stage.set_world(session.world)
	movement.restore()
	var companion: CharacterBody3D = stage.get_actor_body("buddy")
	var center: Vector3 = stage.tile_position(session.world.point_for("m:garden:-2:0"))
	var before: Dictionary = session.world.snapshot()
	var prepared: RefCounted = session.prepare(Command.interact("turn:garden"))
	_check(prepared.accepted, "real turn intent remains legal in the domain")
	for along: float in [0.20, 0.24, 0.29]:
		companion.position = center + Vector3(0, 0, -along)
		companion.position.y = stage.support_height(companion.position, "m:garden:-2:0") + 0.018
		_check(not movement.can_change_to(prepared.after), "capsule footprint blocks retracting the occupied external step at " + str(along))
	_check(session.world.snapshot() == before, "blocked departure leaves transaction and support state unchanged")
	companion.position = center + Vector3(0, 0.018, -0.10)
	_check(movement.can_change_to(prepared.after), "returning to the same module's flat landing allows the original turn")

func _audit_root_stair_edges() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if not str(entry.name) in ["authored/3-3", "authored/3-4"]: continue
		for step: Dictionary in entry.steps:
			var model := Session.new(str(entry.levelId), step.snapshot)
			var tiles: Array = model.world.tiles()
			authored_root_states += 1
			for tile: Dictionary in tiles:
				if not str(tile.id).begins_with("g:"): continue
				for neighbor: Dictionary in tiles:
					var distance := absf(float(tile.x) - float(neighbor.x)) + absf(float(tile.z) - float(neighbor.z))
					if is_equal_approx(distance, 1.0) and is_equal_approx(absf(float(tile.h) - float(neighbor.h)), 1.0): authored_root_stair_edges += 1
	_check(authored_root_states > 0, "audited real authored generic-root states for high-step retraction boundaries")
