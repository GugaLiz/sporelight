extends RefCounted
## 3-1's existing optical mechanism, expressed at its real rule coordinates.
## All added matter is soft foliage or hangs outside the legal walking shore.
## No support, collision, input, discovery or puzzle state is created here.

const RayArt = preload("res://presentation/native/garden_ray.gdshader")
const RAY_HEIGHT := 0.37
const RECEIVER := {"id": "lightwell:receiver", "x": 3, "z": 3, "h": 0}
const BLOCKER := {"id": "lightwell:window", "x": 3, "z": 2, "h": 0}
const VIEW_NORMAL := Vector3(0.612372, 0.5, 0.612372)

var _socket: Node3D
var _receiver: Node3D
var _window: Node3D
var _source: Node3D
var _receiver_face: StandardMaterial3D
var _receiver_glow: StandardMaterial3D
var _first_ray: MeshInstance3D
var _lamp_rays: Array[Dictionary] = []
var _ray_origin := Vector3.ZERO
var _ray_direction := Vector3.ZERO
var _ray_target := Vector3.ZERO
var _ray_length := 0.0
var _last_state := ""

func begin_build() -> void:
	_socket = null
	_receiver = null
	_window = null
	_source = null
	_receiver_face = null
	_receiver_glow = null
	_last_state = ""
	# Rule rays have their own lifecycle and may survive a prop rebuild.
	if not is_instance_valid(_first_ray): _first_ray = null

func build_mark(stage: Node, root: Node3D, mark: Dictionary) -> bool:
	if str(stage.world.level.id) != "3-1" or str(mark.id) != "socket": return false
	_socket = root
	root.set_meta("lightwell_part", "socket")
	root.set_meta("lightwell_role", "socket")
	root.set_meta("not_walkable_support", true)
	# A living rolled leaf replaces the generic disc. The middle remains an
	# actual aperture; its soft stem and leaves do not introduce a hard base.
	var mouth := _node(root, "LeafAperture", Vector3(0.10, 0.32, -0.29))
	var rim := _mesh(mouth, "RolledLeaf", _leaf_ring(), Color("91b49b"))
	rim.set_meta("soft_foliage", true)
	_line(stage, root, "SoftStem", Vector3(0, 0.018, 0.14), Vector3(0.10, 0.035, -0.29), 0.016, Color("708d77"))
	var leaf := _mesh(root, "RestingLeaf", _leaf(), Color("7e9c77"))
	leaf.position = Vector3(0, 0.022, 0.12)
	leaf.rotation.x = -PI / 2
	leaf.scale = Vector3(0.80, 0.70, 0.8)
	return true

func finish_build(stage: Node) -> void:
	if str(stage.world.level.id) != "3-1": return
	_build_receiver(stage)
	_build_window(stage)
	_source = _node(stage._props, "LightwellLampContact")
	_source.set_meta("lightwell_part", "source")
	_source.set_meta("lightwell_role", "source")
	_source.set_meta("not_walkable_support", true)
	var ember: MeshInstance3D = stage._sphere(_source, 0.025, Vector3.ZERO, Color("ffe6a6"))
	ember.name = "WarmLampPoint"
	ember.material_override = _glow(Color("ffe6a6"), 0.12)
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := MeshInstance3D.new()
	halo.name = "LocalLampHalo"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.24
	halo.mesh = quad
	var right := Vector3(1, 0, -1).normalized()
	halo.basis = Basis(right, VIEW_NORMAL.normalized().cross(right), VIEW_NORMAL.normalized())
	var material := ShaderMaterial.new()
	material.shader = RayArt
	material.set_shader_parameter("contact", true)
	material.set_shader_parameter("tint", Color(1.0, 0.84, 0.48, 0.18))
	material.set_shader_parameter("emission_strength", 0.04)
	halo.material_override = material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_source.add_child(halo)
	_link_window_lever(stage)

