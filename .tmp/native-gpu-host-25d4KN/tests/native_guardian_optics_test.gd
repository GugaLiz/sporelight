extends SceneTree
## Physical optical presentation and actual four-direction lamp emission.
const World = preload("res://core/garden_world.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func _run() -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary = {}
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/3-4": fixture = entry
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	var cold := World.new("3-4")
	stage.set_world(cold)
	_check(not stage._effects.get_children().filter(func(n: Node) -> bool: return n.has_meta("rule_ray")).is_empty(), "unaligned lamp still emits toward its actual current direction")
	_check(not cold.beam_hits(-4,0), "cold westward lamp does not falsely illuminate flowerbed")
	var cold_mirror: Node3D = stage._props_nodes["item:mirror"]
	_check(cold_mirror.get_meta("physical_item_offset").is_equal_approx(Vector3(0,0,-.20)), "seedbed mirror retains reviewed lane clearance")
	for angle: int in range(4):
		var snapshot: Dictionary = fixture.steps[94].snapshot.duplicate(true)
		snapshot.items.mirror.angle = angle
		var world := World.new("3-4", snapshot)
		var before: Dictionary = world.snapshot().duplicate(true)
		var ray: Array = world.rays().duplicate(true)
		stage.set_world(world)
		var mirror: Node3D = stage._props_nodes["item:mirror"]
		var face: MeshInstance3D = mirror.get_node("ReflectionFace")
		_check(mirror.get_meta("mirror_form") == "double-sided-oval-silver", "guardian uses recognizable silver glass at angle " + str(angle))
		_check(not mirror.has_node("ReflectionLeafBack") and mirror.has_node("FixedMirrorGimbal"), "glass has a real metal mounting instead of an opaque leaf back")
		_check(mirror.get_node("FixedMirrorGimbal").get_meta("metal_only"), "fixed gimbal is metal and does not falsify optical direction")
		_check(face.material_override is ShaderMaterial and not face.material_override.shader.code.contains("depth_test_disabled"), "mirror retains real depth and shared glass material")
		_check(is_equal_approx(face.position.y, .37), "glass centre aligns with authored ray height")
		var normal: Vector3 = face.global_basis.z.normalized()
		var incoming := Vector3(0,0,-1)
		var reflected := incoming - 2 * incoming.dot(normal) * normal
		_check(reflected.is_equal_approx(Vector3(-1 if angle % 2 == 0 else 1,0,0)), "real mirror plane reflects incident north ray to independently expected direction")
		var parts := {}
		for node: Node3D in stage._effects.get_children():
			if not node.has_meta("rule_ray"): continue
			var part := str(node.get_meta("rule_ray_part"))
			parts[part] = true
			_check(part in ["core","halo","contact"], "final garden has no legacy thin ray")
			_check(node.material_override is ShaderMaterial and not node.material_override.shader.code.contains("depth_test_disabled"), "beam retains normal depth")
			if part == "core":
				_check(node.mesh is CylinderMesh and is_equal_approx(node.mesh.top_radius, .0575) and not node.mesh.cap_top and not node.mesh.cap_bottom, "soft beam has smooth open cylindrical body without joining discs")
			if str(node.get_meta("rule_contact_item", "")) == "mirror":
				_check(is_equal_approx(node.global_position.y, face.global_position.y), "contact stays at glass centre")
				_check(is_equal_approx(absf((node.global_position-face.global_position).dot(normal)), .0145), "contact lies on real mirror surface")
		_check(parts.has("core") and parts.has("halo") and parts.has("contact"), "actual lit state has body fringe and contact")
		_check(world.snapshot() == before and world.rays() == ray, "optical dressing does not change rules or saved angles")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"guardian-optics","checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
