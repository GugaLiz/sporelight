class_name GardenNativeMovement
extends RefCounted
## A single physical executor for keyboard, click paths and partner following.
## Rule support IDs change only after an actual, approved boundary crossing.

signal support_changed(who: String, result: RefCounted)
signal blocked(message: String)

const SPEED := 3.25
const FOLLOW_SPEED := 3.45
const GRAVITY := 20.0
const EDGE_LIMIT := 0.495
const CLOSED_LIMIT := 0.32
const ARRIVE_DISTANCE := 0.055
const LANE_ALIGN_SPEED := 2.6
const LANDING_RELEASE_EPSILON := 0.002
const ACTORS := ["luvie", "buddy"]

var session: RefCounted
var stage: Node2D
var router: RefCounted
var click_path: Array = []
var rejoining := false
var suspended := false
var rolling := false
var _walking_group := false
var _last_facing := {"luvie": "front", "buddy": "front"}
var _moving := {"luvie": false, "buddy": false}
var _mechanism_origins: Dictionary = {}
var _mechanism_from: Dictionary = {}
var _mechanism_to: Dictionary = {}
var _mechanism_before: Dictionary = {}
var _mechanism_after: Dictionary = {}
var _block_delay := 0.0

func setup(value: RefCounted, view: Node2D, input: RefCounted) -> void:
	session = value
	stage = view
	router = input
	suspended = false
	rolling = false
	restore()

func restore() -> void:
	click_path.clear()
	rejoining = false
	_walking_group = false
	_mechanism_origins.clear()
	_mechanism_from.clear()
	_mechanism_to.clear()
	_mechanism_before.clear()
	_mechanism_after.clear()
	_moving = {"luvie": false, "buddy": false}
	if session == null or stage == null:
		return
	if stage.has_method("reset_actor_actions"):
		stage.reset_actor_actions()
	stage.refresh_world(session.world, true)
	var poses: Dictionary = session.world.state.get("runtime", {}).get("poses", {})
	for who: String in ACTORS:
		var body: CharacterBody3D = stage.get_actor_body(who)
		var tile: Dictionary = session.world.point_for(str(session.world.state.actors[who]))
		if body == null or tile.is_empty():
			continue
		var center: Vector3 = stage.tile_position(tile)
		var pose: Dictionary = poses.get(who, {})
		var offset := Vector3.ZERO
		if pose.is_empty() and who == "buddy" and str(session.world.state.actors.luvie) == str(tile.id):
			# A real local stance on the same legal support, not a drawn offset.
			offset = Vector3(-0.23, 0, 0.2)
		if pose.get("support", "") == str(tile.id) and pose.get("offset") is Array and pose.offset.size() == 3:
			offset = Vector3(float(pose.offset[0]), float(pose.offset[1]), float(pose.offset[2]))
			offset.x = clampf(offset.x, -0.48, 0.48)
			offset.z = clampf(offset.z, -0.48, 0.48)
			_last_facing[who] = str(pose.get("facing", "front"))
		body.position = stage.physical_position(stage.logical_position(center) + offset)
		var safe_horizontal := _restore_volume_position(who, tile, Vector2(body.position.x, body.position.z))
		body.position.x = safe_horizontal.x
		body.position.z = safe_horizontal.y
		var surface_y: float = stage.support_height(body.position, str(tile.id), who)
		if pose.is_empty() or body.position.y < surface_y - 0.02 or body.position.y > surface_y + 0.25:
			body.position.y = surface_y + 0.018
		body.velocity = Vector3.ZERO
		body.floor_snap_length = 0.4
		body.floor_max_angle = deg_to_rad(56.0)
		body.floor_constant_speed = true
		body.floor_stop_on_slope = true
		body.platform_floor_layers = 0
		stage.update_actor_visual(who, Vector3.ZERO, str(_last_facing[who]), "")
		if stage.has_method("set_actor_mode"):
			stage.set_actor_mode(who, rolling and who == session.world.actor())
	capture()

func stop(clear_route: bool = true) -> void:
	if clear_route:
		click_path.clear()
		rejoining = false
	for who: String in ACTORS:
		var body: CharacterBody3D = stage.get_actor_body(who)
		if body != null:
			body.velocity = Vector3.ZERO
			_moving[who] = false
			stage.update_actor_visual(who, Vector3.ZERO, str(_last_facing[who]), "")
	_walking_group = false
	capture()