func bind_ray(stage: Node) -> void:
	_first_ray = null
	_lamp_rays.clear()
	if str(stage.world.level.id) != "3-1": return
	var path: Array = stage.world.lamp_ray()
	if path.size() < 2: return
	_ray_origin = stage._effects.to_global(stage.tile_position(path[0]) + Vector3.UP * RAY_HEIGHT)
	_ray_direction = (stage._effects.to_global(stage.tile_position(path[1]) + Vector3.UP * RAY_HEIGHT) - _ray_origin).normalized()
	_ray_length = 0.0
	for child: Node in stage._effects.get_children():
		if not child is MeshInstance3D or str(child.get_meta("rule_path", "")) != "lamp": continue
		var beam := child as MeshInstance3D
		var pair: Array = beam.get_meta("rule_segment_points", [])
		if pair.size() != 2 or not beam.mesh is CylinderMesh: continue
		var a: Vector3 = stage._effects.to_global(stage.tile_position(pair[0]) + Vector3.UP * RAY_HEIGHT)
		var b: Vector3 = stage._effects.to_global(stage.tile_position(pair[1]) + Vector3.UP * RAY_HEIGHT)
		var start := (a - _ray_origin).dot(_ray_direction)
		var end := (b - _ray_origin).dot(_ray_direction)
		_lamp_rays.append({"beam": beam, "height": maxf(0.001, (beam.mesh as CylinderMesh).height), "start": start, "end": end})
		if int(child.get_meta("rule_segment_index", -1)) == 0: _first_ray = beam
		if end > _ray_length:
			_ray_length = end
			_ray_target = b
		child.set_meta("lightwell_bound_source", true)

func update(stage: Node) -> void:
	if stage.world == null or str(stage.world.level.id) != "3-1": return
	var open: bool = stage.world.flag("window")
	var hit: bool = stage.world.lamp_at_receiver()
	var current := "window-open" if open else "receiver-lit" if hit else "receiver-unlit"
	var state_key := str(open) + ":" + str(hit)
	if is_instance_valid(_receiver):
		_receiver.visible = stage.world.visible(RECEIVER, stage._tiles)
		_receiver.set_meta("receiver_hit", hit)
		_receiver.set_meta("powered", hit)
		_receiver.set_meta("window_open", open)
		_receiver.set_meta("lightwell_state", current)
	if is_instance_valid(_window):
		var shore: Dictionary = stage._tile_map.get("f:3:1", {})
		_window.visible = not shore.is_empty() and stage.world.visible(shore, stage._tiles)
		_window.set_meta("window_open", open)
		_window.set_meta("opened", open)
		_window.set_meta("receiver_hit", hit)
		_window.set_meta("lightwell_state", "open" if open else "closed")
	if is_instance_valid(_socket):
		_socket.set_meta("receiver_hit", hit)
		_socket.set_meta("window_open", open)
		_socket.set_meta("lightwell_state", current)
	if state_key != _last_state:
		_last_state = state_key
		if _receiver_face != null:
			_receiver_face.albedo_color = Color("d5dcaa") if hit else Color("adc49b") if open else Color("82a58d")
			_receiver_face.emission_enabled = hit or open
			_receiver_face.emission = Color("efd58f") * (0.12 if hit else 0.025)
		if _receiver_glow != null:
			_receiver_glow.albedo_color = Color("ffe4a5") if hit else Color("c5d9af") if open else Color("617f70")
			_receiver_glow.emission_enabled = hit or open
			_receiver_glow.emission = Color("ffe4a5") * (0.16 if hit else 0.025)
	_update_source(stage)

