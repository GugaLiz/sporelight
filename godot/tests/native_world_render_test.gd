extends SceneTree
const FirstGarden = preload("res://presentation/native/first_garden_profile.gd")
## Runtime geometry checks use the actual PhysicsServer collision, rather than
## trusting a presentation label. GPU pixels remain a separate acceptance step.

const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
var checks := 0
var failures: Array[String] = []
var cases := 0
var stage: Node2D
var level_ids: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	await process_frame
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	var cloud: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json"))
	for level: Dictionary in content.levels: level_ids.append(str(level.id))
	for level: Dictionary in cloud.levels: level_ids.append(str(level.id))
	for id: String in level_ids:
		var world: RefCounted = Cloud.new(id) if id.begins_with("cloud-") else World.new(id)
		await _validate_state(world, id + "/initial")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if not str(entry.name).begins_with("authored/"): continue
		var world: RefCounted = World.new(str(entry.levelId), entry.get("saved", {}))
		var last_topology := ""
		for step: Dictionary in entry.steps:
			var command: Dictionary = step.command
			if command.kind == "move": world.move(str(command.value))
			elif command.kind == "act": world.act(str(command.value), bool(command.get("internal", false)))
			elif command.kind == "undo": world.undo()
			var topology := JSON.stringify(world.tiles())
			if topology != last_topology:
				last_topology = topology
				await _validate_state(world, str(entry.name) + "/" + str(command.value))
		await _validate_state(world, str(entry.name) + "/final")
	var clouds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for entry: Dictionary in clouds.levels:
		var world := Cloud.new(str(entry.id))
		var last_topology := ""
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "move": world.move(str(step.command.value))
			else: world.act(str(step.command.value))
			var topology := JSON.stringify(world.tiles())
			if topology != last_topology:
				last_topology = topology
				await _validate_state(world, str(entry.id) + "/" + str(step.command.value))
		await _validate_state(world, str(entry.id) + "/final")
	var rotating := World.new("1-3")
	var first: Dictionary = rotating.snapshot()
	var after: Dictionary = first.duplicate(true)
	after.turns.garden = (int(after.turns.get("garden", 0)) + 1) % 4
	# The fixture mechanism ID is discovered from content, not assumed.
	for module: Dictionary in rotating.level.modules:
		if module.kind != "rotate": continue
		after = first.duplicate(true)
		after.turns[module.id] = (int(first.turns.get(module.id, 0)) + 1) % 4
		stage.set_world(rotating)
		for local: Array in module.shape:
			var id := "m:%s:%s:%s" % [module.id, str(local[0]), str(local[1])]
			var a: Vector3 = stage.sample_tile_position(first, after, id, 0)
			var middle: Vector3 = stage.sample_tile_position(first, after, id, 0.5)
			var pivot := Vector2(float(module.x), float(module.z))
			_check(absf(Vector2(a.x, a.z).distance_to(pivot) - Vector2(middle.x, middle.z).distance_to(pivot)) < 0.0001, "rotating passenger follows a circular orbit")
	var body: CharacterBody3D = stage.get_actor_body("luvie")
	var art: AnimatedSprite3D = body.get_node("Visual/Art")
	_check(not art.no_depth_test, "actor participates in native depth")
	_check(art.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS, "actor uses opaque alpha depth prepass")
	_check(body.collision_layer == 2 and body.collision_mask == 1, "actor/world layers do not collide actor against actor")
	_check(stage.asset_errors().is_empty(), "native asset resources load")
	await _state_feedback_contract()
	var result := {"suite": "native-world-render-contract", "passed": failures.is_empty(), "checks": checks, "states": cases, "levels": level_ids, "failures": failures, "gpuPixelsVerified": false, "scope": "Actual 3D mesh/collider support samples, level-independent flat landings and bounded ramps, topology refresh caching and circular module motion. GPU appearance and moving character contact require separate checks."}
	print(JSON.stringify(result))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _state_feedback_contract() -> void:
	var dark := World.new("3-1")
	stage.set_world(dark)
	var hidden: Dictionary = {}
	for tile: Dictionary in dark.tiles():
		if not dark.visible(tile):
			hidden = tile
			break
	_check(not hidden.is_empty(), "dark garden has undiscovered supports")
	if not hidden.is_empty():
		var before := int(stage.render_statistics().meshRebuilds)
		_check(not stage._surfaces[str(hidden.id)].visible, "unknown support initially hidden")
		dark.state.discovered.append(str(hidden.id))
		stage.refresh_world(dark, true)
		_check(stage._surfaces[str(hidden.id)].visible, "discovery reveals same cached geometry")
		_check(int(stage.render_statistics().meshRebuilds) == before, "discovery does not rebuild unchanged meshes")
	var cloud := Cloud.new("cloud-1")
	stage.set_world(cloud)
	var seed: Node3D = stage._props_nodes.get("mark:seed")
	_check(seed != null and seed.get_child_count() > 0, "cloud seed is visibly present before pickup")
	cloud.state.cloudSeed = true
	stage.refresh_world(cloud, true)
	seed = stage._props_nodes.get("mark:seed")
	_check(seed != null and seed.get_child_count() == 0, "cloud seed visual disappears after pickup")
	stage.set_world(World.new("1-1"))
	var body: CharacterBody3D = stage.get_actor_body("luvie")
	var at := body.position
	stage.set_actor_mode("luvie", true)
	stage.update_actor_visual("luvie", Vector3.ZERO)
	_check(str(body.get_node("Visual/Art").animation) == "roll", "rolling uses the retained ball artwork")
	stage.set_actor_mode("buddy", true)
	stage.update_actor_visual("buddy", Vector3.ZERO)
	_check(str(stage.get_actor_body("buddy").get_node("Visual/Art").animation) == "roll", "partner rolling also has a persistent ball representation")
	stage.set_actor_mode("buddy", false)
	stage.set_actor_mode("luvie", false)
	stage.play_emote("luvie", "jump")
	stage.update_actor_visual("luvie", Vector3.ZERO, "front", "")
	_check(str(body.get_node("Visual/Art").animation) == "jump", "empty motion update does not cancel jump")
	var player: AnimationPlayer = body.get_node("Visual/AnimationPlayer")
	player.advance(0.26)
	_check(float(body.get_node("Visual/Art").position.y) > 0.1, "native AnimationPlayer performs a visible jump")
	_check(body.position == at, "cosmetic jump preserves physical support root")
	player.advance(0.3)
	stage.set_settings({"quality": "soft", "particles": false, "dynamicLight": false})
	_check(stage._viewport.msaa_3d == Viewport.MSAA_DISABLED, "soft quality uses lower render cost")
	_check(not stage._motes.visible and not stage._motes.emitting, "particles setting controls native effect")
	_check(stage._scene.get_node("Sun").light_energy == 0.0, "dynamic light setting controls decorative lighting")

