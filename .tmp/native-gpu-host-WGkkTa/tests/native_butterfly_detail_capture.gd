extends "res://tests/native_fourth_visibility_capture.gd"
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer=SubViewport.new();outer.size=dimensions;outer.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(outer)
	_setup();app.reparent(outer);app.view.set_settings(app.settings);app.hud.apply_settings(app.settings)
	await load_home("luvie")
	app.view.set_process(false);app.hud.hide()
	var camera: Camera3D=app.view._camera
	var focus:=Vector3(-9,.8,0)
	camera.global_position=focus+app.view.CAMERA_RAY*60;camera.look_at(focus,Vector3.UP);camera.size=5.3
	var fx: Node3D=app.view._garden_effects
	var samples: Array=[]
	for time_ms: float in [0.0,175.0,350.0,700.0]:
		app.view.visual_time=time_ms;fx.update()
		for unused in 8: await RenderingServer.frame_post_draw
		var file: String="butterfly-%04dms.jpg"%int(time_ms)
		outer.get_texture().get_image().save_jpg(output.path_join(file),.98)
		samples.append({"timeMs":time_ms,"flap":float(fx.atmosphere.butterflies[0].material.get_shader_parameter("flap")),"file":file})
	_check(samples[0].flap > .99 and samples[2].flap < .39 and samples[1].flap > .6,"butterfly covers open/mid/folded wings without vanishing")
	app.view.set_paused(true);var frozen: float=app.view.visual_time;app.view._process(.2);_check(app.view.visual_time==frozen,"pause freezes butterfly clock")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"sourceSha256":source_sha,"checks":checks,"passed":failures.is_empty(),"failures":failures,"samples":samples,"scope":"GPU close view, explicit millisecond clock samples; camera-only QA framing, in-memory prepared state. No gameplay or performance claim."},"  "))
	print(JSON.stringify({"checks":checks,"failures":failures,"samples":samples}))
	await _dispose();finished=true;quit(0 if failures.is_empty() else 1)
