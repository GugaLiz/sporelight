extends RefCounted
## The original 3-2 mechanisms share sun/moon silhouettes, not floating words.
## Decoration only: no rule, discovery, collision, placement or support writes.
const Props = preload("res://elements/prop_definitions.gd")
const Assets = preload("res://elements/element_assets.gd")
const FACE_RIGHT := Vector3(0.70710678, 0, -0.70710678)
const FACE_UP := Vector3(-0.35355339, 0.8660254, -0.35355339)
const FACE_NORMAL := Vector3(0.61237244, 0.5, 0.61237244)
const SUN := Color("e7b95d")
const MOON := Color("bed9e9")
const DARK := Color("596b67")
static var _shapes: Dictionary = {}
static var _materials: Dictionary = {}
static var _icons: Dictionary = {}
static var _asset_revision := -1
static var _definition_revision := -1

static func stone_spec(mode: int) -> Dictionary:
	return Props.natural_spec("shadow", "sun" if mode == 0 else "moon")

static func build_item(stage: Node, root: Node3D, id: String) -> bool:
	if str(stage.world.level.id) != "3-2" or not id in ["sunPost", "moonPost"]: return false
	var mode := 0 if id == "sunPost" else 1
	var active := int(stage.world.state.get("mode", 0)) == mode
	# Identity belongs to the painted mineral, never a separate badge. Fit the
	# measured opaque body uniformly inside the previous stone envelope and
	# keep the existing conservative footprint and later slot offset.
	var post: Sprite3D = stage._sprite(root, "crystal", 0.5, Vector3.ZERO)
	var spec := stone_spec(mode)
	post.texture = icon_texture(mode)
	post.pixel_size = float(spec.pixelSize)
	var crop: Array = spec.atlasAlpha8
	var foot: Array = spec.footPixel
	post.offset = Vector2(post.texture.get_width() * .5 - (float(foot[0]) - float(crop[0])), float(foot[1]) - float(crop[1]) - post.texture.get_height() * .5)
	post.modulate = Color.WHITE if active else Color(.84, .86, .88)
	post.set_meta("natural_shadow_stone", mode)
	post.set_meta("stone_body_world_size", Vector2(float(spec.visibleWorldSize[0]), float(spec.visibleWorldSize[1])))
	root.set_meta("shadow_role", "post")
	root.set_meta("shadow_mode", mode)
	root.set_meta("shadow_active", active)
	return true

static func build_mark(stage: Node, root: Node3D, mark: Dictionary) -> bool:
	if str(stage.world.level.id) != "3-2": return false
	var id := str(mark.id)
	if id == "mode":
		_mode(stage, root)
	elif id == "freeze":
		_memory(stage, root)
	elif id in ["sunSlot", "moonSlot"]:
		_slot(stage, root, 0 if id == "sunSlot" else 1)
	else: return false
	return true

static func _mode(stage: Node, root: Node3D) -> void:
	var selected := int(stage.world.state.get("mode", 0))
	var offset := Vector3(0.28, 0, 0)
	# Same named base, dimensions and offset as the existing instrument: the
	# shared prop-obstacle builder continues to derive its real hard footprint.
	var base: MeshInstance3D = stage._cylinder(root, 0.19, 0.12, Vector3(0, 0.06, 0) + offset, Color("aaad82"))
	base.name = "InstrumentBase"
	var stem: MeshInstance3D = stage._cylinder(root, 0.055, 0.37, Vector3(0, 0.28, 0) + offset, Color("b9a471"))
	stem.name = "InstrumentStem"
	var face := Basis(FACE_RIGHT, FACE_UP, FACE_NORMAL)
	var center := Vector3(0, 0.48, 0) + offset
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.12
	wheel.outer_radius = 0.17
	var rim: MeshInstance3D = stage._mesh_instance(root, wheel, Color("c9b886"), center)
	rim.name = "InstrumentWheel"
	rim.basis = face * Basis(Vector3.RIGHT, PI / 2)
	for mode in range(2):
		var active := mode == selected
		var at := center + FACE_RIGHT * (-0.078 if mode == 0 else 0.078) + FACE_NORMAL * 0.035
		var ink := SUN if mode == 0 else MOON
		_symbol(root, "CurrentSun" if mode == 0 else "CurrentMoon", mode, at, 0.092 if active else 0.061, ink if active else Color("75827c"), face)
		if active:
			var dot: MeshInstance3D = stage._sphere(root, 0.021, at - FACE_UP * 0.13, ink)
			dot.name = "CurrentModeNotch"
	root.set_meta("shadow_role", "mode")
	root.set_meta("shadow_mode", selected)
	root.set_meta("motion_kind", "daylight")
	root.set_meta("mechanism_state", "sunlight" if selected == 0 else "moonlight")

