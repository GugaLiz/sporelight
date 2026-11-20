extends "res://tests/native_route_test.gd"

var diagnostic_output := "G:/works/liuli/sporelight/docs/qa-godot-native/fourth-overlap-diagnostic-20261117"
var observations: Array = []

func _observe(label: String) -> void:
	var row := {"label":label,"world":app.session.world.snapshot(),"context":app._native_interaction_context(),"native":app.native_movement.qa_state(),"actors":[]}
	for who: String in ["luvie","buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		var sprite: AnimatedSprite3D = body.get_node("Visual/Art")
		var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
		row.actors.append({"who":who,"body":str(body.position),"clip":str(sprite.animation),"frame":sprite.frame,"frameTexture":texture.resource_path,"spriteChildren":body.get_node("Visual").get_child_count(),"projection":str(app.view._occlusion_projection(sprite,texture).rect),"rest":str(app.view.actor_rest_position(app.session.world.point_for(str(app.session.world.state.actors[who])),who))})
	observations.append(row)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(diagnostic_output.path_join(label+".png"))

func _run() -> void:
	root.size = Vector2i(1841,907)
	DirAccess.make_dir_recursive_absolute(diagnostic_output)
	_setup()
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var state := {}
	for entry: Dictionary in ref.cases:
		if str(entry.name) != "authored/1-4": continue
		for step: Dictionary in entry.steps:
			if str(step.command.get("value","")) == "use:home": state=step.snapshot.duplicate(true);break
		break
	state.active="buddy";state.follow=true
	state.actors={"luvie":"f:-4:0","buddy":"f:-4:0"}
	state.erase("runtime")
	app.repository.data.mainline.runs["1-4"]=state
	app._enter_level("1-4")
	await _tick();await _tick()
	await _observe("01-at-home-buddy-active")
	_check(await _walk_to("f:-8:1","buddy leads to flower side"),"buddy reaches visible bedside")
	await _observe("02-buddy-bedside-settled")
	for unused in range(60): await _tick()
	await _observe("03-buddy-bedside-idle")
	app._on_command("switch")
	await _drain()
	await _observe("04-switched-to-luvie")
	var candidates: Array = []
	var tile: Dictionary = app.session.world.point_for("f:-8:1")
	var center: Vector3 = app.view.tile_position(tile)
	var current: Vector3 = app.view.get_actor_body("luvie").position
	var other: Vector3 = app.view.get_actor_body("buddy").position
	for x: float in [-.44,-.22,0,.22,.44]:
		for z: float in [-.44,-.22,0,.22,.44]:
			var point := center+Vector3(x,0,z)
			var local: Dictionary = app.native_movement._validated_local_target("luvie",point)
			if not local.is_empty() and app.view.prop_point_clear(point,"luvie") and app.view.prop_segment_clear(current,point,"luvie"):
				candidates.append({"point":str(point),"distanceToBuddy":Vector2(point.x-other.x,point.z-other.z).length()})
	var output := FileAccess.open(diagnostic_output.path_join("diagnostic.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"sameSupportCandidates":candidates},"  "))
	print(JSON.stringify({"suite":"fourth-overlap-diagnostic","checks":checks,"failures":failures}))
	app.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
