class_name PaintedStoneUV
extends RefCounted

## Rectified faces in the original 142 x 147 stair artwork; not a terrain rule.
static func sample(face: Vector2, riser := false) -> Vector2:
	var pixel := Vector2(33, 67) + Vector2(41, 13) * face.x + Vector2(0, 10) * face.y if riser else Vector2(43, 59) + Vector2(42, 13) * face.x + Vector2(-11, 6) * (1.0 - face.y)
	return pixel / Vector2(142, 147)
