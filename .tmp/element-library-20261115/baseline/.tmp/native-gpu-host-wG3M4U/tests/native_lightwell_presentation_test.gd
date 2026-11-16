extends SceneTree
## Structural/state checks only; rendered readability is checked by GPU capture.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const RECEIVER := {"id": "lightwell:receiver", "x": 3, "z": 3, "h": 0}
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var aperture_samples: Array[Dictionary] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _part(role: String) -> Node3D:
	for node: Node in stage._props.find_children("*", "Node3D", true, false):
		if str(node.get_meta("lightwell_role", "")) == role: return node as Node3D
	return null

func _lamp_segments() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in stage._effects.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh and str(child.get_meta("rule_path", "")) == "lamp": result.append(child)
	result.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return int(a.get_meta("rule_segment_index")) < int(b.get_meta("rule_segment_index")))
	return result

func _endpoints(beam: MeshInstance3D) -> Array[Vector3]:
	var half: Vector3 = beam.global_basis.y * (beam.mesh as CylinderMesh).height * .5
	return [beam.global_position - half, beam.global_position + half]

func _plane_hit(node: Node3D, origin: Vector3, direction: Vector3) -> Vector3:
	var local_origin := node.to_local(origin)
	var local_direction := node.to_local(origin + direction) - local_origin
	if absf(local_direction.z) < .000001: return Vector3(INF, INF, INF)
	return local_origin - local_direction * (local_origin.z / local_direction.z)

func _inspect_ray(world: RefCounted, label: String) -> void:
	var source := _part("source")
	var beams := _lamp_segments()
	if source == null or not source.visible or beams.is_empty(): return
	var first := _endpoints(beams.front())
	var last := _endpoints(beams.back())
	var origin := first[0]
	var axis := (last[1] - origin).normalized()
	_check(origin.distance_to(source.global_position) < .001, label + " full beam starts at the actual lamp")
	var previous := origin
	for beam: MeshInstance3D in beams:
		var ends := _endpoints(beam)
		_check(ends[0].distance_to(previous) < .001, label + " beam join is continuous at segment " + str(beam.get_meta("rule_segment_index")))
		for point: Vector3 in ends:
			_check((point - origin).cross(axis).length() < .001, label + " every beam endpoint shares one straight axis")
		_check((ends[1] - ends[0]).dot(axis) > 0, label + " beam segments travel forward")
		previous = ends[1]
	if not world.lamp_at_receiver(): return
	var receiver := _part("receiver")
	_check((receiver.global_position - origin).cross(axis).length() < .001, label + " current receiving leaf lies on the straight beam")
	# These measurements use actual art openings, not enlarged test tolerances.
	# The beam has radius .018; its body must fit inside the clear aperture.
	var lamp: Dictionary = world.state.items.lamp
	var lamp_tile := str(world.state.actors.get(str(lamp.get("holder", "")), lamp.get("tile", "")))
	if lamp_tile == "f:3:5":
		var socket := _part("socket")
		var mouth := socket.get_node("LeafAperture") as Node3D
		var hit := _plane_hit(mouth, origin, axis)
		var ellipse := pow(hit.x / (.28 - .018), 2) + pow(hit.y / (.24 - .018), 2)
		aperture_samples.append({"state": label, "part": "socket", "localHit": [hit.x, hit.y, hit.z], "ellipse": ellipse})
		_check(ellipse <= 1.0, label + " beam clears actual leaf aperture: " + str(hit) + " ellipse=" + str(ellipse))
	var crosses_window := false
	for point: Dictionary in world.lamp_ray():
		if int(point.x) == 3 and int(point.z) == 2: crosses_window = true
	if crosses_window:
		var window := _part("window")
		var hit := _plane_hit(window, origin, axis)
		aperture_samples.append({"state": label, "part": "window", "localHit": [hit.x, hit.y, hit.z], "open": world.flag("window")})
		_check(absf(hit.x) + .018 <= .33 and hit.y - .018 >= -.2525 and hit.y + .018 <= .2575, label + " beam meets actual stone-window opening: " + str(hit))
		if not world.flag("window"):
			_check(absf(window.to_local(last[1]).z) < .001, label + " closed stone window terminates the whole straight beam")

func _inspect_subtile_motion(world: RefCounted, label: String) -> void:
	var holder := str(world.state.items.lamp.get("holder", ""))
	if holder.is_empty(): return
	var body: CharacterBody3D = stage.get_actor_body(holder)
	var saved := body.position
	var snapshot: Dictionary = world.snapshot()
	for offset: Vector3 in [Vector3(.11, 0, 0), Vector3(-.11, 0, 0), Vector3(0, 0, .11), Vector3(0, 0, -.11), Vector3(.20, 0, 0), Vector3(-.20, 0, 0), Vector3(0, 0, .20), Vector3(0, 0, -.20)]:
		body.position = saved + offset
		stage._lightwell_dressing.update(stage)
		_inspect_ray(world, label + " subtile " + str(offset))
	body.position = saved
	stage._lightwell_dressing.update(stage)
	_check(world.snapshot() == snapshot, label + " visual subtile sampling leaves puzzle state unchanged")

