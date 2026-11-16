class_name GardenView
extends Node2D

signal tile_selected(id: String)
signal command_selected(id: String)

const Iso = preload("res://presentation/world/iso_projection.gd")
const Paint = preload("res://presentation/world/garden_paint.gd")
const Landscape = preload("res://presentation/world/garden_landscape.gd")
const Creatures = preload("res://presentation/actors/creature_art.gd")
const CharacterMotion = preload("res://presentation/actors/character_motion.gd")
const Props = preload("res://presentation/world/garden_prop_art.gd")
const EnvironmentArt = preload("res://presentation/world/garden_environment.gd")
const MoleConversation = preload("res://presentation/actors/mole_conversation.gd")
const WalkBlendSurface = preload("res://presentation/actors/walk_blend_surface.gd")
const BuddySurface = preload("res://presentation/actors/buddy_surface.gd")
const TerrainPresentation = preload("res://presentation/world/terrain_presentation.gd")
const StairSurface = preload("res://presentation/world/stair_surface.gd")
const DepthStage = preload("res://presentation/world/depth_stage.gd")

class DepthOverlay:
	extends Node2D
	var view: Node2D
	func _draw() -> void:
		if view != null:
			view._draw_depth_overlay(self)

var world: RefCounted
var images: Dictionary = {}
var overview := false
var scale_factor := 1.0
var origin := Vector2.ZERO
var label_font: Font
var visual_time := 0.0
var settings := {"lowMotion": false, "particles": true, "dynamicLight": true, "quality": "standard"}
var hint_visible := false
var _layout := Rect2()
var _motion_from: Dictionary = {}
var _motion_to: Dictionary = {}
var _motion_progress := 0.0
var _motion_kind := ""
var _motion_started := 0.0
var _walk_started := 0.0
var _last_walk_end := -1000.0
var _before_world: RefCounted
var _future_world: RefCounted
var _from_tiles: Array = []
var _to_tiles: Array = []
var _scenery: Array = []
var _facing := "front"
var _paused := false
var _manual_time := false
var _asset_errors: Array[String] = []
var _mole_conversation := MoleConversation.new()
var _mole_speech := ""
var _mole_position := Vector2.ZERO
var walk_stop_ms := CharacterMotion.WALK_STOP_MS
var walk_start_ms := CharacterMotion.WALK_START_MS
var _stop_from: Dictionary = {}
var _stop_started := 0.0
var _start_from: Dictionary = {}
var _start_started := 0.0
var _start_facing := "front"
var _blend_surface: SubViewport
var _buddy_surface: SubViewport
var _character_frame: Dictionary = {}
var _in_draw := false
var _draw_tiles: Array = []
var _draw_tile_by_id: Dictionary = {}
var _ui_regions: Array[Rect2] = []
var _dialogue_rect := Rect2()
var _dialogue_fallback := "inactive"
var _pond_geometry: Dictionary = {}
var _pond_geometry_signature := 0
var _from_steps: Array = []
var _to_steps: Array = []
var _depth_stage: SubViewport
var _depth_image: Sprite2D
var _depth_overlay: Node2D
var _overlay_ink: CanvasItem
var _depth_captions: Array = []
var _depth_static_snapshot: Array = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_load_assets()
	_blend_surface = WalkBlendSurface.new()
	add_child(_blend_surface)
	images["_walk_transition"] = _blend_surface.get_texture()
	_buddy_surface = BuddySurface.new()
	add_child(_buddy_surface)
	images["_buddy_composite"] = _buddy_surface.get_texture()
	_depth_stage = DepthStage.new()
	add_child(_depth_stage)
	_depth_image = Sprite2D.new()
	_depth_image.centered = false
	_depth_image.texture = _depth_stage.get_texture()
	_depth_image.visible = false
	add_child(_depth_image)
	_depth_overlay = DepthOverlay.new()
	_depth_overlay.view = self
	_depth_overlay.visible = false
	add_child(_depth_overlay)
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _load_assets() -> void:
	if not images.is_empty():
		return
	var path := "res://content/visual-assets.json"
	if not FileAccess.file_exists(path):
		_asset_errors.append("Missing visual-assets.json; run tools/godot-migration/sync-assets.mjs")
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary:
		_asset_errors.append("Invalid visual-assets.json")
		return
	for entry in manifest.get("entries", []):
		if ResourceLoader.exists(entry.resource):
			var texture: Texture2D = load(entry.resource)
			if texture != null:
				images[entry.id] = texture
			else:
				_asset_errors.append(str(entry.id))
		else:
			_asset_errors.append(str(entry.resource))
	for message in _asset_errors:
		push_warning(message)

func asset_errors() -> Array[String]:
	return _asset_errors.duplicate()

func set_world(value: RefCounted) -> void:
	var old_id := str(world.level.get("id", "")) if world != null else ""
	world = value
	if world != null and old_id != str(world.level.get("id", "")):
		_scenery = Landscape.scenery(world.level)
		_facing = "front"
		_mole_conversation = MoleConversation.new()
		clear_motion(false)
	queue_redraw()

func set_settings(value: Dictionary) -> void:
	settings.merge(value, true)
	if settings.get("lowMotion", false):
		_reset_walk_transitions()
	queue_redraw()

## Empty layout preserves the original camera. Explicit rectangles opt into HUD-safe framing.
func set_layout(rect: Rect2) -> void:
	_layout = rect
	queue_redraw()

func set_ui_regions(regions: Array) -> void:
	var rectangles: Array[Rect2] = []
	for entry in regions:
		if not entry is Dictionary:
			continue
		var value: Variant = entry.get("rect", [])
		if value is Rect2:
			if value.has_area():
				rectangles.append(value)
		elif value is Array and value.size() == 4:
			var rect := Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
			if rect.has_area():
				rectangles.append(rect)
	if rectangles != _ui_regions:
		_ui_regions = rectangles
		queue_redraw()

func set_paused(value: bool) -> void:
	_paused = value

func set_visual_time(milliseconds: float) -> void:
	visual_time = milliseconds
	_manual_time = true
	queue_redraw()

func resume_visual_time() -> void:
	_manual_time = false

func set_motion(from: Dictionary, to: Dictionary, progress: float, kind: String) -> void:
	if world == null:
		return
	if _motion_from != from or _motion_to != to or _motion_kind != kind:
		var previous_walk := _luvie_walking(_motion_from, _motion_to, _motion_kind)
		var next_walk := _luvie_walking(from, to, kind)
		var linked_walk: bool = previous_walk and next_walk and from.get("actors", {}).get("luvie", "") == _motion_to.get("actors", {}).get("luvie", "") and from.get("levelId", "") == _motion_to.get("levelId", "")
		var resume_stop: bool = next_walk and not _stop_from.is_empty() and visual_time - _stop_started < clampf(walk_stop_ms, 80, 120)
		if next_walk and not linked_walk:
			_start_from = character_presentation().get("pose", {}).duplicate(true)
			_start_started = visual_time
			_start_facing = "" if resume_stop else _facing
			if not resume_stop:
				_walk_started = visual_time
		elif not next_walk:
			_start_from = {}
		_stop_from = {}
		_motion_from = from.duplicate(true)
		_motion_to = to.duplicate(true)
		_motion_kind = kind
		_motion_started = visual_time
		# Build rule-derived endpoints once per motion, never on every draw frame.
		if world.has_method("fork"):
			_before_world = world.fork(from)
			_future_world = world.fork(to)
			_from_tiles = _before_world.tiles()
			_to_tiles = _future_world.tiles()
		elif world.has_method("tiles_for_state"):
			_from_tiles = world.tiles_for_state(from)
			_to_tiles = world.tiles_for_state(to)
		else:
			_from_tiles = world.tiles()
			_to_tiles = world.tiles()
		if TerrainPresentation.enabled(world.level):
			_from_steps = Landscape.steps(_from_tiles)
			_to_steps = Landscape.steps(_to_tiles)
		if from.get("actors", {}).get("luvie", "") != to.get("actors", {}).get("luvie", ""):
			var first := _tile_for(str(from.get("actors", {}).get("luvie", "")), _from_tiles)
			var last := _tile_for(str(to.get("actors", {}).get("luvie", "")), _to_tiles)
			if not first.is_empty() and not last.is_empty():
				_facing = _travel_facing(first, last)
	_motion_progress = clampf(progress, 0, 1)
	queue_redraw()

