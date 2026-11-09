class_name NativeGardenStage
extends Node2D

## Public facade matches the application view; the garden itself is authored
## 3D geometry and native character bodies, never Canvas vertices in disguise.
signal tile_selected(id: String)
signal command_selected(id: String)

const HEIGHT_UNIT := 0.65
const WorldScene = preload("res://presentation/native/native_world.tscn")
const ActorScene = preload("res://presentation/native/native_actor.tscn")
const Surface = preload("res://presentation/native/native_surface.gd")
const Profiles = preload("res://presentation/native/level_presentation_profiles.gd")
const TerraceMaterials = preload("res://presentation/native/terrace_materials.gd")
const BuddySurface = preload("res://presentation/actors/buddy_surface.gd")
const RuleWorld = preload("res://core/garden_world.gd")
const WaterShader = preload("res://presentation/native/garden_water.gdshader")
const PropShader = preload("res://presentation/native/garden_prop.gdshader")
const ContactShader = preload("res://presentation/native/garden_contact.gdshader")
const MoleArt = preload("res://presentation/native/native_mole_art.gd")
const LowArch = preload("res://presentation/native/native_low_arch.tscn")
const MechanismProfile = preload("res://presentation/native/mechanism_visual_profile.tres")
const CAMERA_RAY := Vector3(0.612372, 0.5, 0.612372)
const CORNERS := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
const DIRECTIONS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

var world: RefCounted
var _presentation: Dictionary = {}
var _terrain_profile: Script
var _dressing: Script

func has_presentation_feature(feature: String) -> bool:
	return bool(_presentation.get(feature, false))

func _select_presentation() -> void:
	_presentation = Profiles.for_level(str(world.level.id)) if world != null else {}
	_terrain_profile = _presentation.get("terrain")
	_dressing = _presentation.get("dressing")

var images: Dictionary = {}
var overview := false
var hint_visible := false
var scale_factor := 1.0
var origin := Vector2.ZERO
var label_font: Font
var visual_time := 0.0
var settings: Dictionary = {}
var _viewport: SubViewport
var _scene: Node3D
var _camera: Camera3D
var _image: Sprite2D
var _terrain: Node3D
var _props: Node3D
var _effects: Node3D
var _actors: Node3D
var _surfaces: Dictionary = {}
var _bodies: Dictionary = {}
var _tiles: Array = []
var _tile_map: Dictionary = {}
var _architecture_tiles: Array = []
var _materials: Dictionary = {}
var _asset_map: Dictionary = {}
var _errors: Array[String] = []
var _layout := Rect2()
var _regions: Array[Rect2] = []
var _paused := false
var _manual_time := false
var _terrain_signature := 0
var _props_signature := 0
var _bounds := AABB()
var _framing_size := 10.0
var _focus := Vector3.ZERO
var _target_focus := Vector3.ZERO
var _fit_focus := Vector3.ZERO
var _last_level := ""
var _buddy_surface: SubViewport
var _actor_state: Dictionary = {}
var _motion_before: RefCounted
var _motion_after: RefCounted
var _motion_kind := ""
var _motion_progress := 0.0
var _motion_key := 0
var _motion_positions: Dictionary = {}
var _props_nodes: Dictionary = {}
var _occluders: Array[Sprite3D] = []
var _build_count := 0
var _last_frame := {}
var _motes: CPUParticles3D
var _effect_signature := 0
var _last_touch_ms := -1000
var _mole_art: SubViewport
var _water_module_roots: Dictionary = {}
var _water_links: Array[Dictionary] = []
var _water_drop_mesh: SphereMesh
var _water_drop_material: StandardMaterial3D
var _interaction_context: Dictionary = {}
var _interaction_ring: MeshInstance3D

class ContextOverlay:
	extends Node2D
	var stage: Node2D
	func _draw() -> void:
		if stage != null: stage.draw_context(self)

var _context_overlay: Node2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/visual-assets.json"))
	if manifest is Dictionary:
		for entry: Dictionary in manifest.get("entries", []):
			_asset_map[str(entry.id)] = str(entry.resource)
	_viewport = WorldScene.instantiate()
	add_child(_viewport)
	_scene = _viewport.get_node("Garden")
	_terrain = _scene.get_node("Terrain")
	_props = _scene.get_node("Props")
	_effects = _scene.get_node("Effects")
	_create_motes()
	_actors = _scene.get_node("Actors")
	_camera = _scene.get_node("Camera")
	_image = Sprite2D.new()
	_image.name = "NativeGardenImage"
	_image.centered = false
	_image.texture = _viewport.get_texture()
	add_child(_image)
	_context_overlay = ContextOverlay.new()
	_context_overlay.stage = self
	add_child(_context_overlay)
	_buddy_surface = BuddySurface.new()
	add_child(_buddy_surface)
	_buddy_surface.update_pose({"ball": _texture("ball")}, 0, {"low_motion": true})
	_buddy_surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	for who: String in ["luvie", "buddy"]:
		_create_actor(who)
	get_viewport().size_changed.connect(_resize)
	_resize()
	if world != null:
		set_world(world)

func _texture(alias: String) -> Texture2D:
	if images.has(alias):
		return images[alias]
	var path: String = str(_asset_map.get(alias, ""))
	if path.is_empty():
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		_errors.append("Missing native texture: " + path)
	images[alias] = texture
	return texture

func asset_errors() -> Array[String]:
	return _errors.duplicate()

func _create_actor(who: String) -> void:
	var body := ActorScene.instantiate() as CharacterBody3D
	body.name = "Luvie" if who == "luvie" else "Buddy"
	body.set_meta("actor_id", who)
	_actors.add_child(body)
	_bodies[who] = body
	_actor_state[who] = {"facing": "front", "moving": false, "action": "", "velocity": Vector3.ZERO, "rolling": false, "emote": ""}
	var art: AnimatedSprite3D = body.get_node("Visual/Art")
	if who == "buddy":
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.13
		capsule.height = 0.56
		(body.get_node("Collision") as CollisionShape3D).shape = capsule
		body.get_node("Collision").position.y = 0.28
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	if who == "luvie":
		for facing: String in ["front", "back", "left", "right"]:
			var idle := "idle-back" if facing == "back" else "idle-side" if facing in ["left", "right"] else "idle-front"
			_add_clip(frames, "idle_" + facing, [idle], 1.0)
			# All directions share the same step cycle duration; only coherent views
			# from the original frame sheets are included.
			var keys: Array[String] = []
			if facing == "back":
				for frame in range(1, 13): keys.append("walk-back-%d" % frame)
			elif facing in ["left", "right"]:
				# The old three poses all extended the same leg. Use the existing
				# complete cycle, including passing feet and the opposite contact.
				for frame in range(1, 13): keys.append("walk-side-%d" % frame)
			else:
				keys.assign(["walk-1", "walk-7", "walk-8", "walk-9", "walk-10", "walk-11", "walk-12", "walk-8"])
			_add_clip(frames, "walk_" + facing, keys, keys.size() / 0.55)
		_add_clip(frames, "interact", ["interact"], 1)
		_add_clip(frames, "sow", ["sow-1", "sow-2", "sow-3", "sow-4", "sow-5"], 9)
		_add_clip(frames, "complete", ["salute"], 1)
		var jump_keys: Array[String] = []
		for index in range(1, 13): jump_keys.append("jump-%d" % index)
		_add_clip(frames, "jump", jump_keys, 24)
		_add_clip(frames, "roll", ["ball"], 1)
		art.offset = Vector2(0, 108)
	else:
		frames.add_animation("idle_front")
		frames.add_frame("idle_front", _buddy_surface.get_texture())
		_add_clip(frames, "roll", ["ball"], 1)
		art.pixel_size = 0.0062
		art.offset = Vector2(0, 48)
	art.sprite_frames = frames
	art.play("idle_front")
	var shadow_mat := _solid_material(Color(0.25, 0.28, 0.19, 0.19), false)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.no_depth_test = false
	(body.get_node("Shadow") as MeshInstance3D).material_override = shadow_mat
	var player: AnimationPlayer = body.get_node("Visual/AnimationPlayer")
	var library := AnimationLibrary.new()
	var breathe := Animation.new()
	breathe.length = 2.4
	breathe.loop_mode = Animation.LOOP_LINEAR
	var track := breathe.add_track(Animation.TYPE_VALUE)
	breathe.track_set_path(track, NodePath(".:scale"))
	breathe.track_insert_key(track, 0.0, Vector3.ONE)
	breathe.track_insert_key(track, 1.2, Vector3(1.004, 1.01, 1.004))
	breathe.track_insert_key(track, 2.4, Vector3.ONE)
	library.add_animation("breathe", breathe)
	for soft: bool in [false, true]:
		var jump := Animation.new()
		jump.length = 0.55
		var jump_track := jump.add_track(Animation.TYPE_VALUE)
		jump.track_set_path(jump_track, NodePath("Art:position"))
		jump.track_set_interpolation_type(jump_track, Animation.INTERPOLATION_CUBIC)
		jump.track_insert_key(jump_track, 0.0, Vector3.ZERO)
		jump.track_insert_key(jump_track, 0.26, Vector3(0, 0.04 if soft else 0.3, 0))
		jump.track_insert_key(jump_track, 0.55, Vector3.ZERO)
		library.add_animation("jump_soft" if soft else "jump", jump)
	player.add_animation_library("", library)
	player.animation_finished.connect(func(clip: StringName) -> void:
		if str(clip).begins_with("jump"):
			_actor_state[who].emote = ""
			if not bool(settings.get("lowMotion", false)): player.play("breathe"))
	player.play("breathe")

func _add_clip(frames: SpriteFrames, clip: String, aliases: Array, fps: float) -> void:
	frames.add_animation(clip)
	frames.set_animation_speed(clip, fps)
	frames.set_animation_loop(clip, clip.begins_with("walk") or clip.begins_with("idle"))
	for alias: String in aliases:
		var texture := _texture(alias)
		if texture != null: frames.add_frame(clip, texture)

func get_actor_body(who: String) -> CharacterBody3D:
	return _bodies.get(who)

