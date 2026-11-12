extends "res://tests/native_route_test.gd"

func _run() -> void:
	_setup()
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary
	for entry: Dictionary in reference.cases:
		if str(entry.name)=="authored/2-2":fixture=entry;break
	var saved: Dictionary=fixture.steps[18].snapshot.duplicate(true)
	saved.actors={"luvie":"f:3:0","buddy":"f:3:1"};saved.follow=true
	saved.runtime={"version":1,"poses":{"luvie":{"support":"f:3:0","offset":[.032,0,.441],"facing":"front"},"buddy":{"support":"f:3:1","offset":[-.082,0,-.266],"facing":"front"}}}
	app.repository.data.mainline.runs["2-2"]=saved
	app._enter_level("2-2")
	for frame in range(80):
		await _tick()
	_check(str(app.session.world.state.actors.buddy)=="f:3:0","partner naturally crosses the stone-front approach")
	print(JSON.stringify({"suite":"native-prop-follow","passed":failures.is_empty(),"checks":checks,"failures":failures}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