func _travel_facing(first: Dictionary, last: Dictionary) -> String:
	if str(world.level.id) != "1-1":
		return CharacterMotion.facing_for(Iso.raw(last) - Iso.raw(first))
	var delta := Vector2(float(last.x) - float(first.x), float(last.z) - float(first.z))
	if delta.is_zero_approx():
		return _facing
	if absf(delta.x) >= absf(delta.y):
		return "right" if delta.x > 0.0 else "left"
	return "front" if delta.y > 0.0 else "back"

func clear_motion(smooth_stop: bool = true) -> void:
	if smooth_stop and not settings.get("lowMotion", false) and _luvie_walking(_motion_from, _motion_to, _motion_kind):
		_stop_from = character_presentation().get("pose", {}).duplicate(true)
		_stop_started = visual_time
		_last_walk_end = visual_time
		_start_from = {}
	elif not smooth_stop or not _motion_from.is_empty():
		_reset_walk_transitions()
	_motion_from = {}
	_motion_to = {}
	_motion_kind = ""
	_from_tiles = []
	_to_tiles = []
	_before_world = null
	_future_world = null
	_from_steps = []
	_to_steps = []
	queue_redraw()

func _luvie_walking(from: Dictionary, to: Dictionary, kind: String) -> bool:
	return kind in ["move", "rejoin"] and not from.is_empty() and from.get("actors", {}).get("luvie", "") != to.get("actors", {}).get("luvie", "")

func _reset_walk_transitions() -> void:
	_stop_from = {}
	_start_from = {}
	_last_walk_end = -1000.0
	_walk_started = visual_time
	if _blend_surface != null:
		_blend_surface.deactivate()

## Read-only visual diagnostics. The anchor is a real grid point, never an
## inertial presentation position. Tests and QA can inspect phase continuity.
func character_presentation() -> Dictionary:
	if world == null:
		return {"pose": {}, "moving": false, "blend": false}
	var state := _state()
	var moving: bool = not _motion_from.is_empty() and _motion_from.get("actors", {}).get("luvie", "") != _motion_to.get("actors", {}).get("luvie", "")
	var active: bool = state.get("active", "luvie") == "luvie"
	var action := _motion_kind if not moving and active else ""
	var travel: Dictionary = {"progress": _motion_progress, "started_at": _walk_started, "jump": _motion_kind == "hop", "rolling": _motion_kind == "roll", "distance": 45} if moving else {"progress": _motion_progress, "started_at": _motion_started, "jump": true, "rolling": false, "distance": 0} if _motion_kind in ["jump", "hop"] and active else {}
	var action_pose: Dictionary = {}
	if action == "repair" or action.begins_with("grow:") or action == "use:plant":
		action_pose = {"kind": "sow", "started_at": _motion_started}
	elif action.begins_with("take:") or action.begins_with("drop:") or action.begins_with("use:"):
		action_pose = {"kind": "interact", "started_at": _motion_started}
	var pose := CharacterMotion.grounded_pose(CharacterMotion.pose(_time(), _facing, settings.get("lowMotion", false), state.get("completed", false) and not moving and _motion_kind not in ["jump", "hop"], travel, action_pose))
	if not moving and action.is_empty() and state.get("active", "") == "buddy" and not settings.get("lowMotion", false):
		pose.key = "idle-side" if int(_time() / 3600) % 3 == 1 else "lean" if int(_time() / 3600) % 3 == 2 else "idle-front"
	var result := {"pose": pose, "key": str(pose.key), "moving": moving, "blend": false, "stop_blend_active": false, "weight": 1.0, "from_key": str(pose.key), "to_key": str(pose.key), "walk_started": _walk_started, "facing": _facing, "stop_progress": 1.0}
	var before := _tile_for(str(state.get("actors", {}).get("luvie", "")), _tiles())
	if not before.is_empty():
		result["anchor"] = _interpolate(before, _tile_for(str(_motion_to.get("actors", {}).get("luvie", "")), _to_tiles), true)
		result["footpoint"] = actor_ground_point("luvie")
		var screen_point := actor_screen_footpoint("luvie")
		result["screen_footpoint"] = {"x": screen_point.x, "y": screen_point.y}
		result["stair_contact"] = actor_stair_contact("luvie")
	if settings.get("lowMotion", false) or state.get("completed", false):
		return result
	if not moving and action.is_empty() and not _stop_from.is_empty():
		var progress := clampf((visual_time - _stop_started) / clampf(walk_stop_ms, 80, 120), 0, 1)
		result.pose = CharacterMotion.settle_parameters(_stop_from, pose, progress)
		result.from_key = str(_stop_from.key)
		result.to_key = str(pose.key)
		result.weight = progress * progress * (3 - 2 * progress)
		result.stop_progress = progress
		result.stop_blend_active = progress < 1
		result.blend = progress < 1 and result.from_key != result.to_key and bool(_stop_from.get("flip", false)) == bool(pose.get("flip", false))
	elif _luvie_walking(_motion_from, _motion_to, _motion_kind) and not _start_from.is_empty():
		var progress := clampf((visual_time - _start_started) / clampf(walk_start_ms, 40, 90), 0, 1)
		result.pose = CharacterMotion.settle_parameters(_start_from, pose, progress)
		result.from_key = str(_start_from.get("key", pose.key))
		result.to_key = str(pose.key)
		result.weight = progress * progress * (3 - 2 * progress)
		result.blend = progress < 1 and _start_facing == _facing and result.from_key != result.to_key
	return result

func _process(delta: float) -> void:
	if not _paused and not _manual_time:
		visual_time += minf(delta, 0.05) * 1000.0
	queue_redraw()

func _state() -> Dictionary:
	return _motion_from if not _motion_from.is_empty() else world.state

func _tiles() -> Array:
	if _in_draw:
		return _draw_tiles
	return _from_tiles if not _motion_from.is_empty() else world.tiles()

func _rule_world() -> RefCounted:
	return _before_world if _before_world != null else world

func _time() -> float:
	return 0.0 if settings.get("lowMotion", false) else visual_time

func _ease() -> float:
	return _motion_progress * _motion_progress * (3 - 2 * _motion_progress)

func _tile_for(id: String, tiles: Array) -> Dictionary:
	for tile in tiles:
		if str(tile.id) == id:
			return tile
	return {}

func _interpolate(point: Dictionary, next: Dictionary, travel := false) -> Dictionary:
	if next.is_empty() or _motion_from.is_empty():
		return point
	var progress := _motion_progress if travel and _motion_kind in ["move", "roll", "rejoin"] else _ease()
	if point.has("module") and point.get("id", "") == next.get("id", ""):
		for module in world.level.get("modules", []):
			if module.id == point.module and module.kind == "rotate":
				var before := int(_motion_from.get("turns", {}).get(module.id, 0))
				var after := int(_motion_to.get("turns", {}).get(module.id, 0))
				var turns := posmod(after - before, 4)
				if turns > 2:
					turns -= 4
				var rotated := Vector2(float(point.x) - float(module.x), float(point.z) - float(module.z)).rotated(turns * PI / 2 * _ease())
				return Iso.point(float(module.x) + rotated.x, float(module.z) + rotated.y, lerpf(float(point.h), float(next.h), _ease()))
	return Iso.interpolate(point, next, progress)

func project(point: Dictionary) -> Vector2:
	return origin + Iso.raw(point) * scale_factor

func _player_point(state: Dictionary, tiles: Array) -> Dictionary:
	var actor: String = state.get("active", "luvie")
	var before := _tile_for(str(state.get("actors", {}).get(actor, "")), tiles)
	if before.is_empty():
		return Iso.point(0, 0)
	if _motion_from.is_empty():
		return before
	return _interpolate(before, _tile_for(str(_motion_to.get("actors", {}).get(actor, "")), _to_tiles), true)

func _stair_surface(tiles: Array) -> Dictionary:
	if world == null or str(world.level.id) != "1-1":
		return {}
	var low := _tile_for("g:root:1:0", tiles)
	var high := _tile_for("f:2:0", tiles)
	return StairSurface.build(world.level, [low, high]) if not low.is_empty() and not high.is_empty() else {}

func _travel_progress() -> float:
	return _motion_progress if _motion_kind in ["move", "roll", "rejoin"] else _ease()