func actor_visual_root(who: String) -> Node3D:
	var body := get_actor_body(who)
	return body.get_node("Visual") if body != null else null

func tile_position(tile: Dictionary) -> Vector3:
	var base_height: float = _terrain_profile.base_height(tile) if _terrain_profile != null and _terrain_profile.has_method("base_height") else float(tile.get("h", 0)) * HEIGHT_UNIT
	return physical_position(Vector3(float(tile.get("x", 0)), base_height, float(tile.get("z", 0))))

func physical_position(at: Vector3) -> Vector3:
	return _terrain_profile.to_physical(at) if _terrain_profile != null else at

func logical_position(at: Vector3) -> Vector3:
	return _terrain_profile.to_logical(at) if _terrain_profile != null else at

func _surface_scale(surface: Node3D) -> Vector3:
	return _terrain_profile.tile_scale(surface.center.x) if _terrain_profile != null else Vector3.ONE

func point_position(tile: Dictionary) -> Vector3:
	return tile_position(tile)

func tile_position_id(id: String) -> Vector3:
	return tile_position(_tile_map.get(id, {}))

func world_position(tile: Dictionary) -> Vector3:
	return tile_position(tile)

func support_height(at: Vector3, support_id: String, _who: String = "") -> float:
	var surface: Node3D = _surfaces.get(support_id)
	return float(surface.sample_height(at)) if surface != null else tile_position_id(support_id).y

func stair_pace(at: Vector3, direction: Vector2) -> float:
	if _terrain_profile == null: return 1.0
	var logical := logical_position(at)
	var profile: Dictionary = _terrain_profile.stair_spec(Vector2(logical.x, logical.z))
	if profile.is_empty(): return 1.0
	var along := absf(direction.x) if int(profile.axis) == 0 else absf(direction.y)
	return lerpf(1.0, 0.62, along)

func traversal_profile(from: String, to: String) -> Dictionary:
	var first: Dictionary = _tile_map.get(from, {})
	var last: Dictionary = _tile_map.get(to, {})
	if first.is_empty() or last.is_empty(): return {}
	var delta := Vector2(float(last.x) - float(first.x), float(last.z) - float(first.z))
	var width := 0.5 if has_presentation_feature("full_width_traversal") else Surface.RAMP_HALF_WIDTH
	return {"slope": not is_equal_approx(float(first.h), float(last.h)), "axis": delta.normalized(), "half_width": width, "entry_distance": Surface.LANDING_HALF, "center_clearance": width - 0.16 - 0.02, "from_height": float(first.h) * HEIGHT_UNIT, "to_height": float(last.h) * HEIGHT_UNIT}

func traversal_profiles(from: String) -> Array:
	# First garden has continuous full-width stone surfaces, not individual
	# shoulder lanes. Applying two perpendicular lane gates at its west stair
	# corner traps an off-center capsule between imaginary corridor walls.
	# Physical slopes and the motor's legal-edge guard still govern movement.
	if has_presentation_feature("full_width_traversal"): return []
	var tile: Dictionary = _tile_map.get(from, {})
	var surface: Node3D = _surfaces.get(from)
	if tile.is_empty() or surface == null: return []
	var profiles: Array = []
	for index in range(4):
		var rise := float(surface.rises[index])
		if is_zero_approx(rise): continue
		var axis: Vector2 = DIRECTIONS[index]
		var target := ""
		for candidate: Dictionary in _tiles:
			if is_equal_approx(float(candidate.x), float(tile.x) + axis.x) and is_equal_approx(float(candidate.z), float(tile.z) + axis.y) and is_equal_approx(float(candidate.h) * HEIGHT_UNIT, float(tile.h) * HEIGHT_UNIT + rise):
				target = str(candidate.id)
				break
		var width := 0.5 if has_presentation_feature("full_width_traversal") else Surface.RAMP_HALF_WIDTH
		profiles.append({"from": from, "to": target, "slope": true, "axis": axis, "half_width": width, "entry_distance": Surface.LANDING_HALF, "center_clearance": width - 0.16 - 0.02, "from_height": float(tile.h) * HEIGHT_UNIT, "to_height": float(tile.h) * HEIGHT_UNIT + rise})
	return profiles