static func _memory(stage: Node, root: Node3D) -> void:
	var frozen: Variant = stage.world.state.get("frozen")
	var leaf: Sprite3D = stage._sprite(root, "lilypad", 0.60, Vector3(0, 0.035, 0), true)
	leaf.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	leaf.rotation.x = -PI / 2
	leaf.offset = Vector2.ZERO
	leaf.modulate = Color("b5c49d") if frozen == null else Color("d8ca93") if int(frozen) == 0 else Color("a9c5d0")
	var plane := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
	if frozen != null:
		var mode := int(frozen)
		_symbol(root, "RetainedImprintBorder", mode, Vector3(0, 0.045, 0), 0.163, DARK, plane)
		_symbol(root, "RetainedImprint", mode, Vector3(0, 0.048, 0), 0.145, Color("f3d78c") if mode == 0 else Color("d5e8ef"), plane)
		# The same closed contour appears on retained road surfaces. It means
		# the existing impression is held, rather than a second live projection.
		_memory_outline(root, Vector3(0, 0.046, 0), 0.23, SUN if mode == 0 else MOON)
	root.set_meta("shadow_role", "memory")
	root.set_meta("shadow_mode", -1 if frozen == null else int(frozen))
	root.set_meta("mechanism_state", "empty_memory" if frozen == null else "sun_memory" if int(frozen) == 0 else "moon_memory")
	root.set_meta("shadow_memory_points", stage.world.state.get("shadowMemory", []).duplicate(true))
	root.set_meta("not_walkable_support", true)

static func _slot(stage: Node, root: Node3D, mode: int) -> void:
	# A flat soft leaf inlay identifies the suggested resting place; it adds
	# no pedestal or collision and does not turn this suggestion into a rule.
	var leaf: Sprite3D = stage._sprite(root, "lilypad", 0.54, Vector3(0, 0.022, 0), true)
	leaf.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	leaf.rotation.x = -PI / 2
	leaf.offset = Vector2.ZERO
	leaf.modulate = Color("c8c79d") if mode == 0 else Color("a6bbb7")
	var plane := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
	_symbol(root, "SlotImprintBorder", mode, Vector3(0, 0.031, 0), 0.18, DARK, plane)
	_symbol(root, "SlotImprint", mode, Vector3(0, 0.034, 0), 0.16, Color("f3d78c") if mode == 0 else Color("d5e8ef"), plane)
	root.set_meta("shadow_role", "slot")
	root.set_meta("shadow_mode", mode)
	root.set_meta("not_walkable_support", true)

static func finish_build(stage: Node) -> void:
	if str(stage.world.level.id) != "3-2": return
	var frozen: Variant = stage.world.state.get("frozen")
	for tile: Dictionary in stage._tiles:
		if str(tile.get("kind", "")) != "shadow" or not stage.world.visible(tile, stage._tiles): continue
		var mode := 0 if str(tile.id).begins_with("shadow:sun") else 1
		var retained: bool = frozen != null and int(frozen) == mode
		var root := Node3D.new()
		root.name = "ShadowSurfaceImprint_" + str(tile.id).replace(":", "_")
		root.position = stage.tile_position(tile)
		stage._props.add_child(root)
		# Sample the existing physical top instead of using a guessed display
		# height. This is a thin inlay, never an extra supporting surface.
		var surface: Node3D = stage._surface_for_support(str(tile.id))
		var at := root.global_position
		if surface != null and surface.has_method("sample_height"):
			at.y = surface.sample_height(at)
		root.global_position = at + Vector3.UP * 0.008
		var plane := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
		_symbol(root, "RoadImprintBorder", mode, Vector3.ZERO, 0.158, DARK, plane)
		_symbol(root, "RoadImprint", mode, Vector3.UP * 0.003, 0.14, Color("ecd49b") if mode == 0 else Color("d0e2eb"), plane)
		if retained: _memory_outline(root, Vector3.ZERO, 0.32, Color("e1d4ac") if mode == 0 else Color("c6dae4"))
		root.set_meta("shadow_role", "road")
		root.set_meta("shadow_mode", mode)
		root.set_meta("shadow_retained", retained)
		root.set_meta("tile_id", str(tile.id))
		root.set_meta("not_walkable_support", true)

