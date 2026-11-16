extends "res://tests/native_route_test.gd"
## Real 30 Hz physics: a short remaining corner segment must not be skipped
## or overshot into the stone, even though the next frame is twice as long.
var _stride_failures: Dictionary = {}

func _tick() -> void:
	await physics_frame
	app._process(1.0/30.0)
	app._physics_process(1.0/30.0)
	for who: String in ["luvie","buddy"]:
		var body: CharacterBody3D=app.view.get_actor_body(who)
		var key: String=str(app.session.world.level.id)+"/"+who
		if not app.view.prop_physical_point_clear(body.position,who) and not _stride_failures.has(key):
			_stride_failures[key]=true
			_check(false,key+" 30 Hz movement penetrated a hard base")

func _run() -> void:
	Engine.physics_ticks_per_second=30
	_setup()
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json")).cases
	var cases := {"1-4":17,"3-2":4,"3-4":37}
	for fixture: Dictionary in fixtures:
		var id: String=str(fixture.get("levelId",""))
		if not cases.has(id) or str(fixture.name)!="authored/"+id: continue
		var step: int=cases[id]
		app.repository.data.mainline.runs[id]=fixture.steps[step-1].snapshot.duplicate(true)
		app._enter_level(id)
		await _tick()
		_check(await _walk_to(str(fixture.steps[step].command.value),id+" 30 Hz corner"),id+" 30 Hz local detour reaches its original support")
	print(JSON.stringify({"suite":"native-prop-corner-stride","checks":checks,"passed":failures.is_empty(),"failures":failures}))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
