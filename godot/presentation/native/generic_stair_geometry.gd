class_name GenericStairGeometry
extends RefCounted

## A whole one-cell connection has four physical risers. Its middle is a
## horizontal tread, so ownership changes at the shared support edge safely.
const HALF_WIDTH := 0.32
const LANDING := 0.20
const RUN := 0.15
const NOSES := [0.275, 0.425]
const GRID := [-0.5, -0.425, -0.32, -0.275, -0.20, 0.0, 0.20, 0.275, 0.32, 0.425, 0.5]
const AXES := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const StoneUV = preload("res://presentation/native/painted_stone_uv.gd")

static func height(region: Vector2, rises: Array[float], stride := false) -> float:
	var positive := 0.0
	var negative := 0.0
	for direction in range(4):
		var axis: Vector2 = AXES[direction]
		var distance := region.dot(axis)
		if absf(region.dot(Vector2(-axis.y, axis.x))) > HALF_WIDTH: continue
		var fraction := 0.0
		for nose: float in NOSES:
			if stride:
				fraction += smoothstep(nose - 0.10, nose, distance) if rises[direction] > 0 else smoothstep(nose, nose + 0.10, distance)
			elif distance > nose:
				fraction += 1.0
		var value := rises[direction] * fraction / 4.0
		positive = maxf(positive, value)
		negative = minf(negative, value)
	return positive + negative

static func descriptor(region: Vector2, rises: Array[float]) -> Dictionary:
	var result := {}
	var strongest := -1.0
	for direction in range(4):
		if is_zero_approx(rises[direction]): continue
		var axis: Vector2 = AXES[direction]
		var distance := region.dot(axis)
		if distance < LANDING or absf(region.dot(Vector2(-axis.y, axis.x))) > HALF_WIDTH: continue
		if distance <= strongest: continue
		strongest = distance
		result = {"axis": axis, "distance": distance, "rise": rises[direction], "step_height": absf(rises[direction]) / 4.0}
	return result

static func tread_uv(at: Vector2, region: Vector2, rises: Array[float]) -> Vector2:
	var spec := descriptor(region, rises)
	if spec.is_empty(): return Vector2.ZERO
	var axis: Vector2 = spec.axis
	var across := Vector2(-axis.y, axis.x)
	var direction := 1.0 if float(spec.rise) > 0 else -1.0
	var distance := float(spec.distance)
	# Extend the half-tread UV across the neighboring support with no seam.
	var start := 0.125 if distance < NOSES[0] else NOSES[0] if distance < NOSES[1] else NOSES[1]
	var along := clampf((at.dot(axis) - start) / RUN, 0.0, 1.0)
	return Vector2(clampf(at.dot(across) * direction / (2.0 * HALF_WIDTH) + 0.5, 0.0, 1.0), along if direction > 0 else 1.0 - along)
