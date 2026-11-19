extends RefCounted
## Clip only the drawn light to the visible garden's footprint. Domain rays
## retain their authored range, reflection points, receiver checks and reveals.

const RayShader = preload("res://presentation/native/garden_ray.gdshader")
const ColumnShader = preload("res://presentation/native/garden_beam_column.gdshader")
const LampShader = preload("res://presentation/native/lamp_beam.gdshader")
const VIEW_NORMAL := Vector3(0.612372, 0.5, 0.612372)
const RAY_HEIGHT := 0.37
const POND_CORE_WIDTH := 0.115
const POND_COLUMN_WIDTH := 0.28

static func build(stage: Node) -> void:
	var paths := {"mirror": stage.world.rays()}
	if stage.world.has_method("lamp_ray"): paths["lamp"] = stage.world.lamp_ray()
	var soft_mirror_beam := str(stage.world.level.id) in ["2-2", "3-4"]
	var bounds := visible_bounds(stage.world, stage._tiles)
	for path_name: String in paths:
		var points: Array = paths[path_name]
		var drawn: Array = []
		for index: int in range(1, points.size()):
			var clipped := clip_segment(points[index - 1], points[index], bounds)
			if not clipped.is_empty(): drawn.append({"index": index - 1, "points": clipped})
		for index: int in range(drawn.size()):
			var entry: Dictionary = drawn[index]
			var pair: Array = entry.points
			var a: Vector3 = stage.tile_position(pair[0]) + Vector3.UP * RAY_HEIGHT
			var b: Vector3 = stage.tile_position(pair[1]) + Vector3.UP * RAY_HEIGHT
			if soft_mirror_beam:
				# Both layers follow the real rule segment. Only the outer tail
				# fades; cell joins and mirror hits retain continuous light.
				var head_fade := 0.045 if index == 0 else 0.0
				var tail_fade := 0.14 if index == drawn.size() - 1 else 0.0
				var core_head := head_fade
				var core_tail := tail_fade
				for item_id: String in stage.world.state.get("items", {}):
					if not item_id.begins_with("mirror"): continue
					# Focus the round body to the glass contact instead of showing
					# two clipped white pipe sections through the mirror surface.
					if _ground_mirror_at(stage.world, item_id, pair[0]): core_head = maxf(core_head, 0.075)
					if _ground_mirror_at(stage.world, item_id, pair[1]): core_tail = maxf(core_tail, 0.075)
				for part: String in ["core", "halo"]:
					var beam := _soft_segment(stage, a, b, part, core_head if part == "core" else head_fade, core_tail if part == "core" else tail_fade)
					_tag_segment(beam, path_name, int(entry.index), pair, part)
			elif str(stage.world.level.id) == "3-1" and path_name == "lamp":
				var beam := _lamp_segment(stage,a,b,index == 0,index == drawn.size()-1)
				_tag_segment(beam,path_name,int(entry.index),pair,"lamp_volume")
			else:
				# Other chapters keep their reviewed native beam geometry.
				var mesh := CylinderMesh.new()
				mesh.top_radius = 0.018
				mesh.bottom_radius = 0.018
				mesh.height = a.distance_to(b)
				mesh.radial_segments = 8
				var beam: MeshInstance3D = stage._mesh_instance(stage._effects, mesh, Color("ffe3a0"), a.lerp(b, 0.5), false)
				beam.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
				_tag_segment(beam, path_name, int(entry.index), pair, "legacy")
		# An unaligned final garden returns only its source point. Do not add
		# a glowing contact until a real incident segment exists.
		if soft_mirror_beam and points.size() > 1: _contacts(stage, path_name, points, bounds)

static func _tag_segment(node: MeshInstance3D, path_name: String, index: int, pair: Array, part: String) -> void:
	node.set_meta("rule_ray", true)
	node.set_meta("rule_path", path_name)
	node.set_meta("rule_segment_index", index)
	node.set_meta("rule_segment_points", pair.duplicate(true))
	node.set_meta("rule_ray_part", part)

