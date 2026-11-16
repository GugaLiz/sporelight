extends "res://tests/native_movement_test.gd"

func _run() -> void:
	await _setup("1-2")
	var obstacle: Node = stage._props.get_node_or_null("IsolatedRockSpire")
	_check(obstacle != null, "rock is an isolated unpaved outcrop, not a bridge pedestal")
	if obstacle != null:
		_check(obstacle.find_children("*", "CollisionObject3D", true, false).is_empty(), "decorative rock never adds support")
	_check(session.world.point_for("f:2:1").is_empty(), "blocked rock cell remains absent from walkable tiles")
	movement.request_path(session.world.path_to("f:1:1"))
	await _frames(55)
	for direction: String in ["up","right","right","down"]:
		await _action("grow:root:" + direction)
	movement.request_path(session.world.path_to("g:root:3:1"))
	await _frames(170)
	var hero: CharacterBody3D = stage.get_actor_body("luvie")
	for offset: float in [-0.30,-0.22,0.22,0.30]:
		hero.position.z = 1.0 + offset
		_key(KEY_D,true)
		await _frames(34)
		_key(KEY_D,false)
		await _frames(4)
		_check(session.world.state.actors.luvie == "f:4:1", "off-center entrance reaches flowerbed landing")
		var stopped := hero.position
		await _frames(8)
		_check(hero.position.distance_to(stopped) < 0.025, "stopping on arrival flight stays stable")
		_key(KEY_A,true)
		await _frames(34)
		_key(KEY_A,false)
		await _frames(4)
		_check(session.world.state.actors.luvie == "g:root:3:1", "off-center entrance descends to the required fourth root")
		movement.request_path(["g:root:3:1"])
		await _frames(30)
	for lane in [4,5]:
		movement.request_path(session.world.path_to("f:%d:1" % lane))
		await _frames(100)
		for offset: float in [-0.30,-0.22,0.22,0.30]:
			hero.position.x = stage.physical_position(Vector3(lane + offset,0,0)).x
			hero.position.y = stage.support_height(hero.position, "f:%d:1" % lane) + 0.018
			_key(KEY_W,true)
			await _frames(34)
			_key(KEY_W,false)
			await _frames(4)
			_check(session.world.state.actors.luvie == "f:%d:0" % lane, "rear stairs ascend in both lanes")
			_key(KEY_S,true)
			await _frames(34)
			_key(KEY_S,false)
			await _frames(4)
			_check(session.world.state.actors.luvie == "f:%d:1" % lane, "rear stairs descend in both lanes")
			movement.request_path(["f:%d:1" % lane])
			await _frames(30)
	for who: String in ["luvie","buddy"]:
		stage.update_actor_visual(who,Vector3.ZERO)
		_check(stage.get_actor_body(who).get_node("Visual/Art").billboard == BaseMaterial3D.BILLBOARD_DISABLED, "second garden uses vertical actor depth")
	_check(maximum_floor_error < 0.20,"contact stays within step tolerance: " + str(maximum_floor_error))
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"second-garden-structure", "checks":checks,"passed":failures.is_empty(),"failures":failures,"maxContactError":maximum_floor_error,"worstContact":worst_contact}))
	quit(0 if failures.is_empty() else 1)
