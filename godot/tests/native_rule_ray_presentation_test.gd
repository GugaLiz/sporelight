extends SceneTree
const Rays = preload("res://presentation/native/rule_ray_presentation.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node2D

class EmptyGarden:
	extends RefCounted
	func tiles() -> Array: return []
	func visible(_tile: Dictionary, _world_tiles: Array = []) -> bool: return false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_clipping()
	stage = Stage.new()
	root.add_child(stage)
	await process_frame
	_test_lamp()
	_test_receiver("3-1", "use:window", Vector2(3, 3), true)
	_test_receiver("2-2", "repair", Vector2(4, 0), false)
	_test_receiver("3-4", "repair", Vector2(-4, 0), false)
	_test_alignment_motion("3-4", "turn:light")
	_test_alignment_motion("2-2", "angle:mirrorA")
	print(JSON.stringify({"suite": "native-rule-ray-presentation", "passed": failures.is_empty(), "checks": checks, "failures": failures, "gpuPixelsVerified": false, "scope": "Slab clipping, real native light endpoints, current discovery bounds and unchanged receiver/reflection rules."}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_clipping() -> void:
	var bounds := Rect2(-1, -1, 2, 2)
	_check(Rays.clip_segment(_point(-2, 2), _point(2, 2), bounds).is_empty(), "parallel outside segment is hidden")
	_check(Rays.clip_segment(_point(0, 0), _point(0, 0), bounds).is_empty(), "zero-length ray creates no cylinder")
	_check(Rays.clip_segment(_point(0, 0), _point(1, 0), Rect2()).is_empty(), "empty view has no light decoration")
	var across := Rays.clip_segment(_point(-3, 0), _point(4, 0), bounds)
	_check(across.size() == 2 and is_equal_approx(across[0].x, -1) and is_equal_approx(across[1].x, 1), "crossing clips both outside ends")
	var reversed := Rays.clip_segment(_point(4, 0), _point(-3, 0), bounds)
	_check(reversed.size() == 2 and is_equal_approx(reversed[0].x, 1) and is_equal_approx(reversed[1].x, -1), "reverse beam retains its actual direction")
	var edge := Rays.clip_segment(_point(-3, 1), _point(4, 1), bounds)
	_check(edge.size() == 2, "boundary-aligned beam remains visible")
	var diagonal := Rays.clip_segment(_point(-2, -2, 0), _point(2, 2, 4), bounds)
	_check(diagonal.size() == 2 and is_equal_approx(diagonal[0].h, 1) and is_equal_approx(diagonal[1].h, 3), "clipped height is interpolated rather than flattened")
	var points := [_point(0, 0), _point(8, 0)]
	_check(Rays.segments(EmptyGarden.new(), points).is_empty(), "no discovered tiles is safe")
	_check(points == [_point(0, 0), _point(8, 0)], "input ray points are never edited")

func _test_lamp() -> void:
	var world := World.new("3-1")
	var source: Array = world.lamp_ray().duplicate(true)
	var snapshot: Dictionary = world.snapshot()
	var clipped := Rays.segments(world, source)
	var bounds := Rays.visible_bounds(world)
	_check(source.size() == 9, "initial lamp retains full authored eight-cell range")
	_check(clipped.size() > 0 and clipped.size() < source.size() - 1, "initial skyward tail is clipped at discovered garden edge")
	stage.set_world(world)
	var count := 0
	for node: Node in stage._effects.get_children():
		if not node.has_meta("rule_ray"): continue
		count += 1
		var beam := node as MeshInstance3D
		var axis := beam.quaternion * Vector3.UP * (beam.mesh as CylinderMesh).height / 2
		for endpoint: Vector3 in [beam.position - axis, beam.position + axis]:
			_check(bounds.grow(0.001).has_point(Vector2(endpoint.x, endpoint.z)), "real native light endpoint stays within visible footprint")
	_check(count == clipped.size(), "stage draws the clipped segments rather than full source ray")
	_check(world.lamp_ray() == source and world.snapshot() == snapshot, "clipping changes neither authored range nor discovery state")
	# A moving lamp can reveal another edge. Build the new bounds from current
	# state, not from level definition or a stale initial framing rectangle.
	var receiver_world := _before_action("3-1", "use:window")
	var later := Rays.visible_bounds(receiver_world)
	_check(later != bounds, "receiver phase has a different real discovery footprint")
	stage.set_world(receiver_world)
	_check(stage.world.snapshot() == receiver_world.snapshot(), "phase change does not rewrite the saved world")

func _test_receiver(level: String, action: String, target: Vector2, lamp: bool) -> void:
	var world := _before_action(level, action)
	var original: Dictionary = world.snapshot()
	var source: Array = world.lamp_ray() if lamp else world.rays()
	var original_ray := source.duplicate(true)
	var clipped := Rays.segments(world, source)
	_check(_covers(clipped, target), level + " actual receiver remains on the visible beam")
	_check(world.lamp_at_receiver() if lamp else world.beam_hits(target.x, target.y), level + " actual receiver logic remains true")
	stage.set_world(world)
	_check(world.snapshot() == original and source == original_ray, level + " dressing preserves receiver state and all reflection points")
	# All in-garden reflection vertices must survive; clipping only tails must
	# not connect nonadjacent pieces across a reflected corner.
	var bounds := Rays.visible_bounds(world)
	for point: Dictionary in source:
		var at := Vector2(float(point.x), float(point.z))
		if bounds.has_point(at):
			_check(_covers(clipped, at), level + " in-garden ray vertex is retained")

func _covers(segments: Array, target: Vector2) -> bool:
	for segment: Array in segments:
		var a := Vector2(float(segment[0].x), float(segment[0].z))
		var b := Vector2(float(segment[1].x), float(segment[1].z))
		if Geometry2D.get_closest_point_to_segment(target, a, b).distance_to(target) < 0.0001: return true
	return false

func _test_alignment_motion(level: String, action: String) -> void:
	var world := _before_action(level, action)
	var before: Dictionary = world.snapshot()
	_check(world.act(action).ok, level + " real action prepares a changed ray")
	var after: Dictionary = world.snapshot()
	var before_world := World.new(level, before)
	_check(before_world.rays() != world.rays(), level + " fixture covers an actual reflection change")
	stage.set_world(before_world)
	stage.set_motion(before, after, 0.0, action)
	var beams := _beam_nodes()
	_check(not beams.is_empty(), level + " aligned destination has a real visible ray")
	var identities := _beam_ids(beams)
	for phase: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		stage.set_motion(before, after, phase, action)
		_check(beams.all(func(beam: MeshInstance3D) -> bool: return beam.visible == (phase == 1.0)), level + " ray waits for actual alignment at " + str(phase))
		_check(_beam_ids(_beam_nodes()) == identities, level + " beam visibility reuses native nodes and meshes")
	stage.set_motion(before, after, 0.5, action)
	stage.set_paused(true)
	_check(beams.all(func(beam: MeshInstance3D) -> bool: return not beam.visible), level + " pausing mid-turn cannot announce receiver light")
	stage.set_paused(false)
	stage.clear_motion(false)
	_check(_beam_nodes().all(func(beam: MeshInstance3D) -> bool: return beam.visible), level + " clear restores current committed world's beam")
	stage.set_motion(after, before, 0.0, "undo")
	var reverse := _beam_nodes()
	for phase: float in [0.0, 0.5, 1.0]:
		stage.set_motion(after, before, phase, "undo")
		_check(reverse.all(func(beam: MeshInstance3D) -> bool: return beam.visible == (phase == 1.0)), level + " reverse turn also waits for alignment at " + str(phase))
	stage.clear_motion(false)
	stage.set_world(world)
	stage.set_motion(after, after, 0.5, "stationary")
	_check(_beam_nodes().all(func(beam: MeshInstance3D) -> bool: return beam.visible), level + " unchanged light is not hidden by unrelated motion")
	stage.clear_motion(false)
	_check(world.snapshot() == after and before_world.snapshot() == before, level + " visibility never mutates domain snapshots")

func _beam_nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: Node in stage._effects.get_children():
		if node.has_meta("rule_ray"): result.append(node as MeshInstance3D)
	return result

func _beam_ids(nodes: Array[MeshInstance3D]) -> Array:
	var result: Array = []
	for node: MeshInstance3D in nodes:
		result.append([node.get_instance_id(), node.mesh.get_instance_id()])
	return result

func _point(x: float, z: float, height := 0.0) -> Dictionary:
	return {"x": x, "z": z, "h": height}

func _before_action(level: String, action: String) -> RefCounted:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) != "authored/" + level: continue
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act" and str(step.command.value) == action:
				return World.new(level, before)
			before = step.snapshot
	_check(false, "fixture action exists: " + level + "/" + action)
	return World.new(level)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
