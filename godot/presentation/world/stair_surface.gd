class_name GardenStairSurface
extends RefCounted

const TREAD_COUNT := 8
const RUN_START := 0.1
const RUN_END := 0.9
const HALF_WIDTH := 0.29
const STEP_RUN := (RUN_END - RUN_START) / TREAD_COUNT
const SLOT_START := 0.5
const SLOT_FAR_SIDE := -0.34
const SLOT_NEAR_SIDE := 0.5
const Iso = preload("res://presentation/world/iso_projection.gd")
static var _architecture_cache: Dictionary = {}

## A local art pilot for the existing right root connection. It changes neither
## rule endpoints nor adjacency, and does not opt other stairs into the pilot.
static func build(level: Dictionary, pair: Array) -> Dictionary:
	if str(level.get("id", "")) != "1-1" or pair.size() != 2:
		return {}
	if not pair[0] is Dictionary or not pair[1] is Dictionary:
		return {}
	var low: Dictionary = pair[0] if str(pair[0].get("id", "")) == "g:root:1:0" else pair[1]
	var high: Dictionary = pair[1] if low == pair[0] else pair[0]
	if str(low.get("id", "")) != "g:root:1:0" or str(high.get("id", "")) != "f:2:0":
		return {}
	if not is_equal_approx(float(low.get("x", INF)), 1.0) or not is_zero_approx(float(low.get("z", INF))) or not is_zero_approx(float(low.get("h", INF))):
		return {}
	if not is_equal_approx(float(high.get("x", INF)), 2.0) or not is_zero_approx(float(high.get("z", INF))) or not is_equal_approx(float(high.get("h", INF)), 1.0):
		return {}
	return _descriptor(low, high, "steps", RUN_START, RUN_END, RUN_START - STEP_RUN, RUN_END - STEP_RUN)

## Only existing cardinal, one-height rule connections in the first garden
## participate. The two omitted rear stairs become stone slopes, not stairs.
static func connection(level: Dictionary, pair: Array) -> Dictionary:
	if str(level.get("id", "")) != "1-1" or pair.size() != 2 or not pair[0] is Dictionary or not pair[1] is Dictionary:
		return {}
	var a: Dictionary = pair[0]
	var b: Dictionary = pair[1]
	if a.is_empty() or b.is_empty() or a.get("solid", false) or b.get("solid", false):
		return {}
	var delta := Vector2(float(b.x) - float(a.x), float(b.z) - float(a.z))
	if not is_equal_approx(absf(delta.x) + absf(delta.y), 1.0) or not is_zero_approx(delta.x) and not is_zero_approx(delta.y) or not is_equal_approx(absf(float(b.h) - float(a.h)), 1.0):
		return {}
	var exact := build(level, pair)
	if not exact.is_empty():
		return exact
	var low: Dictionary = a if float(a.h) < float(b.h) else b
	var high: Dictionary = b if float(a.h) < float(b.h) else a
	var hidden_stair := str(low.get("id", "")) in ["f:2:0", "f:3:0"] and str(high.get("id", "")) in ["f:2:-1", "f:3:-1"] and is_equal_approx(float(low.x), float(high.x))
	return _descriptor(low, high, "ramp" if hidden_stair else "steps", 0.2 if hidden_stair else 0.275, 0.8 if hidden_stair else 0.875, 0.2, 0.8)

static func _descriptor(low: Dictionary, high: Dictionary, style: String, run_start: float, run_end: float, rail_start: float, rail_end: float) -> Dictionary:
	return {"key": str(low.id) + "|" + str(high.id), "low": low.duplicate(), "high": high.duplicate(), "direction": Vector2(float(high.x) - float(low.x), float(high.z) - float(low.z)), "run_start": run_start, "run_end": run_end, "rail_start": rail_start, "rail_end": rail_end, "half_width": HALF_WIDTH, "treads": TREAD_COUNT, "step_run": (run_end - run_start) / TREAD_COUNT, "style": style}

static func connectors(level: Dictionary, board: Array) -> Array:
	if str(level.get("id", "")) != "1-1":
		return []
	var result: Array = []
	for first in range(board.size()):
		for second in range(first + 1, board.size()):
			var surface := connection(level, [board[first], board[second]])
			if not surface.is_empty():
				result.append(surface)
	return result

