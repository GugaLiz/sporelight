class_name GardenNativeMovement
extends RefCounted
## A single physical executor for keyboard, click paths and partner following.
## Rule support IDs change only after an actual, approved boundary crossing.

signal support_changed(who: String, result: RefCounted)
signal blocked(message: String)
signal interaction_changed(who: String, result: RefCounted)

const SPEED := 3.25
const FOLLOW_SPEED := 3.45
const GRAVITY := 20.0
const EDGE_LIMIT := 0.495
const CLOSED_LIMIT := 0.32
const ARRIVE_DISTANCE := 0.055
const LANE_ALIGN_SPEED := 2.6
const LANDING_RELEASE_EPSILON := 0.002
const ACTORS := ["luvie", "buddy"]
const GenericStairs = preload("res://presentation/native/generic_stair_geometry.gd")

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
var _query_active := false
var _query_world: RefCounted
var _query_revision := -1
var _query_tiles: Array = []
var _prop_paths: Dictionary = {}
var _prop_path_stamp: Array = []
var _prop_local_routes: Dictionary = {}
var _prop_edges: Dictionary = {}
var _prop_edge_steps: Dictionary = {}
var _local_target: Dictionary = {}
var _local_companions: Dictionary = {}

func _uses_prop_obstacles() -> bool:
	return stage.has_method("prop_obstacles_enabled") and bool(stage.prop_obstacles_enabled())

func _prop_waypoint(tile: Dictionary, who: String) -> Dictionary:
	if tile.is_empty(): return {}
	var preferred: Vector3 = stage.actor_rest_position(tile, who)
	return stage.prop_waypoint(tile, who, preferred)

func _prop_path(target: String, who: String) -> Dictionary:
	# Followers ask every frame, but search only when supports, items, or
	# terrain actually change. Failed routes are cached as well.
	var stamp: Array = [session.world, session.revision, int(stage.prop_obstacle_revision)]
	if stamp != _prop_path_stamp:
		_prop_paths.clear()
		_prop_edges.clear()
		_prop_path_stamp = stamp
	var start: String = str(session.world.state.actors[who])
	var key: String = who + "/" + start + "/" + target
	if _prop_paths.has(key): return _prop_paths[key]
	var result: Dictionary = {"found": false, "path": [], "requested": target, "approach": target}
	var first: Dictionary = _prop_waypoint(_point_for(start), who)
	var body: CharacterBody3D = stage.get_actor_body(who)
	if body != null and bool(stage.prop_physical_point_clear(body.position,who)): first={"point":body.position}
	var last: Dictionary = _prop_waypoint(_point_for(target), who)
	if not first.is_empty() and last.is_empty() and _is_core_request(target):
		# Repair already permits an adjacent support at the same rule height.
		# An occupied flowerbed means approach the stone, not enter its centre.
		var core: Dictionary = _point_for(target)
		var neighbors: Array = _neighbors(target, who)
		if stage.has_method("prop_core_approaches"):
			for preferred_id: String in stage.prop_core_approaches(target,who):
				for neighbor: Dictionary in neighbors:
					if str(neighbor.id)!=preferred_id or absf(float(neighbor.h)-float(core.h))>.1: continue
					var approach: Dictionary = _prop_path(preferred_id,who)
					if bool(approach.found):
						result={"found":true,"path":approach.path.duplicate(),"requested":target,"approach":preferred_id}
						_prop_paths[key]=result
						return result
		for neighbor: Dictionary in neighbors:
			if absf(float(neighbor.h)-float(core.h)) > .1: continue
			var approach: Dictionary = _prop_path(str(neighbor.id),who)
			if bool(approach.found) and (not bool(result.found) or approach.path.size() < result.path.size()):
				result = {"found":true,"path":approach.path.duplicate(),"requested":target,"approach":str(neighbor.id)}
		_prop_paths[key] = result
		return result
	if first.is_empty() or last.is_empty():
		_prop_paths[key] = result
		return result
	var queue: Array[String] = [start]
	var previous: Dictionary = {start: ""}
	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		if current == target:
			var path: Array = []
			var step: String = target
			while step != start:
				path.push_front(step)
				step = str(previous[step])
			result = {"found": true, "path": path, "requested": target, "approach": target}
			break
		for neighbor: Dictionary in _neighbors(current, who):
			var id: String = str(neighbor.id)
			if previous.has(id): continue
			var to: Dictionary = _prop_waypoint(neighbor, who)
			if to.is_empty(): continue
			var edge: Array = _prop_start_edge(_point_for(current),neighbor,who) if current==start else _prop_edge(_point_for(current),neighbor,who)
			if edge.is_empty(): continue
			previous[id] = current
			queue.append(id)
	_prop_paths[key] = result
	return result

