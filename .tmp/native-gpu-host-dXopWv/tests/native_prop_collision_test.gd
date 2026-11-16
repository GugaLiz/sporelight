extends "res://tests/native_route_test.gd"
## Real capsule sweeps into the visible 1-4 stone planter, not a coordinate-only
## prop assertion. The original puzzle fixture remains authoritative.
var peak_penetration := 0.0

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	app.input_router.handle_key(event)

func _base() -> Rect2:
	var node: Node3D = app.view._props_nodes["mark:core"]
	for child in node.get_children():
		if not child.has_meta("core_planter"): continue
		var at: Vector3 = node.to_global(child.get_meta("ground_footprint_center"))
		var span: Vector2 = child.get_meta("ground_footprint_span")
		return Rect2(Vector2(at.x,at.z)-span*.5,span)
	return Rect2()

func _penetration(body: CharacterBody3D, rect: Rect2) -> float:
	var at := Vector2(body.position.x,body.position.z)
	var shape: CapsuleShape3D = body.get_node("Collision").shape
	return maxf(0,shape.radius-at.distance_to(at.clamp(rect.position,rect.end)))

func _run() -> void:
	_setup()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary
	for entry: Dictionary in reference.cases:
		if str(entry.name)=="authored/1-4": fixture=entry;break
	var saved: Dictionary = fixture.steps[-2].snapshot.duplicate(true)
	saved.actors={"luvie":"f:-8:1","buddy":"f:-9:0"}
	saved.active="luvie";saved.follow=false;saved.erase("runtime")
	app.repository.data.mainline.runs["1-4"]=saved
	app._enter_level("1-4");await _tick();await _tick()
	var hero: CharacterBody3D = app.view.get_actor_body("luvie")
	var rect := _base()
	var start := hero.position
	_key(KEY_UP,true)
	for frame in range(40):
		await _tick()
		peak_penetration=maxf(peak_penetration,_penetration(hero,rect))
	_key(KEY_UP,false);await _tick()
	_check(hero.position.distance_to(start)>.2,"real input approaches the planter")
	_check(peak_penetration<.004,"capsule never enters the visible stone-base footprint")
	_check(absf(hero.position.y-app.view.support_height(hero.position,str(app.session.world.state.actors.luvie)))<.03,"the planter is not an extra walkable platform")
	_key(KEY_LEFT,true)
	for frame in range(18): await _tick()
	_key(KEY_LEFT,false);await _tick()
	_check(_penetration(hero,rect)<.004,"sliding along the stone edge does not enter its base")
	_check(await _walk_to("f:-9:0","walk around stone base"),"original care support remains reachable")
	_check(_penetration(hero,rect)<.004,"care stance remains outside the stone base")
	app._go("f:-8:-1")
	_check(await _drain(),"a click into the stone does not leave an endless walking loop")
	_check(_penetration(hero,rect)<.004,"click input cannot walk through the stone")
	# A pre-fix save may name a walkable rule tile whose centre is now occupied
	# by the visible stone. Recover position without resetting puzzle progress.
	saved.actors.luvie="f:-8:-1"
	saved.runtime={"version":1,"poses":{"luvie":{"support":"f:-8:-1","offset":[0,0,0],"facing":"front"}}}
	app.repository.data.mainline.runs["1-4"]=saved
	app._enter_level("1-4");await _tick();await _tick()
	hero=app.view.get_actor_body("luvie")
	_check(_penetration(hero,_base())<.004,"old inside-base pose is restored to a legal nearby landing")
	_check(app.session.world.state.flags==saved.flags and app.session.world.state.collected==saved.collected and not app.session.world.state.completed,"recovering an invalid pose preserves puzzle progress")
	app.repository.data.mainline.runs.erase("1-4")
	await _replay("1-4",fixture.steps,fixture.initial.snapshot)
	await _pond(reference)
	print(JSON.stringify({"suite":"native-prop-collision","checks":checks,"passed":failures.is_empty(),"failures":failures,"peakPenetration":peak_penetration,"routes":routes,"samples":samples}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

func _pond(reference: Dictionary) -> void:
	var fixture: Dictionary
	for entry: Dictionary in reference.cases:
		if str(entry.name)=="authored/2-2": fixture=entry;break
	# Restore pre-fix centre poses, then press physically into each hard base.
	for target: String in ["item:mirrorA","item:mirrorB","mark:source","OriginalScenery_04_stone_lantern","OriginalScenery_06_river_rock"]:
		var saved: Dictionary = fixture.initial.snapshot.duplicate(true)
		var support: String = {"item:mirrorA":"f:1:1","item:mirrorB":"f:4:3","mark:source":"f:0:1","OriginalScenery_04_stone_lantern":"f:3:1","OriginalScenery_06_river_rock":"f:5:1"}[target]
		saved.actors={"luvie":support,"buddy":"f:0:2"};saved.follow=false
		saved.runtime={"version":1,"poses":{"luvie":{"support":support,"offset":[0,0,0],"facing":"front"}}}
		app.repository.data.mainline.runs["2-2"]=saved
		app._enter_level("2-2");await _tick();await _tick()
		var hero: CharacterBody3D=app.view.get_actor_body("luvie")
		var entry: Dictionary={}
		for obstacle: Dictionary in app.view._prop_obstacles:
			if str(obstacle.id)==target: entry=obstacle;break
		_check(not entry.is_empty(),target+" has a real local hard-base obstacle")
		if entry.is_empty():continue
		var rect: Rect2=entry.rect
		_check(_penetration(hero,rect)<.004,target+" restores outside hard base")
		var direction: Vector2=rect.get_center()-Vector2(hero.position.x,hero.position.z)
		var horizontal: int=KEY_RIGHT if direction.x>0 else KEY_LEFT
		var vertical: int=KEY_DOWN if direction.y>0 else KEY_UP
		_key(horizontal,true);_key(vertical,true)
		for frame in range(22):
			await _tick()
			if _penetration(hero,rect)>=.004 and frame==10: print("PROP PENETRATION ",target," at=",hero.position," rect=",rect," support=",app.session.world.state.actors.luvie)
			_check(_penetration(hero,rect)<.004,target+" continuous physical input stays outside base")
		_key(horizontal,false);_key(vertical,false);await _tick()
	# Ordinary fixed tiles remain legal drop destinations. Walk aside first.
	var saved: Dictionary=fixture.steps[5].snapshot.duplicate(true)
	saved.actors={"luvie":"f:3:3","buddy":"f:3:3"};saved.follow=false
	saved.runtime={"version":1,"poses":{"luvie":{"support":"f:3:3","offset":[0,0,0],"facing":"front"},"buddy":{"support":"f:3:3","offset":[0,0,0],"facing":"front"}}}
	app.repository.data.mainline.runs["2-2"]=saved
	app._enter_level("2-2");await _tick();await _tick()
	app._on_command("drop:mirrorB:f:3:3")
	_key(KEY_LEFT,true);await _tick();_key(KEY_LEFT,false);await _tick()
	_check(app._pending_prop_drop.is_empty() and str(app.session.world.state.items.mirrorB.get("holder",""))=="luvie","manual input cancels pending placement without losing mirror")
	app.repository.data.mainline.runs["2-2"]=saved
	app._enter_level("2-2");await _tick();await _tick()
	var hero: CharacterBody3D=app.view.get_actor_body("luvie")
	var before:=hero.position
	_check(app._prop_stance_reached(hero,hero.position+Vector3(.054,.018,0)),"stance arrival shares motor horizontal tolerance with separate contact-height clearance")
	_check(not app._prop_stance_reached(hero,hero.position+Vector3(0,.031,0)),"stance arrival still rejects excessive vertical separation")
	app._on_command("drop:mirrorB:f:3:3")
	_check(str(app.session.world.state.items.mirrorB.get("holder",""))=="luvie","drop waits while actor physically clears new base")
	_check(await _drain(),"ordinary non-slot drop settles")
	print("DROP RESULT ",JSON.stringify(app.native_movement.qa_state())," status=",app.status_message," item=",app.session.world.state.items.mirrorB)
	_check(str(app.session.world.state.items.mirrorB.get("tile",""))=="f:3:3" and str(app.session.world.state.items.mirrorB.get("holder","")).is_empty(),"original non-slot destination is preserved")
	_check(hero.position.distance_to(before)>.25,"drop stance is reached by real movement")
	for obstacle: Dictionary in app.view._prop_obstacles:
		_check(_penetration(hero,obstacle.rect)<.004,"drop does not generate hard base inside actor")
		_check(_penetration(app.view.get_actor_body("buddy"),obstacle.rect)<.004,"drop also clears waiting partner before the base appears")
	app._on_command("undo");_check(await _drain(),"undo ordinary placement")
	_check(str(app.session.world.state.items.mirrorB.get("holder",""))=="luvie" and not app.view._props_nodes.has("item:mirrorB"),"undo restores carried mirror and removes floor obstacle")
	app._on_command("drop:mirrorB:f:3:3");_check(await _drain(),"repeat ordinary placement after undo")
	app._on_command("take:mirrorB");_check(await _drain(),"pick mirror back up")
	_check(not app.view._props_nodes.has("item:mirrorB"),"carried mirror leaves no floor obstacle")
	# The nearby slot can be different from the actor support; do not rewrite it.
	saved=fixture.steps[5].snapshot.duplicate(true)
	saved.actors={"luvie":"f:0:0","buddy":"f:0:2"};saved.follow=false;saved.erase("runtime")
	app.repository.data.mainline.runs["2-2"]=saved
	app._enter_level("2-2");await _tick();await _tick()
	app._on_command("drop:mirrorB:f:1:0");_check(await _drain(),"drop into a neighbouring legal slot")
	_check(str(app.session.world.state.actors.luvie)=="f:0:0" and str(app.session.world.state.items.mirrorB.tile)=="f:1:0","nearby drop preserves distinct actor support and mirror target")
	app.repository.data.mainline.runs.erase("2-2")
	await _replay("2-2",fixture.steps,fixture.initial.snapshot)
	var solved: Dictionary=fixture.steps[-2].snapshot.duplicate(true)
	solved.actors={"luvie":"f:1:0","buddy":"f:0:2"};solved.follow=false;solved.erase("runtime")
	var world: RefCounted=app.session.world.fork(solved)
	_check(world.beam_hits(4,0),"authored reflection still reaches receiver")
	_check(world.act("angle:mirrorB").ok and not world.beam_hits(4,0),"wrong mirror angle removes live receiver light")
	world=app.session.world.fork(solved)
	_check(world.act("take:mirrorB").ok and not world.beam_hits(4,0),"carried mirror no longer reflects light")
	solved.actors.luvie="f:1:1";world=app.session.world.fork(solved)
	_check(world.act("angle:mirrorA").ok and not world.beam_hits(4,0),"turning A back closes receiver light")
	_check(not world.act("take:mirrorA").ok,"fixed mirror A still cannot be carried")
	# Isolated ray unit probe, not an attainable gameplay preparation: remove
	# reflectors so the original integer cursor meets the JSON float wall.
	world.state.items={}
	var ray: Array=world.rays()
	_check(not ray.is_empty() and int(ray[-1].x)==2 and int(ray[-1].z)==1,"isolated direct-light probe stops at the unchanged numeric wall")
	if not bool(app.session.world.state.completed):
		print("POND END ",JSON.stringify(app.native_movement.qa_state())," status=",app.status_message," waiting=",app.waiting_repair)
		print("POND FOLLOW ",app.native_movement._prop_path(str(app.session.world.state.actors.luvie),"buddy"))
		var buddy: CharacterBody3D=app.view.get_actor_body("buddy")
		for index in range(buddy.get_slide_collision_count()):
			var collision:=buddy.get_slide_collision(index)
			print("BUDDY COLLISION ",collision.get_position()," normal=",collision.get_normal()," collider=",collision.get_collider().get_path())
		print("BUDDY DIRECT ",app.view.prop_segment_clear(buddy.position,Vector3(3,0,.44),"buddy")," EDGES ",app.native_movement._neighbors(str(app.session.world.state.actors.buddy),"buddy"))
		for tile: Dictionary in app.session.world.tiles():
			print("POND WAYPOINT ",tile.id," ",app.native_movement._prop_waypoint(tile,"buddy"))
