class_name NativeGardenSurface
extends Node3D

## Flat support islands with explicitly bounded ramp corridors. One geometry
## definition supplies the visible mesh, collision and motor sampling.
const HALF := 0.5
const RAMP_HALF_WIDTH := 0.32
const RAMP_SHOULDER := 0.42
const LANDING_HALF := 0.20
const GRID := [-0.5, -RAMP_SHOULDER, -RAMP_HALF_WIDTH, -LANDING_HALF, 0.0, LANDING_HALF, RAMP_HALF_WIDTH, RAMP_SHOULDER, 0.5]
var tile_id := ""
var center := Vector3.ZERO
var rises: Array[float] = []
var _top: MeshInstance3D
var _sides: MeshInstance3D
var _ramps: MeshInstance3D
var _treads: MeshInstance3D
var _risers: MeshInstance3D
var _body: PhysicsBody3D
var _geometry_key := ""
var geometry_rebuilds := 0
var thin_plate := false
const TRAVERSAL_THICKNESS := 0.20
var terrain_profile: Script
var authored_terrace := false
var _grid: Array = GRID
const GrowthTop = preload("res://presentation/native/garden_growth_top.gdshader")
var _growth_overrides: Dictionary = {}

func set_growth_reveal(progress: float, glow: bool = true, path_direction: Vector3 = Vector3.ZERO) -> void:
	if progress >= 1.0:
		for part: MeshInstance3D in _growth_overrides:
			part.material_override = _growth_overrides[part]
		_growth_overrides.clear()
		return
	if not thin_plate or not authored_terrace: return
	var axis := Vector2.RIGHT if absf(center.x) > absf(center.z) else Vector2.DOWN
	var positive_is_high := _connector_bottom(axis * HALF) > _connector_bottom(-axis * HALF)
	var direction := Vector3(axis.x, 0, axis.y) * (-1.0 if positive_is_high else 1.0)
	if not path_direction.is_zero_approx(): direction = path_direction
	for part: MeshInstance3D in [_top, _ramps, _risers, _sides, _treads]:
		if part.mesh == null: continue
		if not _growth_overrides.has(part):
			_growth_overrides[part] = part.material_override
			var original: Material = part.get_active_material(0)
			var material: ShaderMaterial
			if original is ShaderMaterial:
				material = original.duplicate()
			else:
				material = ShaderMaterial.new()
				material.shader = GrowthTop
				material.set_shader_parameter("original_paving", original.albedo_texture)
				material.set_shader_parameter("tint", original.albedo_color)
			part.material_override = material
		part.material_override.set_shader_parameter("growth_axis", direction)
		part.material_override.set_shader_parameter("growth_progress", clampf(progress, 0, 1))
		part.material_override.set_shader_parameter("growth_glow", glow)

