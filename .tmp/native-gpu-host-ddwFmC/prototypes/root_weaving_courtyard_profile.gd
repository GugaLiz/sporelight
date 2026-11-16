extends "res://presentation/native/second_garden_profile.gd"
## The rear garden is a level terrace, not a second destination above the goal.
## Keep the entrance, socket coordinates, domain graph and island footprint.
const BaseProfile = preload("res://presentation/native/second_garden_profile.gd")

static func base_height(tile: Dictionary) -> float:
	return HEIGHT_UNIT if float(tile.get("x", 0)) >= 3.5 else 0.0

static func height(at: Vector2, region: Vector2 = Vector2(INF, INF)) -> float:
	if not region.is_finite(): region = at
	if region.x >= 3.5 and region.y < 0.5: return HEIGHT_UNIT
	return HEIGHT_UNIT * Stairs.stair_fraction(region.x, ENTRANCE) if region.x >= 3.5 else 0.0

static func stride_height(at: Vector2) -> float:
	if at.x >= 3.5 and at.y < 0.5: return HEIGHT_UNIT
	return HEIGHT_UNIT * Stairs.stride_fraction(at.x, ENTRANCE, false, 1.0 + LANDING_EXTRA) if at.x >= 3.5 else 0.0

static func sampling_grid() -> Array:
	var result: Array = [-0.5, 0.0, 0.5]
	for index in range(int(ENTRANCE.z)):
		var value := ENTRANCE.x + index * (ENTRANCE.y - ENTRANCE.x) / ENTRANCE.z
		value -= floorf(value + 0.5)
		if not result.has(value): result.append(value)
	result.sort()
	return result

static func stair_spec(region: Vector2) -> Dictionary:
	if region.y >= 0.5 and region.x > ENTRANCE.x and region.x < ENTRANCE.y:
		return {"spec": ENTRANCE, "axis": 0, "distance": region.x}
	return {}

static func tread_uv(at: Vector2, region: Vector2) -> Vector2:
	var descriptor := stair_spec(region)
	return Stairs.tread_uv(at, region, descriptor) if not descriptor.is_empty() else Vector2(at.x - floorf(region.x + 0.5) + 0.5, at.y - floorf(region.y + 0.5) + 0.5)

static func material_spec(tile: Dictionary) -> Dictionary:
	var spec := BaseProfile.material_spec(tile)
	spec.key = "courtyard_" + str(spec.key)
	return spec