func _is_core_request(id: String) -> bool:
	for mark: Dictionary in session.world.level.get("marks",[]):
		if str(mark.get("kind",""))=="core" and str(mark.get("tile",""))==id: return true
	return false

func _prop_edge(from: Dictionary, to: Dictionary, who: String) -> Array:
	var key: String = str(hash([session.world,session.revision,int(stage.prop_obstacle_revision),who,str(from.id),str(to.id)]))
	if not _prop_edges.has(key):
		_prop_edges[key] = stage.prop_edge_route(from,to,who)
	return _prop_edges[key]

func _prop_start_edge(from: Dictionary, to: Dictionary, who: String) -> Array:
	# A newly dropped base can split one logical cell into two physical regions.
	# Start from the actual stance instead of demanding a trip through the base
	# to its canonical waypoint. Continuous movement cannot change that region
	# without a support crossing or geometry revision, so this remains cached.
	var key: String = "start/"+str(hash([session.world,session.revision,int(stage.prop_obstacle_revision),who,str(from.id),str(to.id)]))
	if not _prop_edges.has(key):
		var body: CharacterBody3D = stage.get_actor_body(who)
		_prop_edges[key] = stage.prop_edge_route_from(from,to,who,body.position)
	return _prop_edges[key]

func _prop_step(who: String, body: CharacterBody3D, target: Vector3) -> Dictionary:
	if bool(stage.prop_segment_clear(body.position, target, who)): return {"point": target}
	# A manual stop may be away from the graph's safe waypoint. Reach that
	# same-cell waypoint before following an otherwise legal outgoing edge.
	var support: String = str(session.world.state.actors[who])
	var tile: Dictionary = _point_for(support)
	# A legal adjacent edge may need a turn before crossing its boundary.
	# The edge cache contains only paths inside those two original supports.
	var logical_target: Vector3 = stage.logical_position(target)
	for neighbor: Dictionary in _neighbors(support,who):
		if absf(logical_target.x-float(neighbor.x)) > EDGE_LIMIT or absf(logical_target.z-float(neighbor.z)) > EDGE_LIMIT: continue
		var key: Array = [session.world, session.revision, support, str(neighbor.id), int(stage.prop_obstacle_revision), target]
		var progress: Dictionary = _prop_edge_steps.get(who,{})
		if progress.is_empty() or progress.key != key:
			progress = {"key":key,"points":_prop_start_edge(tile,neighbor,who).duplicate()}
			_prop_edge_steps[who] = progress
		var points: Array = progress.points
		while not points.is_empty():
			var point: Vector3 = points[0]
			var onward: Vector3 = points[1] if points.size()>1 else target
			if Vector2(point.x-body.position.x,point.z-body.position.z).length()<ARRIVE_DISTANCE and bool(stage.prop_segment_clear(body.position,onward,who)):
				points.pop_front()
				continue
			if bool(stage.prop_segment_clear(body.position,point,who)): return {"point":point}
			break
		break
	var current: Dictionary = _prop_waypoint(tile, who)
	if current.is_empty() or Vector2(body.position.x-current.point.x,body.position.z-current.point.z).length() < .001: return {}
	if bool(stage.prop_segment_clear(body.position, current.point, who)): return current
	if not stage.has_method("prop_local_route"): return {}
	# Keep a small per-actor polyline cache. A dropped mirror can separate the
	# actual stance from this cell's graph waypoint without closing the cell.
	# Only changed geometry/intent or deviation from the cached segment needs
	# another local search; an unchanged failed search also remains cached.
	var key: Array = [session.world, support, int(stage.prop_obstacle_revision), target, current.point]
	var cached: Dictionary = _prop_local_routes.get(who, {})
	var position: Vector2 = Vector2(body.position.x, body.position.z)
	var rebuild: bool = cached.is_empty() or cached.key != key
	if not rebuild:
		var points: Array = cached.points
		while not points.is_empty():
			var first: Vector3 = points[0]
			var onward: Vector3 = points[1] if points.size()>1 else target
			if position.distance_to(Vector2(first.x, first.z)) >= ARRIVE_DISTANCE or not bool(stage.prop_segment_clear(body.position,onward,who)): break
			cached.anchor = points.pop_front()
		if points.is_empty():
			var origin: Vector3 = cached.origin
			rebuild = position.distance_to(Vector2(origin.x, origin.z)) > .14
		else:
			var next: Vector3 = points[0]
			var anchor: Vector3 = cached.anchor
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(position, Vector2(anchor.x, anchor.z), Vector2(next.x, next.z))
			rebuild = position.distance_to(closest) > .14 or not bool(stage.prop_segment_clear(body.position, next, who))
	if rebuild:
		var route: Array = stage.prop_local_route(tile, who, body.position, current.point)
		cached = {"key": key, "points": route.duplicate(), "origin": body.position, "anchor": body.position}
		_prop_local_routes[who] = cached
	var remaining: Array = cached.points
	while not remaining.is_empty():
		var next: Vector3 = remaining[0]
		var onward: Vector3 = remaining[1] if remaining.size()>1 else target
		if position.distance_to(Vector2(next.x, next.z)) < ARRIVE_DISTANCE and bool(stage.prop_segment_clear(body.position,onward,who)):
			cached.anchor = remaining.pop_front()
			continue
		var logical: Vector3 = stage.logical_position(next)
		if absf(logical.x - float(tile.x)) > EDGE_LIMIT or absf(logical.z - float(tile.z)) > EDGE_LIMIT or not bool(stage.prop_segment_clear(body.position, next, who)):
			remaining.clear()
			cached.origin = body.position
			return {}
		return {"point": next}
	return {}