func configure(tile: Dictionary, ramp_rises: Array[float], exposed: Array[bool], bottom: float, materials: Dictionary) -> void:
	tile_id = str(tile.id)
	name = "Surface_" + tile_id.replace(":", "_")
	terrain_profile = materials.get("terrain_profile")
	var base_height: float = terrain_profile.base_height(tile) if terrain_profile != null and terrain_profile.has_method("base_height") else float(tile.h) * 0.65
	center = Vector3(float(tile.x), base_height, float(tile.z))
	position = center
	rises = ramp_rises.duplicate()
	authored_terrace = terrain_profile != null
	_grid = terrain_profile.sampling_grid() if authored_terrace else GRID
	thin_plate = str(tile.get("kind", "")) in ["root", "bridge", "shadow"] or str(tile.id).begins_with("g:")
	if _top != null:
		_top.material_override = materials.top
		_sides.material_override = materials.side
		_ramps.material_override = materials.ramp
		_treads.material_override = materials.trim
		_risers.material_override = materials.get("riser", materials.side)
	var key := str([rises, exposed, bottom - center.y, tile.get("kind", "fixed"), materials.get("key", "")])
	if _geometry_key == key:
		return
	_geometry_key = key
	geometry_rebuilds += 1
	if _top == null:
		_top = MeshInstance3D.new()
		_top.name = "WalkableTop"
		_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_top)
		_sides = MeshInstance3D.new()
		_sides.name = "Foundation"
		_sides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_sides)
		_ramps = MeshInstance3D.new()
		_ramps.name = "StoneStairRun"
		_ramps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ramps)
		_treads = MeshInstance3D.new()
		_treads.name = "StoneTreadEdges"
		_treads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_treads)
		_risers = MeshInstance3D.new()
		_risers.name = "OriginalStoneRisers"
		_risers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_risers)
		_body = AnimatableBody3D.new() if tile.get("kind", "") == "module" else StaticBody3D.new()
		if _body is AnimatableBody3D:
			# The mechanism coordinator moves the entire support in the physics
			# transaction and carries passengers once. Parent transforms must not
			# be restored by a second implicit local-transform synchronizer.
			_body.sync_to_physics = false
		_body.name = "SupportCollision"
		_body.collision_layer = 1
		_body.collision_mask = 0
		add_child(_body)
		var collision := CollisionShape3D.new()
		collision.name = "SharedSurfaceShape"
		_body.add_child(collision)
	_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sides.cast_shadow = _top.cast_shadow
	_ramps.cast_shadow = _top.cast_shadow
	var top_vertices := PackedVector3Array()
	var top_uvs := PackedVector2Array()
	var wall_vertices := PackedVector3Array()
	var wall_uvs := PackedVector2Array()
	var wall_face_uvs := PackedVector2Array()
	var flat_vertices := PackedVector3Array()
	var flat_uvs := PackedVector2Array()
	var ramp_vertices := PackedVector3Array()
	var ramp_uvs := PackedVector2Array()
	var ramp_face_uvs := PackedVector2Array()
	var riser_vertices := PackedVector3Array()
	var riser_uvs := PackedVector2Array()
	var riser_face_uvs := PackedVector2Array()
	for z in range(_grid.size() - 1):
		for x in range(_grid.size() - 1):
			var middle := Vector2((_grid[x] + _grid[x + 1]) / 2.0, (_grid[z] + _grid[z + 1]) / 2.0)
			var corners: Array[Vector3] = []
			for at: Vector2 in [Vector2(_grid[x], _grid[z]), Vector2(_grid[x + 1], _grid[z]), Vector2(_grid[x + 1], _grid[z + 1]), Vector2(_grid[x], _grid[z + 1])]:
				corners.append(Vector3(at.x, _height_in_region(at, middle), at.y))
			# The A-C diagonal is also the max-height ridge at crossing ramps.
			for index in [0, 2, 1, 0, 3, 2]:
				var vertex: Vector3 = corners[index]
				top_vertices.append(vertex)
				top_uvs.append(Vector2(vertex.x + HALF, vertex.z + HALF))
			for triangle: Array in [[0, 2, 1], [0, 3, 2]]:
				var a: Vector3 = corners[triangle[0]]
				var b: Vector3 = corners[triangle[1]]
				var c: Vector3 = corners[triangle[2]]
				var sloped := maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)) > 0.0001
				if authored_terrace and not terrain_profile.stair_spec(Vector2(center.x, center.z) + middle).is_empty(): sloped = true
				for vertex: Vector3 in [a, b, c]:
					if sloped:
						ramp_vertices.append(vertex)
						ramp_uvs.append(terrain_profile.stone_uv(terrain_profile.tread_uv(Vector2(center.x + vertex.x, center.z + vertex.z), Vector2(center.x, center.z) + middle)) if authored_terrace else Vector2(vertex.x + HALF, vertex.z + HALF))
						if authored_terrace:
							var face: Vector2 = terrain_profile.tread_uv(Vector2(center.x + vertex.x, center.z + vertex.z), Vector2(center.x, center.z) + middle)
							var spec: Dictionary = terrain_profile.stair_spec(Vector2(center.x, center.z) + middle)
							# The descending connector's exposed nose is the far edge.
							if int(spec.get("axis", 0)) == 1: face.y = 1.0 - face.y
							ramp_face_uvs.append(face)
					else:
						flat_vertices.append(vertex)
						flat_uvs.append(Vector2(vertex.x + HALF, vertex.z + HALF))
			for edge in range(4):
				var exterior: bool = z == 0 if edge == 0 else x == _grid.size() - 2 if edge == 1 else z == _grid.size() - 2 if edge == 2 else x == 0
				var a: Vector3 = corners[edge]
				var b: Vector3 = corners[(edge + 1) % 4]
				if exterior:
					if exposed[edge]:
						var lower_a := _connector_bottom(Vector2(a.x, a.z)) if thin_plate and authored_terrace else a.y - TRAVERSAL_THICKNESS if thin_plate else bottom - center.y
						var lower_b := _connector_bottom(Vector2(b.x, b.z)) if thin_plate and authored_terrace else b.y - TRAVERSAL_THICKNESS if thin_plate else bottom - center.y
						if _has_connector_side(edge):
							_connector_side(wall_vertices, wall_uvs, wall_face_uvs, a, b, lower_a, lower_b)
						else:
							_wall(wall_vertices, wall_uvs, a, b, lower_a, lower_b)
				else:
					var step: Vector2 = [Vector2(0, -0.001), Vector2(0.001, 0), Vector2(0, 0.001), Vector2(-0.001, 0)][edge]
					var edge_middle := Vector2((a.x + b.x) / 2.0, (a.z + b.z) / 2.0)
					var region := edge_middle + step
					var other_a := _height_in_region(Vector2(a.x, a.z), region)
					var other_b := _height_in_region(Vector2(b.x, b.z), region)
					if a.y > other_a + 0.0001 or b.y > other_b + 0.0001:
						if authored_terrace:
							_step_wall(riser_vertices, riser_uvs, a, b, other_a, other_b, riser_face_uvs)
						else:
							_wall(wall_vertices, wall_uvs, a, b, other_a, other_b)
			if thin_plate and authored_terrace:
				# The solid slab has a sloping underside and exposed tread edges.
				for index in [0, 1, 2, 0, 2, 3]:
					var vertex: Vector3 = corners[index]
					vertex.y = _connector_bottom(Vector2(vertex.x, vertex.z))
					wall_vertices.append(vertex)
					wall_uvs.append(Vector2((center.x + vertex.x + center.z + vertex.z) / 4.5, -(center.y + vertex.y) / 4.5))
	_top.mesh = _mesh(flat_vertices, flat_uvs, materials.top)
	_ramps.mesh = _mesh(ramp_vertices, ramp_uvs, materials.ramp, ramp_face_uvs) if not ramp_vertices.is_empty() else null
	while wall_face_uvs.size() < wall_vertices.size(): wall_face_uvs.append(Vector2(0, -1))
	_sides.mesh = _mesh(wall_vertices, wall_uvs, materials.side, wall_face_uvs) if not wall_vertices.is_empty() else null
	_risers.mesh = _mesh(riser_vertices, riser_uvs, materials.get("riser", materials.side), riser_face_uvs) if not riser_vertices.is_empty() else null
	var edge_vertices := PackedVector3Array()
	var edge_uvs := PackedVector2Array()
	if authored_terrace:
		# A continuous coping lip follows the same height field as the floor.
		# No independent diagonal boards or repeated painted stair stripes.
		for edge in range(4):
			if not exposed[edge]: continue
			if _has_connector_side(edge): continue
			for index in range(_grid.size() - 1):
				var a2: Vector2
				var b2: Vector2
				match edge:
					0:
						a2 = Vector2(_grid[index], -HALF)
						b2 = Vector2(_grid[index + 1], -HALF)
					1:
						a2 = Vector2(HALF, _grid[index])
						b2 = Vector2(HALF, _grid[index + 1])
					2:
						a2 = Vector2(_grid[index + 1], HALF)
						b2 = Vector2(_grid[index], HALF)
					3:
						a2 = Vector2(-HALF, _grid[index + 1])
						b2 = Vector2(-HALF, _grid[index])
				# Both endpoints belong to this tread. Sampling each endpoint's
				# next stair region used to draw a diagonal strip over the riser.
				var inward: Vector2 = [Vector2(0, 0.0001), Vector2(-0.0001, 0), Vector2(0, -0.0001), Vector2(0.0001, 0)][edge]
				var region := (a2 + b2) * 0.5 + inward
				var a := Vector3(a2.x, _height_in_region(a2, region), a2.y)
				var b := Vector3(b2.x, _height_in_region(b2, region), b2.y)
				var outward: Vector3 = [Vector3(0, 0, -0.002), Vector3(0.002, 0, 0), Vector3(0, 0, 0.002), Vector3(-0.002, 0, 0)][edge]
				a += outward
				b += outward
				_wall(edge_vertices, edge_uvs, a, b, a.y - 0.025, b.y - 0.025)
	for direction in range(4):
		if authored_terrace: continue
		if is_zero_approx(rises[direction]): continue
		var axis: Vector2 = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][direction]
		var cross_axis := Vector2(-axis.y, axis.x)
		for distance: float in [0.25, 0.31, 0.37, 0.43, 0.49]:
			var corners: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-0.27, -0.005), Vector2(0.27, -0.005), Vector2(0.27, 0.005), Vector2(-0.27, 0.005)]:
				var point := axis * (distance + corner.y) + cross_axis * corner.x
				corners.append(Vector3(point.x, sample_height(to_global(Vector3(point.x, 0, point.y))) - global_position.y + 0.006, point.y))
			for index in [0, 2, 1, 0, 3, 2]:
				edge_vertices.append(corners[index])
				edge_uvs.append(Vector2.ZERO)
	_treads.mesh = _mesh(edge_vertices, edge_uvs, materials.trim) if not edge_vertices.is_empty() else null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	var faces := top_vertices.duplicate()
	faces.append_array(wall_vertices)
	faces.append_array(riser_vertices)
	shape.set_faces(faces)
	(_body.get_child(0) as CollisionShape3D).shape = shape
	set_meta("support_id", tile_id)
	_body.set_meta("support_id", tile_id)

