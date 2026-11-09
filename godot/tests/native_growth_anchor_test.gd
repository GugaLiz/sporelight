extends "res://tests/native_movement_test.gd"

func _assert_choices(expected: int) -> Array:
	var choices: Array = stage.growth_choice_layout()
	_check(choices.size() == expected, "all legal directions remain visible")
	for choice: Dictionary in choices:
		var at := Vector2(choice.x, choice.y)
		var anchor := Vector2(choice.anchorX, choice.anchorY)
		_check(at.distance_to(anchor) >= 49.9 and at.distance_to(anchor) <= 64.1, "choices stay beside seedbed")
		_check(choice.placement == "seedbed", "first garden explicitly opts into seedbed controls")
		_check(stage.command_hit_test(at) == choice.id, "drawn center selects its own direction")
		_check(stage.command_hit_test(at + Vector2(0, 20)) == choice.id, "touch margin selects same direction")
	return choices

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _setup("1-1")
	var original := _assert_choices(2)
	for choice: Dictionary in original:
		_check(stage.command_hit_test(stage.project(stage._growth_target(choice.target))) == "", "old road location is no longer a command hotspot")
	# Simulate repositioning the rendered seedbed without changing logical sockets.
	var prop: Node3D = stage._props_nodes["mark:root"]
	prop.position += Vector3(0.2, 0, -0.2)
	var shifted := _assert_choices(2)
	for i in range(mini(original.size(), shifted.size())):
		var delta := Vector2(shifted[i].x-original[i].x, shifted[i].y-original[i].y)
		var anchor_delta := Vector2(shifted[i].anchorX-original[i].anchorX, shifted[i].anchorY-original[i].anchorY)
		_check(delta.length() > 1 and delta.distance_to(anchor_delta) < 0.01, "button follows actual prop transform")
	if not shifted.is_empty():
		var at := Vector2(shifted[0].x, shifted[0].y)
		stage.set_ui_regions([Rect2(at - Vector2(15, 15), Vector2(30, 30))])
		_check(stage.command_hit_test(at) == "", "HUD-hidden choice cannot be clicked")
	stage.set_ui_regions([])
	stage.set_paused(true)
	_check(stage.growth_choice_layout().is_empty(), "paused overlay has no hotspots")
	stage.set_paused(false)
	for route: Array in [["up", "right", "right", "down"], ["down", "right", "right", "up"]]:
		await _setup("1-2")
		session.world.state.actors.luvie = "f:1:1"
		stage.refresh_world(session.world, true)
		movement.restore()
		await physics_frame
		var rock_ray := PhysicsRayQueryParameters3D.create(Vector3(2, 3, 1), Vector3(2, -2, 1), 1)
		_check(stage._scene.get_world_3d().direct_space_state.intersect_ray(rock_ray).is_empty(), "rock dressing creates no walkable bridge across gap")
		var rock: Node3D = stage._props.get_node("Surface_rock-foundation")
		_check(rock.position == Vector3(2,0,1) and rock.scale.x < 1.0, "central obstacle keeps its original cell with visible gaps at its sides")
		for direction: String in route:
			var choices: Array = stage.growth_choice_layout()
			for choice: Dictionary in choices:
				var expected: Vector2 = stage.world_to_screen(stage.tile_position(stage._growth_target(choice.target)) + Vector3(0, 0.05, 0))
				_check(choice.placement == "socket" and expected.distance_to(Vector2(choice.x, choice.y)) < 0.01, "second garden displays each actual next socket, not a fixed seedbed direction pad")
				_check(stage.command_hit_test(expected) == choice.id, "next socket hit region matches the displayed planting location")
			var matching := choices.filter(func(c: Dictionary) -> bool: return c.id == "grow:root:" + direction)
			_check(matching.size() == 1, "continuing root direction remains available " + direction)
			if not matching.is_empty():
				var c: Dictionary = matching[0]
				await _action(stage.command_hit_test(Vector2(c.x, c.y)))
		_check(session.world.budget() == 0 and session.world.connected(), "four correct selections complete original route")
		_check(stage.growth_choice_layout().is_empty(), "exhausted root has no plus buttons")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"growth-anchor", "checks":checks, "passed":failures.is_empty(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
