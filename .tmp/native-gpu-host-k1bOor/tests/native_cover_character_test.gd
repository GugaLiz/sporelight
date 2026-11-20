extends SceneTree
## Shared character identity and cover foot registration. Optional GPU captures
## use the actual cover at fixed choreography times; no user save is loaded.
const HUD := preload("res://ui/garden_hud.gd")
const Assets := preload("res://elements/element_assets.gd")
const Vignette := preload("res://ui/menu_vignette.gd")
var checks := 0
var failures: Array[String] = []
var output := ""
var captures: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var hud := HUD.new()
		viewport.add_child(hud)
		hud.show_home(levels,{"records":{},"runs":{},"memories":{}},false)
		for unused in 5: await process_frame
		var stage = hud._home_cover.scenery
		stage.set_process(false)
		check(stage._frames["idle-front"] == Assets.texture("idle-front"), "home and map share front identity")
		check(stage._frames["idle-side"] == Assets.texture("cover-idle-side"), "cover uses approved three-quarter identity")
		for index in 6:
			check(stage._frames["palm-%d" % index].resource_path == stage.PALM_ART[index], "whole crouch/reach/hold pose %d is loaded" % index)
			check(stage._frames["attention-%d" % index].resource_path == stage.ATTENTION_ART[index], "whole gaze/gesture pose %d is loaded" % index)
		for index in 8:
			check(stage._frames["step-%d" % (index+1)] == Assets.texture("cover-step-%d" % (index+1)), "cover uses registered quarter walk frame %d" % (index+1))
		var times := [0,900,1900,4500,6800,7100,7500,8250,9500,10500,11400,11900,12180,12350,12800,13250,15000,18200,19000,20350,21400,23000,23999]
		for time: int in times:
			stage.elapsed_ms = time
			stage.refresh_pose()
			if stage.current_pose.tracking:
				check(stage.hero.texture == stage._frames[stage.current_pose.attention.key], "standing expression follows light location at %d" % time)
				check(stage.current_pose.hero.flip == stage.current_pose.attention.flip, "standing body faces the light at %d" % time)
				check(absf(stage.head_material.get_shader_parameter("head_angle"))<=0.0451, "head response stays within gentle bounds")
			if stage.current_pose.holding:
				check(stage.orb.position.is_equal_approx(stage.current_pose.palm), "mote stays on registered palm at %d" % time)
				var frame := int(str(stage.current_pose.hero.key).trim_prefix("palm-"))
				var actual_palm: Vector2 = stage.hero.transform * (stage.hero.offset + stage.PALM_ANCHORS[frame]) + Vector2(0,-6)
				check(actual_palm.is_equal_approx(stage.orb.position), "rendered hand and mote share coordinates at %d" % time)
				check(is_zero_approx(stage.hero.rotation), "holding uses hands and expression, not whole-body shaking")
			check(stage.hero.position.is_equal_approx(Vector2(stage.current_pose.hero.x,stage.current_pose.hero.y)), "authored foot path retained at %d" % time)
			for art: Sprite2D in [stage.hero]:
				if not art.visible: continue
				var foot := art.offset + Vector2(art.texture.get_width() * 0.5,art.texture.get_height() * 236.0 / 256.0)
				check(foot.is_zero_approx(), "registered foot retained at %d/%s" % [time,art.name])
				check(is_equal_approx(absf(art.scale.x),art.scale.y) or absf(absf(art.scale.x)-art.scale.y)<0.006, "character proportions retained at %d/%s" % [time,art.name])
			if not output.is_empty() and (dimensions.x != 390 or time in [0,6800,8250,9500,10500,11900,12800,19000]):
				for unused in 3: await RenderingServer.frame_post_draw
				var file := "%dx%d-%05d.png" % [dimensions.x,dimensions.y,time]
				check(viewport.get_texture().get_image().save_png(output.path_join(file)) == OK, "GPU capture saved")
				captures.append({"file":file,"time":time,"viewport":[dimensions.x,dimensions.y],"texture":stage.hero.texture.resource_path})
		stage.configure({"lowMotion":true})
		check(not stage.is_processing() and stage.hero.texture == Assets.texture("idle-front"), "reduced motion retains shared neutral identity")
		check(is_zero_approx(stage.hero.rotation) and is_zero_approx(stage.head_material.get_shader_parameter("head_angle")), "reduced motion clears body/head tracking")
		viewport.queue_free()
		await process_frame
	# A release starts from the held point and rejoins the original flight path.
	for boundary in [8050,11350,11750,24000]:
		check(Vignette.pose_at(boundary-0.01).light.distance_to(Vignette.pose_at(boundary+0.01).light)<0.05, "mote path continuous at %d" % boundary)
	var at := {"x":325.0,"y":642.0,"progress":0.0}
	var eye := Vector2(325,642-290*0.455)
	# One fixed character sees the mote move through all gaze directions.
	var targets := [Vector2(-80,-80),Vector2(-80,0),Vector2(-80,80),Vector2(-20,-100),Vector2(20,-100),Vector2(0,-100)]
	for index in targets.size():
		var look := Vignette.attention_for(at,eye+targets[index])
		check(look.frame == index, "light drives up/level/down/overhead gaze %d" % index)
		if index<3:
			check(not look.flip and Vignette.attention_for(at,eye+Vector2(80,targets[index].y)).flip, "side gaze follows light across the body")
	check(Vignette.attention_for(at,eye+Vector2(-80,-40)).head_angle != Vignette.attention_for(at,eye+Vector2(-80,-100)).head_angle, "head responds continuously within the same upward pose")
	check(Vignette.pose_at(1900).tracking and Vignette.pose_at(1900).hero.x == 325, "noticing and turning precede the first step")
	check(Vignette.pose_at(12800).light.y < 365, "released light passes above the head instead of covering the eyes")
	check(Vignette.pose_at(0).hero.key == Vignette.pose_at(23999).hero.key, "loop boundary retains engaged gaze instead of a neutral stare")
	check(Assets.errors().is_empty(), "shared theme resolution has no errors")
	var report := {"suite":"native-cover-character","checks":checks,"passed":failures.is_empty(),"failures":failures,"captures":captures,"adapter":RenderingServer.get_video_adapter_name(),"scope":"Shared identity, full walk frame bindings, foot registration and proportions across real cover states/sizes. Optional GPU captures are prepared times, not pointer or performance testing."}
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("captures.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