func set_world(value: RefCounted) -> void:
	world = value
	_select_presentation()
	if _viewport == null: return
	var changed_level := _last_level != str(world.level.id)
	_last_level = str(world.level.id)
	(_scene.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	(_scene.get_node("Environment") as WorldEnvironment).environment.ambient_light_energy = 0.82
	refresh_world(value, not changed_level)
	if changed_level:
		_calculate_bounds()
		_focus = _fit_focus
		_target_focus = _focus
		_fit_camera(true)
	queue_redraw()

func refresh_world(value: RefCounted, preserve_pose: bool = true) -> void:
	world = value
	_select_presentation()
	if _viewport == null or world == null: return
	_tiles = world.tiles()
	_architecture_tiles = _tiles.duplicate()
	for root: Dictionary in world.level.get("roots", []):
		for socket: Array in root.get("sockets", []):
			_architecture_tiles.append({"x": socket[0], "z": socket[1], "h": root.get("h", 0)})
	_tile_map.clear()
	for tile: Dictionary in _tiles: _tile_map[str(tile.id)] = tile
	var terrain_key := hash([str(world.level.id), _tiles, world.state.get("mode", 0), world.state.get("frozen", null)])
	if terrain_key != _terrain_signature:
		_terrain_signature = terrain_key
		_update_terrain()
	# Discovery/light changes visibility independently of geometry. Moving a
	# lamp must reveal an existing surface without rebuilding that surface.
	for tile: Dictionary in _tiles:
		if _surfaces.has(str(tile.id)): _surfaces[str(tile.id)].visible = world.visible(tile)
	var plate_occupancy: Dictionary = {}
	for mark: Dictionary in world.level.get("marks", []):
		if str(mark.get("kind", "")) == "plate":
			plate_occupancy[str(mark.id)] = str(world.state.actors.get("buddy", "")) == str(mark.tile)
	var props_key := hash([str(world.level.id), world.state.get("items", {}), world.state.get("collected", []), world.state.get("flags", []), world.state.get("completed", false), world.state.get("water", 0), world.state.get("mode", 0), world.state.get("frozen", -1), world.state.get("turns", {}), world.state.get("growth", {}), world.state.get("discovered", []), plate_occupancy, world.state.get("cloudSeed", false), world.state.get("cloudLatch", false), world.state.get("cloudBuddy", "")])
	if props_key != _props_signature:
		_props_signature = props_key
		_update_props()
	var effect_key := hash([world.rays(), world.lamp_ray()])
	if effect_key != _effect_signature:
		_effect_signature = effect_key
		for node in _effects.get_children():
			if node.has_meta("rule_ray"):
				_effects.remove_child(node)
				node.queue_free()
		_add_rays()
	for who: String in _bodies:
		var body: CharacterBody3D = _bodies[who]
		var point: Dictionary = _tile_map.get(str(world.state.actors.get(who, "")), {})
		body.visible = not point.is_empty()
		if not preserve_pose and not point.is_empty():
			body.position = tile_position(point)
			body.velocity = Vector3.ZERO
		_update_carry(who)
		update_actor_visual(who, body.velocity, str(_actor_state[who].facing))
	queue_redraw()

func _update_terrain() -> void:
	_build_count += 1
	var live: Dictionary = {}
	var minimum := 0.0
	for tile: Dictionary in _tiles: minimum = minf(minimum, float(tile.h) * HEIGHT_UNIT)
	var materials := _terrain_materials()
	for tile: Dictionary in _tiles:
		var id := str(tile.id)
		live[id] = true
		var surface: Node3D = _surfaces.get(id)
		if surface == null:
			surface = Surface.new()
			_terrain.add_child(surface)
			_surfaces[id] = surface
		var heights: Array[float] = []
		for direction: Vector2 in DIRECTIONS: heights.append(_ramp_rise(tile, direction))
		var exposed: Array[bool] = []
		for direction: Vector2 in DIRECTIONS:
			exposed.append(not _has_neighbor(tile, direction))
		if _terrain_profile != null:
			# Socket reservations are not walls or floors. Close the island edge
			# underneath a future bridge and keep that foundation stable on sow.
			for index in range(4):
				var neighbor_found := false
				for neighbor: Dictionary in world.level.tiles:
					if is_equal_approx(float(neighbor.x), float(tile.x) + DIRECTIONS[index].x) and is_equal_approx(float(neighbor.z), float(tile.z) + DIRECTIONS[index].y): neighbor_found = true
				exposed[index] = not neighbor_found
		var own_materials: Dictionary = materials
		if str(tile.get("kind", "")) in ["root", "shadow", "bridge"]:
			own_materials = materials.duplicate()
			own_materials.top = _root_material(str(tile.get("kind", "")), tile)
			own_materials.key = str(tile.get("kind", ""))
		if _terrain_profile != null:
			own_materials = _terrace_materials(tile)
		surface.configure(tile, heights, exposed, _terrain_profile.foundation(tile) if _terrain_profile != null else minimum - 0.95, own_materials)
		surface.position = tile_position(tile)
		surface.scale = _surface_scale(surface)
		surface.visible = world.visible(tile)
	for id: String in _surfaces.keys():
		if not live.has(id):
			_surfaces[id].queue_free()
			_surfaces.erase(id)

func _corner_height(tile: Dictionary, offset: Vector2) -> float:
	var corner := Vector2(float(tile.x), float(tile.z)) + offset
	var candidates: Array = []
	for other: Dictionary in _tiles:
		if other.get("solid", false) or tile.get("solid", false): continue
		if absf(float(other.x) - corner.x) <= 0.5001 and absf(float(other.z) - corner.y) <= 0.5001:
			candidates.append(other)
	var connected: Array = [tile]
	var found := true
	while found:
		found = false
		for other: Dictionary in candidates:
			if other in connected: continue
			for current: Dictionary in connected:
				var delta := absf(float(other.x) - float(current.x)) + absf(float(other.z) - float(current.z))
				if is_equal_approx(delta, 1) and absf(float(other.h) - float(current.h)) <= 1.001:
					connected.append(other)
					found = true
					break
	var sum := 0.0
	for value: Dictionary in connected: sum += float(value.h) * HEIGHT_UNIT
	return sum / connected.size()

func _ramp_rise(tile: Dictionary, direction: Vector2) -> float:
	if tile.get("solid", false): return 0.0
	for other: Dictionary in _architecture_tiles:
		if other.get("solid", false): continue
		if is_equal_approx(float(other.x), float(tile.x) + direction.x) and is_equal_approx(float(other.z), float(tile.z) + direction.y) and absf(float(other.h) - float(tile.h)) <= 1.001:
			return (float(other.h) - float(tile.h)) * HEIGHT_UNIT
	return 0.0

func _has_neighbor(tile: Dictionary, direction: Vector2) -> bool:
	for other: Dictionary in _architecture_tiles:
		if is_equal_approx(float(other.x), float(tile.x) + direction.x) and is_equal_approx(float(other.z), float(tile.z) + direction.y) and absf(float(other.h) - float(tile.h)) <= 1.001 and not other.get("solid", false):
			return true
	return false

func _terrain_materials() -> Dictionary:
	var chapter := str(world.level.get("chapter", "valley"))
	var key := "terrain_" + chapter
	if _materials.has(key): return _materials[key]
	var top := _solid_material(Color.WHITE)
	top.albedo_texture = _texture("paving-pond" if chapter == "pond" else "paving-moss" if chapter == "cave" else "paving-valley")
	var side := _solid_material(Color.WHITE)
	side.albedo_texture = _texture("masonry-pond" if chapter == "pond" else "masonry-valley")
	var stair := _solid_material(Color("bcc1a4"))
	var trim := _solid_material(Color("e4dfc1"))
	var values := {"top": top, "side": side, "ramp": stair, "trim": trim, "key": key}
	_materials[key] = values
	return values

func _terrace_materials(tile: Dictionary) -> Dictionary:
	var spec: Dictionary = _terrain_profile.material_spec(tile)
	var key := str(spec.key)
	if not _materials.has(key):
		_materials[key] = TerraceMaterials.create(spec, _terrain_profile, _texture, _solid_material)
	return _materials[key]

func _root_material(kind: String, tile: Dictionary = {}) -> Material:
	var mode := 0 if str(tile.get("id", "")).begins_with("shadow:sun") else 1
	var memory: bool = kind == "shadow" and world.state.get("frozen", null) == mode
	var key := "top_" + kind + ("_%d_%s" % [mode, str(memory)] if kind == "shadow" else "")
	if not _materials.has(key):
		var color := Color("bfcc9b")
		if kind == "shadow":
			color = Color("dacb8c") if mode == 0 else Color("aebcd6")
			if memory: color = color.lightened(0.18)
		var material := _solid_material(color)
		material.albedo_texture = _texture("paving-moss" if kind != "shadow" else "paving-pond")
		if kind == "shadow":
			material.emission_enabled = memory
			material.emission = color * 0.08
		_materials[key] = material
	return _materials[key]

func _solid_material(color: Color, shaded: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if shaded else BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.texture_repeat = true
	return material

func _create_motes() -> void:
	_motes = CPUParticles3D.new()
	_motes.name = "AmbientMotes"
	_motes.amount = 12
	_motes.lifetime = 4.0
	_motes.preprocess = 1.0
	_motes.direction = Vector3.UP
	_motes.spread = 28.0
	_motes.gravity = Vector3.ZERO
	_motes.initial_velocity_min = 0.025
	_motes.initial_velocity_max = 0.08
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(2, 0.6, 2)
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.014
	mesh.height = 0.028
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _solid_material(Color("eadc9c"), false)
	_motes.mesh = mesh
	_scene.add_child(_motes)

func _clear_group(group: Node3D) -> void:
	for child in group.get_children():
		group.remove_child(child)
		child.queue_free()

func _update_props() -> void:
	_clear_group(_props)
	_clear_group(_effects)
	_props_nodes.clear()
	_occluders.clear()
	_water_module_roots.clear()
	_water_links.clear()
	var level: Dictionary = world.level
	for mark: Dictionary in level.get("marks", []):
		var tile: Dictionary = _tile_map.get(str(mark.get("tile", "")), {})
		if tile.is_empty() or not world.visible(tile): continue
		var root := Node3D.new()
		root.name = "Mark_" + str(mark.get("id", "garden"))
		root.position = tile_position(tile)
		root.set_meta("tile_id", str(tile.id))
		_props.add_child(root)
		_props_nodes["mark:" + str(mark.id)] = root
		var kind := str(mark.get("kind", ""))
		match kind:
			"core":
				# First garden retains the entire authored isometric flowerbed.
				if has_presentation_feature("integrated_props"):
					_dressing.planter(self, root)
				else:
					_box(root, Vector3(0.48, 0.07, 0.48), Vector3(0, 0.035, 0), Color("b4bf94"))
					_sprite(root, "bloom" if bool(world.state.get("completed", false)) else "flower", 0.76, Vector3(0, 0.07, 0), true)
			"root":
				# The interaction belongs to the seedbed, not a future road tile.
				var anchor := Node3D.new()
				anchor.name = "GrowthAnchor"
				anchor.position = Vector3(0.16, 0.10, 0.16) if has_presentation_feature("integrated_props") else Vector3(0, 0.10, 0)
				root.add_child(anchor)
				if has_presentation_feature("integrated_props"):
					var seedbed := _sprite(root, "vine", 0.82, Vector3(0.16, 0.012, 0.16), true)
					seedbed.offset = Vector2(0, 102)
					_integrate_prop(seedbed, 1)
					_contact_patch(root, Vector2(0.70, 0.62), Vector3(0, 0.008, 0), 0.19)
				else:
					_sprite(root, "vine", 0.62, Vector3(0, 0.015, 0), true)
			"plate":
				_cylinder(root, 0.3, 0.045, Vector3(0, 0.025, 0), Color("c5cd9f") if str(world.state.actors.get("buddy", "")) != str(tile.id) else Color("eadc9e"))
				var leaf := _sprite(root, "lilypad", 0.49, Vector3(0, 0.06, 0))
				leaf.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				leaf.rotation.x = -PI / 2
			"turn", "valve", "lift":
				_cylinder(root, 0.19, 0.12, Vector3(0.24, 0.06, 0.12), Color("aaad82"))
				_cylinder(root, 0.055, 0.37, Vector3(0.24, 0.28, 0.12), Color("b9a471"))
				var wheel := TorusMesh.new()
				wheel.inner_radius = 0.12
				wheel.outer_radius = 0.17
				var wheel_node := _mesh_instance(root, wheel, Color("e5cd8a"), Vector3(0.24, 0.48, 0.12))
				wheel_node.rotation.x = PI / 2
			"lever":
				_box(root, Vector3(0.38, 0.1, 0.3), Vector3(0.2, 0.05, 0.1), Color("b3b18c"))
				var lever := _box(root, Vector3(0.045, 0.47, 0.045), Vector3(0.2, 0.33, 0.1), Color("c7b179"))
				var held: bool = bool(world.flag(str(mark.id))) or (str(mark.id) == "latch" and bool(world.state.get("cloudLatch", false)))
				lever.rotation.z = -0.38 if held else 0.38
				_sphere(root, 0.09, Vector3(0.11 if held else 0.29, 0.54, 0.1), Color("cf9870"))
			"latch":
				_sprite(root, "arch", 0.92, Vector3(0, 0, -0.1))
			"flower":
				_sprite(root, "bloom" if world.flag(str(mark.id)) else "flowers", 0.67, Vector3.ZERO, true)
			"song":
				_box(root, Vector3(0.62, 0.15, 0.35), Vector3(0, 0.1, 0), Color("b4b993"))
				for index in range(3):
					_box(root, Vector3(0.15, 0.035, 0.25), Vector3(-0.2 + index * 0.2, 0.2, 0), [Color("d9d6a5"), Color("c4d2a5"), Color("b5c9bb")][index])
			"slot":
				_cylinder(root, 0.26, 0.04, Vector3(0, 0.02, 0), Color("c3dbbb"))
			"lamp":
				_sprite(root, "stone-lantern", 0.58, Vector3.ZERO)
			"rest", "observe", "note":
				_sprite(root, "blue-flowers", 0.38, Vector3(0.2, 0, 0.15), true)
			"item":
				if not world.state.get("items", {}).has(str(mark.id)) and not bool(world.state.get("cloudSeed", false)):
					_sprite(root, "spore", 0.38, Vector3(0, 0.23, 0))
					_sprite(root, "vine", 0.4, Vector3.ZERO)
	for id: String in world.state.get("items", {}):
		var item: Dictionary = world.state.items[id]
		if not str(item.get("holder", "")).is_empty() or str(item.get("tile", "")).is_empty(): continue
		var tile: Dictionary = _tile_map.get(str(item.tile), {})
		if tile.is_empty() or not world.visible(tile): continue
		var node := Node3D.new()
		node.name = "Item_" + id
		node.position = tile_position(tile)
		node.set_meta("tile_id", str(tile.id))
		_props.add_child(node)
		_props_nodes["item:" + id] = node
		if id.begins_with("mirror"):
			_cylinder(node, 0.2, 0.09, Vector3(0, 0.045, 0), Color("99af85"))
			var leaf := _sprite(node, "lilypad", 0.6, Vector3(0, 0.11, 0))
			leaf.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			leaf.rotation.x = -PI / 2
			var mirror := _box(node, Vector3(0.53, 0.42, 0.025), Vector3(0, 0.32, 0), Color("d9e6c5"))
			mirror.rotation.y = PI / 4 + int(item.get("angle", 0)) * PI / 2
			var glass := _solid_material(Color("d5e8cd"))
			glass.albedo_texture = _texture("water-pigment")
			glass.uv1_scale = Vector3(0.35, 0.35, 1)
			glass.roughness = 0.35
			mirror.material_override = glass
			for side in [-1, 1]:
				_box(mirror, Vector3(0.022, 0.45, 0.04), Vector3(side * 0.265, 0, 0), Color("bdac73"))
				_box(mirror, Vector3(0.55, 0.022, 0.04), Vector3(0, side * 0.21, 0), Color("bdac73"))
			var leaf_back := _sprite(node, "lilypad", 0.5, Vector3(0, 0.35, 0))
			leaf_back.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			leaf_back.offset = Vector2.ZERO
			leaf_back.rotation.y = mirror.rotation.y + PI
		elif id == "bell":
			_bell(node, Vector3.ZERO)
		elif id in ["sunPost", "moonPost"]:
			var post := _sprite(node, "crystal", 0.5, Vector3.ZERO)
			post.modulate = Color("ffe5a2") if id == "sunPost" else Color("bfd7ff")
			var crest := Label3D.new()
			crest.text = "☀" if id == "sunPost" else "☾"
			crest.position.y = 0.56
			crest.font_size = 42
			crest.pixel_size = 0.006
			crest.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			crest.no_depth_test = false
			node.add_child(crest)
		else:
			_sprite(node, _item_alias(id, item), 0.4 if id != "dew" else 0.46, Vector3.ZERO)
	for collectible: Dictionary in level.get("collectibles", []):
		if str(collectible.id) in world.state.get("collected", []): continue
		var tile: Dictionary = _tile_map.get(str(collectible.tile), {})
		if tile.is_empty() or not world.visible(tile): continue
		var sprite := _sprite(_effects, "spore", 0.39, tile_position(tile) + Vector3(0, 0.28, 0))
		sprite.name = "Discovery_" + str(collectible.id)
		if has_presentation_feature("integrated_props"):
			sprite.pixel_size = 0.40 / sprite.texture.get_width()
			sprite.offset = Vector2.ZERO
			sprite.position.y = support_height(tile_position(tile), str(tile.id)) + 0.18
			_integrate_prop(sprite, 2)
			_contact_patch(_effects, Vector2(0.23, 0.23), tile_position(tile) + Vector3(0, 0.009, 0), 0.13)
	for wall: Array in level.get("walls", []):
		if _dressing != null and _dressing.has_method("obstacle"):
			_dressing.obstacle(self, wall)
			continue
		var wall_mesh := _box(_props, Vector3(0.86, 0.95, 0.86), Vector3(float(wall[0]), 0.45, float(wall[1])), Color.WHITE)
		var masonry := _solid_material(Color.WHITE)
		masonry.albedo_texture = _texture("masonry-valley")
		masonry.uv1_scale = Vector3(0.22, 0.22, 0.22)
		wall_mesh.material_override = masonry
	_add_scenery()
	_add_water()
	_add_sanctuary()
	_add_mole()
	_add_low_passages()
	_add_mechanism_flows()
	_effect_signature = 0

func _item_alias(id: String, item: Dictionary = {}) -> String:
	if id == "bug": return "bug"
	if id == "dew": return "dew-parcel" if item.get("picked", false) else "dew-plant"
	if id == "bell": return "stone-lantern"
	if id == "lamp": return "light"
	if id.begins_with("mirror"): return "lilypad"
	return "crystal"

func _update_carry(who: String) -> void:
	var carry: Sprite3D = _bodies[who].get_node("Visual/Carry")
	var model: Node3D = _bodies[who].get_node("Visual/CarryModel")
	_clear_group(model)
	carry.visible = false
	if who == "luvie" and bool(world.state.get("cloudSeed", false)) and not bool(world.state.get("completed", false)):
		carry.texture = _texture("spore")
		carry.visible = true
	for id: String in world.state.get("items", {}):
		var item: Dictionary = world.state.items[id]
		if str(item.get("holder", "")) == who:
			if id == "bell":
				_bell(model, Vector3.ZERO)
				model.scale = Vector3.ONE * 0.7
			else:
				carry.texture = _texture(_item_alias(id, item))
				carry.visible = true
			break

func _add_mole() -> void:
	if str(world.level.id) != "1-4" and not (str(world.level.id) == "3-4" and bool(world.state.get("completed", false))): return
	var point: Dictionary = {}
	for mark: Dictionary in world.level.get("marks", []):
		if str(mark.get("id", "")) == "home": point = _tile_map.get(str(mark.tile), {})
	if point.is_empty():
		for mark: Dictionary in world.level.get("marks", []):
			if str(mark.get("kind", "")) == "core": point = _tile_map.get(str(mark.tile), {})
	if point.is_empty(): return
	if _mole_art == null:
		_mole_art = MoleArt.new()
		add_child(_mole_art)
	var sprite := Sprite3D.new()
	sprite.name = "MoleResident"
	sprite.texture = _mole_art.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.pixel_size = 0.006
	sprite.offset = Vector2(0, 94)
	sprite.position = tile_position(point) + Vector3(-0.45, 0, 0.12)
	_props.add_child(sprite)
	_occluders.append(sprite)

func _add_sanctuary() -> void:
	var sanctuary: Dictionary = world.level.get("sanctuary", {})
	if sanctuary.is_empty(): return
	var gate: Dictionary = sanctuary.get("gate", {})
	if not gate.is_empty():
		var at := tile_position(gate)
		_sprite(_props, "flower-gate-frame", 1.25, at)
		if not world.flag("home"): _sprite(_props, "flower-gate-seal", 0.76, at + Vector3(0, 0.15, 0.03))
	var fountain: Dictionary = sanctuary.get("fountain", {})
	if fountain.is_empty(): return
	var root := Node3D.new()
	root.name = "SanctuaryFountain"
	root.position = tile_position(fountain)
	_props.add_child(root)
	_cylinder(root, 0.46, 0.1, Vector3(0, 0.05, 0), Color("d7d4b6"))
	_cylinder(root, 0.37, 0.025, Vector3(0, 0.12, 0), Color("a8d2ce"))
	_cylinder(root, 0.085, 0.42, Vector3(0, 0.32, 0), Color("d9d3b0"))
	_cylinder(root, 0.22, 0.07, Vector3(0, 0.56, 0), Color("e1dbbd"))
	_cylinder(root, 0.17, 0.014, Vector3(0, 0.605, 0), Color("badfd6"))
	_sprite(root, "glow-flower", 0.25, Vector3(0, 0.6, 0))

func _add_low_passages() -> void:
	for tile: Dictionary in _tiles:
		if not bool(tile.get("small", false)) or not world.visible(tile): continue
		var entrance := Vector2.ZERO
		for neighbor: Dictionary in world.neighbors(str(tile.id), "buddy", _tiles):
			if not bool(neighbor.get("small", false)):
				entrance = Vector2(float(neighbor.x) - float(tile.x), float(neighbor.z) - float(tile.z))
				break
		if entrance.is_zero_approx(): continue
		var arch: Node3D = LowArch.instantiate()
		arch.name = "LowArch_" + str(tile.id).replace(":", "_")
		arch.position = tile_position(tile) + Vector3(entrance.x, 0, entrance.y) * 0.31
		arch.rotation.y = PI / 2 if absf(entrance.x) > 0.5 else 0.0
		var material := _solid_material(Color.WHITE)
		material.albedo_texture = _texture("masonry-valley")
		material.uv1_scale = Vector3(0.16, 0.22, 0.2)
		for child in arch.get_children():
			if child is MeshInstance3D: child.material_override = material
		_props.add_child(arch)

func _add_mechanism_flows() -> void:
	for module: Dictionary in world.level.get("modules", []):
		if str(module.id) != "water": continue
		var root := Node3D.new()
		root.name = "WaterChannels_" + str(module.id)
		_effects.add_child(root)
		_water_module_roots[str(module.id)] = root
		# Two small channels belong to the physical pump, not to global axes.
		# They stay inside its central tile and use the module's parent transform.
		for direction: Vector2 in [DIRECTIONS[0], DIRECTIONS[1]]:
			var bed := _box(root, Vector3(0.10, 0.016, 0.35), Vector3(direction.x, 0, direction.y) * 0.175 + Vector3(0, 0.036, 0), Color("acbca5"))
			var water := _box(root, Vector3(0.052, 0.009, 0.33), Vector3(direction.x, 0, direction.y) * 0.175 + Vector3(0, 0.049, 0), Color("a2dcd8"))
			bed.rotation.y = PI / 2 if absf(direction.x) > 0.5 else 0.0
			water.rotation.y = bed.rotation.y
		_cylinder(root, 0.08, 0.012, Vector3(0, 0.047, 0), Color("b6dfd6"))
	for route: Dictionary in MechanismProfile.water_routes.get(str(world.level.id), []):
		var anchors: Array = route.get("anchors", [])
		for index in range(1, anchors.size()):
			_create_water_link(str(anchors[index - 1]), str(anchors[index]), route)
	_update_water_presentation()

func _water_route_enabled(route: Dictionary, model: RefCounted) -> bool:
	if route.has("flag") and not model.flag(str(route.flag)): return false
	for id: String in route.get("turns", {}):
		if int(model.state.turns.get(id, 0)) != int(route.turns[id]): return false
	return true

func _create_water_link(from: String, to: String, route: Dictionary) -> void:
	if _water_drop_mesh == null:
		_water_drop_mesh = SphereMesh.new()
		_water_drop_mesh.radius = 0.028
		_water_drop_mesh.height = 0.072
		_water_drop_mesh.radial_segments = 8
		_water_drop_mesh.rings = 4
		_water_drop_material = _solid_material(Color(0.57, 0.83, 0.89, 0.7), false)
		_water_drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_drop_material.vertex_color_use_as_albedo = true
		_water_drop_mesh.material = _water_drop_material
	var root := Node3D.new()
	root.name = "WaterTransfer"
	_effects.add_child(root)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _water_drop_mesh
	var distance := _water_anchor_point(world, from).distance_to(_water_anchor_point(world, to))
	multimesh.instance_count = clampi(int(ceil(distance / 0.95)), 4, 12)
	var drops := MultiMeshInstance3D.new()
	drops.name = "SpacedWaterDrops"
	drops.multimesh = multimesh
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(drops)
	var source := _water_receiver(root)
	var receiver := _water_receiver(root)
	_water_links.append({"node": root, "drops": drops, "source": source, "receiver": receiver, "from": from, "to": to, "route": route})

func _water_receiver(parent: Node3D) -> Node3D:
	var marker := Node3D.new()
	marker.name = "ReceivingWater"
	parent.add_child(marker)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.085
	ring.outer_radius = 0.11
	_mesh_instance(marker, ring, Color("a5cbc3"), Vector3(0, 0.016, 0), false)
	_sphere(marker, 0.045, Vector3(0, 0.1, 0), Color("b3e1dc"))
	return marker

func _water_anchor_point(model: RefCounted, id: String) -> Vector3:
	var parts := id.split(":")
	if parts.size() == 4 and parts[0] == "m":
		return tile_position(model.module_point(parts[1], [int(parts[2]), int(parts[3])]))
	return tile_position(model.point_for(id))

func _water_anchor_between(before: RefCounted, after: RefCounted, id: String, progress: float) -> Vector3:
	var first := _water_anchor_point(before, id)
	var last := _water_anchor_point(after, id)
	var parts := id.split(":")
	if parts.size() != 4 or parts[0] != "m": return first.lerp(last, progress)
	for module: Dictionary in before.level.get("modules", []):
		if str(module.id) != parts[1] or str(module.kind) != "rotate": continue
		var first_center := tile_position(before.module_point(str(module.id), [0, 0]))
		var last_center := tile_position(after.module_point(str(module.id), [0, 0]))
		var delta := posmod(int(after.state.turns.get(module.id, 0)) - int(before.state.turns.get(module.id, 0)), 4)
		var angle := float(delta if delta <= 2 else delta - 4) * PI / 2 * progress
		var local := first - first_center
		var rotated := Vector2(local.x, local.z).rotated(angle)
		var center := first_center.lerp(last_center, progress)
		return Vector3(center.x + rotated.x, lerpf(first.y, last.y, progress), center.z + rotated.y)
	return first.lerp(last, progress)

func _update_water_presentation() -> void:
	if world == null: return
	var before: RefCounted = world if _motion_before == null else _motion_before
	var after: RefCounted = world if _motion_after == null else _motion_after
	var progress := 1.0 if _motion_before == null else clampf(_motion_progress, 0, 1)
	var eased := progress * progress * (3 - 2 * progress)
	for id: String in _water_module_roots:
		var root: Node3D = _water_module_roots[id]
		root.position = _water_anchor_between(before, after, "m:%s:0:0" % id, eased)
		var from_turn := int(before.state.turns.get(id, 0))
		var delta := posmod(int(after.state.turns.get(id, 0)) - from_turn, 4)
		root.rotation.y = -(from_turn + float(delta if delta <= 2 else delta - 4) * eased) * PI / 2
	for link: Dictionary in _water_links:
		var node: Node3D = link.node
		var enabled := _water_route_enabled(link.route, after)
		# A newly aligned receiver does not announce supply before the garden
		# physically docks. Existing supply follows the same moving anchors.
		node.visible = enabled and (_water_route_enabled(link.route, before) or progress >= 0.9999)
		var a := _water_anchor_between(before, after, str(link.from), eased) + Vector3(0, 0.065, 0)
		var b := _water_anchor_between(before, after, str(link.to), eased) + Vector3(0, 0.065, 0)
		(link.source as Node3D).position = a
		(link.receiver as Node3D).position = b
		var multimesh: MultiMesh = (link.drops as MultiMeshInstance3D).multimesh
		multimesh.custom_aabb = AABB(a.min(b) - Vector3.ONE, (a - b).abs() + Vector3.ONE * 2)
		var phase := 0.35 if bool(settings.get("lowMotion", false)) else fposmod(visual_time * 0.00017, 1.0)
		for index in range(multimesh.instance_count):
			var u := (index + phase) / float(multimesh.instance_count)
			var at := a.lerp(b, u) + Vector3(0, sin(u * PI) * minf(0.3, a.distance_to(b) * 0.025), 0)
			var alpha := smoothstep(0, 0.12, u) * (1.0 - smoothstep(0.88, 1.0, u))
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, at))
			multimesh.set_instance_color(index, Color(1, 1, 1, alpha))