## One coordinate convention covers the entire pilot, including landing exits.
## Artwork pivots never enter world x/z or the anchor used by depth testing.
func _actor_uses_contact(_actor: String) -> bool:
	return world != null and str(world.level.id) == "1-1"

func _actor_surface(actor: String) -> Dictionary:
	if not _actor_uses_contact(actor):
		return {}
	var first := _tile_for(str(_state().get("actors", {}).get(actor, "")), _tiles())
	var last := _tile_for(str(_motion_to.get("actors", {}).get(actor, "")), _to_tiles)
	if not first.is_empty() and not last.is_empty() and str(first.id) != str(last.id):
		return StairSurface.connection(world.level, [first, last])
	var surface := _stair_surface(_tiles())
	return surface if not surface.is_empty() and str(first.get("id", "")) in [str(surface.low.id), str(surface.high.id)] else {}

func actor_ground_point(actor: String) -> Dictionary:
	var before := _tile_for(str(_state().get("actors", {}).get(actor, "")), _tiles())
	if before.is_empty():
		return Iso.point(0, 0)
	var after := _tile_for(str(_motion_to.get("actors", {}).get(actor, "")), _to_tiles)
	if not _actor_uses_contact(actor):
		return _interpolate(before, after, true)
	var point := Iso.interpolate(before, after, _travel_progress()) if not _motion_from.is_empty() and not after.is_empty() else Iso.point(float(before.x), float(before.z), float(before.h))
	point.z += -0.18 if actor == "luvie" else 0.18
	point.x += -0.02 if actor == "luvie" else -0.18
	if not after.is_empty() and str(before.id) != str(after.id):
		var surface := _actor_surface(actor)
		if not surface.is_empty():
			var direction: Vector2 = surface.direction
			var u := Vector2(float(point.x) - float(surface.low.x), float(point.z) - float(surface.low.z)).dot(direction)
			point.h = StairSurface.contact(surface, u).h
	return point

func _actor_jump(actor: String) -> float:
	return CharacterMotion.jump_height(_motion_progress, settings.get("lowMotion", false)) * scale_factor if _motion_kind in ["jump", "hop"] and _state().get("active", "luvie") == actor else 0.0

func actor_screen_footpoint(actor: String, include_jump := true) -> Vector2:
	var at := project(actor_ground_point(actor))
	if not _actor_uses_contact(actor):
		at += Vector2(_actor_offset(actor), (7.0 if actor == "luvie" else 4.0) * scale_factor)
	return at - Vector2(0, _actor_jump(actor) if include_jump else 0.0)

func actor_stair_contact(actor: String) -> Dictionary:
	var surface := _actor_surface(actor)
	if surface.is_empty():
		return {}
	var point := actor_ground_point(actor)
	var direction: Vector2 = surface.direction
	var delta := Vector2(float(point.x) - float(surface.low.x), float(point.z) - float(surface.low.z))
	var u := delta.dot(direction)
	var v := delta.dot(Vector2(-direction.y, direction.x))
	var result := StairSurface.contact(surface, u)
	if u < -0.5 or u > 1.5 or absf(v) > float(surface.half_width) or not is_equal_approx(float(point.h), float(result.h)):
		return {}
	result.merge({"u": u, "v": v, "key": surface.key}, true)
	return result

func _camera(tiles: Array, player: Dictionary) -> void:
	var size := get_viewport_rect().size
	var all: Array = tiles.duplicate()
	for module in world.level.get("modules", []):
		all.append(Iso.point(float(module.x) + 4, float(module.z) + 4, float(module.get("high", module.h))))
		all.append(Iso.point(float(module.x) - 4, float(module.z) - 4, float(module.h)))
	if world.level.get("chapter", "") == "pond":
		all.append_array(Landscape.pond_footprint(world.level))
	if all.is_empty():
		return
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for point in all:
		var raw := Iso.raw(point)
		min_x = minf(min_x, raw.x)
		max_x = maxf(max_x, raw.x)
		min_y = minf(min_y, raw.y)
		max_y = maxf(max_y, Iso.raw(Iso.point(point.x, point.z)).y)
	min_x -= 65
	max_x += 65
	min_y -= 120
	max_y += 145 if world.level.get("chapter", "") == "valley" else 125
	var max_scale := 1.5 if world.level.get("chapter", "") == "valley" else 1.28
	if _layout.has_area():
		scale_factor = maxf(0.05, minf(max_scale, minf(_layout.size.x / (max_x - min_x), _layout.size.y / (max_y - min_y))))
		origin = _layout.get_center() - Vector2((min_x + max_x) / 2, (min_y + max_y) / 2) * scale_factor
	elif size.x < 650 and not overview:
		scale_factor = 0.92
		origin = Vector2(size.x * 0.38, size.y * 0.5) - Iso.raw(player) * scale_factor
	else:
		scale_factor = maxf(0.05, minf(max_scale, minf((size.x - (25 if size.x < 650 else 330)) / (max_x - min_x), (size.y - (310 if size.x < 650 else 185)) / (max_y - min_y))))
		origin = Vector2(size.x * (0.5 if size.x < 650 else 0.46), size.y * 0.52) - Vector2((min_x + max_x) / 2, (min_y + max_y) / 2) * scale_factor

func _visible(tile: Dictionary) -> bool:
	var model := _rule_world()
	var probe: Dictionary = tile
	if not tile.has("id"):
		probe = tile.duplicate()
		probe["id"] = ""
	return bool(model.visible(probe)) if model.has_method("visible") else true

func _flag(id: String) -> bool:
	return id in _state().get("flags", [])

func _near(id: String) -> bool:
	var state := _state()
	var tiles := _tiles()
	var actor_id := str(state.get("actors", {}).get(state.get("active", "luvie"), ""))
	var a: Dictionary = _draw_tile_by_id.get(actor_id, {}) if _in_draw else _tile_for(actor_id, tiles)
	var b: Dictionary = _draw_tile_by_id.get(id, {}) if _in_draw else _tile_for(id, tiles)
	return not a.is_empty() and not b.is_empty() and absf(float(a.h) - float(b.h)) <= 0.1 and Landscape.distance(a, b) <= 1

func _ready_to_plant() -> bool:
	var model := _rule_world()
	return bool(model.ready()) if model.has_method("ready") else false

## Only one world-space pond layout survives. Camera, animation and water-height
## changes still project and draw every frame; changing geography replaces it.
func pond_geometry(level: Dictionary, tiles: Array) -> Dictionary:
	var signature := hash([level, tiles])
	if _pond_geometry.is_empty() or signature != _pond_geometry_signature:
		_pond_geometry = EnvironmentArt.build_pond_geometry(level, tiles)
		_pond_geometry_signature = signature
	return _pond_geometry

