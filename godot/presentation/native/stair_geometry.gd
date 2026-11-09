class_name StairGeometry
extends RefCounted

## Shared stepped height and visible-sole envelope. Coordinates remain logical;
## stretch converts the anticipation distance to physical units.
static func stair_fraction(distance: float, spec: Vector3) -> float:
	if distance <= spec.x: return 0.0
	if distance >= spec.y: return 1.0
	return (floorf((distance - spec.x) / ((spec.y - spec.x) / spec.z)) + 1.0) / spec.z

static func stride_fraction(distance: float, spec: Vector3, descending := false, stretch := 1.0) -> float:
	# Anticipate an ascent and finish a descent after the edge. This upper
	# envelope never puts the visible sole below the real horizontal tread.
	var blend := 0.10 / stretch
	var value := 0.0
	for index in range(int(spec.z)):
		var nose := spec.x + index * (spec.y - spec.x) / spec.z
		value += smoothstep(nose if descending else nose - blend, nose + blend if descending else nose, distance)
	return value / spec.z

static func tread_uv(at: Vector2, region: Vector2, descriptor: Dictionary) -> Vector2:
	var spec: Vector3 = descriptor.spec
	var run := (spec.y - spec.x) / spec.z
	var start := spec.x + floorf((float(descriptor.distance) - spec.x) / run) * run
	var distance := at.x if descriptor.axis == 0 else at.y if descriptor.axis == 1 else -at.y
	var cross := at.y - floorf(region.y + 0.5) + 0.5 if descriptor.axis == 0 else at.x - floorf(region.x + 0.5) + 0.5
	return Vector2(cross, clampf((distance - start) / run, 0.0, 1.0))