func is_moving() -> bool:
	return not click_path.is_empty() or bool(_moving.luvie) or bool(_moving.buddy) or rejoining

func is_stable() -> bool:
	return _mechanism_origins.is_empty()

func request_path(path: Array) -> void:
	click_path = path.duplicate()
	rejoining = false

func nudge(direction: String) -> void:
	var p: Dictionary = session.world.point()
	var offset: Vector2i = router.OFFSETS.get(direction, Vector2i.ZERO)
	for candidate: Dictionary in session.world.neighbors(str(p.id)):
		if int(candidate.x - p.x) == offset.x and int(candidate.z - p.z) == offset.y:
			request_path([str(candidate.id)])
			return
	_notify_blocked("这里还没有接通的道路。")

func tick(delta: float, enabled: bool = true) -> void:
	if session == null or stage == null:
		return
	_block_delay = maxf(0.0, _block_delay - delta)
	if not enabled or suspended or not _mechanism_origins.is_empty() or bool(session.world.state.playing):
		for who: String in ACTORS:
			var body: CharacterBody3D = stage.get_actor_body(who)
			if body != null:
				body.velocity = Vector3.ZERO
			_moving[who] = false
		return
	var active: String = session.world.actor()
	var intent: Vector2 = router.movement_vector()
	if intent.length_squared() > 0.0:
		click_path.clear()
	var active_body: CharacterBody3D = stage.get_actor_body(active)
	if intent.is_zero_approx() and not click_path.is_empty():
		intent = _route_intent(active, active_body)
	var moved_active := _move_actor(active, intent, delta)
	var other := "buddy" if active == "luvie" else "luvie"
	var follower_intent := Vector2.ZERO
	var other_body: CharacterBody3D = stage.get_actor_body(other)
	if other_body != null and active_body != null and (bool(session.world.state.follow) or rejoining):
		var distance := Vector2(other_body.position.x - active_body.position.x, other_body.position.z - active_body.position.z).length()
		var actor_tile: String = str(session.world.state.actors[active])
		var other_tile: String = str(session.world.state.actors[other])
		var actor_center: Vector3 = stage.tile_position(session.world.point_for(actor_tile))
		var rest := Vector2(clampf(active_body.position.x - 0.23, actor_center.x - 0.27, actor_center.x + 0.27), clampf(active_body.position.z + 0.2, actor_center.z - 0.27, actor_center.z + 0.27))
		rest = _restore_volume_position(other, session.world.point_for(actor_tile), rest)
		var rest_distance := rest.distance_to(Vector2(other_body.position.x, other_body.position.z))
		var settling := not moved_active or rejoining
		if distance > (0.5 if rejoining else 0.78) or not session.world.together() or (settling and (actor_tile != other_tile or rest_distance > 0.06)):
			var path: Array = session.world.path_to(actor_tile, other)
			if not path.is_empty():
				var destination: Dictionary = session.world.point_for(str(path[0]))
				var target: Vector3 = stage.tile_position(destination)
				if str(destination.id) == actor_tile and settling:
					target.x = rest.x
					target.z = rest.y
				follower_intent = Vector2(target.x - other_body.position.x, target.z - other_body.position.z).normalized()
			elif actor_tile == other_tile and rest_distance > 0.06:
				follower_intent = (rest - Vector2(other_body.position.x, other_body.position.z)).normalized()
		if rejoining and actor_tile == other_tile and rest_distance < 0.08:
			rejoining = false
	var moved_other := _move_actor(other, follower_intent, delta, true)
	if not moved_active and not moved_other and intent.is_zero_approx() and follower_intent.is_zero_approx():
		_walking_group = false
	capture()

func _route_intent(who: String, body: CharacterBody3D) -> Vector2:
	while not click_path.is_empty():
		var id := str(click_path[0])
		var tile: Dictionary = session.world.point_for(id)
		if tile.is_empty():
			click_path.clear()
			return Vector2.ZERO
		var target: Vector3 = stage.tile_position(tile)
		var difference := Vector2(target.x - body.position.x, target.z - body.position.z)
		if difference.length() < ARRIVE_DISTANCE:
			click_path.pop_front()
			continue
		# Click paths center their waypoints; direct keyboard movement never does.
		if str(session.world.state.actors[who]) != id:
			var valid := false
			for candidate: Dictionary in session.world.neighbors(str(session.world.state.actors[who]), who):
				if str(candidate.id) == id:
					valid = true
			if not valid:
				click_path.clear()
				return Vector2.ZERO
		return difference.normalized()
	return Vector2.ZERO

