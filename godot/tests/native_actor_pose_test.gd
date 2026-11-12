extends SceneTree
## CPU image measurements and real native actor integration; no GPU claim.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var failures: Array[String] = []
var checks := 0
var images: Dictionary = {}
var measurements: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _image(texture: Texture2D) -> Image:
	var path := texture.resource_path
	if not images.has(path): images[path] = Image.load_from_file(ProjectSettings.globalize_path(path))
	return images[path]

func _hat_width(picture: Image) -> float:
	# Only the upper red hat: arms, cape, soil and jump hands must not affect
	# anatomical scale. This reads original PNG pixels, not the pose table.
	var left := 256
	var right := -1
	for y in range(20, 126):
		for x in range(256):
			var color := picture.get_pixel(x, y)
			if color.a >= 0.5 and color.r > 0.31 and color.r > color.g * 1.4 and color.r > color.b * 1.4:
				left = mini(left, x)
				right = maxi(right, x)
	return float(right - left + 1)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var world := World.new("1-1")
	stage.set_world(world)
	await process_frame
	stage.set_paused(true)
	var body: CharacterBody3D = stage.get_actor_body("luvie")
	var sprite: AnimatedSprite3D = body.get_node("Visual/Art")
	body.get_node("Visual/AnimationPlayer").stop()
	stage.actor_visual_root("luvie").scale = Vector3.ONE
	var body_position := body.position
	var collision: Shape3D = body.get_node("Collision").shape
	var baseline_image := _image(sprite.sprite_frames.get_frame_texture("idle_front", 0))
	var baseline_hat := _hat_width(baseline_image) * 0.00625
	var baseline_height := baseline_image.get_used_rect().size.y * 0.00625
	_check(is_equal_approx(baseline_hat, 0.725), "approved standing head remains 116 pixels at the original pixel size")

	# Every texture actually used by every native animation, including jump
	# and both directional walk cycles, retains its original authored bytes.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/visual-assets.json"))
	var hashes: Dictionary = {}
	for entry: Dictionary in manifest.entries: hashes[str(entry.resource)] = str(entry.sha256)
	for clip: StringName in sprite.sprite_frames.get_animation_names():
		for frame in range(sprite.sprite_frames.get_frame_count(clip)):
			var texture := sprite.sprite_frames.get_frame_texture(clip, frame)
			_check(FileAccess.get_sha256(texture.resource_path) == hashes.get(texture.resource_path, ""), "%s/%d preserves source artwork bytes" % [clip, frame])
			if clip == &"roll": continue
			sprite.play(clip)
			sprite.set_frame_and_progress(frame, 0.5)
			var picture := _image(texture)
			_check(picture.get_size() == Vector2i(256, 256), "%s/%d retains its original canvas" % [clip, frame])
			var width := _hat_width(picture) * sprite.pixel_size
			_check(width >= baseline_hat * 0.85 and width <= baseline_hat * 1.025, "%s/%d head stays within natural standing directional width: %f" % [clip, frame, width])
			if str(clip).begins_with("idle_") or str(clip).begins_with("walk_") or clip == &"jump":
				_check(is_equal_approx(sprite.pixel_size, 0.00625) and sprite.offset == Vector2(0, 108), "%s/%d keeps approved locomotion size and pivot" % [clip, frame])

	for facing: String in ["front", "back", "left", "right"]:
		for action: String in ["grow:root:right", "sow", "repair", "interact"]:
			stage.update_actor_visual("luvie", Vector3.ZERO, facing, action)
			var clip := str(sprite.animation)
			for frame in range(sprite.sprite_frames.get_frame_count(clip)):
				# No manual pose recalibration: the frame signal must fix frame 5
				# even between two calls to update_actor_visual.
				sprite.set_frame_and_progress(frame, 0.5)
				var picture := _image(sprite.sprite_frames.get_frame_texture(clip, frame))
				var width := _hat_width(picture) * sprite.pixel_size
				_check(absf(width - baseline_hat) < 0.01, "%s/%d %s has the same anatomical head scale" % [clip, frame, facing])
				var height := picture.get_used_rect().size.y * sprite.pixel_size
				if clip == "interact" or (clip == "sow" and frame < 4):
					_check(height < baseline_height * 0.90, "crouching remains shorter than standing, not refitted to full height")
				_check_visible_sole(stage, sprite, clip, frame)
			stage.update_actor_visual("luvie", Vector3.ZERO, facing)
			_check(is_equal_approx(sprite.pixel_size, 0.00625) and sprite.offset == Vector2(0, 108), "ending an action restores the full standing baseline")
		world.state.completed = true
		stage.update_actor_visual("luvie", Vector3.ZERO, facing, "repair")
		_check(str(sprite.animation) == "complete", "final repair selects the calibrated salute")
		_check_visible_sole(stage, sprite, "complete", 0)
		world.state.completed = false
	_check(body.position == body_position and body.get_node("Collision").shape == collision, "art calibration never moves the body or changes collision")
	stage._actor_state.luvie.rolling = true
	stage.update_actor_visual("luvie", Vector3.ZERO)
	_check(str(sprite.animation) == "roll" and is_equal_approx(sprite.pixel_size, 0.8 / 99.0) and sprite.offset == Vector2.ZERO, "rolling keeps the existing ball diameter and pivot")
	stage._actor_state.luvie.rolling = false
	stage.update_actor_visual("luvie", Vector3.ZERO)
	_check(is_equal_approx(sprite.pixel_size, 0.00625), "leaving roll restores full standing size")
	for clip: String in ["idle_front", "interact", "sow", "complete", "jump"]:
		for frame in range(sprite.sprite_frames.get_frame_count(clip)):
			sprite.play(clip)
			sprite.set_frame_and_progress(frame, 0.0)
			measurements.append({"clip": clip, "frame": frame, "pixelSize": sprite.pixel_size, "hatWidth": _hat_width(_image(sprite.sprite_frames.get_frame_texture(clip, frame))) * sprite.pixel_size, "offset": [sprite.offset.x, sprite.offset.y]})
	print(JSON.stringify({"suite": "native-actor-pose", "checks": checks, "passed": failures.is_empty(), "failures": failures, "measurements": measurements, "scope": "CPU source pixels, animation signals, native transforms and collision; no GPU render verification"}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_visible_sole(stage: Node, sprite: AnimatedSprite3D, clip: String, frame: int) -> void:
	# Independently marked sole locations from the actual source PNGs. The
	# sow soil lies further down/left and must not become the actor's pivot.
	var foot := Vector2(146, 234)
	if clip == "sow": foot = Vector2(169, 229) if frame < 4 else Vector2(142, 235)
	if clip == "complete": foot = Vector2(146, 235)
	var picture := _image(sprite.sprite_frames.get_frame_texture(clip, frame))
	_check(picture.get_pixel(int(foot.x), int(foot.y) - 3).a > 0.5, "marked sole belongs to the visible character")
	var mirrored_x := 256 - foot.x if sprite.flip_h else foot.x
	var local := Vector3(mirrored_x - 128 + sprite.offset.x, 128 - foot.y + sprite.offset.y, 0) * sprite.pixel_size
	var projected: Vector2 = stage.world_to_screen(sprite.to_global(local))
	var ground: Vector2 = stage.actor_screen_footpoint("luvie")
	_check(projected.distance_to(ground) < 0.01, "actual sole stays on the same ground point, including mirrored actions")
	_check(not sprite.no_depth_test, "corrected action retains structural occlusion")
