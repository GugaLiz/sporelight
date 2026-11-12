extends RefCounted
## Local hard-base obstruction, excluding the accepted first garden. This is not a
## terrain surface, a logical solid tile, or the flower card's bounding box.
## Build/cache on prop rebuild; waypoint/cache on layout or actor-shape change.
const COLLISION_LAYER: int = 8
const LEVELS: Array[String] = ["1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4", "cloud-1", "cloud-2", "cloud-3"]
const CloudDressing = preload("res://presentation/native/original_cloud_dressing.gd")
const HARD_SCENERY: Array[String] = ["stone-lantern", "wood-lantern", "river-rock", "light-tower", "violet-crystal", "lotus-pool"]
const BODY_NAME: String = "CoreStoneObstacle"
const CLEARANCE: float = .02
const HEIGHT_TOLERANCE: float = .025
const WAYPOINT_OFFSETS: Array[float] = [-.44, -.33, -.30, -.22, -.11, 0.0, .11, .22, .30, .33, .44]

static func placement_offset(item_id: String,tile_id: String,level_id: String) -> Vector3:
	# Keep the original day-post slot and projection rule; its complete stone
	# foot sits to the north so a full capsule can enter the eastern shadow.
	if level_id=="3-2" and item_id=="sunPost" and tile_id=="f:0:0": return Vector3(0,0,-.20)
	return Vector3.ZERO

static func placement_entry(item_id: String, at: Vector3, level_id: String) -> Dictionary:
	if level_id == "1-1": return {}
	var half: float = 0.0
	if item_id.begins_with("mirror"): half = .205
	elif item_id in ["sunPost", "moonPost"]:
		# Original 36px crystal canvas / 70px projected tile, complete rocky
		# foot (88px trimmed image), expressed on the two ground axes.
		half = 36.0 / 70.0 * .5
	if half == 0.0: return {}
	# The warm lamp's actual artwork is a soft luminous leaf mat, not a stone
	# lantern. Dew parcels, insects, bells and seed icons also have no hard base.
	return {"id":"item:"+item_id,"rect":Rect2(Vector2(at.x-half,at.z-half),Vector2.ONE*half*2),"floor":at.y,"top":at.y+.41,"height_scoped":true}