func _has_connector_side(edge: int) -> bool:
	if not thin_plate or not authored_terrace: return false
	return edge in [0, 2] if absf(center.x) > absf(center.z) else edge in [1, 3]

func _connector_side(vertices: PackedVector3Array, uvs: PackedVector2Array, face_uvs: PackedVector2Array, a: Vector3, b: Vector3, bottom_a: float, bottom_b: float) -> void:
	# Expose the actual stair silhouette. A raised sloping parapet hides it
	# when the flight rises toward the camera, making it look like a ramp.
	while face_uvs.size() < vertices.size(): face_uvs.append(Vector2(0, -1))
	_wall(vertices, uvs, a, b, bottom_a, bottom_b)
	for index in range(vertices.size() - 6, vertices.size()):
		# Physical depth below THIS tread, never a global repeating stripe.
		face_uvs.append(Vector2(0, a.y - vertices[index].y))

func _connector_bottom(at: Vector2) -> float:
	if terrain_profile.has_method("connector_bottom"):
		return float(terrain_profile.connector_bottom(Vector2(center.x, center.z), at)) - center.y
	# Interpolate between the two actual landing heights, never between
	# quantized tread heights. The extra thickness stays beneath every step.
	var along_x := absf(center.x) > absf(center.z)
	var axis := Vector2.RIGHT if along_x else Vector2.DOWN
	var origin := Vector2(center.x, center.z)
	var low: float = terrain_profile.height(origin - axis * HALF)
	var high: float = terrain_profile.height(origin + axis * HALF)
	return lerpf(low, high, (at.x if along_x else at.y) + HALF) - TRAVERSAL_THICKNESS - center.y

