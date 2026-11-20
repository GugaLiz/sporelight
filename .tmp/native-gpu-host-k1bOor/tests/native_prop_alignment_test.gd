extends SceneTree
## Real mesh/support alignment, including moving modules and resource reuse.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Factory = preload("res://core/world_factory.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const IDS = ["1-1", "1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4", "cloud-1", "cloud-2", "cloud-3"]
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var motions := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	for id: String in IDS: check_static(id)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if not str(entry.name).begins_with("authored/"): continue
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			var first := World.new(str(entry.levelId), before)
			var last := World.new(str(entry.levelId), step.snapshot)
			var moving := ""
			for module: Dictionary in first.level.get("modules", []):
				if stage._module_changes_between(first, last, module):
					moving = str(module.id)
					break
			if not moving.is_empty():
				check_motion(first, last, moving, str(step.command.value))
				check_motion(last, first, moving, "undo")
			before = step.snapshot
	var cloud_fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for entry: Dictionary in cloud_fixture.levels:
		var previous: Dictionary = entry.initial
		for step: Dictionary in entry.steps:
			var action := str(step.command.value)
			if action in ["rotate", "lift"]:
				var first := Cloud.new(str(entry.id), previous)
				var last := Cloud.new(str(entry.id), step.snapshot)
				var kind := "cloud:bridge" if action == "rotate" else "cloud:lift"
				check_motion(first, last, kind, action)
				check_motion(last, first, kind, "undo")
				break
			previous = step.snapshot
	# Switching back after conformed/rotated geometry must restore the exact
	# accepted first-garden torus and its original placement.
	check_static("1-1")
	check_static("1-2")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-prop-alignment", "checks": checks, "motions": motions, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func check_static(id: String) -> void:
	stage.clear_motion(false)
	var world: RefCounted = Factory.create(id)
	var snapshot: Dictionary = world.snapshot()
	stage.set_world(world)
	var preserve := id in ["1-1", "1-2"]
	for key: String in stage._props_nodes:
		var node: Node3D = stage._props_nodes[key]
		var tile_id := str(node.get_meta("tile_id"))
		var tile: Dictionary = stage._tile_map[tile_id]
		check_instrument(node,id+"/"+key)
		var expected: Vector3 = stage.tile_position(tile)
		if not preserve: expected.y = stage._surfaces[tile_id].sample_height(expected)
		check(node.global_position.is_equal_approx(expected), id + " " + key + " rests at its support centre")
		if key.begins_with("mark:"):
			stage.set_interaction_context({"id": key, "tile": tile})
			if preserve:
				check(stage._interaction_ring.mesh is TorusMesh and stage._interaction_ring.basis.is_equal_approx(Basis.IDENTITY), id + " retains original torus and orientation")
				check(stage._interaction_ring.position.is_equal_approx(stage.tile_position(tile) + Vector3(0, 0.025, 0)), id + " retains original ring anchor")
			else:
				check_ring(stage._surfaces[tile_id], id + " " + key)
				check(stage._interaction_ring.global_position.is_equal_approx(node.global_position), id + " object and ring share the support centre")
		if not preserve:
			for child: Node in node.get_children():
				if child is Sprite3D and child.name == "lilypad" and absf(child.rotation.x + PI / 2) < 0.0001:
					check(child.offset == Vector2.ZERO, id + " flat leaf has no rotated sprite foot offset")
	for mark: Dictionary in world.level.get("marks", []):
		if not preserve and str(mark.get("kind", "")) in ["rest", "observe", "note"]:
			var node: Node3D = stage._props_nodes.get("mark:" + str(mark.id))
			if node != null:
				if id.begins_with("cloud-"):
					# Original cloud stories have no physical bouquet until found.
					check(node.get_child_count() == 0,id+" undiscovered original story adds no false ground prop")
				else:
					var alias := "flowers" if str(mark.kind) in ["rest","observe"] else "blue_flowers"
					var art: Sprite3D = node.get_node_or_null(alias)
					check(art != null,id+" observation uses original art "+alias)
					if art != null:
						check(art.position == Vector3.ZERO,id+" observation art is centred on its interaction")
						if alias == "flowers": check(is_equal_approx(art.texture.get_width()*art.pixel_size,34.0*sqrt(2.0)/70.0),id+" original story bouquet34px ratio")
	check(world.snapshot() == snapshot, id + " presentation leaves rules unchanged")