func _restore_prop_position(who: String, tile: Dictionary, body: CharacterBody3D) -> Dictionary:
	# A valid physical contact can sit inside the planner's extra 2 cm route
	# margin. Preserve that saved pose; migrate only actual base penetration.
	if bool(stage.prop_physical_point_clear(body.position, who)): return {}
	var height: float = stage.support_height(body.position, str(tile.id), who)
	var preferred: Vector3 = Vector3(body.position.x, height, body.position.z)
	var same: Dictionary = stage.prop_waypoint(tile, who, preferred)
	if not same.is_empty(): return {"tile": tile, "point": same.point}
	if _is_core_request(str(tile.id)) and stage.has_method("prop_core_approaches"):
		for preferred_id: String in stage.prop_core_approaches(str(tile.id),who):
			for neighbor: Dictionary in _neighbors(str(tile.id),who):
				if str(neighbor.id)!=preferred_id or absf(stage.tile_position(neighbor).y-height)>.025: continue
				var safe: Dictionary = _prop_waypoint(neighbor,who)
				if not safe.is_empty(): return {"tile":neighbor,"point":safe.point}
	# An old save can place the centre in a fully occupied cell. Search its
	# original connected same-height graph, never a disconnected island or a
	# new elevation, and migrate only the affected actor's support/pose.
	var pending: Array[String] = [str(tile.id)]
	var seen: Dictionary = {str(tile.id): true}
	var cursor: int = 0
	var best: Dictionary = {}
	var best_distance: float = INF
	while cursor < pending.size():
		var id: String = pending[cursor]
		cursor += 1
		var candidate: Dictionary = _point_for(id)
		var at: Vector3 = stage.tile_position(candidate)
		if absf(at.y - height) > .025: continue
		var safe: Dictionary = _prop_waypoint(candidate, who)
		if not safe.is_empty():
			var distance: float = body.position.distance_squared_to(safe.point)
			if distance < best_distance:
				best_distance = distance
				best = {"tile": candidate, "point": safe.point}
		for neighbor: Dictionary in _neighbors(id, who):
			var neighbor_id: String = str(neighbor.id)
			if not seen.has(neighbor_id):
				seen[neighbor_id] = true
				pending.append(neighbor_id)
	return best

func _read_tiles() -> Array:
	# One derived board per read-only part of a physics tick. A committed
	# crossing can change bridges/occupancy, so revision changes rebuild it
	# before the follower or the next capture reads anything.
	if not _query_active: return session.world.tiles()
	if _query_world != session.world or _query_revision != session.revision or _query_tiles.is_empty():
		_query_world = session.world
		_query_revision = session.revision
		_query_tiles = session.world.tiles()
	return _query_tiles

func _point_for(id: String) -> Dictionary:
	return session.world.point_for(id, _read_tiles())

func _neighbors(id: String, who: String = "") -> Array:
	return session.world.neighbors(id, who, _read_tiles())

