extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
var checks := 0
var failures: Array[String] = []
var cases: Array = []
var stage: Node2D
var reference: Node2D

class CountingCloud:
	extends Cloud
	static var tile_calls := 0
	func _init(id: String = "cloud-1", saved: Dictionary = {}) -> void: super(id, saved)
	func tiles() -> Array:
		tile_calls += 1
		return super.tiles()
	func fork(saved: Dictionary) -> RefCounted: return CountingCloud.new(str(level.id), saved)

func _initialize() -> void: call_deferred("_run")

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
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for entry: Dictionary in fixture.levels:
		var previous: Dictionary = entry.initial
		for step: Dictionary in entry.steps:
			if str(step.command.value) == "rotate":
				var first := CountingCloud.new(str(entry.id), previous)
				var last := CountingCloud.new(str(entry.id), step.snapshot)
				_test_bridge(first, last)
				_test_bridge(last, first)
				break
			if str(step.command.value) == "lift":
				_test_lift(CountingCloud.new(str(entry.id), previous), CountingCloud.new(str(entry.id), step.snapshot))
				_test_lift(CountingCloud.new(str(entry.id), step.snapshot), CountingCloud.new(str(entry.id), previous))
				break
			previous = step.snapshot
	print(JSON.stringify({"suite": "native-cloud-bridge-motion", "passed": failures.is_empty(), "checks": checks, "cases": cases, "failures": failures, "gpuPixelsVerified": false}))
	stage.queue_free()
	reference.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_bridge(first: RefCounted, last: RefCounted) -> void:
	var label := str(first.level.id) + "/" + str(first.state.turns.bridge) + "->" + str(last.state.turns.bridge)
	var before: Dictionary = first.snapshot()
	var after: Dictionary = last.snapshot()
	stage.clear_motion(false)
	stage.set_world(first)
	reference.set_world(first)
	var original := {}
	var source: Array = []
	var destination: Array = []
	for tile: Dictionary in first.tiles():
		original[str(tile.id)] = {"position": stage._surfaces[str(tile.id)].position, "rises": stage._surfaces[str(tile.id)].rises.duplicate()}
		if str(tile.kind) == "bridge": source.append(tile)
	for tile: Dictionary in last.tiles():
		if str(tile.kind) == "bridge": destination.append(tile)
	stage.set_motion(before, after, 0.0, "rotate")
	_check(stage._motion_geometry_active, label + " holds departure geometry")
	for tile: Dictionary in source:
		_check(stage._surfaces.has(str(tile.id)), label + " source bridge exists at first frame")
	for tile: Dictionary in destination:
		_check(not stage._surfaces.has(str(tile.id)), label + " destination bridge does not appear early")
	var identities := {}
	for id: String in stage._surfaces:
		var surface: Node3D = stage._surfaces[id]
		_check(surface.position.is_equal_approx(original[id].position) and surface.rotation.is_zero_approx(), label + "/" + id + " first frame unchanged")
		var expected: Array = original[id].rises.duplicate()
		var tile: Dictionary = first.point_for(id)
		for edge in range(4):
			for neighbor: Dictionary in first.tiles():
				if not is_equal_approx(float(neighbor.x), float(tile.x) + Stage.DIRECTIONS[edge].x) or not is_equal_approx(float(neighbor.z), float(tile.z) + Stage.DIRECTIONS[edge].y): continue
				if (str(tile.kind) == "bridge") != (str(neighbor.kind) == "bridge"): expected[edge] = 0.0
		_check(surface.rises == expected, label + "/" + id + " external stairs hidden, internal stairs retained")
		identities[id] = _identity(surface)
	var builds: int = stage._build_count
	CountingCloud.tile_calls = 0
	for progress: float in [0.1, 0.25, 0.5, 0.75, 0.9, 0.9999]:
		stage.set_motion(before, after, progress, "rotate")
		var eased := progress * progress * (3.0 - 2.0 * progress)
		var angle := (int(after.turns.bridge) - int(before.turns.bridge)) * PI / 2.0 * eased
		_check(stage._build_count == builds, label + " no intermediate rebuild")
		for id: String in identities:
			var surface: Node3D = stage._surfaces[id]
			_check(_identity(surface) == identities[id], label + "/" + id + " every stair face and collision reused")
			if not id.begins_with("bridge:"):
				_check(surface.position.is_equal_approx(original[id].position) and surface.rotation.is_zero_approx(), label + "/" + id + " fixed shore stays fixed")
			else:
				_check(is_equal_approx(surface.rotation.y, -angle), label + "/" + id + " leaf turns with rigid bridge")
				_check(surface.scale.is_equal_approx(Vector3.ONE), label + "/" + id + " leaf never shrinks or stretches")
		for index in range(source.size()):
			for other in range(index + 1, source.size()):
				var a: Vector3 = stage._surfaces[str(source[index].id)].position
				var b: Vector3 = stage._surfaces[str(source[other].id)].position
				var original_distance: float = original[str(source[index].id)].position.distance_to(original[str(source[other].id)].position)
				_check(is_equal_approx(a.distance_to(b), original_distance), label + " bridge leaf separation stays rigid")
		if progress == 0.5:
			# Explicit quarter-circle midpoints expose the original snap bug.
			var inner_id := "bridge:4:1" if str(first.level.id) == "cloud-1" and before.turns.bridge == 0 else "bridge:6:3" if str(first.level.id) == "cloud-1" else "bridge:8:4" if before.turns.bridge == 0 else "bridge:10:5"
			var expected := Vector3(4 + sqrt(2.0), 0.65, 3 - sqrt(2.0)) if str(first.level.id) == "cloud-1" else Vector3(8 + 1.5 / sqrt(2.0), 0.65, 5 - 1.5 / sqrt(2.0))
			_check(stage._surfaces[inner_id].position.distance_to(expected) < 0.00001, label + " real half-turn geometry lies between both docks")
	_check(CountingCloud.tile_calls == 0, label + " warm frames do not rebuild board queries")
	stage.set_motion(before, after, 1.0, "rotate")
	_check(stage._build_count == builds + 1 and not stage._motion_geometry_active, label + " dock installs destination once")
	reference.set_world(last)
	var actual_ids: Array = stage._surfaces.keys()
	var expected_ids: Array = reference._surfaces.keys()
	actual_ids.sort()
	expected_ids.sort()
	_check(actual_ids == expected_ids, label + " destination support IDs exact")
	for id: String in stage._surfaces:
		var actual: Node3D = stage._surfaces[id]
		var expected: Node3D = reference._surfaces[id]
		_check(actual.position.is_equal_approx(expected.position) and actual.rotation.is_zero_approx(), label + "/" + id + " final transform exact")
		_check(actual._body.get_child(0).shape.get_faces() == expected._body.get_child(0).shape.get_faces(), label + "/" + id + " final collision exact")
	stage.clear_motion()
	_check(stage._motion_cloud_bridge.is_empty(), label + " releases bridge correspondence")
	_check(first.snapshot() == before and last.snapshot() == after, label + " rule/save state unchanged")
	cases.append({"label": label, "bridgeLeaves": source.size(), "warmTileQueries": 0})