func _inspect(world: RefCounted, label: String) -> Color:
	var before: Dictionary = world.snapshot()
	stage.set_world(world)
	stage.refresh_world(world, false)
	stage._lightwell_dressing.update(stage)
	_check(world.snapshot() == before, label + " presentation does not change rules or discovery")
	var receiver := _part("receiver")
	var window := _part("window")
	var source := _part("source")
	_check(receiver != null and window != null and source != null, label + " all existing optical roles have an entity")
	if receiver == null or window == null or source == null: return Color.TRANSPARENT
	_check(receiver.get_meta("rule_point") == Vector2(3, 3) and window.get_meta("rule_point") == Vector2(3, 2), label + " receiver and shutter match actual optical rule coordinates")
	_check(receiver.visible == world.visible(RECEIVER, stage._tiles), label + " receiver respects original exploration visibility")
	_check(window.visible == world.visible(world.point_for("f:3:1"), stage._tiles), label + " suspended window respects its real shore visibility")
	_check(bool(receiver.get_meta("powered")) == world.lamp_at_receiver() and bool(window.get_meta("opened")) == world.flag("window"), label + " current hit and permanent window remain separate")
	_check(receiver.global_position.distance_to(stage.tile_position(RECEIVER) + Vector3.UP * .37) < .001, label + " leaf heart meets the actual ray height")
	for part: Node3D in [receiver, window, source]:
		_check(part.find_children("*", "CollisionObject3D", true, false).is_empty() and bool(part.get_meta("not_walkable_support", false)), label + " optical art adds neither collision nor a walkable platform")
		_check(part.find_children("*", "Label3D", true, false).is_empty(), label + " world art uses no solution text")
	_check(str(source.get_meta("holder")) == str(world.state.items.lamp.get("holder", "")), label + " source ownership follows the original item")
	var ids := [receiver.get_instance_id(), window.get_instance_id(), source.get_instance_id()]
	for unused in range(6): stage._lightwell_dressing.update(stage)
	_check(ids == [_part("receiver").get_instance_id(), _part("window").get_instance_id(), _part("source").get_instance_id()], label + " ordinary visual updates reuse the same nodes")
	var beam: MeshInstance3D = stage._lightwell_dressing._first_ray
	if source.visible and beam != null:
		var start: Vector3 = beam.global_position - beam.global_basis.y * (beam.mesh as CylinderMesh).height * .5
		_check(start.distance_to(source.global_position) < .001, label + " first rendered segment starts at the actual lamp")
	_inspect_ray(world, label)
	return (receiver.get_node("ReceivingLeaf").material_override as StandardMaterial3D).albedo_color

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	var fixture := {}
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/3-1": fixture = entry
	_check(not fixture.is_empty(), "original lightwell reference exists")
	if fixture.is_empty(): quit(1); return
	_inspect(World.new("3-1"), "cold")
	_check(not _part("receiver").visible and not _part("window").visible, "cold optical art does not reveal the far islands")
	for index: int in [1, 13, 20, 21, 23, 42]:
		_inspect(World.new("3-1", fixture.steps[index].snapshot), "original step " + str(index))
	var world := World.new("3-1", fixture.steps[13].snapshot)
	var lit := _inspect(world, "socket lit")
	_check(world.act("angle:lamp").ok, "original holder may freely turn the lamp")
	var unlit := _inspect(world, "socket turned away")
	_check(not world.lamp_at_receiver() and lit != unlit, "wrong angle removes current receiving light")
	world = World.new("3-1", fixture.steps[21].snapshot)
	var opened_lit := _inspect(world, "open and lit")
	_check(world.act("switch").ok and world.act("angle:lamp").ok, "original open-window holder can change direction")
	var opened_unlit := _inspect(world, "open but unlit")
	_check(world.flag("window") and not world.lamp_at_receiver() and opened_lit != opened_unlit, "permanent window does not freeze the receiver's current light color")
	var body: CharacterBody3D = stage.get_actor_body("buddy")
	var origin: Vector3 = _part("source").global_position
	var saved: Vector3 = body.position
	body.position.x += .11
	stage._lightwell_dressing.update(stage)
	_check((_part("source").global_position - origin).distance_to(Vector3(.11, 0, 0)) < .001, "subtile visual movement follows the real carrier rather than the logical cell")
	body.position = saved
	# Prepared presentation states cover both legal holders without claiming
	# that this CPU suite walks the route or exercises operating-system input.
	for opened: bool in [false, true]:
		for who: String in ["luvie", "buddy"]:
			var snapshot: Dictionary = fixture.steps[21 if opened else 13].snapshot.duplicate(true)
			snapshot.active = who
			snapshot.items.lamp.holder = who
			world = World.new("3-1", snapshot)
			for angle: int in range(4):
				var label := who + " angle " + str(angle) + " window " + str(opened)
				_inspect(world, label)
				_inspect_subtile_motion(world, label)
				_check(world.act("angle:lamp").ok, label + " retains original free lamp rotation")
		world = World.new("3-1", fixture.steps[21 if opened else 13].snapshot)
		if world.actor() != "buddy": _check(world.act("switch").ok, "switch to original socket holder for drop")
		_check(world.act("drop:lamp:f:3:5").ok, "original socket drop remains legal")
		_inspect(world, "ground at socket window " + str(opened))
		_check(world.act("take:lamp").ok, "original socket retake remains legal")
		_inspect(world, "retaken at socket window " + str(opened))
	for angle: int in range(4):
		var ground := World.new("3-1")
		ground.state.items.lamp.angle = angle
		_inspect(ground, "prepared ground origin angle " + str(angle))
	stage.set_world(World.new("2-3"))
	_check(_part("receiver") == null and _part("window") == null and _part("source") == null, "lightwell additions do not spill into another level")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-lightwell-presentation", "checks": checks, "failures": failures, "passed": failures.is_empty(), "apertureSamples": aperture_samples, "gpuPixelsVerified": false}))
	quit(0 if failures.is_empty() else 1)