func _move_actor(who: String, intent: Vector2, delta: float, following: bool = false) -> bool:
	var body: CharacterBody3D = stage.get_actor_body(who)
	if body == null:
		return false
	var current_id := str(session.world.state.actors[who])
	var current: Dictionary = session.world.point_for(current_id)
	if current.is_empty():
		return false
	var center: Vector3 = stage.tile_position(current)
	var speed := FOLLOW_SPEED if following else SPEED
	if rolling and not following:
		speed *= 1.15
	speed *= stage.stair_pace(body.position, intent)
	var planned := Vector2(body.position.x, body.position.z) + intent * speed * delta
	var allowed: Array = session.world.neighbors(current_id, who)
	var guard := _guard(planned, center, allowed)
	var target: Vector2 = _guard_traversal_volume(who, current, Vector2(body.position.x, body.position.z), guard.position, delta)
	var actual_intent := (target - Vector2(body.position.x, body.position.z)) / maxf(0.001, delta)
	actual_intent = actual_intent.limit_length(speed)
	if actual_intent.length_squared() > 0.0001 and not _walking_group:
		session.world.record_checkpoint()
		_walking_group = true
	body.velocity.x = actual_intent.x
	body.velocity.z = actual_intent.y
	body.velocity.y = -0.8 if body.is_on_floor() else maxf(-12.0, body.velocity.y - GRAVITY * delta)
	var previous := body.position
	body.move_and_slide()
	if stage.has_presentation_feature("physical_stair_steps"):
		_try_stair_step(body, previous, actual_intent * delta, current, allowed)
	# All unsupported and closed edges are guarded before the physical sweep.
	# Clamp tiny solver drift at an exterior boundary without recentering actors.
	var after_guard := _guard(Vector2(body.position.x, body.position.z), center, allowed)
	var supported: Vector2 = _guard_traversal_volume(who, current, Vector2(previous.x, previous.z), after_guard.position, 0.0)
	body.position.x = supported.x
	body.position.z = supported.y
	# Descending or turning away from a ramp can briefly lose its floor normal.
	# Ask the native capsule sweep to regain the nearby support instead of
	# waiting for gravity or assigning the body's Y from a sampled height.
	body.apply_floor_snap()
	var destination := _crossed_support(who, current, body.position, allowed)
	if not destination.is_empty() and destination != current_id:
		capture()
		var command: RefCounted = GardenCommand.move_actor(who, destination)
		var result: RefCounted = session.prepare(command)
		if result.accepted and not can_change_to(result.after):
			result.accepted = false
			result.message = "伙伴还在跨过这段路，先等它站稳。"
		if result.accepted:
			result = session.commit(result)
		if result.accepted:
			capture()
			support_changed.emit(who, result)
		else:
			body.position = previous
			body.velocity = Vector3.ZERO
			click_path.clear()
			_notify_blocked(str(result.message))
	# A floor can take one physics frame to enter after a fresh mesh rebuild.
	# Recover only on the same approved support, never to a nearby other layer.
	var floor_height: float = stage.support_height(body.position, str(session.world.state.actors[who]), who)
	if body.position.y < floor_height - 0.12 or body.position.y > floor_height + 0.55:
		body.position.y = floor_height + 0.018
		body.velocity.y = 0.0
	var displacement := body.position - previous
	_moving[who] = Vector2(displacement.x, displacement.z).length_squared() > 0.000001
	if _moving[who]:
		_last_facing[who] = _facing(Vector2(displacement.x, displacement.z))
	stage.update_actor_visual(who, Vector3(displacement.x, 0, displacement.z) / maxf(delta, 0.001), str(_last_facing[who]), "")
	if not intent.is_zero_approx() and Vector2(displacement.x, displacement.z).length() < 0.001 and not following:
		_notify_blocked("这边还没有可走的连接。")
	return bool(_moving[who])

