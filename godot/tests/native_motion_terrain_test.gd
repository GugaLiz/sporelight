extends SceneTree
## External stairs retract when supports separate. Internal stairs remain rigid.
## Destination stairs appear only after docking, with no intermediate rebuild.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
var cases: Array = []
var stage: Node2D
var reference: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	stage = Stage.new()
	reference = Stage.new()
	root.add_child(stage)
	root.add_child(reference)
	await process_frame
	stage.set_process(false)
	reference.set_process(false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if not str(entry.name).begins_with("authored/"): continue
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			var first := World.new(str(entry.levelId), before)
			var last := World.new(str(entry.levelId), step.snapshot)
			if _moves_module(first, last):
				for reverse: bool in [false, true]:
					_test_pair(last if reverse else first, first if reverse else last, str(step.command.value), reverse)
			before = step.snapshot
	# The authored route contains only the first quarter-turn. Check every
	# orientation, including the 3->0 wrap, with passengers on the garden.
	for turn in range(4):
		var first := World.new("1-3")
		first.state.turns.garden = turn
		first.state.actors = {"luvie": "m:garden:0:0", "buddy": "m:garden:0:0"}
		var last: RefCounted = first.fork(first.snapshot())
		last.state.turns.garden = (turn + 1) % 4
		_test_pair(first, last, "turn:garden", false)
	print(JSON.stringify({"suite": "native-motion-terrain", "passed": failures.is_empty(), "checks": checks, "cases": cases, "failures": failures, "gpuPixelsVerified": false}))
	stage.queue_free()
	reference.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _moves_module(first: RefCounted, last: RefCounted) -> bool:
	for module: Dictionary in first.level.get("modules", []):
		var id := str(module.id)
		if str(module.kind) == "rotate" and first.state.turns[id] != last.state.turns[id]: return true
		if first.module_point(id, [0, 0]) != last.module_point(id, [0, 0]): return true
	return false

func _test_pair(first: RefCounted, last: RefCounted, action: String, reverse: bool) -> void:
	var label := str(first.level.id) + "/" + action + "/reverse=" + str(reverse) + "/" + str(cases.size())
	var before: Dictionary = first.snapshot()
	var after: Dictionary = last.snapshot()
	stage.clear_motion(false)
	stage.set_world(first)
	reference.set_world(first)
	var expected_rises := {}
	var moving_modules := {}
	for module: Dictionary in first.level.get("modules", []):
		var module_id := str(module.id)
		if (str(module.kind) == "rotate" and first.state.turns[module_id] != last.state.turns[module_id]) or first.module_point(module_id, [0, 0]) != last.module_point(module_id, [0, 0]):
			moving_modules[module_id] = true
	for tile: Dictionary in first.tiles():
		var values: Array = reference._surfaces[str(tile.id)].rises.duplicate()
		for edge in range(4):
			for neighbor: Dictionary in first.tiles():
				if not is_equal_approx(float(neighbor.x), float(tile.x) + Stage.DIRECTIONS[edge].x) or not is_equal_approx(float(neighbor.z), float(tile.z) + Stage.DIRECTIONS[edge].y): continue
				var own := str(tile.get("module", ""))
				var other := str(neighbor.get("module", ""))
				if own != other and (moving_modules.has(own) or moving_modules.has(other)): values[edge] = 0.0
		expected_rises[str(tile.id)] = values
	stage.set_motion(before, after, 0.0, action)
	_check(stage._motion_geometry_active, label + " uses departure geometry")
	var meshes := {}
	var rises := {}
	var builds: int = stage._build_count
	var closed_seams := 0
	for id: String in stage._surfaces:
		var surface: Node3D = stage._surfaces[id]
		var original: Node3D = reference._surfaces[id]
		_check(surface.rises == expected_rises[id], label + "/" + id + " external stairs retract and internal stairs remain")
		# This independent stage supplies the post-retraction rigid support oracle.
		var active_rises: Array[float] = []
		active_rises.assign(expected_rises[id])
		var exposed: Array[bool] = [true, true, true, true]
		original.configure(first.point_for(id), active_rises, exposed, original.center.y - 0.67, reference._terrain_materials())
		meshes[id] = _mesh_identity(surface)
		rises[id] = surface.rises.duplicate()
		var tile: Dictionary = first.point_for(id)
		for edge in range(4):
			var direction: Vector2 = Stage.DIRECTIONS[edge]
			for neighbor: Dictionary in first.tiles():
				if not is_equal_approx(float(neighbor.x), float(tile.x) + direction.x) or not is_equal_approx(float(neighbor.z), float(tile.z) + direction.y): continue
				if absf(float(neighbor.h) - float(tile.h)) > 1.001: continue
				var own_group := str(tile.get("module", ""))
				var other_group := str(neighbor.get("module", ""))
				if own_group == other_group: continue
				if not stage._motion_geometry_modules.has(own_group) and not stage._motion_geometry_modules.has(other_group): continue
				_check(_has_foundation_face(surface, direction), label + "/" + id + " closes departing seam " + str(edge))
				closed_seams += 1
	for progress: float in [0.02, 0.25, 0.5, 0.75, 0.98, 0.9999]:
		stage.set_motion(before, after, progress, action)
		var eased := progress * progress * (3.0 - 2.0 * progress)
		_check(stage._build_count == builds, label + " no per-frame terrain rebuild")
		for id: String in meshes:
			var surface: Node3D = stage._surfaces[id]
			var original: Node3D = reference._surfaces[id]
			_check(_mesh_identity(surface) == meshes[id], label + "/" + id + " rigid mesh and collision reused")
			_check(surface.rises == rises[id], label + "/" + id + " no premature destination ramps")
			var tile: Dictionary = first.point_for(id)
			var angle := _angle(first, last, str(tile.get("module", "")), eased)
			_check(is_equal_approx(surface.rotation.y, -angle), label + "/" + id + " departure mesh rotation")
			for offset: Vector3 in [Vector3.ZERO, Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, -0.3)]:
				var source_point: Vector3 = original.position + offset
				var source_height: float = original.sample_height(source_point)
				var carried_point: Vector3 = surface.position + offset.rotated(Vector3.UP, -angle)
				var expected_height := source_height + surface.position.y - original.position.y
				_check(absf(surface.sample_height(carried_point) - expected_height) < 0.0001, label + "/" + id + " passenger surface remains rigid")
	stage.set_motion(before, after, 1.0, action)
	_check(not stage._motion_geometry_active, label + " docks at completion")
	_check(stage._build_count == builds + 1, label + " destination installed exactly once")
	reference.set_world(last)
	_check(stage._surfaces.keys() == reference._surfaces.keys(), label + " destination surface identities restored")
	for id: String in stage._surfaces:
		var actual: Node3D = stage._surfaces[id]
		var expected: Node3D = reference._surfaces[id]
		_check(actual.position.is_equal_approx(expected.position) and actual.rotation.is_zero_approx(), label + "/" + id + " docked transform exact")
		_check(actual._geometry_key == expected._geometry_key and actual.rises == expected.rises, label + "/" + id + " original destination support geometry")
		_check(actual._body.get_child(0).shape.get_faces() == expected._body.get_child(0).shape.get_faces(), label + "/" + id + " original destination collision")
	stage.clear_motion()
	_check(stage._build_count == builds + 1, label + " clear does not rebuild settled geometry")
	_check(first.snapshot() == before and last.snapshot() == after, label + " rule states remain unchanged")
	cases.append({"label": label, "surfaces": meshes.size(), "closedSeams": closed_seams, "motionBuilds": 2})

func _angle(first: RefCounted, last: RefCounted, module_id: String, progress: float) -> float:
	for module: Dictionary in first.level.get("modules", []):
		if str(module.id) != module_id or str(module.kind) != "rotate": continue
		var turns := posmod(int(last.state.turns[module_id]) - int(first.state.turns[module_id]), 4)
		return float(turns if turns <= 2 else turns - 4) * PI / 2.0 * progress
	return 0.0

func _mesh_identity(surface: Node3D) -> Array:
	var identity: Array = [surface._body.get_child(0).shape.get_rid(), surface.geometry_rebuilds]
	for part: MeshInstance3D in [surface._top, surface._sides, surface._ramps, surface._treads, surface._risers]:
		identity.append(part.mesh.get_rid() if part.mesh != null else RID())
	return identity

func _has_foundation_face(surface: Node3D, direction: Vector2) -> bool:
	if surface._sides.mesh == null: return false
	var vertices: PackedVector3Array = surface._sides.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		var at := Vector2(vertex.x, vertex.z)
		var top: float = surface._height_in_region(at, at - direction * 0.0001)
		if is_equal_approx(at.dot(direction), 0.5) and vertex.y < top - 0.15:
			return true
	return false