func _height_in_region(at: Vector2, region: Vector2) -> float:
	if authored_terrace:
		return terrain_profile.height(Vector2(center.x, center.z) + at, Vector2(center.x, center.z) + region) - center.y
	var positive := 0.0
	var negative := 0.0
	var values: Array[float] = []
	var across_x := clampf((RAMP_SHOULDER - absf(at.x)) / (RAMP_SHOULDER - RAMP_HALF_WIDTH), 0, 1)
	var across_z := clampf((RAMP_SHOULDER - absf(at.y)) / (RAMP_SHOULDER - RAMP_HALF_WIDTH), 0, 1)
	# Orthogonal stairs meet at a real flat landing wider than the capsule.
	# Without this landing a capsule entering one slope hits the shoulder of
	# the next as a steep wall, even when its center-line height is continuous.
	if region.y < -LANDING_HALF: values.append(maxf(0, -at.y - LANDING_HALF) / (HALF - LANDING_HALF) * 0.5 * rises[0] * across_x)
	if region.x > LANDING_HALF: values.append(maxf(0, at.x - LANDING_HALF) / (HALF - LANDING_HALF) * 0.5 * rises[1] * across_z)
	if region.y > LANDING_HALF: values.append(maxf(0, at.y - LANDING_HALF) / (HALF - LANDING_HALF) * 0.5 * rises[2] * across_x)
	if region.x < -LANDING_HALF: values.append(maxf(0, -at.x - LANDING_HALF) / (HALF - LANDING_HALF) * 0.5 * rises[3] * across_z)
	for value: float in values:
		positive = maxf(positive, value)
		negative = minf(negative, value)
	return positive + negative