func _guard(planned: Vector2, center: Vector3, allowed: Array) -> Dictionary:
	var logical: Vector3 = stage.logical_position(Vector3(planned.x, 0, planned.y))
	planned = Vector2(logical.x, logical.z)
	center = stage.logical_position(center)
	var result := planned
	var open_x := false
	var open_z := false
	var x_sign := signf(planned.x - center.x)
	var z_sign := signf(planned.y - center.z)
	for tile: Dictionary in allowed:
		if int(tile.x) == int(round(center.x)) + int(x_sign) and int(tile.z) == int(round(center.z)):
			open_x = true
		if int(tile.z) == int(round(center.z)) + int(z_sign) and int(tile.x) == int(round(center.x)):
			open_z = true
	result.x = clampf(result.x, center.x - (EDGE_LIMIT if open_x and x_sign < 0 else CLOSED_LIMIT), center.x + (EDGE_LIMIT if open_x and x_sign > 0 else CLOSED_LIMIT))
	result.y = clampf(result.y, center.z - (EDGE_LIMIT if open_z and z_sign < 0 else CLOSED_LIMIT), center.z + (EDGE_LIMIT if open_z and z_sign > 0 else CLOSED_LIMIT))
	# Permit one boundary crossing per physical step; missing diagonal cells
	# cannot be reached by cutting a corner between two approved neighbors.
	if open_x and absf(planned.x - center.x) >= 0.49 and absf(planned.x - center.x) >= absf(planned.y - center.z):
		result.x = planned.x
		result.y = clampf(result.y, center.z - CLOSED_LIMIT, center.z + CLOSED_LIMIT)
	elif open_z and absf(planned.y - center.z) >= 0.49:
		result.y = planned.y
		result.x = clampf(result.x, center.x - CLOSED_LIMIT, center.x + CLOSED_LIMIT)
	var physical: Vector3 = stage.physical_position(Vector3(result.x, 0, result.y))
	return {"position": Vector2(physical.x, physical.z)}


func _traversal_profiles(current: Dictionary) -> Array:
	if stage.has_method("traversal_profiles"):
		return stage.traversal_profiles(str(current.id))
	var profiles: Array = []
	if not stage.has_method("traversal_profile"):
		return profiles
	# The geometry of a low arch still exists for the larger actor. Geometric
	# shoulder clearance is separate from that actor's permission to cross it.
	for neighbor: Dictionary in session.world.neighbors(str(current.id), "buddy"):
		var profile: Dictionary = stage.traversal_profile(str(current.id), str(neighbor.id))
		if bool(profile.get("slope", false)):
			profiles.append(profile)
	return profiles

func _try_stair_step(body: CharacterBody3D, before: Vector3, horizontal: Vector2, current: Dictionary, allowed: Array) -> void:
	if horizontal.length_squared() < 0.000001: return
	var achieved := Vector2(body.position.x - before.x, body.position.z - before.z)
	if achieved.dot(horizontal.normalized()) >= horizontal.length() * 0.90: return
	var target := before + Vector3(horizontal.x, 0, horizontal.y)
	var logical_target: Vector3 = stage.logical_position(target)
	var support: Dictionary = {}
	for tile: Dictionary in [current] + allowed:
		if absf(logical_target.x - float(tile.x)) <= 0.50001 and absf(logical_target.z - float(tile.z)) <= 0.50001:
			support = tile
			break
	if support.is_empty(): return
	var floor_y: float = stage.support_height(target, str(support.id))
	if floor_y > before.y + 0.18 or floor_y < before.y - 0.20: return
	# Three full-capsule sweeps: headroom, remaining forward motion, landing.
	# The candidate is already restricted to a currently legal rule neighbor.
	var raised := body.global_transform
	var lift := Vector3.UP * 0.18
	if body.test_move(raised, lift): return
	raised.origin += lift
	var remaining := Vector3(target.x - body.position.x, 0, target.z - body.position.z)
	if body.test_move(raised, remaining): return
	raised.origin += remaining
	var landing := KinematicCollision3D.new()
	if not body.test_move(raised, Vector3.DOWN * 0.24, landing): return
	if landing.get_normal().y < cos(body.floor_max_angle): return
	var settled := raised.origin + landing.get_travel()
	if settled.y <= body.position.y + 0.001 or settled.y > before.y + 0.185: return
	body.global_position = settled
	body.velocity.y = 0.0

