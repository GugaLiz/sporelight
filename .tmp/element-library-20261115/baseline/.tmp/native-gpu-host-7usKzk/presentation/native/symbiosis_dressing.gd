extends RefCounted
## Local 3-3 art: identities belong to real garden objects, not word plaques.
## This adapter reads original rules; it never creates paths or writes progress.
const SOURCES := {
	"wheel": preload("res://assets/images/symbiosis/water-wheel-v1.png"),
	"lift": preload("res://assets/images/symbiosis/lift-frame-v1.png"),
	"root": preload("res://assets/images/symbiosis/root-basin-v1.png"),
	"root_settled": preload("res://assets/images/symbiosis/root-basin-settled-v1.png")
}
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
const RIGHT := Vector3(0.70710678, 0, -0.70710678)
const UP := Vector3(-0.35355339, 0.8660254, -0.35355339)
const NORMAL := Vector3(0.61237244, 0.5, 0.61237244)
const LIFT_OFFSET := Vector3(.28, 0, 0)
const ROOT_OFFSET := Vector3(-.55, 0, -.38)
const BASE_HEIGHT := .025
# The broad root collar contacts the stone at this source-image location.
# The last opaque pixel below it belongs to a trailing fine root, not the
# centre of the hard bowl. Camera elevation is 30 degrees (sin = .5).
const ROOT_BASE_PIXEL := Vector2(794, 740)
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}

static func asset_spec(id: String) -> Dictionary:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/images/symbiosis/manifest.json"))
	return _manifest.assets[id]

static func asset_texture(id: String) -> Texture2D:
	if _textures.has(id): return _textures[id]
	var region: Array = asset_spec(id).atlasAlpha8
	var atlas := AtlasTexture.new()
	atlas.atlas = SOURCES[id]
	atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	atlas.filter_clip = true
	_textures[id] = atlas
	return atlas

static func _art(stage: Node, root: Node3D, id: String, at: Vector3, node_name: String) -> Sprite3D:
	var sprite: Sprite3D = stage._sprite(root, "crystal", .5, at)
	sprite.name = node_name
	sprite.texture = asset_texture(id)
	var spec := asset_spec(id)
	var region: Array = spec.atlasAlpha8
	var foot: Array = spec.footPixel
	sprite.pixel_size = float(spec.pixelSize)
	sprite.offset = Vector2(sprite.texture.get_width() * .5 - (float(foot[0]) - float(region[0])), float(foot[1]) - float(region[1]) - sprite.texture.get_height() * .5)
	sprite.set_meta("symbiosis_asset", id)
	sprite.set_meta("visible_body_size", Vector2(float(spec.visibleWorldSize[0]), float(spec.visibleWorldSize[1])))
	return sprite

static func _pixel_point(id: String, at: Vector3, pixel: Vector2) -> Vector3:
	var spec := asset_spec(id)
	var foot: Array = spec.footPixel
	return at + RIGHT * ((pixel.x - float(foot[0])) * float(spec.pixelSize)) + UP * ((float(foot[1]) - pixel.y) * float(spec.pixelSize)) + NORMAL * .009

static func root_ground_center() -> Vector3:
	var spec := asset_spec("root")
	var foot: Array = spec.footPixel
	var front := Vector3(.70710678, 0, .70710678)
	return ROOT_OFFSET + RIGHT * ((ROOT_BASE_PIXEL.x - float(foot[0])) * float(spec.pixelSize)) - front * ((float(foot[1]) - ROOT_BASE_PIXEL.y) * float(spec.pixelSize) / .5)

static func build_mark(stage: Node, root: Node3D, mark: Dictionary) -> bool:
	if str(stage.world.level.id) != "3-3": return false
	match str(mark.id):
		"turn": _instrument(stage, root, false)
		"lift": _instrument(stage, root, true)
		"care": _root_basin(stage, root)
		"root":
			# The authored decorative root cell is not the actual growing tip.
			# Keep its anchor but share the one receiving root basin at care.
			var anchor := Node3D.new()
			anchor.name = "GrowthAnchor"
			anchor.position = Vector3(.16, .10, .16)
			root.add_child(anchor)
			root.set_meta("shared_visual", "mark:care")
		_: return false
	return true

