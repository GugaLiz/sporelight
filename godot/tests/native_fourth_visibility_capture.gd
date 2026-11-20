extends "res://tests/native_hud_feedback_capture.gd"
## Prepared puzzle snapshots, then real motor walk/switch/follow. GPU views of
## depth/material feedback; memory saves only, no claim of OS/browser input.
var observations: Array = []
func snap(label: String, zoom: float = 1.0) -> void:
	app._update_layout();app.view._fit_camera(true)
	app.view._camera.size *= zoom
	for unused in 8: await RenderingServer.frame_post_draw
	var name := "%s-%dx%d.jpg" % [label,dimensions.x,dimensions.y]
	_check(outer.get_texture().get_image().save_jpg(output.path_join(name),.96)==OK,"GPU "+name)
	images.append(name)
	var bodies := {}
	for who: String in ["luvie","buddy"]:
		var body: CharacterBody3D=app.view.get_actor_body(who)
		bodies[who] = {"at":str(body.position),"support":str(app.session.world.state.actors[who]),"artBasis":str(body.get_node("Visual/Art").basis)}
	observations.append({"label":label,"actors":bodies,"snapshot":app.session.world.snapshot()})
func load_home(leader: String) -> void:
	var ref: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var state: Dictionary
	for entry: Dictionary in ref.cases:
		if str(entry.name)=="authored/1-4":
			for step: Dictionary in entry.steps:
				if str(step.command.get("value",""))=="use:home":state=step.snapshot.duplicate(true);break
	state.collected.erase("spore-0")
	state.actors={"luvie":"f:-4:0","buddy":"f:-4:0"};state.active=leader;state.follow=true;state.erase("runtime")
	app.repository.data.mainline.runs["1-4"]=state;app._enter_level("1-4");await _drain()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer=SubViewport.new();outer.size=dimensions;outer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(outer)
	_setup();app.reparent(outer);app.view.set_settings(app.settings);app.hud.apply_settings(app.settings)
	app.view.tile_selected.connect(app._go);app.view.command_selected.connect(app._on_command)
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		dimensions=size;outer.size=size
		await load_home("luvie")
		await snap("home")
		var resident: Sprite3D=app.view._props.get_node("MoleResident")
		_check(resident.billboard==BaseMaterial3D.BILLBOARD_DISABLED and not resident.no_depth_test,"resident has normal upright depth")
		_check(app.view._prop_obstacles.any(func(e: Dictionary)->bool:return e.id=="resident:mole"),"resident supplies shared collision/planner footprint")
		_check(await _walk_to("f:-4:-1","approach resident"),"actual walk beside resident succeeds")
		await snap("resident-approach")
		_check(app.view.prop_physical_point_clear(app.view.get_actor_body("luvie").position,"luvie"),"actor cannot stand inside resident")
		_check(await _walk_to("f:-5:0","west entrance"),"resident leaves only entrance usable")
		await snap("west-entrance")
		_check(await _walk_to("f:-6:0","open garden gate"),"real ascent through open gate succeeds")
		await snap("garden-gate")
		_check(await _walk_to("f:-8:1","planter bedside"),"real walk to planter succeeds")
		await snap("bedside")
		app._on_command("switch");await _drain();app._on_command("follow");await _drain()
		_check(await _walk_to("f:-4:0","buddy leads back"),"buddy leads safely past resident")
		await snap("buddy-leading-home")
		app._on_command("switch");await _drain();app._on_command("follow");await _drain()
		_check(await _walk_to("f:-3:5","latch side"),"real walk to latch succeeds")
		await snap("latch")
		var light: Dictionary=app.view._garden_effects.collectibles.get("spore-0",{})
		_check(not light.is_empty(),"bell-side foreground light present in prepared uncollected state")
		if not light.is_empty():
			_check(light.sprite.no_depth_test and light.sprite.render_priority==127,"only requested bell-side light uses highest sprite priority")
			_check(app.view.hit_test(app.view.world_to_screen(light.sprite.global_position))=="f:-2:5","foreground light hit keeps its original support")
			_tap(app.view.world_to_screen(light.sprite.global_position));await _drain(800)
			_check("spore-0" in app.session.world.state.collected,"actual light pointer walks and collects foreground pickup")
			app._on_command("undo");await _drain()
			_check(app.view._garden_effects.collectibles.has("spore-0"),"undo restores same foreground light")
		for who: String in ["luvie","buddy"]:
			var art: AnimatedSprite3D=app.view.get_actor_body(who).get_node("Visual/Art")
			_check(not art.no_depth_test and art.alpha_cut==SpriteBase3D.ALPHA_CUT_DISCARD,"actor retains world depth without dual-pass self-overlap")
		for button: Button in app.hud._tool_buttons:
			if button.visible:
				_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),"tool stays in viewport "+str(button.get_meta("action")))
				if button.get_meta("action")=="switch": _check(button.text.begins_with("切换角色"),"clear role-switch label")
		if size.x==1280:
			await _walk_to("f:-8:1","return butterfly garden")
			app.view.set_process(false)
			for phase: float in [0.0,.175,.35]:
				app.view.visual_time=phase*1000.0;app.view._garden_effects.update()
				await snap("butterfly-phase-"+str(phase),.70)
			app.settings.lowMotion=true;app.view.set_settings(app.settings)
			var fx: Node3D=app.view._garden_effects
			fx.update();var flap: float=fx.atmosphere.butterflies[0].material.get_shader_parameter("flap")
			app.view.visual_time+=120;fx.update()
			_check(flap==float(fx.atmosphere.butterflies[0].material.get_shader_parameter("flap")),"reduced motion freezes complete butterfly shape")
			app.settings.lowMotion=false;app.view.set_settings(app.settings)
			app.view.set_process(true)
	dimensions=Vector2i(1280,720);outer.size=dimensions
	app._enter_level("2-1");await _drain()
	for phase in 4:
		for unused in 17: await _tick()
		await snap("actor-single-pass-phase-"+str(phase),.65)
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"sourceSha256":source_sha,"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images,"observations":observations,"scope":"Prepared 1-4 home state followed by actual native motor walk, switch and follow. Three GPU sizes and butterfly time samples; 2-1 single-pass phases. AudioStub, memory saves; not Web/OS input or performance."},"  "))
	print(JSON.stringify({"checks":checks,"images":images.size(),"passed":failures.is_empty(),"failures":failures}))
	await _dispose();finished=true;quit(0 if failures.is_empty() else 1)