static func _lamp_segment(stage: Node, a: Vector3, b: Vector3, first: bool, last: bool) -> MeshInstance3D:
	# One bound segment owns every concentric layer. Movement, turning,
	# obstruction and discovery therefore cannot leave detached glow strips.
	var root := MeshInstance3D.new()
	for i in 3:
		var layer := root if i == 0 else MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		# Keep the bright core inside the authored leaf/window apertures;
		# dimensional softness belongs to the low-opacity fringe, not a pipe.
		mesh.top_radius = [0.020,0.078,0.14][i]
		mesh.bottom_radius = mesh.top_radius
		mesh.height = a.distance_to(b)
		mesh.radial_segments = 32
		mesh.cap_top = false; mesh.cap_bottom = false
		layer.mesh = mesh
		layer.name = ["LampLightCore","LampInnerGlow","LampOuterGlow"][i]
		var material := ShaderMaterial.new()
		material.shader = LampShader
		material.set_shader_parameter("segment_length",mesh.height)
		material.set_shader_parameter("tint",[Color(1,.92,.68,.44),Color(1,.76,.32,.15),Color(1,.68,.24,.055)][i])
		material.set_shader_parameter("softness",[.7,1.8,3.0][i])
		material.set_shader_parameter("head_fade",.10/mesh.height if first else 0.0)
		material.set_shader_parameter("tail_fade",.20/mesh.height if last else 0.0)
		layer.material_override = material
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i > 0: root.add_child(layer)
	root.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	root.position = a.lerp(b,.5)
	stage._effects.add_child(root)
	return root

static func _soft_segment(stage: Node, a: Vector3, b: Vector3, part: String, head_fade: float, tail_fade: float) -> MeshInstance3D:
	if part == "core": return _column_segment(stage, a, b, head_fade, tail_fade)
	var direction := (b - a).normalized()
	var right := direction.cross(VIEW_NORMAL).normalized()
	var column := part == "halo"
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(POND_COLUMN_WIDTH if column else POND_CORE_WIDTH, a.distance_to(b))
	node.mesh = mesh
	node.basis = Basis(right, direction, right.cross(direction))
	node.position = a.lerp(b, 0.5)
	var material := ShaderMaterial.new()
	material.shader = RayShader
	# This is only the local fringe; the cylinder owns the readable light body.
	material.set_shader_parameter("tint", Color(1.0, 0.89, 0.66, 0.14))
	material.set_shader_parameter("soft_volume", column)
	material.set_shader_parameter("emission_strength", 0.08 if column else 0.06)
	if column:
		if head_fade > 0.0: head_fade = maxf(head_fade, 0.16)
		if tail_fade > 0.0: tail_fade = maxf(tail_fade, 0.22)
	material.set_shader_parameter("head_fade", head_fade / mesh.size.y)
	material.set_shader_parameter("tail_fade", tail_fade / mesh.size.y)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage._effects.add_child(node)
	return node