func _bell(parent: Node3D, at: Vector3) -> void:
	var bell := CylinderMesh.new()
	bell.top_radius = 0.055
	bell.bottom_radius = 0.14
	bell.height = 0.22
	bell.radial_segments = 24
	_mesh_instance(parent, bell, Color("d7b46c"), at + Vector3(0, 0.2, 0))
	_sphere(parent, 0.035, at + Vector3(0, 0.075, 0), Color("b79656"))
	var loop := TorusMesh.new()
	loop.inner_radius = 0.045
	loop.outer_radius = 0.06
	var handle := _mesh_instance(parent, loop, Color("bd9b58"), at + Vector3(0, 0.35, 0))
	handle.rotation.x = PI / 2

func _add_scenery() -> void:
	if _dressing != null:
		_dressing.scenery(self)
		return
	for tile: Dictionary in _tiles:
		if not world.visible(tile) or str(tile.get("kind", "fixed")) in ["root", "shadow", "module", "bridge"]: continue
		var reserved := false
		for mark: Dictionary in world.level.get("marks", []):
			if str(mark.tile) == str(tile.id): reserved = true
		if reserved: continue
		var seed := absi(hash(str(tile.id)))
		if seed % 4 == 0 and not _has_neighbor(tile, Vector2(0, 1)):
			var at := tile_position(tile) + Vector3(0.32, 0, 0.31)
			at.y = support_height(at, str(tile.id)) + 0.015
			_sprite(_props, ["fern", "pink-flowers", "blue-flowers", "red-mushroom"][int(seed / 7) % 4], 0.36, at, true)
		if seed % 5 == 1 and not _has_neighbor(tile, Vector2(1, 0)):
			var at := tile_position(tile) + Vector3(0.36, -0.15, 0.15)
			_sprite(_props, "trailing-vine", 0.32, at, true)