static func build_item(stage: Node, root: Node3D, id: String, item: Dictionary) -> bool:
	if str(stage.world.level.id) != "3-3" or id != "dew" or bool(item.get("picked", false)): return false
	var dew: Sprite3D = stage._sprite(root, "dew-plant", Ratios.canvas_width("dew-plant") * .72, Vector3.ZERO)
	dew.set_meta("symbiosis_dew_scale", .72)
	return true

static func _instrument(stage: Node, root: Node3D, lift: bool) -> void:
	var offset := LIFT_OFFSET if lift else Vector3(-.30, 0, -.30)
	if not lift:
		root.set_meta("instrument_local_offset", offset)
		offset = offset.rotated(Vector3.UP, -float(stage.world.state.turns.get("water", 0)) * PI / 2)
		root.set_meta("instrument_module", "water")
		root.set_meta("instrument_offset", offset)
	# Preserve the named real obstruction and original circular footprint.
	var base: MeshInstance3D = stage._cylinder(root, .19, BASE_HEIGHT, offset + Vector3(0, BASE_HEIGHT * .5, 0), Color("707963"))
	base.name = "InstrumentBase"
	var art_at := offset + Vector3(0, BASE_HEIGHT, 0)
	_art(stage, root, "lift" if lift else "wheel", art_at, "NaturalLift" if lift else "NaturalWheel")
	root.set_meta("motion_kind", "lift" if lift else "rotate")
	root.set_meta("symbiosis_role", "lift" if lift else "water_wheel")
	if lift:
		root.set_meta("symbiosis_lift", true)
		var pointer: MeshInstance3D = stage._sphere(root, .025, Vector3.ZERO, Color("e5b764"))
		pointer.name = "LiftFloat"
		pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_float(root, float(int(stage.world.state.turns.get("lift", 0)) % 2))

static func _set_float(root: Node3D, step: float) -> void:
	var pixel := Vector2(397, lerpf(1000, 480, clampf(step, 0, 1)))
	root.get_node("LiftFloat").position = _pixel_point("lift", LIFT_OFFSET + Vector3(0, BASE_HEIGHT, 0), pixel)
	root.set_meta("height_step", step)

static func update_motion(stage: Node, before: RefCounted, after: RefCounted, progress: float) -> void:
	if str(after.level.id) != "3-3": return
	var root: Node3D = stage._props_nodes.get("mark:lift")
	if root == null or not root.has_meta("symbiosis_lift"): return
	var start := float(int(before.state.turns.get("lift", 0)) % 2)
	var finish := float(int(after.state.turns.get("lift", 0)) % 2)
	_set_float(root, lerpf(start, finish, clampf(progress, 0, 1)))

static func _root_basin(stage: Node, root: Node3D) -> void:
	var settled := bool(stage.world.flag("root"))
	# Both painted states retain the same measured pixel scale and original
	# foot registration. Receiving dew fills this same bowl, never a new bed.
	var sprite := _art(stage, root, "root_settled" if settled else "root", ROOT_OFFSET, "NaturalRootBasin")
	# Root tips may spread past the stone; the hard bowl has its own local
	# footprint, rather than retaining the removed large flowerbed collider.
	sprite.set_meta("hard_planter", true)
	sprite.set_meta("ground_footprint_span", Vector2(.60, .60))
	sprite.set_meta("ground_footprint_center", root_ground_center())
	sprite.set_meta("hard_base_source_pixel", ROOT_BASE_PIXEL)
	root.set_meta("mechanism_state", "rooted" if settled else "awaiting_dew")
	root.set_meta("symbiosis_role", "root_basin")