static func _column_segment(stage: Node, a: Vector3, b: Vector3, head_fade: float, tail_fade: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = POND_CORE_WIDTH * 0.5
	mesh.bottom_radius = mesh.top_radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 24
	mesh.rings = 8
	mesh.cap_top = false
	mesh.cap_bottom = false
	node.mesh = mesh
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	node.position = a.lerp(b, 0.5)
	var material := ShaderMaterial.new()
	material.shader = ColumnShader
	material.set_shader_parameter("segment_length", mesh.height)
	material.set_shader_parameter("tint", Color("fadba0"))
	material.set_shader_parameter("head_fade", head_fade / mesh.height)
	material.set_shader_parameter("tail_fade", tail_fade / mesh.height)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage._effects.add_child(node)
	return node

static func _contacts(stage: Node, path_name: String, points: Array, bounds: Rect2) -> void:
	for index: int in range(points.size()):
		var point: Dictionary = points[index]
		if not bounds.has_point(Vector2(float(point.x), float(point.z))): continue
		var contact_item := "source" if index == 0 else ""
		if index > 0:
			for item_id: String in stage.world.state.get("items", {}):
				if not item_id.begins_with("mirror"): continue
				if _ground_mirror_at(stage.world, item_id, point):
					contact_item = item_id
					break
		if contact_item.is_empty(): continue
		var node := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * (0.30 if index == 0 else 0.26)
		node.mesh = mesh
		var right := Vector3(1, 0, -1).normalized()
		node.basis = Basis(right, VIEW_NORMAL.normalized().cross(right), VIEW_NORMAL.normalized())
		var at: Vector3 = stage.tile_position(point) + Vector3.UP * RAY_HEIGHT
		node.position = at if contact_item == "source" else _surface_contact_position(stage, contact_item, at)
		var material := ShaderMaterial.new()
		material.shader = RayShader
		material.set_shader_parameter("contact", true)
		material.set_shader_parameter("tint", Color(1.0, 0.84, 0.44, 0.32 if index == 0 else 0.28))
		material.set_shader_parameter("emission_strength", 0.08)
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("rule_ray", true)
		node.set_meta("rule_path", path_name)
		node.set_meta("rule_point_index", index)
		node.set_meta("rule_contact_item", contact_item)
		node.set_meta("rule_contact_point", point.duplicate(true))
		node.set_meta("rule_ray_part", "contact")
		stage._effects.add_child(node)
		if contact_item != "source":
			_align_contact_to_glass(stage, contact_item, node)

static func update_motion(stage: Node, before: RefCounted, after: RefCounted, progress: float) -> void:
	# A destination reflection is valid only after alignment. In the pond the
	# unchanged incoming prefix still reaches the turning mirror, so keep it
	# and its real contact lit without previewing any downstream reflection.
	var before_paths := {"mirror": before.rays(), "lamp": before.lamp_ray()}
	var after_paths := {"mirror": after.rays(), "lamp": after.lamp_ray()}
	var changed: bool = before_paths != after_paths
	var aligned := not changed or progress >= 1.0
	var pond := str(after.level.id) == "2-2"
	var stable := {}
	if pond and not aligned:
		stable["mirror"] = _common_prefix(before_paths.mirror, after_paths.mirror)
		stable["lamp"] = _common_prefix(before_paths.lamp, after_paths.lamp)
	for node: Node in stage._effects.get_children():
		if not node.has_meta("rule_ray"): continue
		var keep := aligned
		if pond and not aligned:
			var count := int(stable.get(str(node.get_meta("rule_path", "")), 0))
			if node.has_meta("rule_segment_index"):
				keep = int(node.get_meta("rule_segment_index")) + 1 < count
			elif node.has_meta("rule_point_index"):
				var index := int(node.get_meta("rule_point_index"))
				keep = index < count
				var item_id := str(node.get_meta("rule_contact_item", ""))
				if keep and item_id != "source":
					var points: Array = after_paths[str(node.get_meta("rule_path"))]
					keep = _ground_mirror_at(before, item_id, points[index]) and _ground_mirror_at(after, item_id, points[index])
		(node as Node3D).visible = keep
		if keep and node.has_meta("rule_contact_item") and str(node.get_meta("rule_contact_item")) != "source":
			var at: Vector3 = stage.tile_position(node.get_meta("rule_contact_point")) + Vector3.UP * RAY_HEIGHT
			(node as Node3D).position = _surface_contact_position(stage, str(node.get_meta("rule_contact_item")), at)
			_align_contact_to_glass(stage, str(node.get_meta("rule_contact_item")), node)

static func _align_contact_to_glass(stage: Node, item_id: String, contact_node: Node3D) -> void:
	var root: Node3D = stage._props_nodes.get("item:" + item_id)
	var face: MeshInstance3D = root.get_node_or_null("ReflectionFace") as MeshInstance3D if root != null else null
	if face != null:
		# A camera-facing card cuts through an oblique opaque mirror. Its
		# shimmer must lie on the actual glass plane, including during a turn.
		contact_node.global_basis = face.global_basis.orthonormalized()

static func _surface_contact_position(stage: Node, item_id: String, at: Vector3) -> Vector3:
	var root: Node3D = stage._props_nodes.get("item:" + item_id) as Node3D
	var face: MeshInstance3D = root.get_node_or_null("ReflectionFace") as MeshInstance3D if root != null else null
	if face == null or face.mesh == null: return at
	var normal := face.global_basis.z.normalized()
	var side := 1.0 if normal.dot(VIEW_NORMAL) >= 0.0 else -1.0
	var half_thickness := face.mesh.get_aabb().size.z * face.global_basis.z.length() * 0.5
	# Put the shimmer on the actual visible glass surface, not inside the
	# opaque box or above its frame. The small gap only avoids coplanar flicker.
	return at + normal * (side * (half_thickness + 0.002) - (at - face.global_position).dot(normal))

static func _common_prefix(before: Array, after: Array) -> int:
	var count := 0
	for index: int in range(mini(before.size(), after.size())):
		if not _same_point(before[index], after[index]): break
		count += 1
	return count

static func _same_point(a: Dictionary, b: Dictionary) -> bool:
	return is_equal_approx(float(a.x), float(b.x)) and is_equal_approx(float(a.z), float(b.z)) and is_equal_approx(float(a.get("h", 0)), float(b.get("h", 0)))

static func _ground_mirror_at(world: RefCounted, item_id: String, point: Dictionary) -> bool:
	var item: Dictionary = world.state.get("items", {}).get(item_id, {})
	if item.is_empty() or not str(item.get("holder", "")).is_empty() or str(item.get("tile", "")).is_empty(): return false
	var at: Dictionary = world._raw_item_point(str(item.tile))
	return not at.is_empty() and _same_point(at, point)

static func visible_bounds(world: RefCounted, world_tiles: Array = []) -> Rect2:
	if world_tiles.is_empty(): world_tiles = world.tiles()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for tile: Dictionary in world_tiles:
		if not world.visible(tile, world_tiles): continue
		var point := Vector2(float(tile.x), float(tile.z))
		low = low.min(point - Vector2(0.5, 0.5))
		high = high.max(point + Vector2(0.5, 0.5))
	return Rect2(low, high - low) if low.is_finite() else Rect2()

static func segments(world: RefCounted, points: Array, world_tiles: Array = []) -> Array:
	var result: Array = []
	if points.size() < 2: return result
	var bounds := visible_bounds(world, world_tiles)
	if not bounds.has_area(): return result
	for index in range(1, points.size()):
		var clipped := clip_segment(points[index - 1], points[index], bounds)
		if not clipped.is_empty(): result.append(clipped)
	return result

static func clip_segment(a: Dictionary, b: Dictionary, bounds: Rect2) -> Array:
	if not bounds.has_area(): return []
	var start := Vector2(float(a.x), float(a.z))
	var delta := Vector2(float(b.x), float(b.z)) - start
	if delta.length_squared() < 0.00000001: return []
	var near := 0.0
	var far := 1.0
	for axis in range(2):
		if absf(delta[axis]) < 0.000001:
			if start[axis] < bounds.position[axis] or start[axis] > bounds.end[axis]: return []
			continue
		var first := (bounds.position[axis] - start[axis]) / delta[axis]
		var last := (bounds.end[axis] - start[axis]) / delta[axis]
		near = maxf(near, minf(first, last))
		far = minf(far, maxf(first, last))
		if far <= near: return []
	var height_a := float(a.get("h", 0))
	var height_b := float(b.get("h", 0))
	var clipped_a := start + delta * near
	var clipped_b := start + delta * far
	return [
		{"x": clipped_a.x, "z": clipped_a.y, "h": lerpf(height_a, height_b, near)},
		{"x": clipped_b.x, "z": clipped_b.y, "h": lerpf(height_a, height_b, far)}
	]