func _integrate_prop(sprite: Sprite3D, kind: int) -> void:
	# The camera uses a fixed isometric direction; keep original painted axes
	# aligned with it while retaining depth testing and normal occlusion fades.
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.rotation = Vector3(-PI / 6, PI / 4, 0)
	var key := "integrated_prop_%s_%d" % [sprite.texture.resource_path, kind]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = PropShader
		material.set_shader_parameter("original_paint", sprite.texture)
		material.set_shader_parameter("prop_kind", kind)
		_materials[key] = material
	sprite.material_override = _materials[key]

func _contact_patch(parent: Node3D, span: Vector2, at: Vector3, strength: float, square := false) -> void:
	var plane := PlaneMesh.new()
	plane.size = span
	var patch := MeshInstance3D.new()
	patch.name = "ContactPatch"
	patch.mesh = plane
	patch.position = at
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = ContactShader
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("square_footprint", square)
	patch.material_override = material
	parent.add_child(patch)


func set_interaction_context(context: Dictionary) -> void:
	_interaction_context = context
	if _interaction_ring == null:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.35
		ring.outer_radius = 0.38
		_interaction_ring = _mesh_instance(_scene, ring, Color("e8cc83"), Vector3.ZERO, false)
		_interaction_ring.name = "NearbyInteractionRing"
	_interaction_ring.visible = has_presentation_feature("interaction_ring") and not context.is_empty() and not bool(world.state.completed)
	if _interaction_ring.visible:
		_interaction_ring.position = tile_position(context.tile) + Vector3(0, 0.025, 0)

func _add_water() -> void:
	# A chapter backdrop does not imply a water volume. Only the authored
	# water-level garden and the ferry garden own a visible water surface.
	if str(world.level.id) not in ["2-1", "2-4"] and not bool(world.level.get("waterSurface", false)): return
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for tile: Dictionary in _tiles:
		low = low.min(Vector2(float(tile.x), float(tile.z)))
		high = high.max(Vector2(float(tile.x), float(tile.z)))
	if not low.is_finite(): return
	var plane := PlaneMesh.new()
	plane.size = (high - low) + Vector2(3, 3)
	var material := ShaderMaterial.new()
	material.shader = WaterShader
	material.set_shader_parameter("water_paint", _texture("water-pigment"))
	var water := MeshInstance3D.new()
	water.name = "GardenWater"
	water.mesh = plane
	water.material_override = material
	water.position = Vector3((low.x + high.x) / 2, (float(world.state.get("water", 0)) - 0.45) * HEIGHT_UNIT, (low.y + high.y) / 2)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_effects.add_child(water)

func _add_rays() -> void:
	var paths: Array = [world.rays()]
	if world.has_method("lamp_ray"): paths.append(world.lamp_ray())
	for points: Array in paths:
		for index in range(1, points.size()):
			var a := tile_position(points[index - 1]) + Vector3(0, 0.37, 0)
			var b := tile_position(points[index]) + Vector3(0, 0.37, 0)
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.018
			mesh.bottom_radius = 0.018
			mesh.height = a.distance_to(b)
			mesh.radial_segments = 8
			var beam := _mesh_instance(_effects, mesh, Color("ffe3a0"), a.lerp(b, 0.5), false)
			beam.set_meta("rule_ray", true)
			beam.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func _sprite(parent: Node3D, alias: String, width: float, at: Vector3, soft := false) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = alias.replace("-", "_")
	sprite.texture = _texture(alias)
	if alias in ["flower", "bloom"] and sprite.texture != null:
		var plant := AtlasTexture.new()
		plant.atlas = sprite.texture
		plant.region = Rect2(32, 10, 192, 116)
		sprite.texture = plant
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if sprite.texture != null:
		sprite.pixel_size = width / sprite.texture.get_width()
		sprite.offset = Vector2(0, sprite.texture.get_height() * (0.5 if alias in ["flower", "bloom"] else 0.4))
	sprite.position = at
	parent.add_child(sprite)
	if soft: _occluders.append(sprite)
	return sprite

