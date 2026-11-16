class_name GardenCharacterMotion
extends RefCounted

const WALK_FRAME_MS := 55.0
const WALK_FRAME_COUNT := 12
const JUMP_FRAME_COUNT := 12
const WALK_STOP_MS := 100.0
const WALK_START_MS := 70.0
## The supplied walk sheet mixes viewpoints. Select coherent views, without
## altering the PNGs: front source keyPose IDs 1/4/5/6 (files walk-1/7/9/11
## plus their inbetweens), side keyPose IDs 2/3 (files walk-3/4/5), back all 12.
## Front uses the original 55ms spacing; side ping-pongs the matching 3/4/5
## source poses at 110ms so both forward-facing cycles last 440ms. Back keeps
## the authored 660ms cycle. Frame 8 bridges the front loop back to frame 1.
const WALK_CLIPS := {
	"front": {"frames": [1, 7, 8, 9, 10, 11, 12, 8], "frame_ms": 55.0, "prefix": "walk-", "flip_right": false},
	"side": {"frames": [3, 4, 5, 4], "frame_ms": 110.0, "prefix": "walk-", "flip_right": true},
	"back": {"frames": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], "frame_ms": 55.0, "prefix": "walk-back-", "flip_right": false}
}

static func walk_group(facing: String) -> String:
	return "side" if facing in ["left", "right"] else "back" if facing == "back" else "front"

static func grounded_pose(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	# A small body stretch replaces whole-sprite bobbing. The sprite transform's
	# origin remains the authored foot anchor, including through start and stop.
	if str(result.get("clip", "")).begins_with("walk"):
		result.scale_y = float(result.get("scale_y", 1)) - float(result.get("offset_y", 0)) / 115.0
		result.offset_y = 0.0
	return result

static func settle_parameters(from: Dictionary, to: Dictionary, progress: float) -> Dictionary:
	var result := to.duplicate(true)
	var t := clampf(progress, 0, 1)
	t = t * t * (3 - 2 * t)
	for key in ["scale_x", "scale_y", "offset_y"]:
		result[key] = lerpf(float(from.get(key, 0 if key == "offset_y" else 1)), float(to.get(key, 0 if key == "offset_y" else 1)), t)
	result.rotation = lerp_angle(float(from.get("rotation", 0)), float(to.get("rotation", 0)), t)
	return result

static func facing_for(delta: Vector2) -> String:
	if absf(delta.y) > absf(delta.x) * 0.85:
		return "back" if delta.y < 0 else "front"
	return "right" if delta.x > 0 else "left"

static func jump_height(progress: float, low_motion: bool) -> float:
	return 0.0 if low_motion else sin(clampf((progress - 0.14) / 0.72, 0.0, 1.0) * PI) * 85.0

static func pose(time: float, facing: String, low_motion: bool, complete: bool, travel: Dictionary = {}, action: Dictionary = {}) -> Dictionary:
	var result := {"key": "idle-front", "clip": "idle", "flip": false, "rotation": 0.0, "scale_x": 1.0, "scale_y": 1.0, "offset_y": 0.0}
	if complete:
		result.merge({"key": "salute", "clip": "bow"}, true)
		return result
	if low_motion:
		return result
	if not travel.is_empty():
		var elapsed := maxf(0, time - float(travel.get("started_at", 0)))
		var progress := clampf(float(travel.get("progress", 0)), 0.0, 1.0)
		if travel.get("jump", false):
			var landing := sin((progress - 0.8) / 0.2 * PI) if progress > 0.8 else 0.0
			result.merge({"key": "jump-%d" % (1 + mini(11, int(progress * 12))), "clip": "takeoff" if progress < 0.14 else "landing" if progress > 0.8 else "jump", "flip": facing == "right", "scale_x": 1.0 + landing * 0.025, "scale_y": 1.0 - landing * 0.025}, true)
		elif travel.get("rolling", false):
			result.merge({"key": "ball", "clip": "roll", "rotation": progress * float(travel.get("distance", 45)) / 32.0 * (-1.0 if facing == "left" else 1.0), "scale_x": 0.8, "scale_y": 0.8}, true)
		else:
			var group := walk_group(facing)
			var definition: Dictionary = WALK_CLIPS[group]
			var frames: Array = definition.frames
			var index := int(elapsed / float(definition.frame_ms)) % frames.size()
			var cycle := float(definition.frame_ms) * frames.size()
			result.merge({"key": "%s%d" % [definition.prefix, frames[index]], "clip": "walk-back" if group == "back" else "walk", "flip": facing == "right" and bool(definition.flip_right), "offset_y": 0.0 if group == "back" else -absf(sin(elapsed / cycle * TAU)) * 3.0, "rotation": 0.0 if group == "back" else sin(elapsed / cycle * TAU) * 0.018, "walk_group": group}, true)
		return result
	if not action.is_empty():
		var elapsed := time - float(action.get("started_at", 0))
		var kind: String = action.get("kind", "interact")
		if elapsed >= 0 and elapsed < 900:
			if kind == "symbiosis":
				result.merge({"key": "symbiosis", "clip": "symbiosis"}, true)
			elif kind == "sow":
				result.merge({"key": "sow-%d" % (1 + mini(4, int(elapsed / 140))), "clip": "sow", "flip": facing == "left"}, true)
			else:
				result.merge({"key": "lean" if kind == "note" else "interact", "clip": kind, "flip": facing == "right", "offset_y": -sin(minf(1, elapsed / 450.0) * PI) * 3.0 if kind == "note" else 0.0}, true)
			return result
	result.key = "idle-back" if facing == "back" else "idle-side" if facing in ["left", "right"] else "idle-front"
	result.flip = facing == "right"
	var breath := sin(time / 700.0)
	result.scale_y = 1.0 + breath * 0.012
	result.scale_x = 1.0 - breath * 0.006
	return result