func _test_lift(first: RefCounted, last: RefCounted) -> void:
	stage.clear_motion(false)
	stage.set_world(first)
	var before: Dictionary = first.snapshot()
	var after: Dictionary = last.snapshot()
	var expected_rises := {}
	for tile: Dictionary in first.tiles():
		var values: Array = stage._surfaces[str(tile.id)].rises.duplicate()
		for edge in range(4):
			for neighbor: Dictionary in first.tiles():
				if not is_equal_approx(float(neighbor.x), float(tile.x) + Stage.DIRECTIONS[edge].x) or not is_equal_approx(float(neighbor.z), float(tile.z) + Stage.DIRECTIONS[edge].y): continue
				if (str(tile.kind) == "lift") != (str(neighbor.kind) == "lift"): values[edge] = 0.0
		expected_rises[str(tile.id)] = values
	var identities := {}
	for progress: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		stage.set_motion(before, after, progress, "lift")
		_check(stage._motion_cloud_bridge.is_empty(), "cloud-2 does not enter bridge rotation")
		if progress < 1.0:
			_check(stage._motion_geometry_active, "cloud-2 lift keeps source geometry until docking")
			for id: String in stage._surfaces:
				var surface: Node3D = stage._surfaces[id]
				_check(surface.rises == expected_rises[id], "cloud-2 external stairs hidden, internal stairs retained: " + id)
				if progress == 0.0: identities[id] = _identity(surface)
				else: _check(_identity(surface) == identities[id], "cloud-2 every stair face and collision remains rigid: " + id)
		for tile: Dictionary in first.tiles():
			if str(tile.kind) != "lift": continue
			var other: Dictionary = last.point_for(str(tile.id))
			var eased := progress * progress * (3.0 - 2.0 * progress)
			var expected := Vector3(float(tile.x), lerpf(float(tile.h), float(other.h), eased) * 0.65, float(tile.z))
			_check(stage._surfaces[str(tile.id)].position.is_equal_approx(expected), "cloud-2 original lift path preserved")
	reference.set_world(last)
	_check(not stage._motion_geometry_active, "cloud-2 destination installed only after docking")
	for id: String in stage._surfaces:
		_check(stage._surfaces[id].rises == reference._surfaces[id].rises, "cloud-2 docked stairs match destination: " + id)
		_check(stage._surfaces[id]._body.get_child(0).shape.get_faces() == reference._surfaces[id]._body.get_child(0).shape.get_faces(), "cloud-2 destination stair collision restored: " + id)
	stage.clear_motion()
	cases.append({"label": "cloud-2/lift", "originalPathPreserved": true})

func _identity(surface: Node3D) -> Array:
	var result: Array = [surface._body.get_child(0).shape.get_rid(), surface.geometry_rebuilds]
	for part: MeshInstance3D in [surface._top, surface._sides, surface._ramps, surface._treads, surface._risers]:
		result.append(part.mesh.get_rid() if part.mesh != null else RID())
	return result