func _mesh_instance(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, shaded := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _solid_material(color, shaded)
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if has_presentation_feature("prop_shadows") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_instance(parent, mesh, color, at)

func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.05
	mesh.height = height
	mesh.radial_segments = 24
	return _mesh_instance(parent, mesh, color, at)

func _sphere(parent: Node3D, radius: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	return _mesh_instance(parent, mesh, color, at)

func set_settings(value: Dictionary) -> void:
	settings = value.duplicate(true)
	if _viewport != null:
		var quality := str(settings.get("quality", "standard"))
		_viewport.msaa_3d = Viewport.MSAA_DISABLED if quality in ["low", "soft"] else Viewport.MSAA_8X if quality == "hd" else Viewport.MSAA_4X
		(_scene.get_node("Sun") as DirectionalLight3D).light_energy = 0.65 if bool(settings.get("dynamicLight", true)) else 0.0
		_motes.visible = bool(settings.get("particles", true))
		_motes.emitting = _motes.visible
		_motes.amount = 8 if quality in ["low", "soft"] else 20 if quality == "hd" else 12
	for who: String in _bodies:
		var player: AnimationPlayer = _bodies[who].get_node("Visual/AnimationPlayer")
		if bool(settings.get("lowMotion", false)):
			player.pause()
			actor_visual_root(who).scale = Vector3.ONE
		else:
			player.play("breathe")
	queue_redraw()

func set_layout(rect: Rect2) -> void:
	if _layout == rect: return
	_layout = rect
	_calculate_bounds()
	_fit_camera(false)

func set_ui_regions(regions: Array) -> void:
	_regions.clear()
	for entry in regions:
		if entry is Rect2:
			_regions.append(entry)
		elif entry is Dictionary:
			var values: Variant = entry.get("rect", [])
			if values is Array and values.size() == 4:
				_regions.append(Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3])))
	queue_redraw()

func set_paused(value: bool) -> void:
	_paused = value
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if value else SubViewport.UPDATE_ALWAYS
	for who: String in _bodies:
		var sprite: AnimatedSprite3D = _bodies[who].get_node("Visual/Art")
		if value: sprite.pause()
		elif not sprite.animation.is_empty(): sprite.play()
		var player: AnimationPlayer = _bodies[who].get_node("Visual/AnimationPlayer")
		if value: player.pause()
		elif not bool(settings.get("lowMotion", false)) or not str(_actor_state[who].get("emote", "")).is_empty(): player.play()

func prepare_initial_frame() -> void:
	# UPDATE_ONCE draws even when the Sprite2D displaying this viewport is
	# hidden. Gameplay, actor animation and audio remain paused at home; the
	# renderer only needs one draw; explicitly release the request afterwards.
	if _viewport != null and _paused:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if not RenderingServer.frame_post_draw.is_connected(_finish_initial_frame):
			RenderingServer.frame_post_draw.connect(_finish_initial_frame, CONNECT_ONE_SHOT)

func _finish_initial_frame() -> void:
	# Continue may have arrived before the draw finished. Never disable the
	# active scene in that case. Keep the observable viewport mode in sync.
	if is_instance_valid(_viewport) and _paused:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func set_visual_time(milliseconds: float) -> void:
	_manual_time = true
	visual_time = milliseconds

func resume_visual_time() -> void:
	_manual_time = false

func _resize() -> void:
	if _viewport == null: return
	var dimensions := get_viewport_rect().size
	_viewport.size = Vector2i(maxi(1, int(dimensions.x)), maxi(1, int(dimensions.y)))
	if world != null: _calculate_bounds()
	_fit_camera(true)
	queue_redraw()

func _calculate_bounds() -> void:
	if world == null: return
	var points: Array = world.level.get("tiles", []).duplicate(true)
	points.append_array(_tiles)
	for root: Dictionary in world.level.get("roots", []):
		for socket: Array in root.get("sockets", []):
			points.append({"x": socket[0], "z": socket[1], "h": root.get("h", 0)})
	for module: Dictionary in world.level.get("modules", []):
		for local: Array in module.get("shape", []):
			for turn in range(4):
				var point := Vector2(float(local[0]), float(local[1])).rotated(turn * PI / 2)
				points.append({"x": float(module.x) + point.x, "z": float(module.z) + point.y, "h": module.get("high", module.get("h", 0))})
	if points.is_empty(): points.append({"x": 0, "z": 0, "h": 0})
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var camera_right := Vector3(0.70710678, 0, -0.70710678)
	var camera_up := Vector3(-0.35355339, 0.8660254, -0.35355339)
	var screen_low := Vector2(INF, INF)
	var screen_high := Vector2(-INF, -INF)
	for point: Dictionary in points:
		var at := tile_position(point)
		low = low.min(at)
		high = high.max(at)
		for offset: Vector3 in [Vector3(-0.5, -0.9, -0.5), Vector3(0.5, 1.6, 0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, -0.5)]:
			var vertex := at + offset
			var screen := Vector2(vertex.dot(camera_right), vertex.dot(camera_up))
			screen_low = screen_low.min(screen)
			screen_high = screen_high.max(screen)
	_bounds = AABB(low, high - low)
	_fit_focus = (low + high) / 2 + Vector3(0, 0.25, 0)
	var size := Vector2(_viewport.size)
	var safe := _safe_rect()
	var aspect := safe.size.x / maxf(1, safe.size.y)
	_framing_size = maxf((screen_high.y - screen_low.y) + 0.75, ((screen_high.x - screen_low.x) + 1.0) / aspect)
	_framing_size *= size.y / maxf(1, safe.size.y)

func _safe_rect() -> Rect2:
	var dimensions := Vector2(_viewport.size) if _viewport != null else get_viewport_rect().size
	if _layout.has_area(): return _layout
	return Rect2(Vector2(22, minf(96, dimensions.y * 0.16)), Vector2(maxf(1, dimensions.x - 44), maxf(1, dimensions.y - minf(180, dimensions.y * 0.28))))

func _fit_camera(immediate: bool = false) -> void:
	if _camera == null or world == null: return
	var dimensions := Vector2(_viewport.size)
	var safe := _safe_rect()
	var small_screen := dimensions.x < 650 or dimensions.y < 430
	var ppu_limit := 52.0 if dimensions.y < 430 else 68.0 if dimensions.x < 650 else 57.0
	var follow_size := dimensions.y / ppu_limit
	var fit_size := maxf(5.8, _framing_size)
	_camera.size = fit_size if overview else follow_size if small_screen else minf(fit_size, follow_size)
	var close_follow := not overview and (small_screen or fit_size > _camera.size * 1.02)
	_target_focus = _fit_focus
	if close_follow:
		var body := get_actor_body(str(world.state.get("active", "luvie")))
		if body != null:
			_target_focus = body.position + Vector3(0, 0.45, 0)
	if immediate: _focus = _target_focus
	var right := Vector3(0.70710678, 0, -0.70710678)
	var up := Vector3(-0.35355339, 0.8660254, -0.35355339)
	var density := dimensions.y / _camera.size
	var anchor := safe.get_center()
	if close_follow and dimensions.x < 650 and dimensions.y > 600:
		anchor.y = safe.position.y + safe.size.y * 0.38
	var offset := anchor - dimensions / 2
	var aim := _focus - right * offset.x / density + up * offset.y / density
	_camera.position = aim + CAMERA_RAY * 60
	_camera.look_at(aim, Vector3.UP)
	scale_factor = density / 49.49747468
	origin = _camera.unproject_position(Vector3.ZERO)

func world_to_screen(at: Vector3) -> Vector2:
	return _camera.unproject_position(at) if _camera != null else Vector2.ZERO

func reset_camera() -> void:
	_fit_camera(true)

func set_actor_mode(who: String, rolling: bool) -> void:
	if _actor_state.has(who): _actor_state[who].rolling = rolling

func reset_actor_actions() -> void:
	for who: String in _actor_state:
		_actor_state[who].emote = ""
		_actor_state[who].rolling = false
		_actor_state[who].action = ""
		var body: CharacterBody3D = _bodies[who]
		var art: AnimatedSprite3D = body.get_node("Visual/Art")
		art.position = Vector3.ZERO
		art.rotation = Vector3.ZERO
		art.scale = Vector3.ONE
		var player: AnimationPlayer = body.get_node("Visual/AnimationPlayer")
		player.stop()
		if not bool(settings.get("lowMotion", false)): player.play("breathe")
		if world != null: update_actor_visual(who, Vector3.ZERO, str(_actor_state[who].facing))

func play_emote(who: String, emote: String) -> void:
	if not _bodies.has(who) or emote != "jump": return
	_actor_state[who].emote = emote
	var player: AnimationPlayer = _bodies[who].get_node("Visual/AnimationPlayer")
	player.play("jump_soft" if bool(settings.get("lowMotion", false)) else "jump")
	update_actor_visual(who, Vector3.ZERO)

func project(point: Dictionary) -> Vector2:
	return world_to_screen(tile_position(point))