func _draw() -> void:
	if world == null:
		return
	if images.is_empty():
		_load_assets()
	var size := get_viewport_rect().size
	var level: Dictionary = world.level
	var state := _state()
	_depth_captions = []
	var depth_enabled := str(level.id) == "1-1" and _depth_stage != null
	if _depth_image != null:
		_depth_image.visible = depth_enabled
		_depth_overlay.visible = depth_enabled
		_depth_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS if depth_enabled else SubViewport.UPDATE_DISABLED
		if not depth_enabled and _buddy_surface != null:
			_buddy_surface.deactivate()
	_in_draw = false
	var tiles := _tiles()
	_draw_tiles = tiles
	_draw_tile_by_id = {}
	for tile in tiles:
		if not _draw_tile_by_id.has(tile.id):
			_draw_tile_by_id[tile.id] = tile
	_in_draw = true
	var time := _time()
	_camera(tiles, _player_point(state, tiles))
	_character_frame = character_presentation()
	if _blend_surface != null:
		if _character_frame.get("blend", false) and images.has(_character_frame.from_key) and images.has(_character_frame.to_key):
			_blend_surface.blend(images[_character_frame.from_key], images[_character_frame.to_key], _character_frame.weight)
		else:
			_blend_surface.deactivate()
	_mole_speech = ""
	var p := Paint.new(self, images)
	EnvironmentArt.background(p, size, level.get("chapter", "valley"))
	if level.get("chapter", "") == "pond":
		EnvironmentArt.rain(p, size, time, false, settings)
		EnvironmentArt.pond(p, self, level, tiles, _water_height(), time, settings)
	var objects: Array = []
	var painted: Array = []
	for tile in tiles:
		if not _visible(tile):
			continue
		var next := _tile_for(str(tile.id), _to_tiles)
		var point: Dictionary = tile.duplicate()
		point.merge(_interpolate(tile, next), true)
		point["alpha"] = 1.0 if _motion_from.is_empty() or not next.is_empty() else 1.0 - _ease()
		painted.append(point)
	if not _motion_from.is_empty():
		for tile in _to_tiles:
			if _tile_for(str(tile.id), tiles).is_empty():
				var point: Dictionary = tile.duplicate()
				point["alpha"] = _ease()
				painted.append(point)
	var connections := _step_entries(painted)
	for tile in painted:
		_add_object(objects, "floor", tile, 0, {"tile": tile})
	for connection in connections:
		var pair: Array = connection.pair
		var surface := StairSurface.connection(level, pair)
		var depth := StairSurface.stairs_depth(surface) if not surface.is_empty() else maxf(Iso.ground_depth(pair[0]), Iso.ground_depth(pair[1])) + 0.04
		objects.append({"kind": "steps", "depth": depth, "order": objects.size(), "pair": pair, "alpha": connection.alpha, "surface": surface})
	if str(level.id) == "1-1":
		for surface: Dictionary in StairSurface.connectors(level, painted):
			if str(surface.style) == "ramp":
				objects.append({"kind": "ramp", "depth": Iso.ground_depth(surface.low), "order": objects.size(), "pair": [surface.low, surface.high], "alpha": minf(float(surface.low.get("alpha", 1.0)), float(surface.high.get("alpha", 1.0))), "surface": surface})
	var runoff := EnvironmentArt.runoff_source(level, tiles)
	if not runoff.is_empty() and level.get("chapter", "") != "cave":
		_add_object(objects, "runoff", runoff, 0.6, {"point": runoff})
	_add_surface_lines(objects)
	for prop in _scenery:
		var visibility_probe: Dictionary = prop.duplicate()
		visibility_probe["id"] = ""
		if _visible(visibility_probe):
			_add_object(objects, "prop", prop, 0.08, {"prop": prop}, float(prop.get("depth", Iso.ground_depth(prop) + 0.08)))
	if level.has("sanctuary"):
		_add_object(objects, "gate", level.sanctuary.gate, 0.2)
		_add_object(objects, "fountain", level.sanctuary.fountain, 0.1)
		if settings.get("particles", true):
			objects.append({"kind": "butterflies", "depth": 1000.0, "order": objects.size()})
	if level.id == "1-4" or level.id == "3-4" and state.get("completed", false):
		var home: Dictionary = {}
		for mark in level.get("marks", []):
			if mark.get("id", "") == "home":
				home = mark
		if home.is_empty():
			for mark in level.get("marks", []):
				if mark.kind == "core":
					home = mark
		var tile := _tile_for(str(home.get("tile", "")), tiles)
		if not tile.is_empty():
			var mole_point := Iso.point(float(tile.x) - 1, float(tile.z) + 0.3, tile.h)
			_mole_position = project(mole_point)
			if level.id == "1-4":
				_mole_speech = _mole_conversation.update(state, _near(str(tile.id)), visual_time)
			_add_object(objects, "mole", tile, 0.2, {"point": mole_point})
	for wall in level.get("walls", []):
		_add_object(objects, "wall", Iso.point(wall[0], wall[1]), 0.1, {"point": Iso.point(wall[0], wall[1])})
	for mark in level.get("marks", []):
		var tile := _tile_for(str(mark.tile), tiles)
		if not tile.is_empty() and _visible(tile):
			_add_object(objects, "mark", tile, 0.1, {"mark": mark, "point": _interpolate(tile, _tile_for(str(tile.id), _to_tiles))})
	for id in state.get("items", {}):
		var item: Dictionary = state.items[id]
		var next: Dictionary = _motion_to.get("items", {}).get(id, {})
		var ground: Dictionary = item if str(item.get("holder", "")).is_empty() and not str(item.get("tile", "")).is_empty() else next if str(next.get("holder", "")).is_empty() and not str(next.get("tile", "")).is_empty() else {}
		if ground.is_empty():
			continue
		var tile := _tile_for(str(ground.tile), tiles)
		if tile.is_empty():
			tile = _tile_for(str(ground.tile), _to_tiles)
		if not tile.is_empty():
			var opacity := _ease() if not str(item.get("holder", "")).is_empty() else 1.0 - _ease() if not str(next.get("holder", "")).is_empty() else 1.0
			_add_object(objects, "item", tile, 0.25, {"id": id, "item": ground, "point": _interpolate(tile, _tile_for(str(tile.id), _to_tiles)), "alpha": opacity})
	for collectible in level.get("collectibles", []):
		if collectible.id in state.get("collected", []):
			continue
		var tile := _tile_for(str(collectible.tile), tiles)
		if not tile.is_empty() and _visible(tile):
			_add_object(objects, "collectible", tile, 0.3, {"point": tile, "tile_id": str(tile.id)})
	for actor in ["buddy", "luvie"]:
		var tile := _tile_for(str(state.get("actors", {}).get(actor, "")), tiles)
		if not tile.is_empty():
			var point := actor_ground_point(actor)
			_add_object(objects, "actor", point, 0.51 if actor == "luvie" else 0.5, {"actor": actor, "point": point, "before": tile})
	if level.get("chapter", "") == "pond":
		for point in EnvironmentArt.residents(level, tiles):
			_add_object(objects, "resident", point, 0.15, {"point": point})
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.depth) < float(b.depth) if not is_equal_approx(float(a.depth), float(b.depth)) else int(a.order) < int(b.order))
	if depth_enabled:
		_depth_stage.setup_size(size, origin, scale_factor)
		var stable_objects: Array = []
		for object in objects:
			if object.kind in ["floor", "steps", "ramp", "prop"]:
				stable_objects.append(object)
		if _depth_stage.begin_static(hash([level.id, stable_objects])):
			var stable_paint := Paint.new(_depth_stage.paint_target, images)
			for object in stable_objects:
				_depth_stage.paint_target.begin_object(_object_anchor(object))
				_draw_object(stable_paint, object, painted, time)
			_depth_stage.end_static()
			_depth_static_snapshot = stable_objects.duplicate(true)
		_depth_stage.begin_frame()
		var depth_paint := Paint.new(_depth_stage.paint_target, images)
		for object in objects:
			if object.kind in ["floor", "steps", "ramp", "prop"]:
				continue
			_depth_stage.paint_target.begin_object(_object_anchor(object), 1 if object.kind == "runoff" else 0, 0.001 if object.kind == "actor" else 0.0)
			_draw_object(depth_paint, object, painted, time)
		_depth_stage.end_frame()
		_depth_overlay.queue_redraw()
	else:
		for object in objects:
			_draw_object(p, object, painted, time)
		_draw_interaction_light(p, time)
		if level.get("chapter", "") == "pond":
			EnvironmentArt.rain(p, size, time, true, settings)
		_draw_spatial_guides(p, time)
		_draw_growth_targets(p)
		_draw_mole_dialogue()
	if state.get("completed", false) and settings.get("particles", true) and not settings.get("lowMotion", false):
		for index in range(16):
			p.oval(fposmod(index * 173 + sin(time * 0.001 + index) * 15, size.x), fposmod(size.y + index * 91 - time * 0.02, size.y), 2, 2, "#ffedaf88")
	_in_draw = false
	_draw_tiles = []
	_draw_tile_by_id = {}

func _object_anchor(object: Dictionary) -> Dictionary:
	if object.kind in ["steps", "ramp"]:
		return object.pair[0]
	return object.get("point", object.get("tile", object.get("prop", Iso.point(0, 0))))

## Keep unchanged connections visible during topology changes. Rule tiles and
## transactions stay independent from this opt-in presentation transition.
func _step_entries(painted: Array) -> Array:
	var entries: Array = []
	if TerrainPresentation.enabled(world.level):
		if not _motion_from.is_empty():
			entries = TerrainPresentation.connections(_from_steps, _to_steps, _ease())
		else:
			var pairs := Landscape.steps(painted)
			entries = TerrainPresentation.connections(pairs, pairs, 1.0)
		# Preserve the two rear stair removals explicitly requested for 1-1.
		entries = entries.filter(func(entry: Dictionary) -> bool:
			var endpoints := [str(entry.pair[0].id), str(entry.pair[1].id)]
			return endpoints not in [["f:2:0", "f:2:-1"], ["f:3:0", "f:3:-1"]])
	elif _motion_from.is_empty() or _motion_kind in ["move", "roll", "rejoin", "jump", "hop"]:
		for pair in Landscape.steps(_tiles()):
			entries.append({"pair": pair, "alpha": 1.0})
	return entries