func setup(value: RefCounted, view: Node2D, input: RefCounted) -> void:
	session = value
	stage = view
	router = input
	suspended = false
	rolling = false
	restore()

func restore() -> void:
	_prop_local_routes.clear()
	_prop_edges.clear()
	_prop_edge_steps.clear()
	_local_target.clear()
	_local_companions.clear()
	_prop_paths.clear()
	_prop_path_stamp.clear()
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
		var tile: Dictionary = _point_for(str(session.world.state.actors[who]))
		if body == null or tile.is_empty():
			continue
		var center: Vector3 = stage.tile_position(tile)
		var pose: Dictionary = poses.get(who, {})
		var offset := Vector3.ZERO
		if pose.is_empty() and stage.has_method("actor_rest_position"):
			offset = stage.logical_position(stage.actor_rest_position(tile, who)) - stage.logical_position(center)
		if pose.is_empty() and offset.is_zero_approx() and who == "buddy" and str(session.world.state.actors.luvie) == str(tile.id):
			# A real local stance on the same legal support, not a drawn offset.
			offset = Vector3(-0.23, 0, 0.2)
		if pose.get("support", "") == str(tile.id) and pose.get("offset") is Array and pose.offset.size() == 3:
			offset = Vector3(float(pose.offset[0]), float(pose.offset[1]), float(pose.offset[2]))
			offset.x = clampf(offset.x, -0.48, 0.48)
			offset.z = clampf(offset.z, -0.48, 0.48)
			_last_facing[who] = str(pose.get("facing", "front"))
			# Completed memories made before physical repair stances stored the
			# exact old centre/default follower offset. Repair only those defaults;
			# ordinary continuous saved walking positions remain authoritative.
			var old_center := Vector2(offset.x,offset.z).length() < .001
			var old_follower := who == "buddy" and str(session.world.state.actors.luvie) == str(tile.id) and Vector2(offset.x,offset.z).distance_to(Vector2(-.23,.2)) < .001
			var instrument_stance := not preload("res://presentation/native/mechanism_props.gd").standing_offset(session.world,str(tile.id),who).is_zero_approx()
			if not instrument_stance and bool(session.world.state.get("completed", false)) and (old_center or old_follower) and stage.has_method("actor_rest_offset") and not stage.actor_rest_offset(tile,who).is_zero_approx():
				offset = stage.logical_position(stage.actor_rest_position(tile,who))-stage.logical_position(center)
		body.position = stage.physical_position(stage.logical_position(center) + offset)
		var safe_horizontal := _restore_volume_position(who, tile, Vector2(body.position.x, body.position.z))
		body.position.x = safe_horizontal.x
		body.position.z = safe_horizontal.y
		var surface_y: float = stage.support_height(body.position, str(tile.id), who)
		var contact_clearance: float = maxf(0.25, stage.stair_capsule_clearance(body, str(tile.id)) + 0.02)
		if pose.is_empty() or body.position.y < surface_y - 0.02 or body.position.y > surface_y + contact_clearance:
			body.position.y = surface_y + 0.018
		if _uses_prop_obstacles():
			var recovered: Dictionary = _restore_prop_position(who, tile, body)
			if not recovered.is_empty():
				session.world.state.actors[who] = str(recovered.tile.id)
				body.position = recovered.point + Vector3(0.0, .018, 0.0)
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
	_prop_local_routes.clear()
	_prop_edge_steps.clear()
	_local_target.clear()
	_local_companions.clear()
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
	return not _local_target.is_empty() or not _local_companions.is_empty() or not click_path.is_empty() or bool(_moving.luvie) or bool(_moving.buddy) or rejoining

func is_stable() -> bool:
	return _mechanism_origins.is_empty()

func request_path(path: Array) -> void:
	_prop_local_routes.clear()
	_prop_edge_steps.clear()
	_local_target.clear()
	_local_companions.clear()
	click_path = path.duplicate()
	rejoining = false
	if _uses_prop_obstacles() and not path.is_empty():
		var goal: String = str(path.back())
		var planned: Dictionary = _prop_path(goal, session.world.actor())
		click_path = planned.path.duplicate() if bool(planned.found) else []
		if bool(planned.found) and click_path.is_empty(): click_path = [str(planned.approach)]
		if not bool(planned.found): _notify_blocked("石基占住了这个落脚点，请选择旁边的空地。")

