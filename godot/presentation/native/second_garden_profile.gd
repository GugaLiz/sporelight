class_name SecondGardenProfile
extends RefCounted

const Stairs = preload("res://presentation/native/stair_geometry.gd")
const Stone = preload("res://presentation/native/painted_stone_uv.gd")
const ENTRANCE := Vector3(3.53, 3.79, 5)
const REAR := Vector3(-0.46, 0.38, 6)
const LANDING_EXTRA := 1.4
const HEIGHT_UNIT := 0.45

static func base_height(tile: Dictionary) -> float:
	return float(tile.get("h", 0)) * HEIGHT_UNIT

static func to_physical(at: Vector3) -> Vector3:
	return Vector3(at.x + clampf(at.x - 3.5, 0, 1) * LANDING_EXTRA, at.y, at.z)

static func to_logical(at: Vector3) -> Vector3:
	var x := at.x
	if x > 4.5 + LANDING_EXTRA: x -= LANDING_EXTRA
	elif x > 3.5: x = 3.5 + (x - 3.5) / (1.0 + LANDING_EXTRA)
	return Vector3(x, at.y, at.z)

static func tile_scale(x: float) -> Vector3:
	return Vector3(1.0 + LANDING_EXTRA if is_equal_approx(x, 4.0) else 1.0, 1, 1)

static func height(at: Vector2, region: Vector2 = Vector2(INF, INF)) -> float:
	if not region.is_finite(): region = at
	# All seven root sockets stay flat, including both routes around the rock.
	if region.x < 3.5: return 0.0
	if region.y < 0.5: return HEIGHT_UNIT * (1.0 + Stairs.stair_fraction(-region.y, REAR))
	return HEIGHT_UNIT * Stairs.stair_fraction(region.x, ENTRANCE)

static func stride_height(at: Vector2) -> float:
	if at.x < 3.5: return 0.0
	var entrance := Stairs.stride_fraction(at.x, ENTRANCE, false, 1.0 + LANDING_EXTRA)
	entrance = lerpf(entrance, 1.0, smoothstep(-0.60, -0.50, -at.y))
	return HEIGHT_UNIT * (entrance + (Stairs.stride_fraction(-at.y, REAR) if at.y < 0.5 else 0.0))

static func sampling_grid() -> Array:
	var result: Array = [-0.5, 0.0, 0.5]
	for spec: Vector3 in [ENTRANCE, REAR]:
		for index in range(int(spec.z)):
			var value := spec.x + index * (spec.y - spec.x) / spec.z
			if spec == REAR: value = -value
			value -= floorf(value + 0.5)
			if not result.any(func(existing: float) -> bool: return absf(existing - value) < 0.00001): result.append(value)
	result.sort()
	return result

static func stair_spec(region: Vector2) -> Dictionary:
	if region.x >= 3.5 and region.y < 0.5 and -region.y > REAR.x and -region.y < REAR.y:
		return {"spec": REAR, "axis": 2, "distance": -region.y}
	if region.x > ENTRANCE.x and region.x < ENTRANCE.y:
		return {"spec": ENTRANCE, "axis": 0, "distance": region.x}
	return {}

static func tread_uv(at: Vector2, region: Vector2) -> Vector2:
	var descriptor := stair_spec(region)
	return Stairs.tread_uv(at, region, descriptor) if not descriptor.is_empty() else Vector2(at.x - floorf(region.x + 0.5) + 0.5, at.y - floorf(region.y + 0.5) + 0.5)

static func stone_uv(face: Vector2, riser := false) -> Vector2:
	return Stone.sample(face, riser)

static func foundation(_tile: Dictionary) -> float:
	return -0.67

static func connector_bottom(_center: Vector2, _at: Vector2) -> float:
	# Root roads are level slabs, never an inferred diagonal staircase.
	return -0.20

static func wall_uv(at: Vector3) -> Vector2:
	var physical := to_physical(at)
	return Vector2((physical.x + physical.z) / 4.5, -physical.y / 4.5)

static func material_spec(tile: Dictionary) -> Dictionary:
	var connector := str(tile.id).begins_with("g:")
	var paving := "paving-moss" if connector else "paving-grass" if str(tile.id) in ["f:-1:0", "f:-1:2", "f:5:0", "f:5:2"] else "paving-valley"
	var width := tile_scale(float(tile.x)).x
	return {"paving": paving, "connector": connector, "top_scale": Vector3(width,1,1), "face_repeat": width, "key": "second_garden_" + paving + ("_root" if connector else "") + ("_wide" if width > 1.0 else "")}
