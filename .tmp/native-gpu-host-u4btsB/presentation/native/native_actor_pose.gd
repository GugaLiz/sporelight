extends RefCounted
## The 256px action canvases were independently fitted to the same height.
## A crouch therefore contains a larger head than the approved standing art.
## Calibrate the hat, not the whole silhouette (which includes hands/soil),
## and pivot around the visible soles. Never resize/repaint the source PNGs.

const Definitions = preload("res://elements/actor_definitions.gd")

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
	if clip == "roll": return # Ball diameter/rotation are visual-only skin settings.
	var skin: Dictionary = sprite.get_meta("actor_skin_definition", Definitions.skin("luvie.original"))
	var standing: Dictionary = skin.standing
	var pose: Dictionary = skin.get("pose_overrides", {}).get(clip, {})
	pose = pose.get("frames", {}).get(str(sprite.frame), pose)
	var foot: Array = pose.get("foot", standing.foot)
	var canvas: Array = standing.canvas
	var offset := Vector2(float(canvas[0])*.5-float(foot[0]), float(foot[1])-float(canvas[1])*.5)
	if sprite.flip_h: offset.x = -offset.x
	sprite.pixel_size = float(standing.pixel_size) * float(pose.get("scale", 1.0))
	sprite.offset = offset
