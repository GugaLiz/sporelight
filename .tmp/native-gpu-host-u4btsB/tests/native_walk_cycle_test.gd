extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_world(World.new("1-1"))
	stage.set_process(false)
	var sprite: AnimatedSprite3D = stage.get_actor_body("luvie").get_node("Visual/Art")
	for direction: String in ["left", "right"]:
		var clip := "walk_" + direction
		_check(sprite.sprite_frames.get_frame_count(clip) == 12, direction + " has a complete alternating-foot cycle")
		_check(sprite.sprite_frames.get_animation_loop(clip), direction + " loops while held")
		for index in range(12):
			_check(sprite.sprite_frames.get_frame_texture(clip, index).resource_path == "res://assets/images/menu-walk/step-%d.png" % (index + 1), direction + " uses existing registered pose " + str(index))
	stage.update_actor_visual("luvie", Vector3(-3.2, 0, 0), "left")
	sprite.set_frame_and_progress(5, 0.5)
	stage.update_actor_visual("luvie", Vector3(3.2, 0, 0), "right")
	_check(sprite.frame == 5 and is_equal_approx(sprite.frame_progress, 0.5), "turning preserves gait phase")
	_check(sprite.flip_h, "right gait mirrors the same complete cycle")
	var seen := {}
	for unused in range(36):
		stage.update_actor_visual("luvie", Vector3(3.2, 0, 0), "right")
		await create_timer(0.025).timeout
		seen[sprite.frame] = true
	_check(seen.size() >= 10 and seen.has(0) and seen.has(6), "continuous updates advance both half-cycles and loop")
	stage.update_actor_visual("luvie", Vector3.ZERO, "right")
	_check(sprite.animation == "idle_right", "release restores original idle")
	stage.update_actor_visual("luvie", Vector3.ZERO, "right", "grow:root:right")
	_check(sprite.animation == "sow", "planting still owns its original pose")
	stage.update_actor_visual("luvie", Vector3.ZERO, "right")
	_check(sprite.animation == "idle_right", "planting completion restores idle")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-walk-cycle", "passed":failures.is_empty(), "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
