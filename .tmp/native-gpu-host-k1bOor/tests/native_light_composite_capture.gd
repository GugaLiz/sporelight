extends "res://tests/native_hud_feedback_capture.gd"
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app._enter_level("1-2")
	await _drain()
	branch = "composite"
	app.view.set_process(false)
	app.view._camera.size *= .6
	for variant: String in ["current", "premul", "no-aura"]:
		if variant == "premul":
			var material := CanvasItemMaterial.new()
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
			app.view._image.material = material
		if variant == "no-aura":
			for entry: Dictionary in app.view._garden_effects.collectibles.values(): entry.aura.hide()
		for unused in 8: await RenderingServer.frame_post_draw
		outer.get_texture().get_image().save_png(output.path_join(variant+".png"))
	await _dispose()
	finished = true
	quit()
