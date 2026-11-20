extends RefCounted
## Chapter cover art is a distant, non-interactive backdrop behind the 3D view.
## Blend against chapter mist so painted paving cannot compete with playable tiles.
const PROFILES := {
	"valley": {"image": preload("res://assets/images/chapter-covers-20261119-v2/valley.png"), "mist": Color("d4d2b6"), "opacity": 0.46},
	"pond": {"image": preload("res://assets/images/chapter-covers-20261119-v2/pond.png"), "mist": Color("73938c"), "opacity": 0.50},
	"cave": {"image": preload("res://assets/images/chapter-covers-20261119-v2/cave.png"), "mist": Color("282e4c"), "opacity": 0.48},
}

static func draw(canvas: CanvasItem, dimensions: Vector2, chapter: String) -> void:
	var profile: Dictionary = PROFILES.get(chapter, PROFILES.valley)
	var texture: Texture2D = profile.image
	var image_size := texture.get_size()
	# Aspect-preserving cover, with a small crop to keep the cover's main island
	# behind the board rather than showing a second competing foreground island.
	var scale := maxf(dimensions.x / image_size.x, dimensions.y / image_size.y) * 1.08
	var draw_size := image_size * scale
	canvas.draw_rect(Rect2(Vector2.ZERO, dimensions), profile.mist)
	canvas.draw_texture_rect(texture, Rect2((dimensions - draw_size) * Vector2(0.5, 0.46), draw_size), false, Color(1, 1, 1, profile.opacity))