static func build(stage: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if stage.world == null or not str(stage.world.level.id) in LEVELS: return entries
	entries = _core(stage)
	if str(stage.world.level.id) != "2-2":
		entries.append_array(_other_bases(stage))
		return entries
	var top := .41
	for tile: Dictionary in stage._tiles:
		if not bool(tile.get("solid",false)): top = maxf(top,stage.tile_position(tile).y+.41)
	for key: String in stage._props_nodes:
		if not key.begins_with("item:mirror") and key != "mark:source": continue
		var root: Node3D = stage._props_nodes[key]
		if not root.is_visible_in_tree(): continue
		var half: float = .205 if key.begins_with("item:mirror") else .213
		entries.append(_small_obstacle(root,key,half,top))
	for child: Node in stage._props.get_children():
		if not child is Sprite3D or not child.is_visible_in_tree(): continue
		if not str(child.get_meta("original_scenery_alias", "")) in ["stone-lantern", "river-rock", "lotus-pool"]: continue
		entries.append(_small_obstacle(child,str(child.name),float(child.get_meta("original_scenery_foot_radius")),top))
	return entries

static func _other_bases(stage: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: String in stage._props_nodes:
		var root: Node3D = stage._props_nodes[key]
		if not root.is_visible_in_tree(): continue
		if key.begins_with("item:"):
			var placed: Dictionary = placement_entry(key.trim_prefix("item:"),root.global_position+Vector3(root.get_meta("physical_item_offset",Vector3.ZERO)),str(stage.world.level.id))
			if not placed.is_empty(): entries.append(_rect_obstacle(root,key,placed.rect,float(placed.floor),float(placed.top)))
		if str(stage.world.level.id).begins_with("cloud-") and key in ["mark:turn","mark:valve","mark:dock"]:
			entries.append_array(_cloud_bases(root,key.trim_prefix("mark:")))
		# Moving instrument meshes carry their own child collider. The stage
		# rebuilds the planner entries at landing, while actor input is locked
		# during rotation/lift/slide; no final-position obstacle is shown early.
		for name: String in ["InstrumentBase", "LeverBase", "SongBase", "LatchPost"]:
			var base: MeshInstance3D = root.get_node_or_null(name) as MeshInstance3D
			if base == null or base.mesh == null: continue
			var bounds: AABB = base.mesh.get_aabb()
			var minimum := Vector2(INF, INF)
			var maximum := Vector2(-INF, -INF)
			var floor_y: float = INF
			for corner: int in range(8):
				var at: Vector3 = base.to_global(bounds.get_endpoint(corner))
				minimum = minimum.min(Vector2(at.x, at.z))
				maximum = maximum.max(Vector2(at.x, at.z))
				floor_y = minf(floor_y, at.y)
			entries.append(_rect_obstacle(base, key + "/" + name, Rect2(minimum, maximum - minimum), floor_y, floor_y + .41))
		for child: Node in root.get_children():
			if child is Sprite3D and str(child.name)=="arch": entries.append_array(_main_arch_bases(child,key+"/arch"))
			if child is Sprite3D and child.has_meta("hard_planter"):
				var center: Vector3=root.to_global(child.get_meta("ground_footprint_center"))
				var span: Vector2=child.get_meta("ground_footprint_span")
				var rect := Rect2(Vector2(center.x,center.z)-span*.5,span)
				entries.append(_rect_obstacle(child,key+"/FlowerStoneFoot",rect,center.y,center.y+.41,"FlowerStoneFoot"))
	for child: Node in stage._props.get_children():
		if not child is Node3D or not child.is_visible_in_tree(): continue
		if child is Sprite3D and str(child.get_meta("original_scenery_alias", "")) in HARD_SCENERY:
			var half: float = float(child.get_meta("original_scenery_foot_radius"))
			var entry: Dictionary = _small_obstacle(child, str(child.name), half, child.global_position.y + .41)
			entry["height_scoped"] = true
			entries.append(entry)
		if child.has_meta("original_kind"):
			entries.append_array(_cloud_bases(child))
		elif child is Sprite3D and str(child.get_meta("original_scenery_alias", "")) == "arch":
			entries.append_array(_main_arch_bases(child,str(child.name)))
	return entries

static func _main_arch_bases(card: Sprite3D, id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	# Painted stone feet in the original 256px arch, independently of its
	# ivy/flower crown. The current Sprite offset supplies the actual source
	# anchor (scenery and latch cards deliberately use different anchors).
	var anchor := Vector2(card.texture.get_width()*.5-card.offset.x,card.texture.get_height()*.5+card.offset.y)
	var feet := [Vector4(72,188,30,15),Vector4(164,213,32,16)]
	for index: int in range(feet.size()):
		var foot: Vector4 = feet[index]
		var minimum := Vector2(INF,INF)
		var maximum := Vector2(-INF,-INF)
		for corner: Vector2 in [Vector2(-foot.z,0),Vector2(0,-foot.w),Vector2(foot.z,0),Vector2(0,foot.w)]:
			var pixel: Vector2 = Vector2(foot.x,foot.y)+corner-anchor
			var point: Vector3 = card.global_position+CloudDressing.RIGHT*pixel.x*card.pixel_size+CloudDressing.FRONT*pixel.y*card.pixel_size*2
			minimum=minimum.min(Vector2(point.x,point.z))
			maximum=maximum.max(Vector2(point.x,point.z))
		entries.append(_rect_obstacle(card,id+"/column"+str(index),Rect2(minimum,maximum-minimum),card.global_position.y,card.global_position.y+.41,"HardColumn_"+str(index)))
	return entries

static func _cloud_bases(root: Node3D, mark_kind: String = "") -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var kind: String = str(root.get_meta("original_kind", "")) if mark_kind.is_empty() else mark_kind
	var card: Sprite3D = root.get_child(0) as Sprite3D
	if card == null: return entries
	var pixel: float = float(card.get_meta("source_pixel_world"))
	# Dimensions are the actual original vector bases (not card bounds):
	# half screen width, half depth, and the base's screen-y centre.
	var sizes := {"tower": Vector3(35,17.5,2), "pool": Vector3(42,21,9), "bench": Vector3(20,10,2), "plant": Vector3(9,4.5,5), "plant_large": Vector3(16,8,9), "turn":Vector3(13,6.5,5), "valve":Vector3(9,4.5,0), "dock":Vector3(9,4.5,0)}
	var centres: Array[Vector2] = []
	var size := Vector3.ZERO
	if kind in ["arch", "arch_pink"]:
		# Two visible column plinths only. The centre remains the real doorway.
		size = Vector3(7,3.5,1)
		centres = [Vector2(-24,0),Vector2(24,0)]
	elif sizes.has(kind):
		size = sizes[kind]
		centres = [Vector2.ZERO]
	for index: int in range(centres.size()):
		var minimum := Vector2(INF,INF)
		var maximum := Vector2(-INF,-INF)
		for corner: Vector2 in [Vector2(-size.x,size.z),Vector2(0,size.z-size.y),Vector2(size.x,size.z),Vector2(0,size.z+size.y)]:
			corner += centres[index]
			var point: Vector3 = root.global_position + CloudDressing.RIGHT*(corner.x*pixel) + CloudDressing.FRONT*(corner.y*pixel*2)
			minimum = minimum.min(Vector2(point.x,point.z))
			maximum = maximum.max(Vector2(point.x,point.z))
		entries.append(_rect_obstacle(root,str(root.name)+"/"+str(index),Rect2(minimum,maximum-minimum),root.global_position.y,root.global_position.y+.41,"HardBase_"+str(index)))
	return entries

static func _rect_obstacle(root: Node3D, id: String, rect: Rect2, floor_y: float, top: float, node_name: String = "HardBaseObstacle") -> Dictionary:
	_opaque_structure(root)
	var body: StaticBody3D = root.get_node_or_null(node_name) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = node_name
		root.add_child(body)
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	body.global_transform = Transform3D(Basis.IDENTITY,Vector3(rect.get_center().x,(floor_y+top)*.5,rect.get_center().y))
	var collision: CollisionShape3D = body.get_node_or_null("BaseVolume") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "BaseVolume"
		body.add_child(collision)
	var shape := BoxShape3D.new()
	shape.size = Vector3(rect.size.x,top-floor_y,rect.size.y)
	collision.shape = shape
	body.set_meta("prop_obstacle_id",id)
	body.set_meta("not_walkable_support",true)
	return {"id":id,"rect":rect,"floor":floor_y,"top":top,"height_scoped":true}

static func _core(stage: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if stage.world == null or not str(stage.world.level.id) in LEVELS: return entries
	var core: Node3D = stage._props_nodes.get("mark:core") as Node3D
	if core == null or not core.is_visible_in_tree(): return entries
	var stone: Sprite3D = null
	for child: Node in core.get_children():
		if child is Sprite3D and child.has_meta("core_planter") and child.has_meta("ground_footprint_center") and child.has_meta("ground_footprint_span"):
			stone = child as Sprite3D
			break
	if stone == null: return entries
	# These metadata coordinates belong to the mark root, not to the tilted
	# Sprite3D. Reusing its card transform would rotate the stone footprint.
	var local_center: Vector3 = stone.get_meta("ground_footprint_center")
	var span: Vector2 = stone.get_meta("ground_footprint_span")
	if span.x <= 0.0 or span.y <= 0.0: return entries
	var center: Vector3 = core.to_global(local_center)
	var first_corner: Vector3 = core.to_global(local_center + Vector3(-span.x * .5, 0.0, -span.y * .5))
	var minimum: Vector2 = Vector2(first_corner.x, first_corner.z)
	var maximum: Vector2 = minimum
	for x: float in [-.5, .5]:
		for z: float in [-.5, .5]:
			var corner: Vector3 = core.to_global(local_center + Vector3(span.x * x, 0.0, span.y * z))
			minimum = minimum.min(Vector2(corner.x, corner.z))
			maximum = maximum.max(Vector2(corner.x, corner.z))
	var rect: Rect2 = Rect2(minimum, maximum - minimum)
	var highest_support: float = center.y
	for tile_value: Variant in stage._tiles:
		var tile: Dictionary = tile_value
		if bool(tile.get("solid", false)): continue
		var support_position: Vector3 = stage.tile_position(tile)
		highest_support = maxf(highest_support, support_position.y)
	# An anti-entry volume, never a new step: its top is above every legal
	# landing by more than .4 (and well beyond the motor's .18 step-up).
	var top: float = highest_support + .41 if str(stage.world.level.id) in ["1-4", "2-2"] else center.y + .41
	var size: Vector3 = Vector3(rect.size.x, top - center.y, rect.size.y)
	var body: StaticBody3D = core.get_node_or_null(BODY_NAME) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = BODY_NAME
		core.add_child(body)
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	body.global_transform = Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, (center.y + top) * .5, rect.get_center().y))
	var collision: CollisionShape3D = body.get_node_or_null("StoneVolume") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "StoneVolume"
		body.add_child(collision)
	var shape: BoxShape3D = collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
	elif not shape.size.is_equal_approx(size):
		shape.size = size
	body.set_meta("prop_obstacle_id", "mark:core")
	body.set_meta("not_walkable_support", true)
	entries.append({"id": "mark:core", "rect": rect, "floor": center.y, "top": top})
	if not str(stage.world.level.id) in ["1-4", "2-2"]: entries.back()["height_scoped"] = true
	return entries

static func _small_obstacle(root: Node3D, id: String, half: float, top: float) -> Dictionary:
	_opaque_structure(root)
	var at := root.global_position
	var rect := Rect2(Vector2(at.x-half,at.z-half),Vector2.ONE*half*2)
	var body := StaticBody3D.new()
	body.name = "HardBaseObstacle"
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	root.add_child(body)
	# World axes deliberately ignore the tilted decorative card's rotation.
	body.global_transform = Transform3D(Basis.IDENTITY,Vector3(at.x,(at.y+top)*.5,at.z))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(half*2,top-at.y,half*2)
	collision.shape = shape
	body.add_child(collision)
	body.set_meta("prop_obstacle_id", id)
	body.set_meta("not_walkable_support", true)
	return {"id":id,"rect":rect,"floor":at.y,"top":top}

static func height_overlap(from_y: float, to_y: float, entry: Dictionary, height: float = .8) -> bool:
	var bottom: float = float(entry.floor) - height if bool(entry.get("height_scoped",false)) else -INF
	return minf(from_y,to_y) <= float(entry.top) and maxf(from_y,to_y) >= bottom

static func _opaque_structure(root: Node3D) -> void:
	# Register at the actual collider creation path, including portable and
	# cloud props, so a second artwork factory cannot silently enable ghosting.
	root.set_meta("opaque_structure",true)
	for child: Node in root.get_children():
		if child is Sprite3D:child.set_meta("opaque_structure",true)

static func physical_clear(point: Vector3, radius: float, entries: Array, height: float = .8) -> bool:
	for entry: Dictionary in entries:
		if not height_overlap(point.y,point.y,entry,height): continue
		var rect: Rect2 = entry.rect
		var at := Vector2(point.x,point.z)
		if at.distance_to(at.clamp(rect.position,rect.end)) < radius-.002: return false
	return true

static func clear(point: Vector3, radius: float, entries: Array, height: float = .8) -> bool:
	for entry_value: Variant in entries:
		var entry: Dictionary = entry_value
		if not height_overlap(point.y,point.y,entry,height): continue
		var bounds: Rect2 = (entry.rect as Rect2).grow(maxf(0.0, radius))
		if point.x >= bounds.position.x and point.x <= bounds.end.x and point.z >= bounds.position.y and point.z <= bounds.end.y:
			return false
	# Below-floor points are conservatively blocked too: callers pass feet,
	# not capsule centres. This API must not let a taller body enter sideways
	# below the raised base. Only these gardens' existing support is considered.
	return true

static func segment_clear(from: Vector3, to: Vector3, radius: float, entries: Array, height: float = .8) -> bool:
	for entry_value: Variant in entries:
		var entry: Dictionary = entry_value
		var bounds: Rect2 = (entry.rect as Rect2).grow(maxf(0.0, radius))
		var interval: Vector2 = _segment_rect_interval(Vector2(from.x, from.z), Vector2(to.x, to.z), bounds)
		if interval.x > interval.y: continue
		var first_height: float = lerpf(from.y, to.y, interval.x)
		var last_height: float = lerpf(from.y, to.y, interval.y)
		if height_overlap(first_height,last_height,entry,height): return false
	return true

static func _segment_rect_interval(from: Vector2, to: Vector2, rect: Rect2) -> Vector2:
	var enter: float = 0.0
	var leave: float = 1.0
	var delta: Vector2 = to - from
	for axis: int in range(2):
		var start: float = from[axis]
		var direction: float = delta[axis]
		var low: float = rect.position[axis]
		var high: float = rect.end[axis]
		if absf(direction) < .000001:
			if start < low or start > high: return Vector2(1.0, 0.0)
			continue
		var near_time: float = (low - start) / direction
		var far_time: float = (high - start) / direction
		enter = maxf(enter, minf(near_time, far_time))
		leave = minf(leave, maxf(near_time, far_time))
		if enter > leave: return Vector2(1.0, 0.0)
	return Vector2(enter, leave)

static func waypoint(stage: Node, tile: Dictionary, who: String, preferred: Vector3, entries: Array) -> Dictionary:
	if tile.is_empty() or bool(tile.get("solid", false)) or (who == "luvie" and bool(tile.get("small", false))): return {}
	var body: CharacterBody3D = stage.get_actor_body(who) as CharacterBody3D
	if body == null: return {}
	var collision: CollisionShape3D = body.get_node_or_null("Collision") as CollisionShape3D
	if collision == null or not collision.shape is CapsuleShape3D: return {}
	var capsule: CapsuleShape3D = collision.shape as CapsuleShape3D
	var body_scale: Vector3 = collision.global_basis.get_scale()
	var radius: float = capsule.radius * maxf(absf(body_scale.x), absf(body_scale.z)) + CLEARANCE
	var center: Vector3 = stage.tile_position(tile)
	if absf(preferred.y - center.y) > HEIGHT_TOLERANCE: return {}
	if _safe_waypoint(stage, tile, who, preferred, center.y, radius, entries): return {"point": preferred}
	var candidates: Array[Vector3] = []
	for x: float in WAYPOINT_OFFSETS:
		for z: float in WAYPOINT_OFFSETS:
			var point: Vector3 = stage.physical_position(Vector3(float(tile.x) + x, center.y, float(tile.z) + z))
			point.y = preferred.y
			candidates.append(point)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(preferred) < b.distance_squared_to(preferred))
	for point: Vector3 in candidates:
		if _safe_waypoint(stage, tile, who, point, center.y, radius, entries): return {"point": point}
	return {}

static func _safe_waypoint(stage: Node, tile: Dictionary, who: String, point: Vector3, height: float, radius: float, entries: Array) -> bool:
	var logical: Vector3 = stage.logical_position(point)
	if absf(logical.x - float(tile.x)) > .499 or absf(logical.z - float(tile.z)) > .499: return false
	# A supported point outside the motor's closed-edge guard cannot actually
	# be reached. Use the same legal neighbours; never widen an exterior edge.
	var allowed: Array = stage.world.neighbors(str(tile.id),who,stage._tiles)
	for axis: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		var offset: float = (Vector2(logical.x-float(tile.x),logical.z-float(tile.z))).dot(axis)
		if offset <= .32: continue
		var open := false
		for neighbor: Dictionary in allowed:
			if is_equal_approx(float(neighbor.x),float(tile.x)+axis.x) and is_equal_approx(float(neighbor.z),float(tile.z)+axis.y): open=true;break
		if not open: return false
	var body: CharacterBody3D = stage.get_actor_body(who)
	var capsule: CapsuleShape3D = body.get_node("Collision").shape
	if not clear(point, radius, entries, capsule.height): return false
	if not _flat_support(stage, point, height, who): return false
	# Both interior and perimeter are sampled. Adjacent same-height real
	# terraces may support the capsule, but its centre never changes tile ID.
	for ring: float in [.5, 1.0]:
		for sector: int in range(16):
			var angle: float = TAU * float(sector) / 16.0
			var sample: Vector3 = point + Vector3(cos(angle), 0.0, sin(angle)) * radius * ring
			if not _flat_support(stage, sample, height, who): return false
	return true

static func local_route(stage: Node,tile: Dictionary,who: String,from: Vector3,to: Vector3,entries: Array) -> Array[Vector3]:
	return _visibility_route(stage,[tile],who,from,to,entries)

static func edge_route(stage: Node, from_tile: Dictionary, to_tile: Dictionary, who: String, entries: Array) -> Array[Vector3]:
	var from: Dictionary = stage.prop_waypoint(from_tile,who,stage.actor_rest_position(from_tile,who))
	var to: Dictionary = stage.prop_waypoint(to_tile,who,stage.actor_rest_position(to_tile,who))
	if from.is_empty() or to.is_empty(): return []
	if bool(stage.prop_segment_clear(from.point,to.point,who)): return [to.point]
	return _visibility_route(stage,[from_tile,to_tile],who,from.point,to.point,entries)

static func edge_route_from(stage: Node, from_tile: Dictionary, to_tile: Dictionary, who: String, from: Vector3, entries: Array) -> Array[Vector3]:
	var to: Dictionary = stage.prop_waypoint(to_tile,who,stage.actor_rest_position(to_tile,who))
	if to.is_empty(): return []
	if bool(stage.prop_segment_clear(from,to.point,who)): return [to.point]
	return _visibility_route(stage,[from_tile,to_tile],who,from,to.point,entries)

static func _visibility_route(stage: Node, tiles: Array, who: String, from: Vector3, to: Vector3, entries: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var radius: float = stage._prop_actor_radius(who)
	var points: Array[Vector3] = [from,to]
	# Visibility graph around complete bases, restricted to the requested
	# same support or the two ends of an already legal rule edge.
	# Built only on a blocked approach; the movement executor caches the polyline.
	for entry: Dictionary in entries:
		# radius already includes the planner's 2 cm safety margin. A further
		# 1 cm turn margin leaves legal narrow passages available; the executor
		# reaches the corner before consuming it and caps each physics stride.
		var rect: Rect2 = (entry.rect as Rect2).grow(radius+.01)
		for corner: Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			for tile: Dictionary in tiles:
				var height: float = stage.tile_position(tile).y
				var point := Vector3(corner.x,height,corner.y)
				if _safe_waypoint(stage,tile,who,point,height,radius,entries) and not point in points: points.append(point)
	var queue: Array[int] = [0]
	var previous := {0:-1}
	var cursor := 0
	while cursor<queue.size():
		var index: int = queue[cursor]
		cursor+=1
		if index==1:
			while index!=0:
				result.push_front(points[index])
				index=int(previous[index])
			return result
		for next: int in range(1,points.size()):
			if previous.has(next) or not stage.prop_segment_clear(points[index],points[next],who): continue
			previous[next]=index
			queue.append(next)
	return result

static func _flat_support(stage: Node, point: Vector3, height: float, who: String) -> bool:
	for key_value: Variant in stage._surfaces:
		var key: String = str(key_value)
		var surface: Node3D = stage._surfaces[key] as Node3D
		var tile: Dictionary = stage._tile_map.get(key, {})
		if surface == null or not surface.is_visible_in_tree() or tile.is_empty(): continue
		if bool(tile.get("solid", false)) or (who == "luvie" and bool(tile.get("small", false))): continue
		var local: Vector3 = surface.to_local(point)
		if absf(local.x) > .5001 or absf(local.z) > .5001: continue
		var sampled_height: float = surface.sample_height(point)
		if absf(sampled_height - height) <= .012: return true
	return false