func check_ring(surface: Node3D, label: String) -> void:
	var ring: MeshInstance3D = stage._interaction_ring
	check(ring.visible and ring.mesh is ArrayMesh, label + " has a conformed ring")
	if not ring.mesh is ArrayMesh: return
	var arrays: Array = ring.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var error := 0.0
	var span := 0.0
	for vertex: Vector3 in vertices:
		var at := ring.to_global(vertex)
		var local := surface.to_local(at)
		var radius := Vector2(local.x, local.z).length()
		span = maxf(span, maxf(0.35 * cos(PI / 128) - radius, radius - 0.38))
	for index in range(0, vertices.size(), 3):
		var a := ring.to_global(vertices[index])
		var b := ring.to_global(vertices[index + 1])
		var c := ring.to_global(vertices[index + 2])
		if (b - a).cross(c - a).length_squared() < 0.0000000001: continue
		# Step noses have two valid endpoint heights. Inspect triangle interiors
		# instead: this also catches a strip incorrectly bridging a vertical step.
		for weights: Vector3 in [Vector3(0.333, 0.333, 0.334), Vector3(0.6, 0.2, 0.2)]:
			var at := a * weights.x + b * weights.y + c * weights.z
			error = maxf(error, absf(at.y - surface.sample_height(at) - 0.018))
	check(error < 0.0001, label + " ring triangle interiors follow actual treads without sloped bridges")
	check(span < 0.0001, label + " clipped ring stays inside its authored annulus")
	var identity: RID = ring.mesh.get_rid()
	stage.set_interaction_context(stage._interaction_context)
	check(ring.mesh.get_rid() == identity, label + " unchanged context reuses the mesh RID")

func check_motion(first: RefCounted, last: RefCounted, moving: String, action: String) -> void:
	motions += 1
	var label := str(first.level.id) + "/" + action + "/" + str(motions)
	stage.clear_motion(false)
	stage.set_world(first)
	var before: Dictionary = first.snapshot()
	var after: Dictionary = last.snapshot()
	var target := ""
	for tile: Dictionary in first.tiles():
		var on_module := str(tile.get("module", "")) == moving
		var on_cloud := moving.begins_with("cloud:") and str(tile.get("kind", "")) == moving.trim_prefix("cloud:")
		if (on_module or on_cloud) and stage._surfaces.has(str(tile.id)):
			target = str(tile.id)
			break
	check(not target.is_empty(), label + " has an actual moving support")
	if target.is_empty(): return
	stage.set_motion(before, after, 0.0, action)
	stage.set_interaction_context({"id": "test", "tile": first.point_for(target)})
	if moving == "cloud:bridge":
		for tile: Dictionary in last.tiles():
			if str(tile.kind) == "bridge" and str(stage._motion_cloud_bridge.origins[str(tile.id)].id) == target:
				# Production context may already name the destination snapshot.
				stage.set_interaction_context({"id": "test", "tile": tile})
				break
	var ring: MeshInstance3D = stage._interaction_ring
	var mesh_id: RID = ring.mesh.get_rid()
	var builds: int = stage._build_count
	for progress: float in [0.1, 0.25, 0.5, 0.75, 0.99]:
		stage.set_motion(before, after, progress, action)
		check(ring.mesh.get_rid() == mesh_id and stage._build_count == builds, label + " moving frames reuse ring and terrain geometry")
		var support: Node3D = stage._surfaces[target]
		var expected := support.global_position
		expected.y = support.sample_height(expected)
		check(ring.global_position.is_equal_approx(expected), label + " ring follows current support, not preview destination")
		check_ring(support, label + "/" + str(progress))
		for node: Node3D in stage._props_nodes.values():
			var own: Node3D = stage._surface_for_support(str(node.get_meta("tile_id", "")))
			if own == null: continue
			var at := own.global_position
			at.y = own.sample_height(at)
			check(node.global_position.is_equal_approx(at), label + " prop follows current source support")
			check_instrument(node,label+"/"+str(progress)+"/"+str(node.name))
	check(first.snapshot() == before and last.snapshot() == after, label + " sampling preserves both transaction snapshots")
	stage.set_motion(before, after, 1.0, action)
	if stage._surfaces.has(target): check_ring(stage._surfaces[target], label + "/docked")

func check_instrument(node: Node3D,label: String) -> void:
	var base: MeshInstance3D = node.get_node_or_null("InstrumentBase")
	if base == null: return
	var cylinder := base.mesh as CylinderMesh
	check(is_equal_approx(cylinder.top_radius,.19) and is_equal_approx(cylinder.bottom_radius,.1995) and is_equal_approx(cylinder.height,.12),label+" frozen base size")
	var valid := true
	for index in range(32):
		var angle := TAU*index/32.0
		var foot := base.to_global(Vector3(cos(angle)*cylinder.bottom_radius,-cylinder.height*.5,sin(angle)*cylinder.bottom_radius))
		var supported := false
		for support: Node3D in stage._surfaces.values():
			if not support.is_visible_in_tree(): continue
			var local := support.to_local(foot)
			if absf(local.x)>.5001 or absf(local.z)>.5001: continue
			if absf(support.sample_height(foot)-foot.y)<.001: supported = true; break
		if not supported: valid = false
	check(valid,label+" entire circular base supported on current real deck")
	var tile: Dictionary = stage._tile_map.get(str(node.get_meta("tile_id")),{})
	if tile.is_empty() or stage._motion_before != null: return
	for who: String in ["luvie","buddy"]:
		var stance: Vector3 = stage.actor_rest_position(tile,who)
		var separation := Vector2(stance.x-base.global_position.x,stance.z-base.global_position.z).length()
		check(separation>cylinder.bottom_radius+(.16 if who == "luvie" else .13),label+" default "+who+" capsule clears base")