func request_local_target(point: Vector3, companions: Dictionary = {}) -> bool:
	stop()
	var who: String = session.world.actor()
	var primary: Dictionary = _validated_local_target(who, point)
	if primary.is_empty(): return false
	var prepared: Dictionary = {}
	for companion: String in companions:
		if companion == who or not companion in ACTORS or not companions[companion] is Vector3: return false
		var target: Dictionary = _validated_local_target(companion, companions[companion])
		if target.is_empty(): return false
		prepared[companion] = target
	_local_target = primary
	_local_companions = prepared
	return true

func _validated_local_target(who: String, point: Vector3) -> Dictionary:
	var body: CharacterBody3D = stage.get_actor_body(who)
	var id: String = str(session.world.state.actors[who])
	var tile: Dictionary = _point_for(id)
	if body == null or tile.is_empty(): return {}
	var logical: Vector3 = stage.logical_position(point)
	if absf(logical.x - float(tile.x)) > .48 or absf(logical.z - float(tile.z)) > .48: return {}
	var height: float = stage.support_height(point, id, who)
	if absf(point.y - height) > .025: return {}
	if _uses_prop_obstacles() and (not bool(stage.prop_point_clear(point, who)) or not bool(stage.prop_segment_clear(body.position, point, who))): return {}
	return {"point": point, "who": who, "support": id, "elapsed": 0.0, "stalled": 0.0, "distance": INF}

func _local_intent(who: String, body: CharacterBody3D, delta: float) -> Vector2:
	var target: Dictionary = _local_companions.get(who, _local_target)
	if target.is_empty(): return Vector2.ZERO
	if body == null or str(target.who) != who or str(target.support) != str(session.world.state.actors[who]):
		stop()
		return Vector2.ZERO
	var point: Vector3 = target.point
	var difference: Vector2 = Vector2(point.x - body.position.x, point.z - body.position.z)
	var distance: float = difference.length()
	target.elapsed = float(target.elapsed) + delta
	target.stalled = float(target.stalled) + delta if distance >= float(target.distance) - .0005 else 0.0
	target.distance = distance
	if distance < ARRIVE_DISTANCE:
		if _local_companions.has(who): _local_companions.erase(who)
		else: _local_target.clear()
		return Vector2.ZERO
	if float(target.elapsed) > 3.0 or float(target.stalled) > .4:
		stop()
		return Vector2.ZERO
	if _uses_prop_obstacles() and not bool(stage.prop_segment_clear(body.position, point, who)):
		stop()
		return Vector2.ZERO
	# Even a long physics frame must finish inside this support; local stance
	# movement never asks the normal crossing transaction to change its ID.
	var maximum_speed: float = maxf(FOLLOW_SPEED, SPEED * (1.15 if rolling else 1.0))
	return difference.normalized() * minf(1.0, distance / maxf(.001, maximum_speed * delta))

