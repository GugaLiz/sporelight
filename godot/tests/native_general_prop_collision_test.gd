extends "res://tests/native_route_test.gd"
## Scene-wide audit of actual hard bases. Reference routes are run separately;
## these assertions cover restored stance safety, layer filtering and collider
## ownership without treating a flower crown or doorway as one solid box.
const Obstacles = preload("res://presentation/native/native_prop_obstacles.gd")
var inventory: Array = []
var sweep_inventory: Array = []

func _completed_core_migration() -> void:
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json")).cases
	for fixture: Dictionary in fixtures:
		if str(fixture.name)!="authored/3-4": continue
		var saved: Dictionary=fixture.steps.back().snapshot.duplicate(true)
		var normalized: RefCounted=load("res://application/game_session.gd").new("3-4",saved)
		var expected: Dictionary=normalized.world.snapshot()
		app.repository.data.mainline.memories["3-4"]=saved
		app._enter_level("3-4",true)
		await _tick()
		for who: String in ["luvie","buddy"]:
			var body: CharacterBody3D=app.view.get_actor_body(who)
			_check(str(app.session.world.state.actors[who])=="f:-3:0","3-4 old occupied core recovers to authored legal approach for "+who)
			_check(app.view.prop_physical_point_clear(body.position,who),"3-4 recovered "+who+" clears complete stone base")
		var restored: Dictionary=app.session.world.snapshot()
		for field: String in ["completed","growth","turns","flags","items","collected","follow"]:
			_check(restored[field]==expected[field],"3-4 occupied-core migration preserves "+field)
		var hero: CharacterBody3D=app.view.get_actor_body("luvie")
		var before: Vector3=hero.position
		app.native_movement.capture()
		app.native_movement.restore()
		_check(hero.position.distance_to(before)<.003,"3-4 migrated valid manual pose remains authoritative")

func _sweep_bases(id: String, entries: Array) -> void:
	for entry: Dictionary in entries:
		var rect: Rect2 = entry.rect
		for who: String in ["luvie","buddy"]:
			var body: CharacterBody3D = app.view.get_actor_body(who)
			var capsule: CapsuleShape3D = body.get_node("Collision").shape
			var tested := false
			for axis: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				var at: Vector2 = rect.get_center()+axis*(rect.size*.5+Vector2.ONE*(capsule.radius+.06))
				var floor_point := Vector3(at.x,float(entry.floor),at.y)
				var logical: Vector3 = app.view.logical_position(floor_point)
				var supported := false
				for tile: Dictionary in app.view._tiles:
					if absf(logical.x-float(tile.x))>.495 or absf(logical.z-float(tile.z))>.495: continue
					var safe: Dictionary = app.view.prop_waypoint(tile,who,floor_point)
					if not safe.is_empty() and (safe.point as Vector3).distance_to(floor_point)<.001: supported=true;break
				if not supported: continue
				var transform: Transform3D = body.global_transform
				transform.origin = floor_point+Vector3.UP*.018
				var collision := KinematicCollision3D.new()
				var blocked: bool = body.test_move(transform,Vector3(-axis.x,0,-axis.y)*.4,collision)
				_check(blocked,id+"/"+str(entry.id)+"/"+who+" actual capsule sweep cannot enter hard base")
				if blocked:
					var collider: Node = collision.get_collider() as Node
					_check(collider!=null and str(collider.get_meta("prop_obstacle_id",""))==str(entry.id),id+"/"+str(entry.id)+" owns physical blocking shape")
				tested=true
				break
			sweep_inventory.append({"level":id,"base":entry.id,"actor":who,"legal_approach_swept":tested})

func _run() -> void:
	_setup()
	var raised := [{"id":"raised", "rect":Rect2(-.2,-.2,.4,.4), "floor":.7, "top":1.11, "height_scoped":true}]
	_check(Obstacles.clear(Vector3.ZERO,.15,raised,.56),"short capsule clears an upper base in another layer")
	_check(not Obstacles.clear(Vector3.ZERO,.18,raised,.8),"tall capsule cannot enter the same upper base")
	_check(Obstacles.segment_clear(Vector3(-1,0,0),Vector3(1,0,0),.15,raised,.56),"short actor route stays open below an upper base")
	_check(not Obstacles.segment_clear(Vector3(-1,0,0),Vector3(1,0,0),.18,raised,.8),"tall actor segment keeps actual head clearance")
	for level: Dictionary in app.levels:
		var id: String = str(level.id)
		app._enter_level(id)
		await _tick()
		await _tick()
		var entries: Array = app.view._prop_obstacles
		var names: Array = []
		for entry: Dictionary in entries:
			names.append(str(entry.id))
			_check(entry.rect.size.x>0 and entry.rect.size.y>0 and float(entry.top)>float(entry.floor),id+"/"+str(entry.id)+" has a complete nonempty base")
		_check(entries.is_empty() if id=="1-1" else not entries.is_empty(),id+" retains first-garden exception or actual hard-base coverage")
		for who: String in ["luvie","buddy"]:
			var body: CharacterBody3D = app.view.get_actor_body(who)
			var capsule: CapsuleShape3D = body.get_node("Collision").shape
			_check(Obstacles.physical_clear(body.position,capsule.radius,entries,capsule.height),id+"/"+who+" starts outside every hard base")
			var at: Vector3 = body.position
			var support: String = str(app.session.world.state.actors[who])
			app.native_movement.capture()
			app.native_movement.restore()
			_check(body.position.distance_to(at)<.003 and str(app.session.world.state.actors[who])==support,id+"/"+who+" valid pose survives restore unchanged")
		_sweep_bases(id,entries)
		inventory.append({"level":id,"bases":names})
	await _completed_core_migration()
	print(JSON.stringify({"suite":"native-general-prop-collision","checks":checks,"passed":failures.is_empty(),"failures":failures,"inventory":inventory,"sweeps":sweep_inventory}))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
