extends RefCounted
## Source stone plinths, independent of ivy and the empty doorway. Both
## placement and collision inverse-project these same painted ground feet.
const RIGHT := Vector3(0.70710678, 0, -0.70710678)
const FRONT := Vector3(0.70710678, 0, 0.70710678)
const SCENERY_ANCHOR := Vector2(160, 231.5)
const FEET := [Vector4(72,188,30,15), Vector4(164,213,32,16)]

static func rectangles(at: Vector3, pixel: float, anchor: Vector2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for foot: Vector4 in FEET:
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for corner: Vector2 in [Vector2(-foot.z,0),Vector2(0,-foot.w),Vector2(foot.z,0),Vector2(0,foot.w)]:
			var source := Vector2(foot.x,foot.y) + corner - anchor
			var point := at + RIGHT * source.x * pixel + FRONT * source.y * pixel * 2
			minimum = minimum.min(Vector2(point.x,point.z))
			maximum = maximum.max(Vector2(point.x,point.z))
		result.append(Rect2(minimum,maximum-minimum))
	return result

static func scenery(at: Vector3, width: float) -> Array[Rect2]:
	return rectangles(at,width/256.0,SCENERY_ANCHOR)

static func card(card_node: Sprite3D) -> Array[Rect2]:
	var anchor := Vector2(card_node.texture.get_width()*.5-card_node.offset.x,card_node.texture.get_height()*.5+card_node.offset.y)
	return rectangles(card_node.global_position,card_node.pixel_size,anchor)