func sample_height(at: Vector3) -> float:
	var local: Vector3 = to_local(at)
	var xz := Vector2(clampf(local.x, -HALF, HALF), clampf(local.z, -HALF, HALF))
	for z in range(_grid.size() - 1):
		if xz.y < _grid[z] - 0.0001 or xz.y > _grid[z + 1] + 0.0001: continue
		for x in range(_grid.size() - 1):
			if xz.x < _grid[x] - 0.0001 or xz.x > _grid[x + 1] + 0.0001: continue
			var middle := Vector2((_grid[x] + _grid[x + 1]) / 2, (_grid[z] + _grid[z + 1]) / 2)
			var u := inverse_lerp(_grid[x], _grid[x + 1], xz.x)
			var v := inverse_lerp(_grid[z], _grid[z + 1], xz.y)
			var a := _height_in_region(Vector2(_grid[x], _grid[z]), middle)
			var b := _height_in_region(Vector2(_grid[x + 1], _grid[z]), middle)
			var c := _height_in_region(Vector2(_grid[x + 1], _grid[z + 1]), middle)
			var d := _height_in_region(Vector2(_grid[x], _grid[z + 1]), middle)
			var height := a * (1 - u) + b * (u - v) + c * v if u >= v else a * (1 - v) + c * u + d * (v - u)
			return to_global(Vector3(xz.x, height, xz.y)).y
	return global_position.y

func _step_wall(vertices: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, lower_a: float, lower_b: float, face_uvs: PackedVector2Array) -> void:
	var c := Vector3(b.x, lower_b, b.z)
	var d := Vector3(a.x, lower_a, a.z)
	for vertex: Vector3 in [a, b, c, a, c, d]:
		vertices.append(vertex)
		var across := vertex.x + HALF if absf(a.x - b.x) > absf(a.z - b.z) else vertex.z + HALF
		var face := Vector2(across, clampf((maxf(a.y, b.y) - vertex.y) / maxf(0.001, maxf(a.y - lower_a, b.y - lower_b)), 0, 1))
		uvs.append(terrain_profile.stone_uv(face, true))
		face_uvs.append(face)

func _wall(vertices: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, lower_a: float, lower_b: float) -> void:
	var c := Vector3(b.x, lower_b, b.z)
	var d := Vector3(a.x, lower_a, a.z)
	for vertex: Vector3 in [a, b, c, a, c, d]:
		vertices.append(vertex)
		# Stair subdivision can produce strips narrower than 0.01. A fixed
		# threshold mistook those X-facing spans for Z spans and collapsed
		# their UVs, producing stretched diagonal seams. X+Z unfolds the
		# authored orthogonal walls continuously, including their corners.
		var horizontal := center.x + vertex.x + center.z + vertex.z if authored_terrace else center.x + vertex.x if absf(a.x - b.x) > absf(a.z - b.z) else center.z + vertex.z
		# Masonry source contains several rows of bricks. Continuous world-space
		# UVs keep their physical scale across tiles instead of shrinking an
		# entire wall atlas into every single cell.
		uvs.append(terrain_profile.wall_uv(center + vertex) if authored_terrace and terrain_profile.has_method("wall_uv") else Vector2(horizontal / 4.5, -(center.y + vertex.y) / 4.5))

static func _mesh(vertices: PackedVector3Array, uvs: PackedVector2Array, material: Material, face_uvs: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if face_uvs.size() == vertices.size(): arrays[Mesh.ARRAY_TEX_UV2] = face_uvs
	var normals := PackedVector3Array()
	for index in range(0, vertices.size(), 3):
		var normal := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index]).normalized()
		for unused in range(3):
			normals.append(normal)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
