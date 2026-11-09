extends SceneTree
## Inspect real native nodes/meshes and transforms. This does not assert GPU
## colors or substitute for the matching exported mechanism-frame review.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checked := 0
var failures: Array[String] = []
var stage: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	stage.set_visual_time(1200)
	var rotate := _transition("3-3", "turn:water")
	_check(not rotate.is_empty(), "authored water rotation fixture exists")
	stage.set_world(World.new("3-3", rotate.before))
	var original: Dictionary = rotate.before.duplicate(true)
	stage.set_motion(rotate.before, rotate.after, 0.0, "turn:water")
	var channel: Node3D = stage._water_module_roots.water
	var water_piece: MeshInstance3D = channel.get_child(1)
	var node_id := channel.get_instance_id()
	var mesh_id := water_piece.mesh.get_instance_id()
	var initial_body: Transform3D = stage.get_actor_body("luvie").transform
	var first_turn := int(rotate.before.turns.water)
	var difference := posmod(int(rotate.after.turns.water) - first_turn, 4)
	var signed_delta := difference if difference <= 2 else difference - 4
	var pivot: Vector3 = stage._water_anchor_point(stage._motion_before, "m:water:0:0")
	for raw: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		stage.set_motion(rotate.before, rotate.after, raw, "turn:water")
		var eased := raw * raw * (3 - 2 * raw)
		var angle := (first_turn + signed_delta * eased) * PI / 2
		var expected := pivot + Vector3(sin(angle) * 0.175, 0.049, -cos(angle) * 0.175)
		_check(water_piece.global_position.distance_to(expected) < 0.0002, "local water follows actual module angle at " + str(raw))
		_check(channel.get_instance_id() == node_id and water_piece.mesh.get_instance_id() == mesh_id, "rotating water reuses native nodes and mesh")
		_check(stage.get_actor_body("luvie").transform == initial_body, "water animation never writes actor root")
	_check(rotate.before == original, "presentation does not mutate rule snapshot")
	_check((water_piece.mesh as BoxMesh).size.length() < 0.4, "local channel fits the pump instead of forming a three-cell rod")
	stage.clear_motion(false)
	stage.set_world(World.new("3-3", rotate.after))
	for raw: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		stage.set_motion(rotate.after, rotate.before, raw, "return:water")
		var eased := raw * raw * (3 - 2 * raw)
		var angle := (int(rotate.after.turns.water) - eased) * PI / 2
		var expected := pivot + Vector3(sin(angle) * 0.175, 0.049, -cos(angle) * 0.175)
		var reverse_piece: MeshInstance3D = stage._water_module_roots.water.get_child(1)
		_check(reverse_piece.global_position.distance_to(expected) < 0.0002, "water also follows the reverse signed quarter-turn at " + str(raw))

	var opening := _transition("3-4", "valve:water")
	_check(not opening.is_empty(), "authored supply alignment fixture exists")
	stage.clear_motion(false)
	stage.set_world(World.new("3-4", opening.before))
	stage.set_motion(opening.before, opening.after, 0.5, "valve:water")
	var delivery: Dictionary = stage._water_links[0]
	_check(not delivery.node.visible, "new supply waits for physical docking")
	stage.set_motion(opening.before, opening.after, 1.0, "valve:water")
	_check(delivery.node.visible, "supply appears when aligned")
	var drops: MultiMeshInstance3D = delivery.drops
	_check(drops.multimesh.mesh is SphereMesh, "empty space is represented by separate water droplets")
	_check(drops.multimesh.instance_count >= 4 and drops.multimesh.instance_count <= 12, "water transfer has bounded instancing")
	# Headless uses the dummy rendering backend, whose MultiMesh transform
	# readback is not a GPU assertion. Inspect real anchor spacing and the
	# shared native primitive size; exported GPU frames verify final pixels.
	var span: Vector3 = delivery.receiver.position - delivery.source.position
	var spacing := Vector2(span.x, span.z).length() / drops.multimesh.instance_count
	_check(spacing > 0.5 and drops.multimesh.mesh.radius * 2 < spacing / 8, "droplets preserve large gaps instead of a walkable bar")

	var lift := _transition("3-4", "valve:lift")
	_check(not lift.is_empty(), "authored lift fixture exists")
	stage.clear_motion(false)
	stage.set_world(World.new("3-4", lift.before))
	stage.set_motion(lift.before, lift.after, 0.0, "valve:lift")
	delivery = stage._water_links[0]
	var stable_ids := [delivery.node.get_instance_id(), delivery.drops.multimesh.get_instance_id(), delivery.drops.multimesh.mesh.get_instance_id()]
	var before_model := World.new("3-4", lift.before)
	var after_model := World.new("3-4", lift.after)
	var a: Vector3 = stage._water_anchor_point(before_model, "m:lift:0:0")
	var b: Vector3 = stage._water_anchor_point(after_model, "m:lift:0:0")
	for raw: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		stage.set_motion(lift.before, lift.after, raw, "valve:lift")
		var eased := raw * raw * (3 - 2 * raw)
		var expected := a.lerp(b, eased) + Vector3(0, 0.065, 0)
		_check(Vector3(delivery.receiver.position).distance_to(expected) < 0.0002, "receiving water follows lift height at " + str(raw))
		_check(stable_ids == [delivery.node.get_instance_id(), delivery.drops.multimesh.get_instance_id(), delivery.drops.multimesh.mesh.get_instance_id()], "lift motion never replaces water mesh resources")
	_check(b.y > a.y + 1.0, "test covers a real raised platform")
	stage.clear_motion(false)
	stage.set_world(after_model)
	stage.set_settings({"lowMotion": true, "particles": false, "dynamicLight": false})
	stage._update_water_presentation()
	_check(stage._water_links[0].node.visible, "rule water remains readable with decorative effects disabled")
	stage.set_world(World.new("3-4"))
	_check(not stage._water_links[0].node.visible, "unconnected supply is not announced")
	var report := {"suite": "native-water-presentation", "passed": failures.is_empty(), "checks": checked, "failures": failures, "gpuPixelsVerified": false, "scope": "Actual water module transforms at five phases; native mesh identity reuse; transfer gating, instanced separated droplets and moving receiver anchors. No collision/rule changes."}
	print(JSON.stringify(report))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _transition(level: String, value: String) -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) != "authored/" + level: continue
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act" and str(step.command.value) == value:
				return {"before": before, "after": step.snapshot}
			before = step.snapshot
	return {}

func _check(condition: bool, label: String) -> void:
	checked += 1
	if not condition:
		failures.append(label)
		push_error(label)