func nudge(direction: String) -> void:
	var p: Dictionary = session.world.point()
	var offset: Vector2i = router.OFFSETS.get(direction, Vector2i.ZERO)
	for candidate: Dictionary in _neighbors(str(p.id)):
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
	_query_active = true
	_query_tiles = []
	var active: String = session.world.actor()
	var intent: Vector2 = router.movement_vector()
	if intent.length_squared() > 0.0:
		click_path.clear()
		_local_target.clear()
		_local_companions.clear()
	var local_sequence: bool = not _local_target.is_empty() or not _local_companions.is_empty()
	var active_body: CharacterBody3D = stage.get_actor_body(active)
	if intent.is_zero_approx() and not _local_target.is_empty():
		intent = _local_intent(active, active_body, delta)
	elif intent.is_zero_approx() and not click_path.is_empty():
		intent = _route_intent(active, active_body, delta)
	var moved_active := _move_actor(active, intent, delta)
	var other := "buddy" if active == "luvie" else "luvie"
	var follower_intent := Vector2.ZERO
	var other_body: CharacterBody3D = stage.get_actor_body(other)
	if _local_companions.has(other):
		follower_intent = _local_intent(other, other_body, delta)
	elif not local_sequence and other_body != null and active_body != null and (bool(session.world.state.follow) or rejoining):
		var distance := Vector2(other_body.position.x - active_body.position.x, other_body.position.z - active_body.position.z).length()
		var actor_tile: String = str(session.world.state.actors[active])
		var other_tile: String = str(session.world.state.actors[other])
		var actor_center: Vector3 = stage.tile_position(_point_for(actor_tile))
		var rest := Vector2(clampf(active_body.position.x - 0.23, actor_center.x - 0.27, actor_center.x + 0.27), clampf(active_body.position.z + 0.2, actor_center.z - 0.27, actor_center.z + 0.27))
		if stage.has_method("actor_rest_offset") and not stage.actor_rest_offset(_point_for(actor_tile), other).is_zero_approx():
			var stance: Vector3 = stage.actor_rest_position(_point_for(actor_tile), other)
			rest = Vector2(stance.x, stance.z)
		rest = _restore_volume_position(other, _point_for(actor_tile), rest)
		if _uses_prop_obstacles():
			var canonical: Dictionary = _prop_waypoint(_point_for(actor_tile), other)
			# Rest already has the ordinary motor's same-support bounds. Do not
			# run/cache an 81-candidate support search for a changing foot point
			# on every frame of following.
			var preferred := Vector3(rest.x, actor_center.y, rest.y)
			if not canonical.is_empty() and (not bool(stage.prop_point_clear(preferred,other)) or not bool(stage.prop_segment_clear(canonical.point,preferred,other))):
				var safe_point: Vector3 = canonical.point
				rest = Vector2(safe_point.x,safe_point.z)
		var rest_distance := rest.distance_to(Vector2(other_body.position.x, other_body.position.z))
		var settling := not moved_active or rejoining
		if distance > (0.5 if rejoining else 0.78) or not session.world.together(_read_tiles()) or (settling and (actor_tile != other_tile or rest_distance > 0.06)):
			if _uses_prop_obstacles():
				var planned: Dictionary = _prop_path(actor_tile, other)
				if bool(planned.found):
					var next_id: String = str(planned.path[0]) if not planned.path.is_empty() else actor_tile
					var waypoint: Dictionary = _prop_waypoint(_point_for(next_id), other)
					if not waypoint.is_empty():
						var target: Vector3 = waypoint.point
						if actor_tile == other_tile and settling: target = Vector3(rest.x, actor_center.y, rest.y)
						var step: Dictionary = _prop_step(other, other_body, target)
						if not step.is_empty():
							var step_point: Vector3 = step.point
							var difference: Vector2 = Vector2(step_point.x - other_body.position.x, step_point.z - other_body.position.z)
							if difference.length() >= ARRIVE_DISTANCE or (difference.length() > .001 and (other_tile != next_id or not bool(stage.prop_segment_clear(other_body.position,target,other)))):
								follower_intent = difference.limit_length(FOLLOW_SPEED*delta)/maxf(.001,FOLLOW_SPEED*delta)
						elif rejoining:
							rejoining = false
				elif rejoining:
					rejoining = false
			else:
				var path: Array = session.world.path_to(actor_tile, other)
				if not path.is_empty():
					var destination: Dictionary = _point_for(str(path[0]))
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
	_query_active = false
	_query_tiles = []
	_query_world = null

func _route_intent(who: String, body: CharacterBody3D, delta: float = 1.0/60.0) -> Vector2:
	while not click_path.is_empty():
		var id := str(click_path[0])
		var tile: Dictionary = _point_for(id)
		if tile.is_empty():
			click_path.clear()
			return Vector2.ZERO
		var target: Vector3 = stage.tile_position(tile)
		if click_path.size() == 1 and stage.has_method("actor_rest_position"):
			target = stage.actor_rest_position(tile, who)
		if _uses_prop_obstacles():
			var waypoint: Dictionary = _prop_waypoint(tile, who)
			if waypoint.is_empty():
				click_path.clear()
				return Vector2.ZERO
			target = waypoint.point
		var difference := Vector2(target.x - body.position.x, target.z - body.position.z)
		# A safe stance can be only 2 cm inside a legal neighbouring cell.
		# Proximity alone must never consume it before the real boundary crossing.
		if difference.length() < ARRIVE_DISTANCE and str(session.world.state.actors[who]) == id:
			click_path.pop_front()
			continue
		# Click paths center their waypoints; direct keyboard movement never does.
		if str(session.world.state.actors[who]) != id:
			var valid := false
			for candidate: Dictionary in _neighbors(str(session.world.state.actors[who]), who):
				if str(candidate.id) == id:
					valid = true
			if not valid:
				click_path.clear()
				return Vector2.ZERO
		if _uses_prop_obstacles():
			var step: Dictionary = _prop_step(who, body, target)
			if step.is_empty():
				click_path.clear()
				_notify_blocked("石基挡住了这条路线，请先走到旁边的空地。")
				return Vector2.ZERO
			var step_point: Vector3 = step.point
			difference = Vector2(step_point.x - body.position.x, step_point.z - body.position.z)
			# Long frames must stop at an obstacle corner, not overshoot it into
			# another rule cell. The next segment still needs its own clear check.
			var route_speed: float = SPEED*(1.15 if rolling else 1.0)
			return difference.limit_length(route_speed*delta)/maxf(.001,route_speed*delta)
		return difference.normalized()
	return Vector2.ZERO