func update_actor_visual(who: String, velocity: Vector3, facing: String = "", action: String = "") -> void:
	var body := get_actor_body(who)
	if body == null: return
	var visual_root: Node3D = body.get_node("Visual")
	var support_id := str(world.state.get("actors", {}).get(who, "")) if world != null else ""
	visual_root.position.x = 0.0
	visual_root.position.z = 0.0
	if _surfaces.has(support_id):
		var foot_probe := body.position + Vector3(visual_root.position.x, 0, visual_root.position.z)
		# The capsule contacts a slope with its radius. Its center-bottom may
		# sit above the surface at the art pivot. Ground only the visual child;
		# the physical root remains the single motor's responsibility.
		var ground := support_height(foot_probe, support_id, who)
		var sole := ground
		if has_presentation_feature("smooth_stair_soles") and Vector2(velocity.x, velocity.z).length() > 0.03 and action.is_empty():
			var logical := logical_position(foot_probe)
			sole = maxf(ground, _terrain_profile.stride_height(Vector2(logical.x, logical.z)))
		visual_root.position.y = clampf(sole - body.position.y, -0.2, 0.12)
		(body.get_node("Shadow") as MeshInstance3D).position.y = ground - body.position.y + 0.012
	var moving := Vector2(velocity.x, velocity.z).length() > 0.03
	var state: Dictionary = _actor_state[who]
	if not facing.is_empty(): state.facing = facing
	if moving and facing.is_empty():
		var screen_delta := Vector2(velocity.x - velocity.z, (velocity.x + velocity.z) * 0.5)
		state.facing = "back" if screen_delta.y < 0 and absf(screen_delta.y) > absf(screen_delta.x) * 0.55 else "front" if absf(screen_delta.y) > absf(screen_delta.x) * 0.55 else "right" if screen_delta.x > 0 else "left"
	state.moving = moving
	state.velocity = velocity
	state.action = action
	var sprite: AnimatedSprite3D = body.get_node("Visual/Art")
	var emote := str(state.get("emote", ""))
	var rolling := bool(state.get("rolling", false)) and emote.is_empty()
	if not rolling and emote.is_empty(): sprite.position = Vector3.ZERO
	sprite.scale = Vector3.ONE
	sprite.rotation = Vector3.ZERO
	if who == "buddy":
		# Retain the original companion artwork as one cached texture. Breathing
		# and movement are native transforms; the texture is not redrawn per tick.
		var visual: Node3D = body.get_node("Visual")
		visual.rotation.z = 0.0 if rolling or not moving or settings.get("lowMotion", false) else sin(visual_time * 0.014) * 0.025
		if rolling:
			sprite.play("roll")
			sprite.pixel_size = 0.56 / 99.0
			sprite.offset = Vector2.ZERO
			sprite.position.y = 0.28
			sprite.rotation.z = 0.0 if bool(settings.get("lowMotion", false)) else visual_time * 0.01 * (-1 if str(state.facing) == "left" else 1)
		else:
			sprite.play("idle_front")
			sprite.pixel_size = 0.0062
			sprite.offset = Vector2(0, 48)
		var mode := str(world.state.get("cloudBuddy", ""))
		var waiting := mode in ["sleep", "wait", "sit"] or (not bool(world.state.get("follow", false)) and not moving and str(world.state.get("active", "")) != who)
		if waiting and emote.is_empty() and not rolling:
			sprite.scale = Vector3(1.04, 0.78 if mode in ["sleep", "sit"] else 0.9, 1)
		_align_actor_depth(sprite)
		return
	var clip := ("walk_" if moving else "idle_") + str(state.facing)
	if action != "":
		clip = "sow" if action.begins_with("grow") or action in ["sow", "repair"] else "interact"
	# Completion is persistent progress, not a persistent actor pose. Only
	# the active repair transaction may select the salute; returning to the
	# garden, loading a completed save or stopping a walk restores idle.
	if action == "repair" and bool(world.state.get("completed", false)): clip = "complete"
	if not moving and world.flag("hold") and action.is_empty(): clip = "interact"
	if rolling:
		clip = "roll"
		sprite.pixel_size = 0.8 / 99.0
		sprite.offset = Vector2.ZERO
		sprite.position.y = 0.4
		sprite.rotation.z = 0.0 if bool(settings.get("lowMotion", false)) else visual_time * 0.008 * (-1 if str(state.facing) == "left" else 1)
	else:
		sprite.pixel_size = 0.00625
		sprite.offset = Vector2(0, 108)
	if emote == "jump": clip = "jump"
	if sprite.sprite_frames.has_animation(clip):
		if str(sprite.animation) != clip:
			var was_walking := str(sprite.animation).begins_with("walk_")
			var phase := (sprite.frame + sprite.frame_progress) / sprite.sprite_frames.get_frame_count(sprite.animation) if was_walking else 0.0
			sprite.play(clip)
			# Changing direction must not restart the same foot on every turn.
			if was_walking and clip.begins_with("walk_"):
				var frame_position := phase * sprite.sprite_frames.get_frame_count(clip)
				sprite.set_frame_and_progress(int(frame_position), fposmod(frame_position, 1.0))
		sprite.flip_h = str(state.facing) == "right"
		if moving: sprite.speed_scale = clampf(Vector2(velocity.x, velocity.z).length() / 3.2, 0.45, 1.4)
		else: sprite.speed_scale = 1.0
	_align_actor_depth(sprite)

func _align_actor_depth(sprite: AnimatedSprite3D) -> void:
	# A camera-facing card leans backwards into ascending terrain. Use a
	# vertical card and compensate its projected height, preserving the art,
	# foot pivot and native depth testing rather than drawing over the world.
	if not has_presentation_feature("vertical_actor_depth"):
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		return
	var pose := sprite.basis
	var right := _camera.global_basis.x.normalized()
	var up := Vector3.UP / _camera.global_basis.y.dot(Vector3.UP)
	var forward := right.cross(Vector3.UP).normalized()
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.basis = Basis(right, up, forward) * pose

func actor_ground_point(who: String) -> Dictionary:
	var body := get_actor_body(who)
	if body == null: return {}
	var at: Vector3 = actor_visual_root(who).global_position
	return {"x": at.x, "z": at.z, "h": at.y / HEIGHT_UNIT}

func actor_screen_footpoint(who: String, _include_jump: bool = true) -> Vector2:
	var body := get_actor_body(who)
	return world_to_screen(actor_visual_root(who).global_position) if body != null else Vector2.ZERO

func actor_stair_contact(who: String) -> Dictionary:
	var point := actor_ground_point(who)
	if point.is_empty() or world == null: return {}
	var body := get_actor_body(who)
	var at := Vector3(float(point.x), float(point.h) * HEIGHT_UNIT, float(point.z))
	var support_id := str(world.state.actors.get(who, ""))
	var ground := support_height(at, support_id, who)
	return {"ground": ground / HEIGHT_UNIT, "rail_h": float(point.h), "clearance": maxf(0, at.y - ground), "penetration": maxf(0, ground - at.y), "bodyHeight": body.position.y, "visualHeight": at.y, "supportHeight": ground, "nativeFloor": body.is_on_floor(), "phase": "native-surface"}

func character_presentation() -> Dictionary:
	var result: Dictionary = {}
	for who: String in _bodies:
		var body: CharacterBody3D = _bodies[who]
		var sprite: AnimatedSprite3D = body.get_node("Visual/Art")
		var foot := actor_screen_footpoint(who)
		result[who] = {"point": actor_ground_point(who), "foot": [foot.x, foot.y], "facing": _actor_state[who].facing, "moving": _actor_state[who].moving, "clip": str(sprite.animation), "frame": sprite.frame, "nativeBody": true, "grounded": body.is_on_floor(), "contact": actor_stair_contact(who)}
	var main: Dictionary = result.get("luvie", {})
	result.merge({"pose": {"key": main.get("clip", ""), "clip": main.get("clip", "")}, "key": main.get("clip", ""), "moving": main.get("moving", false), "facing": main.get("facing", "front"), "blend": false, "footpoint": main.get("point", {}), "stair_contact": main.get("contact", {}), "screen_footpoint": {"x": main.get("foot", [0, 0])[0], "y": main.get("foot", [0, 0])[1]}}, true)
	_last_frame = result
	return result

func dialogue_presentation() -> Dictionary:
	return {"visible": false, "fallback": "native-context"}

func render_statistics() -> Dictionary:
	var rebuilds := 0
	for surface: Node3D in _surfaces.values(): rebuilds += int(surface.geometry_rebuilds)
	return {"native": true, "surfaces": _surfaces.size(), "terrainUpdates": _build_count, "meshRebuilds": rebuilds, "props": _props.get_child_count(), "offscreenViews": 1, "viewportUpdateMode": _viewport.render_target_update_mode}

func _process(delta: float) -> void:
	if _paused or world == null: return
	if not _manual_time: visual_time += minf(delta, 0.05) * 1000
	_fit_camera()
	if not bool(settings.get("lowMotion", false)):
		_focus = _focus.lerp(_target_focus, 1.0 - exp(-9.0 * delta))
	else: _focus = _target_focus
	for who: String in _bodies:
		var body: CharacterBody3D = _bodies[who]
		update_actor_visual(who, body.velocity, "", str(_actor_state[who].get("action", "")))
	_update_occlusion()
	_update_water_presentation()
	var body := get_actor_body(str(world.state.get("active", "luvie")))
	if body != null and _motes != null: _motes.position = body.position + Vector3(0, 0.7, 0)
	queue_redraw()

func _update_occlusion() -> void:
	var body := get_actor_body(str(world.state.get("active", "luvie")))
	if body == null: return
	var foot := world_to_screen(body.global_position)
	var head := world_to_screen(body.global_position + Vector3(0, 0.9, 0))
	var density := float(_viewport.size.y) / _camera.size
	for sprite: Sprite3D in _occluders:
		if not is_instance_valid(sprite): continue
		var at := world_to_screen(sprite.global_position)
		var radius := 0.42 * density
		var ahead := (sprite.global_position - body.global_position).dot(CAMERA_RAY) > 0.02
		var overlap := at.x > foot.x - radius and at.x < foot.x + radius and at.y > head.y - radius and at.y < foot.y + radius
		var integrated: bool = sprite.material_override is ShaderMaterial and sprite.material_override.shader == PropShader
		sprite.modulate.a = (0.60 if integrated else 0.3) if ahead and overlap else 1.0

func sample_tile_position(before: Dictionary, after: Dictionary, id: String, progress: float) -> Vector3:
	if _motion_before != null and _motion_after != null and before == _motion_before.state and after == _motion_after.state:
		return _sample_module_position(_motion_before, _motion_after, id, progress)
	var from_world: RefCounted = world.fork(before)
	var to_world: RefCounted = world.fork(after)
	return _sample_module_position(from_world, to_world, id, progress)

func _sample_module_position(from_world: RefCounted, to_world: RefCounted, id: String, progress: float) -> Vector3:
	var first: Dictionary = from_world.point_for(id)
	var last: Dictionary = to_world.point_for(id)
	if first.is_empty(): first = last
	if last.is_empty(): last = first
	var a := tile_position(first)
	var b := tile_position(last)
	var module_id := str(first.get("module", ""))
	for module: Dictionary in from_world.level.get("modules", []):
		if str(module.id) == module_id and str(module.get("kind", "")) == "rotate":
			var turn_from := int(from_world.state.turns.get(module_id, 0))
			var turn_to := int(to_world.state.turns.get(module_id, 0))
			var delta := posmod(turn_to - turn_from, 4)
			var angle := float(delta if delta <= 2 else delta - 4) * PI / 2 * progress
			var pivot := Vector3(float(module.x), a.y, float(module.z))
			var local := a - pivot
			var rotated := Vector2(local.x, local.z).rotated(angle)
			return Vector3(pivot.x + rotated.x, lerpf(a.y, b.y, progress), pivot.z + rotated.y)
	return a.lerp(b, progress)

