extends SceneTree

const World := preload("res://core/garden_world.gd")
const View := preload("res://presentation/world/garden_view.gd")
const HUD := preload("res://ui/garden_hud.gd")
const Journey := preload("res://application/journey_view.gd")
var _output := ""
var _capture_size := Vector2i(1280, 720)
var _level_id := "1-1"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--viewport="):
			var dimensions := argument.trim_prefix("--viewport=").split("x")
			if dimensions.size() != 2:
				push_error("Expected --viewport=WIDTHxHEIGHT as one argument")
				quit(2)
				return
			_capture_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument.begins_with("--level="):
			_level_id = argument.trim_prefix("--level=")
	create_timer(25).timeout.connect(func() -> void: quit(2))
	_run.call_deferred()


func _run() -> void:
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A real GPU and explicit output directory are required")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = _capture_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	var hud := HUD.new()
	viewport.add_child(hud)
	view.label_font = hud.theme.default_font
	var world := World.new(_level_id)
	view.set_world(world)
	view.set_visual_time(1200)
	hud.update_state(world, false, String(world.level.intro))
	hud.set_journey(Journey.describe(world))
	var states := {}
	var primary := ""
	for command: Dictionary in world.commands():
		var result: Dictionary = world.fork(world.snapshot()).act(String(command.id))
		states[command.id] = {"available": bool(result.get("ok", false)), "reason": String(result.get("message", ""))}
		if primary.is_empty() and command.id not in ["switch", "follow"] and result.get("ok", false):
			primary = String(command.id)
			hud.set_action_label("primary", String(command.label) + " · E")
	hud.set_action_feedback(primary, states)
	for index in 8:
		await process_frame
	view.set_ui_regions(hud.layout_regions())
	for index in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_output)
	var capture_name := "hud-%s-%dx%d" % [_level_id, _capture_size.x, _capture_size.y]
	var error := viewport.get_texture().get_image().save_png(_output.path_join(capture_name + ".png"))
	var geometry := {}
	for name_value in ["Heading", "NearbyActions", "JourneyTools", "JourneyMessage"]:
		var control: Control = hud.get_node(name_value)
		geometry[name_value] = {"position": [control.position.x, control.position.y], "size": [control.size.x, control.size.y]}
	var font: Font = hud.theme.default_font
	var report := {"error": error, "snapshot": world.snapshot(), "viewport": [viewport.size.x, viewport.size.y], "geometry": geometry, "title": {"text": hud._title.text, "lines": hud._title.get_line_count(), "font_size": hud._title.get_theme_font_size("font_size"), "width": hud._title.size.x}, "font_weight": font.get_font_weight(), "font_variation": font.variation_opentype if font is FontVariation else {}, "normal_button": hud.theme.get_stylebox("normal", "Button").bg_color.to_html()}
	print(JSON.stringify(report))
	var file := FileAccess.open(_output.path_join(capture_name + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	viewport.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