func _guard_traversal_volume(_who: String, current: Dictionary, actual: Vector2, candidate: Vector2, delta: float) -> Vector2:
	var center := Vector2(float(current.x), float(current.z))
	var result := candidate
	for profile: Dictionary in _traversal_profiles(current):
		if not bool(profile.get("slope", false)):
			continue
		var axis: Vector2 = profile.get("axis", Vector2.ZERO)
		var lateral := Vector2(-axis.y, axis.x)
		var entry := float(profile.get("entry_distance", 0.2))
		var clearance := maxf(0.04, float(profile.get("center_clearance", 0.14)))
		var old_along := (actual - center).dot(axis)
		var old_across := (actual - center).dot(lateral)
		var along := (result - center).dot(axis)
		var across := (result - center).dot(lateral)
		if along <= entry + LANDING_RELEASE_EPSILON:
			continue
		if absf(old_across) <= clearance + 0.0001:
			# Once on a slope, the entire capsule stays inside the authored lane.
			var requested_across := across - old_across
			var requested_along := along - old_along
			if delta > 0.0 and absf(across) > clearance and absf(requested_across) > absf(requested_along) * 1.15 + 0.0001:
				# A deliberate turn must return through the real flat landing.
				# Merely clamping the transverse component would lock an actor
				# forever on the lane's side when a key has no backward component.
				along = minf(along, move_toward(old_along, entry, LANE_ALIGN_SPEED * delta))
			across = clampf(across, -clearance, clearance)
		elif absf(across) > clearance:
			# An off-center approach waits on the flat landing and aligns by
			# ordinary horizontal velocity. No root-position or Y teleport.
			along = minf(along, maxf(entry, old_along))
			if delta > 0.0:
				across = move_toward(old_across, clampf(old_across, -clearance, clearance), LANE_ALIGN_SPEED * delta)
			else:
				across = old_across
		result = center + axis * along + lateral * across
	return result

func _restore_volume_position(_who: String, current: Dictionary, at: Vector2) -> Vector2:
	var center := Vector2(float(current.x), float(current.z))
	var result := at
	for profile: Dictionary in _traversal_profiles(current):
		if not bool(profile.get("slope", false)):
			continue
		var axis: Vector2 = profile.get("axis", Vector2.ZERO)
		var lateral := Vector2(-axis.y, axis.x)
		var entry := float(profile.get("entry_distance", 0.2))
		var clearance := float(profile.get("center_clearance", 0.14))
		var along := (result - center).dot(axis)
		var across := (result - center).dot(lateral)
		if along <= entry or absf(across) <= clearance:
			continue
		# Legacy saves can predate volume clearance. Normalize only within the
		# same legal support during load, never to a different island or layer.
		if along - entry <= absf(across) - clearance:
			along = entry
		else:
			across = clampf(across, -clearance, clearance)
		result = center + axis * along + lateral * across
	return result

func _crossed_support(_who: String, current: Dictionary, position: Vector3, allowed: Array) -> String:
	position = stage.logical_position(position)
	for tile: Dictionary in allowed:
		var dx := float(tile.x) - float(current.x)
		var dz := float(tile.z) - float(current.z)
		var boundary := Vector2(float(current.x) + dx * 0.5, float(current.z) + dz * 0.5)
		var relative := Vector2(position.x, position.z) - boundary
		if relative.dot(Vector2(dx, dz)) > 0.002:
			return str(tile.id)
	return ""

func _facing(direction: Vector2) -> String:
	# Height never changes facing. XZ projection matches the fixed camera.
	var screen := Vector2(direction.x - direction.y, (direction.x + direction.y) * 0.5)
	if absf(screen.y) > absf(screen.x) * 0.8:
		return "back" if screen.y < 0.0 else "front"
	return "right" if screen.x > 0.0 else "left"

func capture() -> Dictionary:
	if session == null or stage == null:
		return {}
	var poses := {}
	for who: String in ACTORS:
		var body: CharacterBody3D = stage.get_actor_body(who)
		var id := str(session.world.state.actors[who])
		var tile: Dictionary = session.world.point_for(id)
		if body == null or tile.is_empty():
			continue
		var offset: Vector3 = stage.logical_position(body.position) - stage.logical_position(stage.tile_position(tile))
		poses[who] = {"support": id, "offset": [snappedf(offset.x, 0.0001), snappedf(offset.y, 0.0001), snappedf(offset.z, 0.0001)], "facing": str(_last_facing[who])}
	session.world.state["runtime"] = {"version": 1, "poses": poses}
	return session.world.state.runtime

