extends "res://tests/native_movement_test.gd"
## Three grown segments must leave a real gap for both detours, including
## held and diagonal input. The fourth must be an actual supported tile.

func _run() -> void:
	for route: Array in [["up", "right", "right", "down"], ["down", "right", "right", "up"]]:
		await _setup("1-2")
		movement.request_path(session.world.path_to("f:1:1"))
		await _frames(60)
		_check(session.world.path_to("f:4:1").is_empty(), "unplanted bank is unreachable")
		for index in range(3):
			await _action("grow:root:" + str(route[index]))
			_check(session.world.path_to("f:4:1").is_empty(), "bank is unreachable after segment " + str(index + 1))
		var tip := str(session.world.state.growth.root.back())
		var gap_key := KEY_S if route[0] == "up" else KEY_W
		_check(not stage._surfaces.has("f:3:1") and not stage._surfaces.has("f:4:2"), "overlapping landing and side shortcut have no geometry")
		_check(not stage._surfaces.has("g:root:3:1"), "fourth root has no premature support")
		for keys: Array in [[KEY_D], [gap_key], [KEY_D, gap_key]]:
			movement.request_path(session.world.path_to(tip))
			await _frames(130)
			_check(session.world.state.actors.luvie == tip, "reach third segment through real movement")
			for code: int in keys: _key(code, true)
			await _frames(65)
			for code: int in keys: _key(code, false)
			await _frames(4)
			var body: CharacterBody3D = stage.get_actor_body("luvie")
			_check(session.world.state.actors.luvie == tip, "held and diagonal input cannot enter bank or unplanted fourth tile")
			_check(body.position.x < 3.5 and (body.position.z < 0.5 if route[0] == "up" else body.position.z > 1.5), "whole body remains on third root side of the gap")
		movement.request_path(session.world.path_to("f:1:1"))
		await _frames(150)
		await _action("grow:root:" + str(route[3]))
		_check(stage._surfaces.has("g:root:3:1"), "fourth segment builds real support")
		_check(not session.world.path_to("f:4:1").is_empty(), "fourth segment joins the bank")
		movement.request_path(session.world.path_to("f:4:1"))
		await _frames(220)
		_check(session.world.state.actors.luvie == "f:4:1", "completed detour physically reaches the flowerbed")
		movement.request_path(session.world.path_to("f:5:2"))
		await _frames(120)
		_check(session.world.state.actors.luvie == "f:5:2", "original optional observation remains reachable")
	_check(maximum_floor_error < 0.20, "physical contact remains within authored stair tolerance")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "second-garden-fourth-link", "checks": checks, "passed": failures.is_empty(), "failures": failures, "floorSamples": floor_samples, "maxContactError": maximum_floor_error}))
	quit(0 if failures.is_empty() else 1)
