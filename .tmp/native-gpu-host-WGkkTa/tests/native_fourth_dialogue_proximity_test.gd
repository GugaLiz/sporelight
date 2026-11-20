extends "res://tests/native_route_test.gd"
func _check_stable_header(dimensions: Vector2i)->void:
	root.size=dimensions;app.hud._layout()
	for frame in 6:await _tick()
	var resize_count: Array[int]=[0]
	var count_resize: Callable=func()->void: resize_count[0]+=1
	app.hud._heading.resized.connect(count_resize)
	var header: Rect2=app.hud._heading.get_global_rect()
	for frame in 120:await _tick()
	app.hud._heading.resized.disconnect(count_resize)
	_check(resize_count[0]==0 and header==app.hud._heading.get_global_rect(),str(dimensions)+" real application header stays stable for 120 frames")
	_check(app.hud._journey_steps.visible==(dimensions.y>420),str(dimensions)+" real application retains final stage visibility")

func _run()->void:
	_setup()
	app.hud.set_dialogue_proximity(Callable(app.view,"mole_dialogue_near_actor"))
	app._enter_level("1-4");await _tick();await _tick()
	_check(app.view.mole_dialogue_near_actor(),"original heavy-lever stance is within the resident's real home visit")
	app.hud._message_remaining=0;app.hud._process(.1)
	_check(app.hud._mole_message_active,"real proximity starts the original resident greeting")
	app._on_command("use:hold");_check(await _drain(),"hold the original heavy lever")
	_check(app.view.mole_dialogue_near_actor(),"approved hold stance remains near the resident")
	app.hud._message_remaining=0;app.hud._process(.1)
	_check(app.hud._mole_message_active and app.hud._mole_conversation.last_stage=="help","actual hold changes the resident's contextual line")
	var before:Dictionary=app.session.world.snapshot()
	app.hud._process(.2)
	_check(app.session.world.snapshot()==before,"dialogue timing never writes puzzle flags or progress")
	# The lower courtyard is on the same level but outside both home visit
	# proximity and the actual NPC radius; changing actor tests the live callback.
	app._on_command("switch");_check(await _drain(),"select distant partner")
	_check(not app.view.mole_dialogue_near_actor(),"distant partner does not inherit another actor's proximity")
	app.hud._process(.1)
	_check(not app.hud._mole_message_active,"leaving the resident hides its speech")
	app._message(app._entry_message());app._sync_hud()
	_check(app.hud._message.text=="当前目标：固定归途","live application default message follows the actual 1-4 milestone")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390),Vector2i(568,320)]:
		await _check_stable_header(dimensions)
	print(JSON.stringify({"suite":"native-fourth-dialogue-proximity","passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"real native actor/NPC positions, live hold/switch, contextual speech and unchanged progress"}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
