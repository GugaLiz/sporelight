extends "res://tests/native_movement_test.gd"

## Real capsule travel through all three lanes, including off-center stops and
## reversals. Surface rays and unchanged rule fixtures are checked separately.
func _run() -> void:
	await _setup("1-1")
	var foundations := {}
	for id: String in stage._surfaces:
		foundations[id] = stage._surfaces[id].geometry_rebuilds
	await _action("grow:root:right")
	for id: String in foundations:
		_check(stage._surfaces[id].geometry_rebuilds == foundations[id], "sowing preserves fixed foundation " + id)
	var hero: CharacterBody3D = stage.get_actor_body("luvie")
	for lane in [2, 3, 4]:
		movement.request_path(session.world.path_to("f:%d:0" % lane))
		await _frames(150)
		_check(session.world.state.actors.luvie == "f:%d:0" % lane, "approach terrace lane %d" % lane)
		for offset: float in [-0.22, 0.22]:
			# Set a legitimate starting stance on this already reached floor;
			# every ascent/descent thereafter is actual held-key motor input.
			hero.position.x = stage.physical_position(Vector3(lane + offset, 0, 0)).x
			_key(KEY_W, true)
			await _frames(8)
			_key(KEY_W, false)
			await _frames(4)
			var stopped := hero.position
			await _frames(8)
			_check(Vector2(hero.position.x, hero.position.z).distance_to(Vector2(stopped.x, stopped.z)) < 0.015, "off-center stop remains still")
			_key(KEY_W, true)
			await _frames(60)
			_key(KEY_W, false)
			await _frames(4)
			_check(session.world.state.actors.luvie == "f:%d:-2" % lane, "off-center ascent reaches the extended rear edge in lane %d at %.2f, actual %s" % [lane, offset, str(hero.position)])
			_key(KEY_S, true)
			await _frames(60)
			_key(KEY_S, false)
			await _frames(4)
			_check(session.world.state.actors.luvie == "f:%d:0" % lane, "off-center descent lane %d" % lane)
			movement.request_path(["f:%d:0" % lane])
			await _frames(25)
		movement.request_path(session.world.path_to("f:%d:-2" % lane))
		await _frames(150)
		_check(session.world.state.actors.luvie == "f:%d:-2" % lane, "extended terrace is reachable in lane %d" % lane)
		_check(absf(hero.position.y - 1.30) < 0.02, "extended terrace is level with the stair landing")
		movement.capture()
		var restored := Session.new("1-1", session.world.snapshot())
		_check(restored.world.state.actors.luvie == "f:%d:-2" % lane, "save restores the new upper terrace support")
	for direction: String in ["right", "down"]:
		for offset: float in [-0.22, 0.22]:
			await _setup("1-1")
			await _action("grow:root:" + direction)
			hero = stage.get_actor_body("luvie")
			if direction == "right": hero.position.z = offset
			else: hero.position.x = offset
			_key(KEY_D if direction == "right" else KEY_S, true)
			await _frames(65)
			_key(KEY_D if direction == "right" else KEY_S, false)
			await _frames(4)
			var reached: Dictionary = session.world.point()
			_check(float(reached.x) >= 2.0 if direction == "right" else float(reached.z) >= 2.0, "off-center bridge reaches island " + direction + " " + str(offset) + " actual " + str(hero.position))
			_key(KEY_A if direction == "right" else KEY_W, true)
			await _frames(85)
			_key(KEY_A if direction == "right" else KEY_W, false)
			await _frames(4)
			_check(float(session.world.point().h) == 0.0, "off-center bridge returns " + direction + " " + str(offset))
	_check(maximum_floor_error < 0.20, "capsule remains in contact: %.4f" % maximum_floor_error)
	print(JSON.stringify({"suite": "first-garden-structure", "checks": checks, "passed": failures.is_empty(), "maxContactError": maximum_floor_error, "worstContact": worst_contact, "failures": failures}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
