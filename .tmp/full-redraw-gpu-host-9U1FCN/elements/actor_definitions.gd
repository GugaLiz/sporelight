class_name GardenActorDefinitions
extends RefCounted
## Identity, motor and rule capabilities never come from a cosmetic skin.
## Runtime accessors return shared read-only data. Editors use definitions().
const PATH := "res://content/actor-elements.json"
static var _data: Dictionary = {}
static var _custom_skins: Dictionary = {}
static var _revision := 0

static func _load() -> void:
	if not _data.is_empty(): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert(parsed is Dictionary and parsed.get("version") == 1, "Invalid actor element definitions")
	_data = parsed
	_revision += 1

static func definitions() -> Dictionary:
	_load()
	var result := _data.duplicate(true)
	result.skins.merge(_custom_skins.duplicate(true), true)
	return result

static func actor(id: String) -> Dictionary:
	_load()
	return _data.actors.get(id, {})

static func skin(id: String) -> Dictionary:
	_load()
	return _custom_skins.get(id, _data.skins.get(id, {}))

static func default_skin(id: String) -> String:
	return str(actor(id).get("default_skin", ""))

static func motor(id: String) -> Dictionary:
	_load()
	return _data.motors.get(str(actor(id).get("motor", "")), {})

static func speed(id: String, following := false, rolling := false) -> float:
	var profile := motor(id)
	return float(profile.follow_speed) if following else float(profile.walk_speed) * (float(profile.roll_multiplier) if rolling else 1.0)

static func has_capability(id: String, capability: String) -> bool:
	_load()
	var profile: Dictionary = _data.capability_profiles.get(str(actor(id).get("capabilities", "")), {})
	return bool(profile.get(capability, false))

static func visual_motion() -> Dictionary:
	_load()
	return _data.visual_motion

static func carry() -> Dictionary:
	_load()
	return _data.carry

static func revision() -> int:
	_load()
	return _revision

static func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _valid_pose(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("scale") and not _positive(value.scale): return false
	if value.has("foot"):
		if not value.foot is Array or value.foot.size()!=2: return false
		for component: Variant in value.foot:
			if not _finite(component): return false
	return true

static func validate_skin(value: Dictionary) -> Dictionary:
	_load()
	if not value.get("renderer") in ["sprite_frames", "procedural_buddy"]: return {"ok":false,"error":"unsupported_actor_renderer"}
	if not value.get("allowed_actors") is Array or value.allowed_actors.is_empty(): return {"ok":false,"error":"missing_actor_compatibility"}
	for who: Variant in value.allowed_actors:
		if not who is String or not _data.actors.has(who): return {"ok":false,"error":"unknown_actor_identity"}
	if value.renderer == "procedural_buddy" and value.allowed_actors != ["buddy"]: return {"ok":false,"error":"procedural_buddy_identity"}
	var standing: Variant = value.get("standing")
	if not standing is Dictionary or not _positive(standing.get("pixel_size")): return {"ok":false,"error":"invalid_actor_scale"}
	for key: String in ["canvas", "foot"]:
		if not standing.get(key) is Array or standing[key].size()!=2: return {"ok":false,"error":"invalid_actor_anchor"}
		for component: Variant in standing[key]:
			if not (component is int or component is float) or not is_finite(float(component)): return {"ok":false,"error":"invalid_actor_anchor"}
	if not _positive(standing.canvas[0]) or not _positive(standing.canvas[1]): return {"ok":false,"error":"invalid_actor_canvas"}
	if not value.get("clips") is Dictionary or not value.clips.has("idle_front") or not value.clips.has("roll"): return {"ok":false,"error":"missing_actor_clips"}
	for id: Variant in value.clips:
		var clip: Variant = value.clips[id]
		if not id is String or not clip is Dictionary or not _positive(clip.get("fps")) or not clip.get("loop") is bool or not clip.get("frames") is Array or clip.frames.is_empty(): return {"ok":false,"error":"invalid_actor_clip"}
		for alias: Variant in clip.frames:
			if not alias is String or alias.is_empty() or (alias.begins_with("@") and (alias!="@procedural_buddy" or value.renderer!="procedural_buddy")): return {"ok":false,"error":"invalid_actor_frame"}
	if not value.get("roll") is Dictionary or not _positive(value.roll.get("pixel_size")) or not _positive(value.roll.get("height")): return {"ok":false,"error":"invalid_roll_visual"}
	if not _finite(value.roll.get("rotation_speed")): return {"ok":false,"error":"invalid_roll_speed"}
	if not value.get("motion") is Dictionary or not _positive(value.get("carry_scale")): return {"ok":false,"error":"invalid_skin_motion_or_carry"}
	for key: String in ["walk_reference_speed", "walk_speed_min", "walk_speed_max"]:
		if value.motion.has(key) and not _positive(value.motion[key]): return {"ok":false,"error":"invalid_walk_motion"}
	if float(value.motion.get("walk_speed_min",.45)) > float(value.motion.get("walk_speed_max",1.4)): return {"ok":false,"error":"invalid_walk_speed_range"}
	if value.renderer == "procedural_buddy":
		for key: String in ["walk_sway_speed", "walk_sway_angle"]:
			if not _finite(value.motion.get(key)): return {"ok":false,"error":"invalid_companion_sway"}
		for key: String in ["waiting_scale", "sleep_scale"]:
			if not value.motion.get(key) is Array or value.motion[key].size()!=3: return {"ok":false,"error":"invalid_companion_scale"}
			for component: Variant in value.motion[key]:
				if not _positive(component): return {"ok":false,"error":"invalid_companion_scale"}
	if not value.get("pose_overrides",{}) is Dictionary: return {"ok":false,"error":"invalid_pose_overrides"}
	for clip: Variant in value.get("pose_overrides",{}):
		if not value.clips.has(clip): return {"ok":false,"error":"unknown_pose_clip"}
		var pose: Variant = value.pose_overrides[clip]
		if not _valid_pose(pose): return {"ok":false,"error":"invalid_pose_anchor"}
		if pose.has("frames"):
			if not pose.frames is Dictionary: return {"ok":false,"error":"invalid_pose_frames"}
			for frame: Variant in pose.frames:
				if not str(frame).is_valid_int() or int(frame)<0 or int(frame)>=value.clips[clip].frames.size() or not _valid_pose(pose.frames[frame]): return {"ok":false,"error":"invalid_pose_frame"}
	return {"ok":true}

static func register_skin(id: String, value: Dictionary) -> Dictionary:
	if id.is_empty(): return {"ok":false,"error":"empty_skin_id"}
	var result := validate_skin(value)
	if not result.ok: return result
	_custom_skins[id] = value.duplicate(true)
	_revision += 1
	return {"ok":true,"skin_id":id}

static func remove_custom_skin(id: String) -> void:
	if _custom_skins.erase(id): _revision += 1