func _update_source(stage: Node) -> void:
	if not is_instance_valid(_source): return
	var lamp: Dictionary = stage.world.state.get("items", {}).get("lamp", {})
	var holder := str(lamp.get("holder", ""))
	var valid := false
	var at := Vector3.ZERO
	if not holder.is_empty():
		var body: CharacterBody3D = stage.get_actor_body(holder)
		var carry: Sprite3D = body.get_node_or_null("Visual/Carry") as Sprite3D if body != null else null
		if body != null and body.visible and carry != null and carry.visible:
			at = carry.global_position
			valid = true
	else:
		var ground: Node3D = stage._props_nodes.get("item:lamp") as Node3D
		if ground != null and ground.is_visible_in_tree():
			# The authored light is a leaf lamp, without a rigid lantern foot.
			at = ground.global_position + Vector3.UP * 0.16
			valid = true
	_source.visible = valid
	_source.set_meta("lamp_holder", holder)
	_source.set_meta("holder", holder)
	_source.set_meta("lamp_tile", str(stage.world.state.actors.get(holder, "")) if not holder.is_empty() else str(lamp.get("tile", "")))
	_source.set_meta("lamp_angle", int(lamp.get("angle", 0)))
	_source.set_meta("lightwell_state", "carried" if valid and not holder.is_empty() else "ground" if valid else "hidden")
	if not valid: return
	_source.global_position = at
	if _lamp_rays.is_empty() or _ray_length < 0.001: return
	# Use one axis for the entire uninterrupted beam, never bend it at a
	# logical cell boundary to join the moving pouch to the old grid line.
	# A receiving leaf fixes the optical contact when powered. Otherwise the
	# authored clipped end fixes the axis. Rule range/visibility stay intact.
	var target := _ray_target
	if stage.world.lamp_at_receiver() and is_instance_valid(_receiver):
		var receiver_distance := (_receiver.global_position - _ray_origin).dot(_ray_direction)
		if receiver_distance > 0.001:
			target = _receiver.global_position
	var travel := (target - at).dot(_ray_direction)
	if absf(travel) < 0.001: return
	var axis := (target - at) / travel
	if axis.length_squared() < 0.000001: return
	var orientation := Basis(Quaternion(Vector3.UP, axis.normalized()))
	var offset := (at - _ray_origin).dot(_ray_direction)
	for entry: Dictionary in _lamp_rays:
		var beam: MeshInstance3D = entry.beam
		if not is_instance_valid(beam): continue
		# Preserve the actual receiver/blocker planes, including when the
		# carrier is ahead of or behind the centre of the logical source cell.
		var start := 0.0 if beam == _first_ray else float(entry.start) - offset
		var a: Vector3 = at + axis * start
		var b: Vector3 = at + axis * (float(entry.end) - offset)
		beam.global_position = a.lerp(b, 0.5)
		beam.global_basis = orientation * Basis.from_scale(Vector3(1, a.distance_to(b) / float(entry.height), 1))
		beam.set_meta("lightwell_source_position", at)

func _build_receiver(stage: Node) -> void:
	_receiver = _node(stage._props, "LightwellReceiver", stage.tile_position(RECEIVER) + Vector3.UP * RAY_HEIGHT)
	_receiver.set_meta("lightwell_part", "receiver")
	_receiver.set_meta("lightwell_role", "receiver")
	_receiver.set_meta("rule_point", Vector2(3, 3))
	_receiver.set_meta("rule_receiver_cell", Vector2i(3, 3))
	_receiver.set_meta("not_walkable_support", true)
	# The receiving leaf grows from the existing north shore; its flexible
	# stem gives it a fixed habitat without suggesting a pedestal or pickup.
	var stem: Array[Vector3] = [Vector3(0.22, -0.35, 0.62), Vector3(0.24, -0.19, 0.38), Vector3(0.13, -0.26, 0.14), Vector3(0, -0.27, 0)]
	for index: int in range(stem.size() - 1):
		var segment := _line(stage, _receiver, "SoftReceiverStem_" + str(index), stem[index], stem[index + 1], 0.014, Color("78967c"))
		segment.set_meta("soft_foliage", true)
	var leaf := _mesh(_receiver, "ReceivingLeaf", _leaf(), Color("82a58d"))
	_receiver_face = leaf.material_override as StandardMaterial3D
	_line(stage, _receiver, "LeafVein", Vector3(0, -0.23, -0.013), Vector3(0, 0.25, -0.013), 0.009, Color("b4cda4"))
	for side: float in [-1.0, 1.0]:
		_line(stage, _receiver, "SideVein", Vector3(0, -0.04, -0.016), Vector3(side * 0.14, 0.10, -0.016), 0.006, Color("a9c49c"))
	var centre: MeshInstance3D = stage._sphere(_receiver, 0.055, Vector3(0, 0, -0.025), Color("617f70"))
	centre.name = "ReceiverHeart"
	_receiver_glow = _glow(Color("617f70"), 0)
	centre.material_override = _receiver_glow
	centre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_window(stage: Node) -> void:
	_window = _node(stage._props, "LightwellStoneWindow", stage.tile_position(BLOCKER) + Vector3.UP * RAY_HEIGHT)
	_window.set_meta("lightwell_part", "window")
	_window.set_meta("lightwell_role", "window")
	_window.set_meta("rule_point", Vector2(3, 2))
	_window.set_meta("rule_blocker_cell", Vector2i(3, 2))
	_window.set_meta("attached_shore", "f:3:1")
	_window.set_meta("not_walkable_support", true)
	var stone := _stone(stage)
	# Every hard piece stays beyond the existing island's south wall. Slender
	# braces visibly carry the suspended vertical window, never a stone floor.
	for side: float in [-1.0, 1.0]:
		var brace := _line(stage, _window, "ShoreBrace", Vector3(side * 0.38, -0.47, -0.48), Vector3(side * 0.38, -0.23, 0), 0.021, Color("7c8c7d"))
		brace.set_meta("outside_walkable_shore", true)
		_box(stage, _window, "WindowSide", Vector3(0.06, 0.56, 0.09), Vector3(side * 0.36, 0, 0), stone)
	_box(stage, _window, "WindowTop", Vector3(0.78, 0.065, 0.09), Vector3(0, 0.29, 0), stone)
	_box(stage, _window, "WindowBottom", Vector3(0.78, 0.055, 0.09), Vector3(0, -0.28, 0), stone)
	var open: bool = stage.world.flag("window")
	for side: float in [-1.0, 1.0]:
		_box(stage, _window, "OpenShutter" if open else "ClosedShutter", Vector3(0.31, 0.47, 0.065), Vector3(side * (0.51 if open else 0.155), 0, 0.005), stone)

