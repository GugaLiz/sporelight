extends SceneTree
const MapView := preload("res://ui/chapter_map.gd")
const HUD := preload("res://ui/garden_hud.gd")
const ErrorLogger := preload("res://tests/visual_error_logger.gd")
var logger := ErrorLogger.new()
var output := ""
var checks := 0
var failures: Array[String] = []
var images: Array[String] = []
var outer: SubViewport
var map: Control
var actions: Array[String] = []
func _initialize() -> void:
	OS.add_logger(logger)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	create_timer(120).timeout.connect(func() -> void: quit(2))
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _settle() -> void:
	for frame in 8: await process_frame
func _action(id: String) -> Button:
	for node: Node in map.find_children("*","Button",true,false):
		if str(node.get_meta("action","")) == id and node.is_visible_in_tree(): return node
	return null
func _press(button: Button) -> void:
	_check(button != null,"pointer target exists")
	if button == null: return
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		outer.push_input(event,true)
	await _settle()
func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var file := "%s-%dx%d.jpg" % [label,outer.size.x,outer.size.y]
	_check(outer.get_texture().get_image().save_jpg(output.path_join(file),.93) == OK,file)
	images.append(file)
func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	outer = SubViewport.new()
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	var progress := {"records":{"1-1":{"completed":true},"1-2":{"completed":true},"1-3":{"completed":true},"1-4":{"completed":true}},"runs":{}}
	var original := JSON.stringify(progress)
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(1913,938),Vector2i(1300,925),Vector2i(844,390),Vector2i(390,844),Vector2i(320,568)]:
		outer.size = extent
		map = MapView.new()
		var hud := HUD.new()
		map.theme = hud._paper_theme()
		hud.free()
		outer.add_child(map)
		map.can_resume = true; map.can_save = true
		map.configure(levels,progress,{"level":"1-4"})
		map.apply_settings({"lowMotion":true})
		map.action_requested.connect(func(id: String) -> void: actions.append(id))
		await _settle()
		var bounds := Rect2(Vector2.ZERO,Vector2(extent))
		for id: String in ["home","world_overview","map_tools"]:
			var button := _action(id)
			_check(bounds.encloses(button.get_global_rect()),"screen button fits / "+id+str(extent))
			_check(button.get_global_transform().get_scale().is_equal_approx(Vector2.ONE),"screen button is not scaled / "+id)
			_check(button.size.y == 48,"consistent button height")
		await _capture("map")
		await _press(_action("map_tools"))
		_check(map._tools_open and map._tools_layer.visible,"actual more click opens sheet")
		_check(bounds.encloses(map._more_panel.get_global_rect()),"sheet stays inside viewport")
		_check(_action("home").disabled,"background controls inert while sheet open")
		await _capture("more")
		await _press(_action("settings"))
		_check(not actions.is_empty() and actions.back() == "settings","real settings tile intent")
		await _press(_action("gallery"))
		_check(actions.back() == "gallery","real gallery tile intent")
		var scroll: ScrollContainer = map._more_panel.get_node("MapToolsScroll")
		scroll.scroll_vertical = 999
		await _settle()
		await _press(_action("save"))
		_check(actions.back() == "save","scroll reaches save action")
		await _press(_action("close_map_tools"))
		_check(not map._tools_open and not _action("home").disabled,"close restores navigation")
		_check(map.selected_id == "1-4" and JSON.stringify(progress) == original,"tools preserve selection and supplied progress")
		if extent == Vector2i(1280,720):
			for chapter: String in ["pond","cave"]:
				map.select_chapter(chapter)
				await _settle()
				await _capture(chapter)
		map.queue_free()
		await process_frame
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"images":images,"scope":"Six GPU sizes, native pointer menu/settings/gallery/save/close, in-memory progress. Three chapter cleanup colors. Not browser or audio/performance evidence."},"  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures}))
	outer.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
