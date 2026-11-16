extends SceneTree
## Observe actual controls and scroll positions after container layout.
const HUD := preload("res://ui/garden_hud.gd")
const Catalog := preload("res://ui/gallery_catalog.gd")
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)


func _settle() -> void:
	for frame in 8:
		await process_frame


func _tab(hud: Control, caption: String) -> Button:
	for button in hud._gallery_frame.get_node("GalleryCategories").get_children():
		if button is Button and button.text == caption:
			return button
	return null


func _run() -> void:
	var hud := HUD.new()
	root.add_child(hud)
	hud.set_game_interface_visible(false)
	var store := {"gallery": {}}
	for item in Catalog.ITEMS:
		store.gallery[item.id] = true
	for extent in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(320, 568), Vector2i(568, 320), Vector2i(594, 462)]:
		root.size = extent
		hud.close_overlay(false)
		hud.show_gallery(store)
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(extent))
		var prefix := "%dx%d/" % [extent.x, extent.y]
		_check(bounds.encloses(hud._gallery_frame.get_global_rect()), prefix + "native gallery frame fits viewport")
		_check(hud._overlay_scroll.scroll_vertical == 0, prefix + "fresh gallery starts at its content top")
		_check(root.gui_get_focus_owner() == _tab(hud, "全部"), prefix + "selected tab owns focus outside scroller")
		_check(hud._gallery_heading.get_global_rect().end.y <= hud._overlay_scroll.get_global_rect().position.y, prefix + "title stays above scroll body")
		for category in Catalog.CATEGORIES:
			hud._overlay_scroll.scroll_vertical = 190
			await _settle()
			_tab(hud, str(category)).pressed.emit()
			await _settle()
			if category != "全部":
				_check(hud._overlay_scroll.scroll_vertical == 0, prefix + str(category) + "/switch starts at top")
			_check(root.gui_get_focus_owner() == _tab(hud, str(category)), prefix + str(category) + "/selected category owns keyboard focus")
			var selected_count := 0
			for button in hud._gallery_frame.get_node("GalleryCategories").get_children():
				selected_count += int(button.button_pressed)
				_check(button.size.x >= 44 and button.size.y >= 44, prefix + button.text + "/minimum tab hit area")
			_check(selected_count == 1, prefix + "only one category is selected")
		hud.show_gallery(store, "植物")
		await _settle()
		hud._overlay_scroll.scroll_vertical = 280
		await _settle()
		var remembered := hud._overlay_scroll.scroll_vertical
		var original: int = hud._overlay.get_instance_id()
		_tab(hud, "植物").pressed.emit()
		await _settle()
		_check(hud._overlay.get_instance_id() == original and hud._overlay_scroll.scroll_vertical == remembered, prefix + "clicking selected tab does not rebuild or jump")
		hud._show_gallery_story(Catalog.ITEMS[0], store, "植物")
		await _settle()
		hud.navigate_back()
		await _settle()
		_check(hud._page_kind == "gallery" and hud._overlay.get_meta("gallery_category") == "植物", prefix + "story back restores its category")
		_check(absi(hud._overlay_scroll.scroll_vertical - remembered) <= 1, prefix + "story back restores the reading offset")
	hud.queue_free()
	await _settle()
	print(JSON.stringify({"suite": "native-gallery-navigation", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "scope": "Actual Godot controls and container scroll layout, not browser pointer or GPU evidence."}))
	quit(0 if _failures.is_empty() else 1)