func _add_object(objects: Array, kind: String, point: Dictionary, offset: float, data: Dictionary = {}, depth := INF) -> void:
	var entry := {"kind": kind, "depth": Iso.ground_depth(point) + offset if is_inf(depth) else depth, "order": objects.size()}
	entry.merge(data)
	objects.append(entry)

func _water_height() -> float:
	var water := float(_state().get("water", 0))
	if not _motion_from.is_empty():
		water = lerpf(water, float(_motion_to.get("water", water)), _ease())
	return -0.55 + water * 0.18 if world.level.id == "2-1" else -0.5

func _draw_object(p: GardenPaint, object: Dictionary, painted: Array, time: float) -> void:
	var state := _state()
	match object.kind:
		"floor":
			Landscape.floor_tile(p, self, object.tile, painted, world.level, state, time, object.tile.alpha, object.get("clip", {}))
		"steps", "ramp":
			p.push(Vector2.ZERO, Vector2.ONE, 0.0, float(object.get("alpha", 1.0)))
			Landscape.terrain_steps(p, self, object.pair, object.get("surface", {}))
			p.pop()
		"prop":
			var point := project(object.prop)
			p.image(object.prop.asset, point.x, point.y + 7 * scale_factor, float(object.prop.width) * scale_factor)
		"wall":
			var point := project(object.point)
			p.image("river-rock" if world.level.id == "2-2" else "rock", point.x, point.y + 5 * scale_factor, (38 if world.level.id == "1-2" else 46 if world.level.id == "2-2" else 70) * scale_factor, 0.9, 0.65 if world.level.id == "1-2" else 1)
		"mark":
			_draw_mark(p, object.mark, object.point, time)
		"item":
			_draw_item(p, str(object.id), object.item, object.point, float(object.alpha))
		"actor":
			_draw_actor(p, str(object.actor), object.point, object.before, time)
		"collectible":
			var point := project(object.point)
			var offset := 18 * scale_factor if state.get("items", {}).get("bell", {}).get("tile", "") == object.tile_id else 0.0
			p.image("spore", point.x - offset, point.y - 20 * scale_factor + sin(time * 0.003) * 2, 35 * scale_factor, 0.5)
		"mole":
			Creatures.mole(p, project(object.point), 58 * scale_factor, time, {"greet": (_flag("home") or state.get("completed", false)) and not _mole_speech.is_empty(), "speaking": not _mole_speech.is_empty(), "low_motion": settings.get("lowMotion", false)})
		"gate":
			var point := project(world.level.sanctuary.gate)
			var opening := 1.0 if _flag("home") else _ease() if "home" in _motion_to.get("flags", []) else 0.0
			p.image("flower-gate-frame", point.x, point.y + 13 * scale_factor, 112 * scale_factor, 0.93)
			p.push(point + Vector2(0, 13 * scale_factor), Vector2(1 - opening * 0.18, 1))
			p.image("flower-gate-seal", 0, 0, 112 * scale_factor, 0.93, 1 - opening)
			p.pop()
			if settings.get("dynamicLight", true) and opening < 1:
				p.glow(point + Vector2(0, -55 * scale_factor), 40 * scale_factor, "#bae8b7", 0.12 * (1 - opening))
		"fountain":
			p.push(project(world.level.sanctuary.fountain), Vector2.ONE * (92.0 / 90.0) * scale_factor)
			Props.fountain(p, time, settings.get("particles", true))
			p.pop()
		"butterflies":
			var fountain: Dictionary = world.level.sanctuary.fountain
			var at := project(fountain)
			var anchors: Array = []
			for prop in _scenery:
				if float(prop.x) <= -7 and prop.asset in ["pink-flowers", "blue-flowers", "yellow-flowers", "ivory-lotus", "glow-flower", "gold-lotus", "flowers"]:
					var texture: Texture2D = images.get(prop.asset)
					var height := float(prop.width) * (texture.get_height() / float(texture.get_width()) if texture != null else 1.3)
					anchors.append((project(prop) - at) / scale_factor - Vector2(0, height * 0.7))
			p.push(at, Vector2.ONE * scale_factor)
			Props.butterflies(p, time, anchors)
			p.pop()
		"runoff":
			EnvironmentArt.runoff(p, self, object.point, world.level, _water_height(), time)
		"resident":
			var point: Dictionary = object.point.duplicate()
			point.h = _water_height()
			EnvironmentArt.resident(p, project(point), scale_factor, time)
		"line":
			p.line([project(object.a), project(object.b)], object.color, float(object.width) * scale_factor)

func _draw_mark(p: GardenPaint, mark: Dictionary, point: Dictionary, time: float) -> void:
	var at := project(point)
	var state := _state()
	var kind: String = mark.kind
	p.push(at, Vector2.ONE * scale_factor)
	match kind:
		"core":
			p.image("bloom" if state.get("completed", false) else "flower", 0, 10, 150 if world.level.id == "3-4" else 86 if world.level.id == "1-1" else 110, 0.9, _soft_occluder_opacity(point))
			if _ready_to_plant() and settings.get("dynamicLight", true):
				p.image("light", 0, 5, 90, 0.9, 0.22)
		"root": p.image("vine", 0, 8, 65)
		"latch": p.image("arch", 0, 8, 90)
		"flower": p.image("bloom" if _flag(str(mark.id)) else "flowers", 0, 8, 55)
		"lamp": p.image("light", 0, 8, 54)
		"plate":
			p.push(Vector2.ZERO, Vector2.ONE * 64.0 / 70.0)
			Props.leaf_plate(p, state.get("actors", {}).get("buddy", "") == mark.tile)
			p.pop()
		"rest", "observe": p.image("flowers", 0, 7, 34)
	if mark.id == "hold":
		p.push(Vector2(28, -8), Vector2.ONE * 57.0 / 70.0)
		Props.lever(p, 1 if _flag("hold") else _ease() if _motion_kind == "use:hold" else 0)
		p.pop()
	if world.level.id == "2-2" and mark.id == "slot":
		p.oval(0, 2, 28, 13, "#b0ead72a", 0, "#c0efdf", 2)
		p.leaf(0, 0, 1.4, -0.3)
	p.pop()
	var captions := {"core": "核心花床", "root": "根台", "turn": "① 固定镜叶" if world.level.id == "2-2" else "转动庭院", "valve": "花阀", "lever": "操作杆", "latch": "门闩", "song": "雨滴琴", "slot": "② 镜叶光槽" if world.level.id == "2-2" else "放置槽", "plate": "轻叶踏板"}
	if captions.has(kind) and mark.id != "hold" and not state.get("completed", false) and _near(str(mark.tile)):
		_caption(at + Vector2(0, -49 * scale_factor), captions[kind])

## Only the already-visible first garden's flower is a soft occluder. Solid
## terrain keeps native depth; no hidden path/actor is drawn through a wall.
func _soft_occluder_opacity(point: Dictionary) -> float:
	if str(world.level.id) != "1-1":
		return 1.0
	var actor := actor_ground_point(str(_state().get("active", "luvie")))
	var distance := Vector2(float(point.x) - float(actor.x), float(point.z) - float(actor.z)).length()
	var nearby := 1.0 - smoothstep(1.15, 1.65, distance)
	var behind := smoothstep(0.0, 0.25, Iso.ground_depth(point) - Iso.ground_depth(actor))
	var height := 1.0 - smoothstep(0.6, 1.1, absf(float(point.h) - float(actor.h)))
	return 1.0 - 0.62 * nearby * behind * height