func can_change_to(after: Dictionary) -> bool:
	var future: RefCounted = session.world.fork(after)
	var future_tiles: Array = future.tiles()
	for who: String in ACTORS:
		var body: CharacterBody3D = stage.get_actor_body(who)
		if body == null:
			continue
		var current_id := str(session.world.state.actors[who])
		var current: Dictionary = session.world.point_for(current_id)
		if current.is_empty():
			return false
		var center: Vector3 = stage.logical_position(stage.tile_position(current))
		var logical_body: Vector3 = stage.logical_position(body.position)
		var future_edges: Array = future.neighbors(current_id, who, future_tiles)
		for tile: Dictionary in session.world.neighbors(current_id, who):
			var dx := float(tile.x) - float(current.x)
			var dz := float(tile.z) - float(current.z)
			var projection := Vector2(logical_body.x - center.x, logical_body.z - center.z).dot(Vector2(dx, dz))
			if projection < 0.31:
				continue
			var still_present := false
			for remaining: Dictionary in future_edges:
				if str(remaining.id) == str(tile.id):
					still_present = true
					break
			if not still_present:
				return false
	return true

func begin_mechanism(before: Dictionary, after: Dictionary) -> void:
	stop()
	_mechanism_origins.clear()
	_mechanism_before = before
	_mechanism_after = after
	var first: RefCounted = session.world.fork(before)
	var last: RefCounted = session.world.fork(after)
	for who: String in ACTORS:
		var body: CharacterBody3D = stage.get_actor_body(who)
		if body == null:
			continue
		_mechanism_origins[who] = body.position
		_mechanism_from[who] = stage.tile_position(first.point_for(str(before.actors[who])))
		_mechanism_to[who] = stage.tile_position(last.point_for(str(after.actors[who])))

func advance_mechanism(progress: float) -> void:
	var eased := progress * progress * (3.0 - 2.0 * progress)
	for who: String in _mechanism_origins:
		var body: CharacterBody3D = stage.get_actor_body(who)
		if body != null:
			var id := str(_mechanism_before.actors[who])
			var offset: Vector3 = _mechanism_origins[who] - _mechanism_from[who]
			var support_position: Vector3 = _mechanism_from[who].lerp(_mechanism_to[who], eased)
			if id == str(_mechanism_after.actors[who]) and stage.has_method("sample_tile_position"):
				support_position = stage.sample_tile_position(_mechanism_before, _mechanism_after, id, eased)
			for module: Dictionary in session.world.level.get("modules", []):
				if module.get("kind", "") != "rotate" or not id.begins_with("m:" + str(module.id) + ":"):
					continue
				var delta_turn := posmod(int(_mechanism_after.turns.get(module.id, 0)) - int(_mechanism_before.turns.get(module.id, 0)), 4)
				var signed_turn := delta_turn if delta_turn <= 2 else delta_turn - 4
				offset = offset.rotated(Vector3.UP, -float(signed_turn) * PI / 2.0 * eased)
			body.position = support_position + offset
			body.velocity = Vector3.ZERO

func finish_mechanism() -> void:
	_mechanism_origins.clear()
	_mechanism_from.clear()
	_mechanism_to.clear()
	_mechanism_before.clear()
	_mechanism_after.clear()
	stage.refresh_world(session.world, true)
	capture()

func qa_state() -> Dictionary:
	var result := {"moving": is_moving(), "stable": is_stable(), "path": click_path.duplicate(), "actors": {}}
	for who: String in ACTORS:
		var body: CharacterBody3D = stage.get_actor_body(who)
		if body == null:
			continue
		var id := str(session.world.state.actors[who])
		result.actors[who] = {"support": id, "position": [body.position.x, body.position.y, body.position.z], "velocity": [body.velocity.x, body.velocity.y, body.velocity.z], "onFloor": body.is_on_floor(), "floorHeight": stage.support_height(body.position, id, who), "facing": _last_facing[who]}
	return result

func _notify_blocked(message: String) -> void:
	if _block_delay <= 0.0 and not message.is_empty():
		blocked.emit(message)
		_block_delay = 1.4
