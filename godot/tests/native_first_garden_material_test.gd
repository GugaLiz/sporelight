extends SceneTree
const FirstGarden = preload("res://presentation/native/first_garden_profile.gd")

const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var world := World.new("1-1")
	stage.set_world(world)
	await physics_frame
	await physics_frame
	for id: String in ["f:-1:2", "f:0:2", "f:-1:3", "f:0:3"]:
		var center: Vector3 = stage.tile_position_id(id)
		for x: float in [-0.48, -0.22, 0, 0.22, 0.48]:
			for z: float in [-0.48, -0.22, 0, 0.22, 0.48]:
				_check(absf(stage.support_height(center + Vector3(x, 0, z), id) + 0.65) < 0.0001, "south island is flat before a road exists: " + id)
	_check(not stage._surfaces.has("g:root:0:1"), "unplanted south gap has no connector")
	for surface_id: String in stage._surfaces:
		var wall_surface: Node3D = stage._surfaces[surface_id]
		for part: MeshInstance3D in [wall_surface._sides, wall_surface._treads]:
			if part.mesh == null: continue
			var arrays: Array = part.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for index in range(0, vertices.size(), 6):
				var span := vertices[index + 1] - vertices[index]
				var width := Vector2(span.x, span.z).length()
				_check(absf(absf(uvs[index + 1].x - uvs[index].x) * 4.5 - width) < 0.00001, "wall UV width preserves even the narrowest stair subdivision")
	# Probe the first lane as well as both tile seams: the former entrance
	# overlap made its left edge a tilted wedge despite central flat treads.
	for z: float in [-0.38, -0.46, -0.54, -0.62, -0.70, -0.78, -0.86, -0.94]:
		var baseline: float = stage.support_height(stage.physical_position(Vector3(3, 0, z)), "f:3:%d" % int(roundf(z)))
		for x: float in [1.51, 1.6, 1.78, 2.49, 2.51, 3.49, 3.51, 4.49]:
			var id := "f:%d:%d" % [int(roundf(x)), int(roundf(z))]
			_check(absf(stage.support_height(stage.physical_position(Vector3(x, 0, z)), id) - baseline) < 0.0001, "one level across the entire rear stair row")
	for id: String in ["f:2:0", "f:2:-1", "f:3:0", "f:3:-1", "f:4:0", "f:4:-1"]:
		var stairs: Node3D = stage._surfaces[id]
		if stairs._ramps.mesh == null: continue
		var stair_normals: PackedVector3Array = stairs._ramps.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		for normal: Vector3 in stair_normals:
			_check(normal.y > 0.999, "every stair lane has horizontal treads including its west edge")
		if stairs._treads.mesh == null: continue
		var coping: PackedVector3Array = stairs._treads.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in range(0, coping.size(), 6):
			_check(absf(coping[index].y - coping[index + 1].y) < 0.0001, "coping follows each horizontal tread without diagonal shortcuts")
	var floor: MeshInstance3D = stage._surfaces["f:-1:0"]._top
	_check(floor.mesh.surface_get_material(0) is StandardMaterial3D, "original paving is a texture material, not replacement procedural stone")
	_check(floor.mesh.surface_get_material(0).albedo_texture == stage._texture("paving-valley"), "uses original valley paving")
	# The front tile is now a complete landing; the flight starts behind it.
	var surface: Node3D = stage._surfaces["f:3:-1"]
	var outer_wall: MeshInstance3D = stage._surfaces["f:4:-1"]._sides
	_check(outer_wall.mesh.surface_get_material(0).get_shader_parameter("original_stone") == stage._texture("paving-valley"), "island walls share the original irregular paving stone")
	_check(surface._ramps.mesh.surface_get_material(0).get_shader_parameter("original_stair") == stage._texture("stairs"), "uses original stair texture for treads")
	_check(surface._risers.mesh.surface_get_material(0).get_shader_parameter("original_stair") == stage._texture("stairs"), "uses original stair texture for risers")
	for part: MeshInstance3D in [surface._ramps, surface._risers]:
		var face_arrays: Array = part.mesh.surface_get_arrays(0)
		var face_uvs: PackedVector2Array = face_arrays[Mesh.ARRAY_TEX_UV2]
		_check(face_uvs.size() == face_arrays[Mesh.ARRAY_VERTEX].size(), "each stair vertex has independent face coordinates for grain and nosing")
		var low := Vector2.ONE
		var high := Vector2.ZERO
		for uv in face_uvs:
			low = low.min(uv)
			high = high.max(uv)
		_check(low.is_equal_approx(Vector2.ZERO) and high.is_equal_approx(Vector2.ONE), "tread and riser coordinates cover both edges without collapsing on narrow subdivisions")
	var data: Array = surface._ramps.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	for normal: Vector3 in normals:
		_check(normal.y > 0.999, "rear stairs have flat treads rather than bevelled ramp faces")
	data = surface._risers.mesh.surface_get_arrays(0)
	normals = data[Mesh.ARRAY_NORMAL]
	_check(not normals.is_empty(), "stair risers have actual mesh faces")
	for normal: Vector3 in normals:
		_check(absf(normal.y) < 0.001, "stair risers are vertical")
	var planter: Node3D = stage._props_nodes["mark:core"]
	_check(planter.get_child_count() == 2 and planter.get_child(0) is Sprite3D and planter.get_child(1).mesh is PlaneMesh, "preserve the authored flowerbed with only a floor contact patch")
	_check(planter.get_child(0).texture == stage._texture("flower"), "complete original flowerbed image including its stone base")
	var patch: MeshInstance3D = planter.get_node("ContactPatch")
	_check(planter.get_meta("tile_id") == "f:3:-2" and is_equal_approx(planter.position.y, 1.30), "flowerbed belongs to the upper platform")
	_check(patch.global_position.z - patch.mesh.size.y / 2.0 > -2.5, "flowerbed footprint remains inside the upper rear edge")
	_check(patch.global_position.z + patch.mesh.size.y / 2.0 < -FirstGarden.REAR.y - 0.15, "flowerbed leaves clearance before the stair flight")
	world.act("grow:root:down")
	stage.refresh_world(world, true)
	await physics_frame
	_check(stage._surfaces.has("g:root:0:1"), "south stair connector appears only after planting")
	var bridge: Node3D = stage._surfaces["g:root:0:1"]
	_check(bridge._ramps.mesh.surface_get_material(0).get_shader_parameter("connector") == true, "short flight has its own stone edge treatment")
	_check(bridge._sides.mesh.surface_get_material(0).get_shader_parameter("stair_side") == true, "short flight side uses stone courses proportioned to slab thickness")
	_check(bridge._treads.mesh == null, "tread lips belong to solid side faces without overlay strips")
	for id: String in ["f:-1:2", "f:0:2", "f:-1:3", "f:0:3"]:
		var center: Vector3 = stage.tile_position_id(id)
		_check(absf(stage.support_height(center + Vector3(0, 0, -0.48), id) + 0.65) < 0.0001, "south landing stays flat after planting")
	_check_connector_soffit(bridge, false)
	var east := World.new("1-1")
	east.act("grow:root:right")
	east.state.actors = {"luvie": "f:3:0", "buddy": "f:3:0"}
	_check(not east.commands().any(func(command: Dictionary) -> bool: return command.id == "repair"), "old downstairs location no longer offers planting")
	east.state.actors = {"luvie": "f:3:-2", "buddy": "f:3:-2"}
	_check(east.commands().any(func(command: Dictionary) -> bool: return command.id == "repair"), "upper flowerbed offers planting")
	stage.set_world(east)
	_check_connector_soffit(stage._surfaces["g:root:1:0"], true)
	stage.set_world(world)
	_check_growth_motion(stage, "right", "g:root:1:0", Vector3.LEFT)
	_check_growth_motion(stage, "down", "g:root:0:1", Vector3.BACK)
	stage.set_world(world)
	world.state.completed = true
	stage.refresh_world(world, true)
	stage.update_actor_visual("luvie", Vector3.ZERO, "front", "repair")
	var actor_art: AnimatedSprite3D = stage.get_actor_body("luvie").get_node("Visual/Art")
	_check(actor_art.animation == "complete", "active completion transaction may salute")
	stage.clear_motion()
	_check(actor_art.animation == "idle_front", "return from completed transaction restores standing idle")
	stage.update_actor_visual("luvie", Vector3(1, 0, 0), "right")
	stage.update_actor_visual("luvie", Vector3.ZERO, "right")
	_check(actor_art.animation == "idle_right", "stopping in completed garden never reapplies salute")
	stage.reset_actor_actions()
	_check(actor_art.animation == "idle_right", "completed save/reset keeps ordinary idle facing")
	print(JSON.stringify({"suite": "first-garden-original-materials", "passed": failures.is_empty(), "checks": checks, "failures": failures}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_growth_motion(stage: Node, direction: String, id: String, axis: Vector3) -> void:
	var initial := World.new("1-1")
	var before: Dictionary = initial.snapshot()
	initial.act("grow:root:" + direction)
	var after: Dictionary = initial.snapshot()
	stage.set_world(initial.fork(before))
	stage.set_motion(before, after, 0.0, "grow:root:" + direction)
	var bridge: Node3D = stage._surfaces[id]
	var rebuilds: int = bridge.geometry_rebuilds
	var originals: Dictionary = bridge._growth_overrides.duplicate()
	_check(not originals.is_empty(), direction + " begins hidden with isolated materials")
	for progress: float in [0.0, 0.25, 0.5, 0.75]:
		stage.set_motion(before, after, progress, "grow:root:" + direction)
		_check(bridge.scale == FirstGarden.tile_scale(bridge.center.x) and bridge.geometry_rebuilds == rebuilds, "reveal never compresses steps or rebuilds geometry")
		for part: MeshInstance3D in originals:
			var material: ShaderMaterial = part.material_override
			_check(material.get_shader_parameter("growth_axis") == axis, direction + " every face reveals high to low")
			_check(is_equal_approx(material.get_shader_parameter("growth_progress"), progress * progress * (3 - 2 * progress)), "all faces share one continuous advancing edge")
			_check(material != originals[part], "growth cannot mutate shared final material")
		var foundation: MeshInstance3D = stage._surfaces["f:-1:0"]._top
		_check(foundation.get_active_material(0) is StandardMaterial3D, "existing paving remains unaffected")
	bridge.set_growth_reveal(0.5, false)
	for part: MeshInstance3D in originals:
		_check(part.material_override.get_shader_parameter("growth_glow") == false, "reduced motion suppresses frontier light")
	stage.set_motion(before, after, 1.0, "grow:root:" + direction)
	for part: MeshInstance3D in originals:
		_check(part.material_override == originals[part], "completed reveal restores exact original materials")
	stage.set_motion(before, after, 0.5, "grow:root:" + direction)
	stage.clear_motion(false)
	_check(bridge._growth_overrides.is_empty(), "clear releases all temporary reveal materials")
	stage.set_world(initial.fork(before))
	_check(not stage._surfaces.has(id), "cancel removes uncommitted stair without stale clipping")
	stage.set_world(initial)
	_check(stage._surfaces[id]._growth_overrides.is_empty(), "re-entering grown state shows complete stairs")

func _check_connector_soffit(bridge: Node3D, east: bool) -> void:
	var arrays: Array = bridge._sides.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var face_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	_check(face_uvs.size() == vertices.size(), "side faces carry physical depth below each own tread")
	var underside_count := 0
	var side_count := 0
	for index in range(0, vertices.size(), 6):
		if absf(normals[index].y) > 0.01 or face_uvs[index].y < 0.0: continue
		side_count += 1
		var middle := bridge.to_global((vertices[index] + vertices[index + 1]) * 0.5)
		var expected: float = bridge.sample_height(middle)
		_check(absf(middle.y - expected) < 0.00001, "exposed stair side ends at its tread, never above it as a parapet")
		for corner in range(6):
			var at := bridge.to_global(vertices[index + corner])
			_check(absf(at.y + face_uvs[index + corner].y - expected) < 0.00001, "stone lip depth follows every tread without crossing the riser")
	for index in range(vertices.size()):
		_check(normals[index].y < 0.5, "no raised sloping cap can hide the visible stair silhouette")
		if normals[index].y > -0.5: continue
		underside_count += 1
		var at := bridge.to_global(vertices[index])
		var distance := (at.x - 0.5) / (1.0 + FirstGarden.EAST_GAP_EXTRA) if east else at.z - 0.5
		var expected := (0.65 if east else -0.65) * distance - 0.20
		_check(absf(at.y - expected) < 0.00001, "connector underside stays on one continuous landing-to-landing plane")
		_check(bridge.sample_height(at) - at.y > 0.07, "sloping slab remains below the stepped walking surface")
	_check(underside_count > 0, "connector has a closed downward-facing underside")
	_check(side_count > 0, "connector retains solid closed sides below exposed tread edges")