func _validate_state(world: RefCounted, label: String) -> void:
	stage.set_world(world)
	await physics_frame
	await physics_frame
	cases += 1
	var tiles: Array = world.tiles()
	var space: PhysicsDirectSpaceState3D = stage._scene.get_world_3d().direct_space_state
	for tile: Dictionary in tiles:
		if not world.visible(tile) or tile.get("solid", false): continue
		var at: Vector3 = stage.tile_position(tile)
		var expected := float(tile.h) * 0.65
		var surface: Node3D = stage._surfaces[str(tile.id)]
		if bool(surface.thin_plate) and surface._sides.mesh != null:
			var side_arrays: Array = surface._sides.mesh.surface_get_arrays(0)
			var max_thickness := 0.0
			var vertices: PackedVector3Array = side_arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = side_arrays[Mesh.ARRAY_NORMAL]
			for index in range(0, vertices.size(), 6):
				# Closed soffit triangles are interleaved with the side quads.
				# Their diagonal span is not slab thickness.
				if normals[index].y < -0.5: continue
				# At a true riser, the same X/Z has two valid top heights.
				# Measure each emitted side quad against its own top endpoints.
				max_thickness = maxf(max_thickness, vertices[index].y - vertices[index + 5].y)
				max_thickness = maxf(max_thickness, vertices[index + 1].y - vertices[index + 2].y)
			# Authored stairs have a diagonal soffit spanning both end landings.
			# Bound the deepest riser nose against that plane, including the
			# short flat ends rather than assuming a constant 0.20 thickness.
			var limit := 0.20
			if surface.terrain_profile == FirstGarden:
				for spec: Vector3 in [FirstGarden.EAST, FirstGarden.SOUTH]:
					for step_index in range(int(spec.z)):
						var distance := spec.x + step_index * (spec.y - spec.x) / spec.z
						var stair_height := 0.65 * (step_index + 1) / spec.z
						limit = maxf(limit, 0.20 + absf(stair_height - 0.65 * (distance - 0.5)))
			_check(max_thickness <= limit + 0.0002, label + "/" + str(tile.id) + ": solid stair side stays below tread and above sloping soffit: " + str(max_thickness))
		# The south grown bridge uses its entire length for real stairs; its
		# center is a tread between the two islands, not a flat h=0 landing.
		if bool(surface.authored_terrace): expected = surface.terrain_profile.height(Vector2(float(tile.x), float(tile.z)))
		_check(absf(stage.support_height(at, str(tile.id)) - expected) < 0.0001, label + "/" + str(tile.id) + ": center matches authored support")
		for offset: Vector2 in [Vector2.ZERO, Vector2(0.2, 0), Vector2(-0.2, 0), Vector2(0, 0.2), Vector2(0, -0.2), Vector2(0.43, 0.43), Vector2(-0.43, -0.43)]:
			var sample: Vector3 = stage.physical_position(stage.logical_position(at) + Vector3(offset.x, 0, offset.y))
			var height: float = stage.support_height(sample, str(tile.id))
			var ray := PhysicsRayQueryParameters3D.create(Vector3(sample.x, height + 0.08, sample.z), Vector3(sample.x, height - 0.08, sample.z), 1)
			ray.hit_back_faces = true
			var hit: Dictionary = space.intersect_ray(ray)
			_check(not hit.is_empty(), label + "/" + str(tile.id) + ": collision exists at sampled support " + str(offset))
			if not hit.is_empty():
				_check(absf(float(hit.position.y) - height) < 0.002, label + "/" + str(tile.id) + ": physical contact matches visible support")
			if absf(offset.x) > 0.4 and absf(offset.y) > 0.4:
				if bool(surface.authored_terrace):
					var logical: Vector3 = stage.logical_position(sample)
					var designed: float = surface.terrain_profile.height(Vector2(logical.x, logical.z))
					_check(absf(height - designed) < 0.03, label + "/" + str(tile.id) + ": authored terrace follows its continuous architectural profile")
				else:
					_check(absf(height - expected) < 0.0001, label + "/" + str(tile.id) + ": ramp does not warp landing corners")
		for neighbor: Dictionary in world.neighbors(str(tile.id), "buddy", tiles):
			var target: Vector3 = stage.tile_position(neighbor)
			var seam: Vector3 = stage.physical_position(stage.logical_position(at).lerp(stage.logical_position(target), 0.5))
			var h1: float = stage.support_height(seam, str(tile.id))
			var h2: float = stage.support_height(seam, str(neighbor.id))
			_check(absf(h1 - h2) < 0.0001, label + "/" + str(tile.id) + ": adjacent support seam joins " + str(neighbor.id))
			var profile: Dictionary = stage.traversal_profile(str(tile.id), str(neighbor.id))
			if profile.get("slope", false):
				_check(float(profile.half_width) - float(profile.center_clearance) >= 0.1799, label + ": slope portal reserves actual capsule radius and safety margin")
	var stats: Dictionary = stage.render_statistics()
	stage.refresh_world(world, true)
	_check(int(stage.render_statistics().meshRebuilds) == int(stats.meshRebuilds), label + ": unchanged world does not rebuild meshes")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		if failures.size() <= 12: push_error(label)