func _move_actor(who: String, intent: Vector2, delta: float, following: bool = false) -> bool:
	var body: CharacterBody3D = stage.get_actor_body(who)
	if body == null:
		return false
	var current_id := str(session.world.state.actors[who])
	var current: Dictionary = _point_for(current_id)
	if current.is_empty():
		return false
	var center: Vector3 = stage.tile_position(current)
	var speed := FOLLOW_SPEED if following else SPEED
	if rolling and not following:
		speed *= 1.15
	speed *= stage.stair_pace(body.position, intent, current_id)
	var planned := Vector2(body.position.x, body.position.z) + intent * speed * delta
	var allowed: Array = _neighbors(current_id, who)
	var routing_props := _uses_prop_obstacles() and (following or not click_path.is_empty() or not _local_target.is_empty())
	var guard := _guard(planned, center, allowed, routing_props)
	var target: Vector2 = _guard_traversal_volume(who, current, Vector2(body.position.x, body.position.z), guard.position, delta)
	var actual_intent := (target - Vector2(body.position.x, body.position.z)) / maxf(0.001, delta)
	actual_intent = actual_intent.limit_length(speed)
	var starts_walk := actual_intent.length_squared() > 0.0001 and not _walking_group
	if starts_walk and not (who == "luvie" and session.world.flag("hold")):
		session.world.record_checkpoint()
		_walking_group = true
	body.velocity.x = actual_intent.x
	body.velocity.z = actual_intent.y
	body.velocity.y = -0.8 if body.is_on_floor() else maxf(-12.0, body.velocity.y - GRAVITY * delta)
	var previous := body.position
	body.move_and_slide()
	# A hand cannot remain on the lever while its owner walks inside a tile.
	# Check the actual sweep, then preview the same domain transaction used by
	# a boundary crossing. If a passenger still needs the bridge, roll back
	# this physical step as well as the rule change (no 'ghost hold').
	if who == "luvie" and session.world.flag("hold") and actual_intent.length_squared() > .0001 and Vector2(body.position.x-previous.x,body.position.z-previous.z).length_squared() > .000001:
		var released: RefCounted = session.prepare(GardenCommand.release_hold(who))
		if released.accepted and not can_change_to(released.after):
			released.accepted = false
			released.message = "伙伴还在短桥边缘，等它站稳后再松开重杆。"
		if released.accepted:
			if starts_walk:
				session.world.record_checkpoint()
				_walking_group = true
			released = session.commit(released)
		if not released.accepted:
			body.position = previous
			body.velocity = Vector3.ZERO
			_moving[who] = false
			click_path.clear()
			_notify_blocked(str(released.message))
			stage.update_actor_visual(who,Vector3.ZERO,str(_last_facing[who]),"")
			return false
		stage.refresh_world(session.world,true)
		interaction_changed.emit(who,released)
		# Releasing the lever invalidates neighbours in this same physics tick.
		allowed = _neighbors(current_id,who)
	if stage.has_presentation_feature("physical_stair_steps"):
		_try_stair_step(body, previous, actual_intent * delta, current, allowed)
	# All unsupported and closed edges are guarded before the physical sweep.
	# Clamp tiny solver drift at an exterior boundary without recentering actors.
	var after_guard := _guard(Vector2(body.position.x, body.position.z), center, allowed, routing_props)
	var supported: Vector2 = _guard_traversal_volume(who, current, Vector2(previous.x, previous.z), after_guard.position, 0.0)
	# A boundary clamp is a second horizontal displacement after the capsule
	# sweep. It must not push a rounded capsule into a hard prop corner.
	if _uses_prop_obstacles() and supported.distance_to(Vector2(body.position.x,body.position.z))>.00001 and not stage.prop_physical_point_clear(Vector3(supported.x,body.position.y,supported.y),who):
		body.position = previous
		body.velocity = Vector3.ZERO
		supported = Vector2(previous.x,previous.z)
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