func _caption(at: Vector2, text: String) -> void:
	if world != null and str(world.level.id) == "1-1" and _overlay_ink == null:
		var protected := _active_actor_protection().grow(8.0)
		var label_width := (label_font if label_font != null else ThemeDB.fallback_font).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
		var bounds := Rect2(Vector2.ZERO, get_viewport_rect().size).grow(-12)
		var placed := false
		for candidate: Vector2 in [at, Vector2(at.x, protected.position.y - 24), Vector2(protected.position.x - label_width / 2 - 10, at.y), Vector2(protected.end.x + label_width / 2 + 10, at.y), Vector2(at.x, protected.end.y + 12)]:
			var rect := Rect2(candidate - Vector2(label_width / 2, 0), Vector2(label_width, 20))
			if bounds.encloses(rect) and not rect.intersects(protected):
				at = candidate
				placed = true
				break
		if not placed:
			return
		_depth_captions.append({"at": at, "text": text})
		return
	var font: Font = label_font if label_font != null else ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14
	var ink: CanvasItem = _overlay_ink if _overlay_ink != null else self
	ink.draw_rect(Rect2(at - Vector2(width / 2, 0), Vector2(width, 20)), Color("fff6e7e8"))
	ink.draw_string(font, at + Vector2(-width / 2 + 7, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("7a6647"))

func _draw_depth_overlay(canvas: CanvasItem) -> void:
	if world == null or str(world.level.id) != "1-1":
		return
	_overlay_ink = canvas
	var p := Paint.new(canvas, images)
	for caption in _depth_captions:
		_caption(caption.at, str(caption.text))
	_draw_interaction_light(p, _time())
	_draw_spatial_guides(p, _time())
	_draw_growth_targets(p)
	_overlay_ink = null

func _draw_item(p: GardenPaint, id: String, item: Dictionary, point: Dictionary, opacity: float) -> void:
	p.push(project(point), Vector2.ONE * scale_factor, 0, opacity)
	if id == "bug":
		p.image("bug", 0, -10, 40)
	elif id == "dew":
		p.image("dew-parcel" if item.get("picked", false) else "dew-plant", 0, 5, 34 if item.get("picked", false) else 49, 1)
	elif id.begins_with("mirror"):
		p.image("lilypad", 0, 0, 52)
		var angle: int = int(item.get("angle", 0)) % 2
		p.line([Vector2(-12, 7 if angle else -7), Vector2(12, -7 if angle else 7)], "#fff0b1", 4)
	elif id == "bell":
		p.push(Vector2(18, 0))
		Props.bell(p)
		p.pop()
	else:
		p.image("light" if id == "lamp" else "crystal", 0, 0, 36)
	p.pop()
	if id == "bell":
		_caption(project(point) + Vector2(18 * scale_factor, -65 * scale_factor), "门铃 · 拾起")

func _carried(state: Dictionary, actor: String) -> String:
	for id in state.get("items", {}):
		if state.items[id].get("holder", "") == actor:
			return id
	return ""

func _actor_offset(actor: String) -> float:
	if _actor_uses_contact(actor):
		return 0.0
	var state := _state()
	var shared: bool = state.get("actors", {}).get("luvie", "") == state.get("actors", {}).get("buddy", "")
	var offset := (-24.0 if actor == "buddy" else 8.0) if shared else 0.0
	if not _motion_to.is_empty():
		var future_shared: bool = _motion_to.get("actors", {}).get("luvie", "") == _motion_to.get("actors", {}).get("buddy", "")
		var future_offset := (-24.0 if actor == "buddy" else 8.0) if future_shared else 0.0
		var progress := _motion_progress if _motion_kind in ["move", "roll", "rejoin"] else _ease()
		offset = lerpf(offset, future_offset, progress)
	return offset * scale_factor

func _draw_actor(p: GardenPaint, actor: String, point: Dictionary, before: Dictionary, time: float) -> void:
	var state := _state()
	var at := project(point)
	var offset := _actor_offset(actor)
	var moving: bool = not _motion_from.is_empty() and _motion_from.get("actors", {}).get(actor, "") != _motion_to.get("actors", {}).get(actor, "")
	var active: bool = state.get("active", "luvie") == actor
	var action := _motion_kind if not moving and active else ""
	var carried := _carried(state, actor)
	var incoming := _carried(_motion_to, actor)
	var carry_alpha := 1.0 - _ease() if not carried.is_empty() and incoming.is_empty() and not _motion_to.is_empty() else 1.0 if not carried.is_empty() else _ease()
	if carried.is_empty():
		carried = incoming
	var jump := _actor_jump(actor)
	var pivot := (0.0 if _actor_uses_contact(actor) else 7.0 if actor == "luvie" else 4.0) * scale_factor
	if actor == "buddy":
		var look := {"moving": moving, "rolling": moving and _motion_kind == "roll", "waiting": not state.get("follow", true) and not active, "low_motion": settings.get("lowMotion", false), "happy": state.get("completed", false)}
		if _actor_uses_contact(actor) and _buddy_surface != null and p.target.has_method("surface"):
			_buddy_surface.update_pose(images, time, look)
			# Compose the original multi-layer illustration in 2D first. Only its
			# finished silhouette participates in world depth; its own shadow is
			# a ground decal, not a vertical fragment cutting through the feet.
			p.target.surface("ground", float(point.h))
			var unit := 46.0 / 48.0 * scale_factor
			p.shadow(at.x + unit, at.y + unit, 20.0 * unit, 5.0 * unit)
			p.target.billboard(point)
			p.image("_buddy_composite", at.x, at.y - jump, 64.0 * scale_factor, 112.0 / 128.0)
		else:
			Creatures.buddy(p, at + Vector2(offset, pivot - jump), 46 * scale_factor, time, look)
		p.push(at + Vector2(offset, pivot - jump), Vector2.ONE * scale_factor, 0, carry_alpha)
		if not carried.is_empty():
			Props.carry_bag(p, carried, true)
		p.pop()
	else:
		var pose: Dictionary = _character_frame.get("pose", {})
		var key: String = pose.key
		p.push(at + Vector2(offset, pivot - jump), Vector2.ONE * scale_factor)
		p.push(Vector2.ZERO, Vector2((-1 if pose.flip else 1) * float(pose.scale_x), float(pose.scale_y)), 0 if pose.clip == "roll" else float(pose.rotation))
		if pose.clip == "roll":
			p.push(Vector2(0, -30), Vector2.ONE, float(pose.rotation))
			p.image("ball", 0, 0, 68, 0.5)
		else:
			p.push(Vector2(0, pose.offset_y))
			p.image("_walk_transition" if _character_frame.get("blend", false) and _blend_surface != null else key, 0, 0, 115, 236.0 / 256.0)
		if not carried.is_empty():
			p.push(Vector2.ZERO, Vector2.ONE, 0, carry_alpha)
			Props.carry_bag(p, carried, false, pose.clip == "roll", key)
			p.pop()
		p.pop()
		p.pop()
		p.pop()
	if active and not state.get("completed", false):
		if p.target.has_method("surface"):
			p.target.surface("ground", float(point.h))
		p.arc(at.x + offset, at.y + (0.0 if _actor_uses_contact(actor) else 4.0) * scale_factor, 24 * scale_factor, 10 * scale_factor, 0, TAU, "#fff0b7", 2)

func _add_surface_lines(objects: Array) -> void:
	var model := _rule_world()
	for method in ["rays", "lamp_ray"]:
		if not model.has_method(method):
			continue
		var points: Array = model.call(method)
		if method == "rays":
			var extent := Rect2()
			var first := true
			for tile in _tiles():
				var point := Vector2(tile.x, tile.z)
				if first:
					extent = Rect2(point, Vector2.ZERO)
					first = false
				else:
					extent = extent.expand(point)
			extent = extent.grow(1.001)
			var filtered: Array = []
			for point in points:
				if extent.has_point(Vector2(point.x, point.z)):
					filtered.append(point)
			points = filtered
		_surface_line(objects, points, "#ffe4a1" if method == "rays" else "#ffeab181", 3.0 if method == "rays" else 4.0)
	for module in world.level.get("modules", []):
		if module.id != "water":
			continue
		var center := _tile_for("m:water:0:0", _tiles())
		if center.is_empty():
			continue
		var turn := int(_state().get("turns", {}).get("water", 0))
		var directions := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
		for index in [turn, (turn + 1) % 4]:
			_surface_line(objects, [center, Iso.point(float(center.x) + directions[index].x * 3, float(center.z) + directions[index].y * 3, center.h)], "#a2e3e4", 4.0)
	if world.level.id == "3-3" and _flag("root"):
		_surface_line(objects, [Iso.point(0, -4), Iso.point(1, -4), Iso.point(4, -3)], "#c4d79b", 2)
	if world.level.id == "3-4" and int(_state().get("turns", {}).get("water", 0)) == 1:
		_surface_line(objects, [Iso.point(0, 8), Iso.point(4, 8), Iso.point(4, 0)], "#b4e6e6", 3)
		if int(_state().get("turns", {}).get("inner", 0)) == 1:
			_surface_line(objects, [Iso.point(4, 0), Iso.point(0, 0), Iso.point(0, -4)], "#b4e6e6", 3)

func _surface_line(objects: Array, points: Array, color: String, width: float) -> void:
	for index in range(1, points.size()):
		var a: Dictionary = points[index - 1]
		var b: Dictionary = points[index]
		var count := maxi(1, int(ceil(maxf(absf(float(b.x) - float(a.x)), absf(float(b.z) - float(a.z))))))
		for step in range(count):
			var first := Iso.interpolate(a, b, step / float(count))
			var second := Iso.interpolate(a, b, (step + 1) / float(count))
			objects.append({"kind": "line", "depth": maxf(Iso.ground_depth(first), Iso.ground_depth(second)) + 0.06, "order": objects.size(), "a": first, "b": second, "color": color, "width": width})

func _draw_interaction_light(p: GardenPaint, time: float) -> void:
	if not settings.get("dynamicLight", true):
		return
	var color: String = {"valley": "#e5cf86", "pond": "#a3e4df", "cave": "#ceb7ff"}.get(world.level.get("chapter", "valley"))
	var pulse := 1.0 if settings.get("lowMotion", false) else 0.86 + sin(time * 0.0025) * 0.14
	for mark in world.level.get("marks", []):
		if mark.kind not in ["core", "root", "turn", "valve", "song", "slot", "lever", "latch"]:
			continue
		var tile := _tile_for(str(mark.tile), _tiles())
		if tile.is_empty() or not _visible(tile):
			continue
		if mark.kind == "core":
			if not _ready_to_plant() and not _state().get("completed", false):
				continue
		elif not _near(str(tile.id)) or _state().get("completed", false):
			continue
		var at := project(tile)
		var radius := (43 if mark.kind == "core" else 26) * scale_factor
		p.push(Vector2.ZERO, Vector2.ONE, 0, 0.45 * pulse)
		p.halo(at + Vector2(0, 2 * scale_factor), radius, radius * 0.48, color, 14 * scale_factor, 1.7)
		p.arc(at.x, at.y + 2 * scale_factor, radius, radius * 0.48, 0, TAU, color, 1.7)
		p.pop()
	if _motion_from.is_empty() or settings.get("lowMotion", false) or _motion_kind in ["move", "hop", "roll", "jump", "rejoin", "switch", "follow"]:
		return
	var point := _player_point(_state(), _tiles())
	var at := project(point)
	var progress := _motion_progress
	var radius := (18 + 48 * progress) * scale_factor
	p.push(Vector2.ZERO, Vector2.ONE, 0, sin(progress * PI) * 0.65)
	p.arc(at.x, at.y, radius, radius * 0.48, 0, TAU, color, 2 * (1 - progress) + 0.5)
	if settings.get("particles", true):
		for index in range(7):
			var angle := index * TAU / 7.0
			p.oval(at.x + cos(angle) * radius * 0.7, at.y - 18 * scale_factor - sin(angle) * radius * 0.4 - progress * 23 * scale_factor, 1.7 * scale_factor, 1.7 * scale_factor, color)
	p.pop()

func _draw_mole_dialogue() -> void:
	_dialogue_rect = Rect2()
	_dialogue_fallback = "inactive"
	if _mole_speech.is_empty() or world.level.id != "1-4":
		return
	var size := get_viewport_rect().size
	var at := _mole_position
	if at.x <= -35 or at.x >= size.x + 35 or at.y <= 100 or at.y >= size.y - 100:
		_dialogue_fallback = "offscreen"
		return
	var width := minf(250, size.x - 32)
	var left := clampf(at.x - width / 2, 16, size.x - width - 16)
	var top := maxf(160, minf(size.y - 260, at.y + 26 * scale_factor))
	var font: Font = label_font if label_font != null else ThemeDB.fallback_font
	var font_size := 11 if size.x < 650 else 12
	var paragraph := TextParagraph.new()
	paragraph.width = width - (28 if size.x < 650 else 34)
	paragraph.add_string(_mole_speech, font, font_size)
	var text_size := paragraph.get_size()
	var height := text_size.y + (20 if size.x < 650 else 26)
	var box := Rect2(left, top, width, height)
	if size.x < 650:
		box = _choose_dialogue_rect(at, box.size, _active_actor_protection())
		if not box.has_area():
			# NPC greetings are decorative. Preserve puzzle guidance and HUD messages
			# when a tiny viewport has no free space for this additional annotation.
			_dialogue_fallback = "no_free_region"
			return
	_dialogue_rect = box
	_dialogue_fallback = "visible"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff9e9ef")
	style.border_color = Color("e7d5ad")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color("67583d17")
	style.shadow_size = 8
	draw_style_box(style, box)
	var tip := _dialogue_tail(box, at) if size.x < 650 else PackedVector2Array([Vector2(left + width * 0.48, top - 8), Vector2(left + width * 0.48 - 7, top + 1), Vector2(left + width * 0.48 + 7, top + 1)])
	draw_colored_polygon(tip, Color("fff9e9"))
	paragraph.draw(get_canvas_item(), box.position + Vector2(14 if size.x < 650 else 17, 10 if size.x < 650 else 13), Color("826b4b"))

func _active_actor_protection() -> Rect2:
	var state := _state()
	var actor := str(state.get("active", "luvie"))
	var tile := _tile_for(str(state.get("actors", {}).get(actor, "")), _tiles())
	if tile.is_empty():
		return Rect2()
	var at := actor_screen_footpoint(actor)
	var half_width := (38 if actor == "luvie" else 26) * scale_factor
	var height := (100 if actor == "luvie" else 56) * scale_factor
	return Rect2(at - Vector2(half_width, height), Vector2(half_width * 2, height + 8 * scale_factor))

func _choose_dialogue_rect(at: Vector2, dimensions: Vector2, actor: Rect2) -> Rect2:
	var bounds := get_viewport_rect().grow(-12)
	if dimensions.x > bounds.size.x or dimensions.y > bounds.size.y:
		return Rect2()
	var gap := 12.0
	var centered_x := clampf(at.x - dimensions.x / 2, bounds.position.x, bounds.end.x - dimensions.x)
	var centered_y := clampf(at.y - dimensions.y / 2, bounds.position.y, bounds.end.y - dimensions.y)
	var candidates := [
		Rect2(centered_x, at.y + 26 * scale_factor, dimensions.x, dimensions.y),
		Rect2(centered_x, minf(at.y, actor.position.y) - dimensions.y - gap, dimensions.x, dimensions.y),
		Rect2(centered_x, maxf(at.y, actor.end.y) + gap, dimensions.x, dimensions.y),
		Rect2(minf(at.x, actor.position.x) - dimensions.x - gap, centered_y, dimensions.x, dimensions.y),
		Rect2(maxf(at.x, actor.end.x) + gap, centered_y, dimensions.x, dimensions.y)
	]
	# Also try the existing vertical free strips between cards. No UI is moved.
	var rows: Array[float] = [bounds.position.y, bounds.end.y - dimensions.y]
	for region in _ui_regions:
		rows.append(region.end.y + gap)
		rows.append(region.position.y - dimensions.y - gap)
	for y in rows:
		candidates.append(Rect2(centered_x, y, dimensions.x, dimensions.y))
	for candidate: Rect2 in candidates:
		var protected := candidate.grow(8)
		if not bounds.encloses(candidate) or actor.has_area() and protected.intersects(actor):
			continue
		var blocked := false
		for region in _ui_regions:
			if protected.intersects(region):
				blocked = true
				break
		if not blocked:
			return candidate
	return Rect2()

func _dialogue_tail(box: Rect2, at: Vector2) -> PackedVector2Array:
	if at.y < box.position.y:
		var x := clampf(at.x, box.position.x + 16, box.end.x - 16)
		return PackedVector2Array([Vector2(x, box.position.y - 8), Vector2(x - 7, box.position.y + 1), Vector2(x + 7, box.position.y + 1)])
	if at.y > box.end.y:
		var x := clampf(at.x, box.position.x + 16, box.end.x - 16)
		return PackedVector2Array([Vector2(x, box.end.y + 8), Vector2(x - 7, box.end.y - 1), Vector2(x + 7, box.end.y - 1)])
	var y := clampf(at.y, box.position.y + 16, box.end.y - 16)
	if at.x < box.position.x:
		return PackedVector2Array([Vector2(box.position.x - 8, y), Vector2(box.position.x + 1, y - 7), Vector2(box.position.x + 1, y + 7)])
	return PackedVector2Array([Vector2(box.end.x + 8, y), Vector2(box.end.x - 1, y - 7), Vector2(box.end.x - 1, y + 7)])

func dialogue_presentation() -> Dictionary:
	return {"visible": _dialogue_rect.has_area(), "rect": [_dialogue_rect.position.x, _dialogue_rect.position.y, _dialogue_rect.size.x, _dialogue_rect.size.y], "fallback": _dialogue_fallback}

func _draw_growth_targets(p: GardenPaint) -> void:
	var model := _rule_world()
	if not model.has_method("commands"):
		return
	for command in model.commands():
		var target_id := str(command.get("target", ""))
		if target_id.is_empty():
			continue
		var pieces := target_id.split(":")
		if pieces.size() < 4:
			continue
		var height := 0.0
		for root in world.level.get("roots", []):
			if root.id == pieces[1]:
				height = float(root.h)
		var at := project(Iso.point(float(pieces[-2]), float(pieces[-1]), height))
		p.line([at + Vector2(-25, 0) * scale_factor, at + Vector2(0, -13) * scale_factor, at + Vector2(25, 0) * scale_factor, at + Vector2(0, 13) * scale_factor], "#e7ca80", 2, true)
		p.oval(at.x, at.y, 22, 22, "#fff4d9c9", 0, "#c4a166", 1)
		var font: Font = label_font if label_font != null else ThemeDB.fallback_font
		var ink: CanvasItem = _overlay_ink if _overlay_ink != null else self
		ink.draw_string(font, at + Vector2(-8, 8), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("a08d5b"))

func _draw_spatial_guides(p: GardenPaint, time: float) -> void:
	var model := _rule_world()
	if world.level.id == "1-2" and not _state().get("completed", false) and model.has_method("growth_guidance"):
		var guide: Dictionary = model.growth_guidance()
		if guide.is_empty():
			return
		var root: Dictionary = guide.root
		var grown: Array = _state().get("growth", {}).get(root.id, [])
		for socket in root.get("sockets", []):
			if "g:%s:%d:%d" % [root.id, int(socket[0]), int(socket[1])] in grown:
				continue
			var at := project(Iso.point(socket[0], socket[1], root.h))
			p.push(at, Vector2.ONE * scale_factor, 0, 0.25 + (0.0 if settings.get("lowMotion", false) else sin(time * 0.002) * 0.07))
			p.poly([[-29, 0], [0, -14.5], [29, 0], [0, 14.5]], "#d5cda018", "#9da876")
			p.pop()
		var at := project(guide.origin)
		p.push(at, Vector2.ONE * scale_factor, 0, 0.75 if settings.get("lowMotion", false) else 0.58 + sin(time * 0.003) * 0.16)
		p.poly([[-29, 0], [0, -14.5], [29, 0], [0, 14.5]], "#f6e6a33b", "#f3d47e")
		p.pop()
		if hint_visible:
			var previous: Dictionary = guide.end
			for point in guide.get("route", []):
				_arrow(p, project(previous), project(point), "#4f9787")
				previous = point
			_caption(project(Iso.point(root.goal[0], root.goal[1], root.h)) + Vector2(0, 18 * scale_factor), "回根台调整根线" if guide.get("retract", false) else "第4节：接入花床")
	if world.level.id == "2-2" and not _state().get("completed", false):
		var items: Dictionary = _state().get("items", {})
		var a: Dictionary = items.get("mirrorA", {})
		var b: Dictionary = items.get("mirrorB", {})
		var target := str(b.get("tile", "")) if str(b.get("holder", "")).is_empty() and b.get("tile", "") != "f:1:0" else "f:1:0" if not str(b.get("holder", "")).is_empty() else str(a.get("tile", "")) if int(a.get("angle", 0)) % 2 != 1 else str(b.get("tile", "")) if int(b.get("angle", 0)) % 2 != 1 else "f:4:0"
		var tile := _tile_for(target, _tiles())
		if not tile.is_empty():
			var at := project(tile)
			p.arc(at.x, at.y + 2 * scale_factor, 29 * scale_factor, 14 * scale_factor, 0, TAU, "#ffdc8a", 2.3 * scale_factor)
			var y := at.y - (50 + (0.0 if settings.get("lowMotion", false) else sin(time * 0.003) * 3)) * scale_factor
			_arrow(p, Vector2(at.x, y - 10 * scale_factor), Vector2(at.x, y + 3 * scale_factor), "#fff6cf")
		if hint_visible or not str(b.get("holder", "")).is_empty():
			var route := ["f:0:1", str(a.get("tile", "")), "f:1:0", "f:4:0"]
			for index in range(1, route.size()):
				var first := _tile_for(route[index - 1], world.level.tiles)
				var second := _tile_for(route[index], world.level.tiles)
				if not first.is_empty() and not second.is_empty():
					_arrow(p, project(first), project(second), "#8ecfbd99")

func _arrow(p: GardenPaint, a: Vector2, b: Vector2, color: String) -> void:
	var delta := b - a
	if delta.length() < 1:
		return
	var unit := delta.normalized()
	var end := b - unit * 7 * scale_factor
	p.line([a + unit * 9 * scale_factor, b - unit * 9 * scale_factor], color, maxf(2, 3.5 * scale_factor))
	p.poly([end, end - unit * 9 * scale_factor + Vector2(-unit.y, unit.x) * 4 * scale_factor, end - unit * 9 * scale_factor - Vector2(-unit.y, unit.x) * 4 * scale_factor], color)

func command_hit_test(screen: Vector2) -> String:
	if world == null:
		return ""
	var local := get_global_transform_with_canvas().affine_inverse() * screen
	for command in _rule_world().commands():
		var id := str(command.get("target", ""))
		if id.is_empty():
			continue
		var parts := id.split(":")
		if parts.size() < 4:
			continue
		var height := 0.0
		for root in world.level.get("roots", []):
			if root.id == parts[1]:
				height = float(root.h)
		if local.distance_to(project(Iso.point(float(parts[-2]), float(parts[-1]), height))) <= 22:
			return str(command.id)
	return ""

func hit_test(screen: Vector2) -> String:
	if world == null:
		return ""
	var local := get_global_transform_with_canvas().affine_inverse() * screen
	var tiles := _tiles().duplicate()
	tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Iso.ground_depth(a) > Iso.ground_depth(b))
	for tile in tiles:
		if tile.get("solid", false) or not _visible(tile):
			continue
		var at := project(tile)
		var mark := false
		for landmark in world.level.get("marks", []):
			if landmark.tile == tile.id:
				mark = true
		var polygon := PackedVector2Array([at + Vector2(-35, 0) * scale_factor, at + Vector2(0, -17.5) * scale_factor, at + Vector2(35, 0) * scale_factor, at + Vector2(0, 17.5) * scale_factor])
		if mark:
			polygon = PackedVector2Array([at + Vector2(-28, -43) * scale_factor, at + Vector2(28, -43) * scale_factor, at + Vector2(35, 22) * scale_factor, at + Vector2(-35, 22) * scale_factor])
		if Geometry2D.is_point_in_polygon(local, polygon):
			return str(tile.id)
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var command := command_hit_test(event.position)
		if not command.is_empty():
			command_selected.emit(command)
			get_viewport().set_input_as_handled()
			return
		var id := hit_test(event.position)
		if not id.is_empty():
			tile_selected.emit(id)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		var command := command_hit_test(event.position)
		if not command.is_empty():
			command_selected.emit(command)
			get_viewport().set_input_as_handled()
			return
		var id := hit_test(event.position)
		if not id.is_empty():
			tile_selected.emit(id)
			get_viewport().set_input_as_handled()
