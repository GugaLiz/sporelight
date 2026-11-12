extends RefCounted
const OriginalRatios = preload("res://presentation/native/original_prop_ratios.gd")
## Reviewed alpha >= 128 bounds, in source pixels. Keep floating icons,
## hanging vines and authored isometric planters on their dedicated anchors.
const GROUND_TRIMMED := ["fern", "pink-flowers", "blue-flowers", "yellow-flowers", "red-mushroom", "blue-mushroom", "stone-lantern", "wood-lantern", "flowers", "crystal", "dew-plant", "dew-parcel"]
const BODY_BOUNDS := {
	"light": Rect2(16, 55, 224, 177),
	"lilypad": Rect2(0, 0, 146, 85),
	"crystal": Rect2(0, 0, 88, 102),
	"dew-parcel": Rect2(0, 0, 91, 97),
	"spore": Rect2(6, 6, 197, 149),
	"bug": Rect2(73, 108, 114, 110),
}
const ITEM_WIDTH := {"light": 0.35, "crystal": 0.40, "dew-parcel": 0.38, "spore": 0.30, "bug": 0.28}

static func item_body(sprite: Sprite3D, alias: String) -> void:
	if sprite.texture == null or not ITEM_WIDTH.has(alias): return
	var bounds: Rect2 = BODY_BOUNDS[alias]
	sprite.pixel_size = float(ITEM_WIDTH[alias]) / bounds.size.x

static func ground_anchor(sprite: Sprite3D, alias: String, level: String) -> void:
	if level == "1-1" or alias not in GROUND_TRIMMED or sprite.texture == null: return
	# These exported images are tightly trimmed: the last opaque row is the
	# painted foot. Centre the bottom pixel on the support, not 10% below it.
	sprite.offset = Vector2(0, (sprite.texture.get_height() - 1) * 0.5)

static func ground_body(sprite: Sprite3D, alias: String) -> void:
	if sprite.texture == null: return
	var width := OriginalRatios.canvas_width(alias)
	if width > 0: sprite.pixel_size = width / sprite.texture.get_width()

static func carried(sprite: Sprite3D, alias: String) -> void:
	if sprite.texture == null or not ITEM_WIDTH.has(alias): return
	var bounds: Rect2 = BODY_BOUNDS[alias]
	item_body(sprite, alias)
	# Hands carry the visible body centre, regardless of transparent padding.
	var centre := bounds.position + bounds.size * 0.5
	sprite.offset = Vector2(sprite.texture.get_width() * 0.5 - centre.x, centre.y - sprite.texture.get_height() * 0.5)

static func insect(sprite: Sprite3D) -> void:
	var bounds: Rect2 = BODY_BOUNDS.bug
	sprite.pixel_size = OriginalRatios.canvas_width("bug") / sprite.texture.get_width()
	# Insect is hovering, not planted. Keep its body visibly above the flower.
	var centre := bounds.position + bounds.size * 0.5
	sprite.offset = Vector2(sprite.texture.get_width() * 0.5 - centre.x, centre.y - sprite.texture.get_height() * 0.5)
	sprite.position.y = (20.5 * sqrt(2.0) / 70.0) / 0.8660254
