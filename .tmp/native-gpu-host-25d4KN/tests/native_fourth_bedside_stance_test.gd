extends "res://tests/native_route_test.gd"
## The fourth garden's displaced bed must not collapse a follower onto its leader.
var output := ""
var observations: Array = []

func _separation(label: String) -> void:
	var luvie: CharacterBody3D = app.view.get_actor_body("luvie")
	var buddy: CharacterBody3D = app.view.get_actor_body("buddy")
	var distance := Vector2(luvie.position.x-buddy.position.x,luvie.position.z-buddy.position.z).length()
	var luvie_shape: CapsuleShape3D = luvie.get_node("Collision").shape
	var buddy_shape: CapsuleShape3D = buddy.get_node("Collision").shape
	_check(distance > luvie_shape.radius+buddy_shape.radius+.08,label+" keeps real bodies separated")
	for who: String in ["luvie","buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		_check(app.view.prop_physical_point_clear(body.position,who),label+" clears hard planter for "+who)
		_check(absf(body.position.y-app.view.support_height(body.position,str(app.session.world.state.actors[who]),who))<.02,label+" keeps real floor contact for "+who)
	observations.append({"label":label,"distance":distance,"snapshot":app.session.world.snapshot(),"native":app.native_movement.qa_state()})
	if not output.is_empty():
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(label+".png"))

func _run() -> void:
	root.unfocusable=true
	root.size=Vector2i(1841,907)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-output="): output=arg.trim_prefix("--capture-output=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	_setup()
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var home := {}
	for entry: Dictionary in reference.cases:
		if str(entry.name)!="authored/1-4":continue
		for step: Dictionary in entry.steps:
			if str(step.command.get("value",""))=="use:home":home=step.snapshot.duplicate(true);break
		break
	for leader: String in ["buddy","luvie"]:
		var initial: Dictionary=home.duplicate(true)
		initial.active=leader;initial.follow=true
		initial.actors={"luvie":"f:-4:0","buddy":"f:-4:0"};initial.erase("runtime")
		app.repository.data.mainline.runs["1-4"]=initial
		app._enter_level("1-4");await _tick();await _tick()
		_check(await _walk_to("f:-8:1",leader+" leads beside visible bed"),leader+" reaches real bedside")
		await _separation("01-"+leader+"-led")
		app._on_command("switch");_check(await _drain(),"switch at bedside settles")
		await _separation("02-switched-from-"+leader)
	# Replay actual baseline runtime poses: only 3.3cm apart, same legal support.
	var legacy: Dictionary=home.duplicate(true)
	legacy.active="buddy";legacy.follow=true;legacy.actors={"luvie":"f:-8:1","buddy":"f:-8:1"}
	legacy.runtime={"version":1,"poses":{"buddy":{"support":"f:-8:1","offset":[.0016,.0009,-.3502],"facing":"left"},"luvie":{"support":"f:-8:1","offset":[.0117,.0008,-.3185],"facing":"left"}}}
	app.repository.data.mainline.runs["1-4"]=legacy
	app._enter_level("1-4");await _tick();await _tick()
	var before: Vector3=app.view.get_actor_body("luvie").position
	_check(Vector2(before.x+7.9883,before.z-.6815).length()<.12,"old save keeps original physical pose rather than teleporting to a new endpoint")
	_check(await _drain(),"legacy follower walks clear on the existing support")
	_check(app.view.get_actor_body("luvie").position.distance_to(before)>.1,"legacy follower actually moves out of overlap")
	_check(app.session.world.flag("latch") and app.session.world.flag("home") and not app.session.world.state.completed,"legacy migration preserves puzzle progress")
	await _separation("03-legacy-runtime-settled")
	app._on_command("switch");await _drain()
	_check(not app.session.world.state.follow,"switch keeps original separate-waiting semantics")
	app._on_command("follow");_check(await _drain(),"explicit original follow resumes after switching")
	app._on_command("approach:core")
	_check(await _drain(),"original real core approach settles after switching to luvie")
	_check(app.session.world.near("f:-9:0") and app.session.world.ready(),"original range and reunion permit cultivation")
	await _separation("04-original-core-ready")
	app._on_command("repair");_check(await _drain(),"explicit original repair settles")
	_check(bool(app.session.world.state.completed),"legal together planting still completes")
	var directory := output if not output.is_empty() else ProjectSettings.globalize_path("res://../docs/qa-godot-native/fourth-bedside-stance-20261117")
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"suite":"native-fourth-bedside-stance","checks":checks,"passed":failures.is_empty(),"failures":failures,"observations":observations},"  "))
	print(JSON.stringify({"suite":"native-fourth-bedside-stance","checks":checks,"passed":failures.is_empty(),"failures":failures}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