func set_motion(before: Dictionary, after: Dictionary, progress: float, kind: String) -> void:
	if world == null: return
	var key := hash([before, after, kind])
	if key != _motion_key:
		_motion_key = key
		_motion_before = world.fork(before)
		_motion_after = world.fork(after)
		_motion_kind = kind
		_motion_positions.clear()
		refresh_world(_motion_after, true)
	_motion_progress = clampf(progress, 0, 1)
	var eased := _motion_progress * _motion_progress * (3 - 2 * _motion_progress)
	for id: String in _surfaces:
		var surface: Node3D = _surfaces[id]
		var from: Dictionary = _motion_before.point_for(id)
		var to: Dictionary = _motion_after.point_for(id)
		if to.is_empty(): continue
		surface.position = _sample_module_position(_motion_before, _motion_after, id, eased)
		var turn_angle := 0.0
		for module: Dictionary in _motion_after.level.get("modules", []):
			if str(module.id) == str(to.get("module", "")) and str(module.get("kind", "")) == "rotate":
				var turn_delta := posmod(int(_motion_after.state.turns.get(module.id, 0)) - int(_motion_before.state.turns.get(module.id, 0)), 4)
				turn_angle = float(turn_delta if turn_delta <= 2 else turn_delta - 4) * PI / 2 * (1.0 - eased)
		# Mesh is generated in the destination frame. Back-rotate it while the
		# whole native module follows the same circular rail as its passenger.
		surface.rotation.y = turn_angle
		if from.is_empty():
			if has_presentation_feature("growth_reveal") and surface.thin_plate:
				# Keep each step full-sized and reveal every face from the high
				# landing toward the low landing, regardless of planting direction.
				surface.scale = _surface_scale(surface)
				var direction := _root_growth_direction(id) if has_presentation_feature("path_growth_reveal") else Vector3.ZERO
				surface.set_growth_reveal(eased, not bool(settings.get("lowMotion", false)), direction)
			else:
				surface.scale = Vector3(1, maxf(0.001, eased), 1)
	for node: Node3D in _props_nodes.values():
		var id := str(node.get_meta("tile_id", ""))
		if not id.is_empty(): node.position = _sample_module_position(_motion_before, _motion_after, id, eased)
	var active := str(after.get("active", "luvie"))
	update_actor_visual(active, Vector3.ZERO, "", kind)
	_update_water_presentation()
	queue_redraw()

func _root_growth_direction(id: String) -> Vector3:
	for root: Dictionary in _motion_after.level.get("roots", []):
		var path: Array = _motion_after.state.growth.get(str(root.id), [])
		var index := path.find(id)
		if index < 0: continue
		var previous := str(root.at) if index == 0 else str(path[index - 1])
		var delta := tile_position(_motion_after.point_for(id)) - tile_position(_motion_after.point_for(previous))
		return Vector3(delta.x, 0, delta.z).normalized()
	return Vector3.ZERO

func clear_motion(_smooth_stop: bool = true) -> void:
	if not _smooth_stop: reset_actor_actions()
	_motion_key = 0
	_motion_kind = ""
	_motion_before = null
	_motion_after = null
	_motion_progress = 0.0
	for surface: Node3D in _surfaces.values():
		surface.set_growth_reveal(1.0)
		surface.scale = _surface_scale(surface)
		surface.rotation = Vector3.ZERO
	for who: String in _actor_state:
		_actor_state[who].action = ""
	if world != null: refresh_world(world, true)

func command_hit_test(screen: Vector2) -> String:
	var selected := ""
	var nearest := 23.0
	for choice: Dictionary in growth_choice_layout():
		var distance := screen.distance_to(Vector2(choice.x, choice.y))
		if distance <= nearest:
			nearest = distance
			selected = str(choice.id)
	return selected

func growth_choice_layout() -> Array:
	# Share visibility and hit testing, not a level-specific interaction model.
	# A one-segment choice may sit by its seedbed; a growing path must show the
	# actual next socket so players can trace the route around obstacles.
	var choices: Array = []
	if world == null or _camera == null or _paused: return choices
	for command: Dictionary in world.commands():
		var placement := _growth_choice_placement(command)
		if placement.is_empty(): continue
		var at_world: Vector3 = placement.world_position
		var query := PhysicsRayQueryParameters3D.create(_camera.global_position, at_world, 1)
		var hit := _scene.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and Vector3(hit.position).distance_to(at_world) > 0.15: continue
		var at: Vector2 = placement.position
		var center: Vector2 = placement.anchor
		var blocked := not get_viewport_rect().grow(-23).has_point(at)
		for region: Rect2 in _regions:
			if region.grow(23).has_point(at): blocked = true
		if blocked: continue
		choices.append({"id": str(command.id), "target": str(command.target), "x": at.x, "y": at.y, "anchorX": center.x, "anchorY": center.y, "placement": placement.kind})
	return choices

func _growth_choice_placement(command: Dictionary) -> Dictionary:
	var point := _growth_target(str(command.get("target", "")))
	if point.is_empty(): return {}
	var at_world := tile_position(point) + Vector3(0, 0.05, 0)
	var at := world_to_screen(at_world)
	if not has_presentation_feature("seedbed_growth_choices"):
		return {"world_position": at_world, "position": at, "anchor": at, "kind": "socket"}
	var parts := str(command.id).split(":")
	var directions := {"up": Vector3(0, 0, -1), "right": Vector3(1, 0, 0), "down": Vector3(0, 0, 1), "left": Vector3(-1, 0, 0)}
	if parts.size() != 3 or not directions.has(parts[2]): return {}
	var prop: Node3D = _props_nodes.get("mark:" + parts[1])
	if prop == null: return {}
	var anchor := prop.get_node_or_null("GrowthAnchor") as Node3D
	if anchor == null: return {}
	at_world = anchor.global_position
	var seedbed := world_to_screen(at_world)
	var direction := (world_to_screen(at_world + directions[parts[2]]) - seedbed).normalized()
	var radius := clampf(float(_viewport.size.y) / _camera.size * 0.52, 50.0, 64.0)
	var center := seedbed - Vector2(0, radius * 0.45)
	return {"world_position": at_world, "position": center + direction * radius, "anchor": center, "kind": "seedbed"}

func _growth_target(id: String) -> Dictionary:
	var pieces := id.split(":")
	if pieces.size() < 4: return {}
	for root: Dictionary in world.level.get("roots", []):
		if str(root.id) == pieces[1]:
			return {"x": float(pieces[-2]), "z": float(pieces[-1]), "h": root.get("h", 0)}
	return {}

func hit_test(screen: Vector2) -> String:
	if world == null or _camera == null: return ""
	var sorted := _tiles.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return tile_position(a).dot(CAMERA_RAY) > tile_position(b).dot(CAMERA_RAY))
	for tile: Dictionary in sorted:
		if tile.get("solid", false) or not world.visible(tile): continue
		var polygon := PackedVector2Array()
		for offset: Vector2 in CORNERS:
			var at := physical_position(Vector3(float(tile.x) + offset.x, float(tile.h) * HEIGHT_UNIT, float(tile.z) + offset.y))
			at.y = support_height(at, str(tile.id))
			polygon.append(world_to_screen(at))
		if Geometry2D.is_point_in_polygon(screen, polygon): return str(tile.id)
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if _paused or world == null: return
	var at := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Time.get_ticks_msec() - _last_touch_ms < 450: return
		at = event.position
	elif event is InputEventScreenTouch and event.pressed:
		_last_touch_ms = Time.get_ticks_msec()
		at = event.position
	else: return
	for region: Rect2 in _regions:
		if region.has_point(at): return
	var command := command_hit_test(at)
	if not command.is_empty():
		get_viewport().set_input_as_handled()
		command_selected.emit(command)
	else:
		var id := hit_test(at)
		if not id.is_empty():
			get_viewport().set_input_as_handled()
			tile_selected.emit(id)

func _draw() -> void:
	var dimensions := get_viewport_rect().size
	var chapter := str(world.level.get("chapter", "valley")) if world != null else "valley"
	var background := _texture("background-cave" if chapter == "cave" else "background-pond" if chapter == "pond" else "background-valley")
	if background != null:
		var image_size := background.get_size()
		var scale := maxf(dimensions.x / image_size.x, dimensions.y / image_size.y)
		var draw_size := image_size * scale
		draw_texture_rect(background, Rect2((dimensions - draw_size) / 2, draw_size), false, Color(0.92, 0.94, 0.88, 1))
	else: draw_rect(Rect2(Vector2.ZERO, dimensions), Color("e5e8d5"))
	if _context_overlay != null: _context_overlay.queue_redraw()

func draw_context(canvas: CanvasItem) -> void:
	if world == null or _paused: return
	for choice: Dictionary in growth_choice_layout():
		var at := Vector2(choice.x, choice.y)
		if choice.placement == "socket":
			var target := tile_position(_growth_target(str(choice.target))) + Vector3(0, 0.05, 0)
			var outline := PackedVector2Array()
			for corner: Vector2 in CORNERS:
				outline.append(world_to_screen(target + Vector3(corner.x, 0, corner.y) * 0.82))
			outline.append(outline[0])
			canvas.draw_polyline(outline, Color("dbcd93ad"), 1.2, true)
		canvas.draw_circle(at, 14, Color("fff3d9e8"))
		canvas.draw_arc(at, 14, 0, TAU, 28, Color("9f9f64"), 1.1, true)
		# Geometric strokes keep the plus centered with every fallback font.
		canvas.draw_line(at - Vector2(5, 0), at + Vector2(5, 0), Color("61764b"), 1.5, true)
		canvas.draw_line(at - Vector2(0, 5), at + Vector2(0, 5), Color("61764b"), 1.5, true)
