extends SceneTree
## Explicit GPU screenshots of the real responsive map; no user save is loaded.
const MapView = preload("res://ui/chapter_map.gd")
var output := ProjectSettings.globalize_path("res://").path_join("../docs/qa-godot-native/feedback-20261117/map").simplify_path()
var rows: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	run.call_deferred()

func capture(viewport: SubViewport, name_value: String) -> void:
	for unused in range(3): await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	assert(pixels != null and pixels.get_size() == viewport.size)
	assert(pixels.save_png(output.path_join(name_value + ".png")) == OK)
	rows.append({"file":name_value + ".png", "viewport":[viewport.size.x,viewport.size.y]})

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var map := MapView.new()
		viewport.add_child(map)
		map.size = dimensions
		map.can_save = true
		map.can_resume = true
		map.configure(levels,{"records":{},"runs":{}},{"level":"1-1"})
		map.apply_settings({"lowMotion":true})
		var prefix := "%dx%d" % [dimensions.x,dimensions.y]
		await capture(viewport,prefix + "-map")
		map.select_level("1-4")
		await capture(viewport,prefix + "-last-garden")
		map.select_level("1-1")
		map._tools_open = true
		map.relayout()
		await capture(viewport,prefix + "-more")
		map._tools_open = false
		map.show_overview()
		await capture(viewport,prefix + "-overview")
		viewport.queue_free()
		await process_frame
	var file := FileAccess.open(output.path_join("captures.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"scope":"Actual GPU map, More actions and overview in three viewports; no pointer/touch or user saves."},"  "))
	quit()
