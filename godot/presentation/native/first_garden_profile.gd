class_name FirstGardenProfile
extends RefCounted

const Stairs = preload("res://presentation/native/stair_geometry.gd")
const Stone = preload("res://presentation/native/painted_stone_uv.gd")

## Original islands; horizontal treads and vertical risers share collision.
## Only the grown south connector descends. The south island stays flat.
const EAST := Vector3(0.58, 1.48, 6)
# Give each tread 0.15 units of depth, matching the connecting flights.
# Keep a clear upper landing before the flowerbed contact patch.
const REAR := Vector3(0.41, 1.31, 6)
const SOUTH := Vector3(0.58, 1.48, 6)
const EAST_GAP_EXTRA := 0.65

static func to_physical(at: Vector3) -> Vector3:
	return Vector3(at.x + clampf(at.x - 0.5, 0.0, 1.0) * EAST_GAP_EXTRA, at.y, at.z)

static func to_logical(at: Vector3) -> Vector3:
	var x := at.x
	if x > 1.5 + EAST_GAP_EXTRA: x -= EAST_GAP_EXTRA
	elif x > 0.5: x = 0.5 + (x - 0.5) / (1.0 + EAST_GAP_EXTRA)
	return Vector3(x, at.y, at.z)

static func tile_scale(x: float) -> Vector3:
	return Vector3(1.0 + EAST_GAP_EXTRA if is_equal_approx(x, 1.0) else 1.0, 1, 1)

static func stair_fraction(distance: float, spec: Vector3) -> float:
	return Stairs.stair_fraction(distance, spec)

static func stride_fraction(distance: float, spec: Vector3, descending := false, stretch := 1.0) -> float:
	return Stairs.stride_fraction(distance, spec, descending, stretch)

static func stride_height(at: Vector2) -> float:
	if at.x >= 1.5 or (at.x >= 0.5 and at.y <= 0.5):
		return 0.65 * (stride_fraction(at.x, EAST, false, 1.0 + EAST_GAP_EXTRA) + (stride_fraction(-at.y, REAR) if at.x >= 1.5 else 0.0))
	if at.y >= 0.5: return -0.65 * stride_fraction(at.y, SOUTH, true)
	return 0.0

static func height(at: Vector2, region: Vector2 = Vector2(INF, INF)) -> float:
	if not region.is_finite(): region = at
	if region.x >= 1.5 or (region.x >= 0.5 and region.y <= 0.5):
		var entrance := stair_fraction(region.x, EAST)
		# The entrance reaches the island's front landing before the rear
		# flight starts. No lateral wedge may skew that flight's first lane.
		var rear := stair_fraction(-region.y, REAR) if region.x >= 1.5 else 0.0
		return 0.65 * (entrance + rear)
	if region.y >= 1.5: return -0.65
	if region.y >= 0.5: return -0.65 * stair_fraction(region.y, SOUTH)
	return 0.0

static func sampling_grid() -> Array:
	var result: Array = [-0.5, -0.35, -0.2, 0.0, 0.2, 0.5]
	for spec: Vector3 in [EAST, REAR, SOUTH]:
		for index in range(int(spec.z)):
			var value := spec.x + index * (spec.y - spec.x) / spec.z
			if spec == REAR: value = -value
			value -= floorf(value + 0.5)
			if not result.any(func(existing: float) -> bool: return absf(existing - value) < 0.00001): result.append(value)
	result.sort()
	return result

static func stair_spec(region: Vector2) -> Dictionary:
	if region.x >= 1.5 and -region.y > REAR.x and -region.y < REAR.y:
		return {"spec": REAR, "axis": 2, "distance": -region.y}
	if region.x > EAST.x and region.x < EAST.y:
		return {"spec": EAST, "axis": 0, "distance": region.x}
	if region.y > SOUTH.x and region.y < SOUTH.y:
		return {"spec": SOUTH, "axis": 1, "distance": region.y}
	return {}

static func tread_uv(at: Vector2, region: Vector2) -> Vector2:
	var descriptor := stair_spec(region)
	if descriptor.is_empty(): return Vector2(at.x - floorf(region.x + 0.5) + 0.5, at.y - floorf(region.y + 0.5) + 0.5)
	return Stairs.tread_uv(at, region, descriptor)

static func foundation(tile: Dictionary) -> float:
	if float(tile.x) >= 2.0: return -0.15
	if float(tile.z) >= 2.0: return -1.23
	return -0.67

## Rectify a painted parallelogram from the original isometric stairs.
## The image is unchanged; each mesh face supplies its own planar coordinates.
static func stone_uv(face: Vector2, riser: bool = false) -> Vector2:
	return Stone.sample(face, riser)

static func material_spec(tile: Dictionary) -> Dictionary:
	var paving := "paving-valley"
	if str(tile.get("kind", "")) == "root": paving = "paving-moss"
	elif str(tile.id) in ["f:0:0", "f:-2:-1", "f:-1:2", "f:-1:3", "f:4:-1", "f:2:-2", "f:4:-2"]: paving = "paving-grass"
	var connector := str(tile.id).begins_with("g:")
	var key := "first_garden_original_" + paving + ("_connector" if connector else "")
	return {"paving": paving, "connector": connector, "key": key}
