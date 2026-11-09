extends "res://tests/native_movement_test.gd"

func _run() -> void:
	await _setup("1-1")
	var original_root: Vector3 = stage.tile_position_id("f:0:0")
	var original_south: Vector3 = stage.tile_position_id("f:0:2")
	_check(is_equal_approx(stage.tile_position_id("f:2:0").x, 2.65), "right island moves outward by 0.65")
	_check(original_root == Vector3.ZERO and original_south.x == 0, "root and southern island retain positions")
	await _action("grow:root:right")
	var bridge: Node3D = stage._surfaces["g:root:1:0"]
	_check(is_equal_approx(bridge.to_global(Vector3(-0.5,0,0)).x,0.5), "extended flight meets old root edge")
	_check(is_equal_approx(bridge.to_global(Vector3(0.5,0,0)).x,2.15), "extended flight meets relocated island edge")
	var hero: CharacterBody3D = stage.get_actor_body("luvie")
	for offset: float in [-0.4, 0, 0.4]:
		var saved: Dictionary = session.world.snapshot()
		saved.actors.luvie = "g:root:1:0"
		saved.runtime = {"version":1, "poses":{"luvie":{"support":"g:root:1:0", "offset":[offset,0,0.1], "facing":"right"}}}
		var restored := Session.new("1-1", saved)
		movement.setup(restored, stage, router)
		var expected: Vector3 = stage.physical_position(Vector3(1+offset,0,0.1))
		_check(absf(hero.position.x-expected.x)<0.0001, "legacy normalized bridge offsets restore at same relative position")
		var pose: Vector3 = hero.position
		var captured: Dictionary = movement.capture()
		_check(absf(captured.poses.luvie.offset[0]-offset)<0.0001, "save retains normalized coordinates instead of enlarged physical offsets")
		movement.restore()
		_check(hero.position.distance_to(pose)<0.0002, "save restore is stable on the extended flight")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"platform-spacing", "checks":checks, "passed":failures.is_empty(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
