extends SceneTree
const HUD := preload("res://ui/garden_hud.gd")
const Catalog := preload("res://ui/gallery_catalog.gd")
const ErrorLogger := preload("res://tests/visual_error_logger.gd")
var logger := ErrorLogger.new()
var outer: SubViewport
var hud: Control
var output := ""
var checks := 0
var failures: Array[String] = []
var images: Array[String] = []
func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	create_timer(90).timeout.connect(func() -> void: quit(2))
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _settle() -> void:
	for unused in 10: await process_frame
func _press(button: Button) -> void:
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
	_check(outer.get_texture().get_image().save_jpg(output.path_join(file),.92) == OK,file)
	images.append(file)
func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	outer = SubViewport.new()
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	outer.size = Vector2i(1280,720)
	root.add_child(outer)
	hud = HUD.new()
	outer.add_child(hud)
	hud.set_game_interface_visible(false)
	var data := {"player":{"name":"露薇"},"mainline":{"records":{"1-1":{"completed":true,"collected":3,"stars":3}}}}
	var unchanged := JSON.stringify(data)
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(390,844),Vector2i(320,568),Vector2i(844,390)]:
		outer.size = extent
		hud.close_overlay(false)
		hud.show_gallery(data)
		await _settle()
		var page: Control = hud._gallery_page
		_check(page._card_buttons.size() == 8,"all eight entries "+str(extent))
		_check(page._count.text == "已收集  1 / 8","real discovery count "+str(extent))
		_check(page._marks(Catalog.ITEMS[0]) == "★★★★★","observation completeness uses spores "+str(extent))
		await _capture("collection")
		await _press(page._card_buttons["flowerbud"])
		_check(page.selected_id == "flowerbud" and page.detail_scroll.visible,"real card opens detail")
		await _press(page._mode_buttons["故事"])
		_check(page.story_mode,"real story tab")
		await _capture("story")
		hud.navigate_back()
		_check(not page.story_mode and hud._page_kind == "gallery","back from story remains in book")
		if page.compact: hud.navigate_back()
		await _settle()
		await _press(page._tabs["生物"])
		_check(page._card_buttons.size() == 1 and page.selected_id == "bug","real category filters cards")
		await _press(page._card_buttons["bug"])
		await _press(page._mode_buttons["故事"])
		_check(page._detail.get_child(1).text == "尚 未 发 现","locked story does not disclose prose")
		_check(page._card_buttons["bug"].get_child(1).get_child(2).material != null,"locked art has silhouette shader")
		await _capture("undiscovered")
		_check(JSON.stringify(data) == unchanged,"render and pointer actions do not write save")
	var all := {"gallery":{}}
	for item: Dictionary in Catalog.ITEMS: all.gallery[item.id] = true
	outer.size = Vector2i(1280,720)
	hud.show_gallery(all)
	await _settle()
	await _capture("all-unlocked")
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"images":images,"scope":"Five native GPU sizes, real card/category/story pointer presses, in-memory fixture only. No browser or user-save mutation."},"  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures}))
	outer.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