## Fixed architectural sockets are art only. The virtual root is used solely
## to reserve the high island's entrance before a real bridge is grown.
static func architecture(level: Dictionary) -> Array:
	if str(level.get("id", "")) != "1-1":
		return []
	var signature := hash(level.get("tiles", []))
	if not _architecture_cache.has(signature):
		var board: Array = level.get("tiles", []).duplicate()
		board.append({"id": "g:root:1:0", "x": 1.0, "z": 0.0, "h": 0.0, "kind": "root"})
		_architecture_cache[signature] = connectors(level, board)
	return _architecture_cache[signature]

static func point_at(surface: Dictionary, u: float, v: float, height: float) -> Dictionary:
	var low: Dictionary = surface.low
	var direction: Vector2 = surface.direction
	return {"x": float(low.x) + direction.x * u - direction.y * v, "z": float(low.z) + direction.y * u + direction.x * v, "h": height}

static func corners(surface: Dictionary, index: int) -> Array:
	if surface.is_empty() or str(surface.get("style", "steps")) == "ramp" or index < 0 or index >= TREAD_COUNT:
		return []
	var low: Dictionary = surface.low
	var direction: Vector2 = surface.direction
	var length := float(surface.step_run)
	var front := float(surface.run_start) + index * length
	var back := float(surface.run_start) + (index + 1) * length
	var height := lerpf(float(low.h), float(surface.high.h), (index + 1.0) / TREAD_COUNT)
	var result: Array = []
	for vertex in [Vector2(-HALF_WIDTH, front), Vector2(HALF_WIDTH, front), Vector2(HALF_WIDTH, back), Vector2(-HALF_WIDTH, back)]:
		result.append({"x": float(low.x) + direction.x * vertex.y - direction.y * vertex.x, "z": float(low.z) + direction.y * vertex.y + direction.x * vertex.x, "h": height})
	return result

static func ramp_corners(surface: Dictionary) -> Array:
	if surface.is_empty() or str(surface.get("style", "")) != "ramp":
		return []
	return [
		point_at(surface, float(surface.rail_start), -float(surface.half_width), float(surface.low.h)),
		point_at(surface, float(surface.rail_start), float(surface.half_width), float(surface.low.h)),
		point_at(surface, float(surface.rail_end), float(surface.half_width), float(surface.high.h)),
		point_at(surface, float(surface.rail_end), -float(surface.half_width), float(surface.high.h))
	]

## A continuous support rail avoids a separate 5ms body jump at every riser.
## The visible treads are independent: clearance reports the real gap between
## the rail and the horizontal step below it, bounded by one 6px riser.
static func contact(surface: Dictionary, u: float) -> Dictionary:
	if surface.is_empty():
		return {}
	var progress := clampf(u, 0.0, 1.0)
	var rise := float(surface.high.h) - float(surface.low.h)
	var rail := clampf((progress - float(surface.rail_start)) / (float(surface.rail_end) - float(surface.rail_start)), 0.0, 1.0)
	var support_index := -1 if progress < float(surface.run_start) else TREAD_COUNT if progress >= float(surface.run_end) else mini(TREAD_COUNT - 1, int(floor((progress - float(surface.run_start) + 0.0000001) / float(surface.step_run))))
	var height := float(surface.low.h) + rise * rail
	var support_height := height if str(surface.style) == "ramp" else float(surface.low.h) if support_index < 0 else float(surface.high.h) if support_index >= TREAD_COUNT else float(surface.low.h) + rise * (support_index + 1.0) / TREAD_COUNT
	return {"u": u, "h": height, "rail_h": height, "ground": support_height, "phase": "ramp" if rail > 0.0 and rail < 1.0 else "landed", "tread_index": support_index, "support_index": support_index, "support_h": support_height, "clearance": maxf(0.0, height - support_height), "penetration": maxf(0.0, support_height - height)}

static func stairs_depth(surface: Dictionary) -> float:
	return float(surface.low.x) + float(surface.low.z) + 0.04

## This is the actual architectural opening in the high landing's top face.
## It is independent of bridge growth and contains no projected actor mask.
static func slot_top(surface: Dictionary) -> Array:
	if surface.is_empty():
		return []
	var height := float(surface.high.h)
	return [
		point_at(surface, SLOT_START, SLOT_FAR_SIDE, height),
		point_at(surface, float(surface.run_end), SLOT_FAR_SIDE, height),
		point_at(surface, float(surface.run_end), SLOT_NEAR_SIDE, height),
		point_at(surface, SLOT_START, SLOT_NEAR_SIDE, height)
	]

## Kept as an art-geometry query for older tooling; no tall actor silhouette.
static func cover_polygon(surface: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in slot_top(surface):
		points.append(Iso.raw(point))
	return points
