extends RefCounted
## The 256px action canvases were independently fitted to the same height.
## A crouch therefore contains a larger head than the approved standing art.
## Calibrate the hat, not the whole silhouette (which includes hands/soil),
## and pivot around the visible soles. Never resize/repaint the source PNGs.

const STANDING_PIXEL_SIZE := 0.00625
const STANDING_HAT_WIDTH := 116.0

static func bind_sprite(sprite: AnimatedSprite3D) -> void:
	# AnimatedSprite3D advances independently of the stage's pose update. In
	# particular, sow frame 5 returns upright and needs its own calibration.
	var update := apply.bind(sprite)
	if not sprite.frame_changed.is_connected(update):
		sprite.frame_changed.connect(update)
	if not sprite.animation_changed.is_connected(update):
		sprite.animation_changed.connect(update)
	apply(sprite)

static func apply(sprite: AnimatedSprite3D) -> void:
	var clip := str(sprite.animation)
	if clip == "roll":
		return # Ball diameter and rotation are owned by the stage.
	var ratio := 1.0
	var foot := Vector2(128, 236)
	match clip:
		"interact":
			ratio = STANDING_HAT_WIDTH / 139.0
			foot = Vector2(146, 234)
		"sow":
			if sprite.frame < 4:
				ratio = STANDING_HAT_WIDTH / 135.0
				# Ignore the painted soil at x25..109, y234: the character's
				# two soles end at y228 and are centered on x169.
				foot = Vector2(169, 229)
			else:
				ratio = STANDING_HAT_WIDTH / 126.0
				foot = Vector2(142, 235)
		"complete":
			ratio = STANDING_HAT_WIDTH / 126.0
			foot = Vector2(146, 235)
	# flip_h mirrors UVs, not the mesh offset. Mirror the pivot correction too.
	var offset := Vector2(128 - foot.x, foot.y - 128)
	if sprite.flip_h: offset.x = -offset.x
	sprite.pixel_size = STANDING_PIXEL_SIZE * ratio
	sprite.offset = offset