func _link_window_lever(stage: Node) -> void:
	var lever: Node3D = stage._props_nodes.get("mark:window") as Node3D
	if lever == null: return
	lever.set_meta("lightwell_part", "window-control")
	lever.set_meta("controls_rule_cell", Vector2i(3, 2))
	lever.set_meta("window_open", stage.world.flag("window"))
	var base := lever.get_node_or_null("LeverBase") as MeshInstance3D
	if base != null: base.material_override = _stone(stage)

func _stone(stage: Node) -> StandardMaterial3D:
	const KEY := "lightwell_suspended_stone_frame"
	if stage._materials.has(KEY): return stage._materials[KEY] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("9caa96")
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = stage._texture("masonry-valley")
	material.uv1_scale = Vector3.ONE * 0.4
	stage._materials[KEY] = material
	return material

func _node(parent: Node3D, name: String, at := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = at
	parent.add_child(node)
	return node

func _mesh(parent: Node3D, name: String, geometry: Mesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = geometry
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _box(stage: Node, parent: Node3D, name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = stage._box(parent, size, at, Color.WHITE)
	node.name = name
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _line(stage: Node, parent: Node3D, name: String, a: Vector3, b: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = stage._cylinder(parent, radius, a.distance_to(b), a.lerp(b, 0.5), color)
	node.name = name
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _glow(color: Color, strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = strength > 0
	material.emission = color * strength
	return material

func _leaf() -> ArrayMesh:
	var outline: Array[Vector3] = [Vector3(0, -0.27, 0), Vector3(-0.16, -0.13, 0), Vector3(-0.23, 0.06, 0), Vector3(-0.14, 0.24, 0), Vector3(0, 0.34, 0), Vector3(0.14, 0.24, 0), Vector3(0.23, 0.06, 0), Vector3(0.16, -0.13, 0)]
	var vertices := PackedVector3Array()
	for index: int in range(outline.size()):
		vertices.append(Vector3(0, 0.02, -0.025))
		vertices.append(outline[index])
		vertices.append(outline[(index + 1) % outline.size()])
	return _geometry(vertices)

func _leaf_ring() -> ArrayMesh:
	var vertices := PackedVector3Array()
	for index: int in range(40):
		var a := TAU * float(index) / 40.0
		var b := TAU * float(index + 1) / 40.0
		var outer_a := Vector3(cos(a) * 0.36, sin(a) * (0.32 + 0.035 * sin(a)), 0.015)
		var outer_b := Vector3(cos(b) * 0.36, sin(b) * (0.32 + 0.035 * sin(b)), 0.015)
		var inner_a := Vector3(cos(a) * 0.28, sin(a) * 0.24, -0.015)
		var inner_b := Vector3(cos(b) * 0.28, sin(b) * 0.24, -0.015)
		vertices.append_array(PackedVector3Array([outer_a, inner_a, inner_b, outer_a, inner_b, outer_b]))
	return _geometry(vertices)

func _geometry(vertices: PackedVector3Array) -> ArrayMesh:
	var normals := PackedVector3Array()
	for index: int in range(vertices.size()): normals.append(Vector3(0, 0, -1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