static func _memory_outline(root: Node3D, at: Vector3, radius: float, color: Color) -> void:
	var outline := MeshInstance3D.new()
	outline.name = "RetainedContour"
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.009
	ring.outer_radius = radius
	ring.rings = 32
	ring.ring_segments = 6
	outline.mesh = ring
	outline.position = at
	outline.material_override = _material(color)
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(outline)

static func _symbol(root: Node3D, name: String, mode: int, at: Vector3, radius: float, color: Color, face: Basis) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = _shape(mode)
	node.material_override = _material(color)
	node.position = at
	node.basis = face * Basis.from_scale(Vector3.ONE * radius)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("celestial_mode", mode)
	root.add_child(node)
	return node

static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material

static func _shape(mode: int) -> ArrayMesh:
	if _shapes.has(mode): return _shapes[mode]
	var points := PackedVector2Array()
	var vertices := PackedVector3Array()
	if mode == 0:
		# A round disc and separate short rays read as sunlight rather than
		# the star-shaped collectible silhouettes used elsewhere in the garden.
		for i in range(32):
			var angle := TAU * float(i) / 32.0
			points.append(Vector2(cos(angle), sin(angle)) * 0.56)
		_append_polygon(vertices, points)
		for i in range(8):
			var angle := TAU * float(i) / 8.0
			var direction := Vector2(cos(angle), sin(angle))
			var across := Vector2(-direction.y, direction.x)
			var ray := PackedVector2Array([direction * 0.73 - across * 0.10, direction - across * 0.055, direction + across * 0.055, direction * 0.73 + across * 0.10])
			_append_polygon(vertices, ray)
	else:
		# Two circular arcs create a true cut-out crescent, not a tinted disc.
		const OFFSET := 0.58
		const INNER := 0.88
		var x := (1.0 + OFFSET * OFFSET - INNER * INNER) / (2.0 * OFFSET)
		var y := sqrt(1.0 - x * x)
		var outer_angle := atan2(y, x)
		for i in range(33):
			var angle := lerpf(outer_angle, TAU - outer_angle, float(i) / 32.0)
			points.append(Vector2(cos(angle), sin(angle)))
		var inner_start := atan2(-y, x - OFFSET)
		var inner_end := -TAU - inner_start
		for i in range(1, 32):
			var angle := lerpf(inner_start, inner_end, float(i) / 32.0)
			points.append(Vector2(OFFSET + cos(angle) * INNER, sin(angle) * INNER))
		_append_polygon(vertices, points)
	var normals := PackedVector3Array()
	for unused in vertices.size():
		normals.append(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_shapes[mode] = mesh
	return mesh

static func _append_polygon(vertices: PackedVector3Array, polygon: PackedVector2Array) -> void:
	for index: int in Geometry2D.triangulate_polygon(polygon):
		vertices.append(Vector3(polygon[index].x, polygon[index].y, 0))

static func icon_texture(mode: int) -> Texture2D:
	if _asset_revision != Assets.revision() or _definition_revision != Props.revision():
		_icons.clear()
		_asset_revision = Assets.revision()
		_definition_revision = Props.revision()
	if _icons.has(mode): return _icons[mode]
	var spec := stone_spec(mode)
	var crop: Array = spec.atlasAlpha8
	var texture := AtlasTexture.new()
	texture.atlas = Assets.texture(str(spec.resource))
	texture.region = Rect2(float(crop[0]), float(crop[1]), float(crop[2]), float(crop[3]))
	texture.filter_clip = true
	_icons[mode] = texture
	return texture
