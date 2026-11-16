class_name GardenIsoProjection
extends RefCounted

const TILE_WIDTH := 70.0
const TILE_HEIGHT := 35.0
const HEIGHT_RISE := 48.0

static func raw(point: Dictionary) -> Vector2:
	return Vector2((float(point.get("x", 0)) - float(point.get("z", 0))) * 35.0, (float(point.get("x", 0)) + float(point.get("z", 0))) * 17.5 - float(point.get("h", 0)) * HEIGHT_RISE)

static func ground_depth(point: Dictionary) -> float:
	return float(point.get("x", 0)) + float(point.get("z", 0))

static func point(x: float, z: float, height: float = 0.0) -> Dictionary:
	return {"x": x, "z": z, "h": height}

static func interpolate(a: Dictionary, b: Dictionary, progress: float) -> Dictionary:
	return point(lerpf(float(a.get("x", 0)), float(b.get("x", 0)), progress), lerpf(float(a.get("z", 0)), float(b.get("z", 0)), progress), lerpf(float(a.get("h", 0)), float(b.get("h", 0)), progress))