func _guard(planned: Vector2, center: Vector3, allowed: Array, prop_route: bool = false) -> Dictionary:
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
		var lateral := EDGE_LIMIT if prop_route else CLOSED_LIMIT
		result.y = clampf(result.y, center.z - lateral, center.z + lateral)
	elif open_z and absf(planned.y - center.z) >= 0.49:
		result.y = planned.y
		var lateral := EDGE_LIMIT if prop_route else CLOSED_LIMIT
		result.x = clampf(result.x, center.x - lateral, center.x + lateral)
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
	for neighbor: Dictionary in _neighbors(str(current.id), "buddy"):
		var profile: Dictionary = stage.traversal_profile(str(current.id), str(neighbor.id))
		if bool(profile.get("slope", false)):
			profiles.append(profile)
	return profiles

func _try_stair_step(body: CharacterBody3D, before: Vector3, horizontal: Vector2, current: Dictionary, allowed: Array) -> void:
	if horizontal.length_squared() < 0.000001: return
	if not str(session.world.level.id) in ["1-1", "1-2"]:
		var surface: Node3D = stage._surface_for_support(str(current.id))
		if surface != null:
			var descriptor: Dictionary = surface.stair_descriptor(before)
			if not descriptor.is_empty() and Vector3(horizontal.x, 0, horizontal.y).dot(descriptor.axis) * float(descriptor.rise) < -0.000001:
				return
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
		var tile: Dictionary = _point_for(id)
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
		var current: Dictionary = _point_for(current_id)
		if current.is_empty():
			return false
		var future_edges: Array = future.neighbors(current_id, who, future_tiles)
		if _occupies_detaching_stair(body, current, future, future_tiles, future_edges): return false
		var center: Vector3 = stage.logical_position(stage.tile_position(current))
		var logical_body: Vector3 = stage.logical_position(body.position)
		for tile: Dictionary in _neighbors(current_id, who):
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

func _occupies_detaching_stair(body: CharacterBody3D, current: Dictionary, future: RefCounted, future_tiles: Array, future_edges: Array) -> bool:
	if str(session.world.level.id) in ["1-1", "1-2"]: return false
	var surface: Node3D = stage._surface_for_support(str(current.id))
	if surface == null or not bool(surface.get("generic_stairs")): return false
	var moving := {}
	for module: Dictionary in session.world.level.get("modules", []):
		if stage._module_changes_between(session.world, future, module): moving[str(module.id)] = true
	var level := str(session.world.level.id)
	if level in ["cloud-1", "cloud-3"] and session.world.state.turns.bridge != future.state.turns.bridge: moving["cloud:bridge"] = true
	if level == "cloud-2" and session.world.state.turns.lift != future.state.turns.lift: moving["cloud:lift"] = true
	var own_group := _stair_motion_group(current, moving)
	var future_current: Dictionary = future.point_for(str(current.id), future_tiles)
	var local: Vector3 = surface.to_local(body.global_position)
	var position := Vector2(local.x, local.z)
	var capsule := body.get_node("Collision").shape as CapsuleShape3D
	var radius := capsule.radius if capsule != null else 0.16
	for index in range(4):
		if is_zero_approx(float(surface.rises[index])): continue
		var axis: Vector2 = GenericStairs.AXES[index]
		if position.dot(axis) + radius < float(GenericStairs.NOSES[0]) - 0.0001: continue
		if absf(position.dot(Vector2(-axis.y, axis.x))) > GenericStairs.HALF_WIDTH + radius: continue
		# The capsule can touch a step before its centre crosses the nose.
		# Do not retract that supporting face underneath its footprint.
		for other: Dictionary in _read_tiles():
			if not is_equal_approx(float(other.x) - float(current.x), axis.x) or not is_equal_approx(float(other.z) - float(current.z), axis.y): continue
			if own_group != _stair_motion_group(other, moving): return true
			var future_other: Dictionary = {}
			for candidate: Dictionary in future_edges:
				if str(candidate.id) == str(other.id): future_other = candidate
			if future_current.is_empty() or future_other.is_empty(): return true
			if not is_equal_approx(float(other.h) - float(current.h), float(future_other.h) - float(future_current.h)): return true
	return false

func _stair_motion_group(tile: Dictionary, moving: Dictionary) -> String:
	var kind := str(tile.get("kind", ""))
	if kind == "bridge" and moving.has("cloud:bridge"): return "cloud:bridge"
	if kind == "lift" and moving.has("cloud:lift"): return "cloud:lift"
	var module := str(tile.get("module", ""))
	return module if moving.has(module) else ""

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
