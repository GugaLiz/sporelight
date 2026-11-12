extends "res://tests/service_modal_lifecycle_test.gd"
## Navigation uses the real HUD/controller and existing save semantics.
const MapView := preload("res://ui/chapter_map.gd")


func _settle_map() -> void:
	for unused in range(4):
		await process_frame


func _meta_button(node: Node, key: String, value: String) -> Button:
	for button: Node in node.find_children("*", "Button", true, false):
		if button.get_meta(key, "") == value:
			return button
	return null


func _navigation() -> void:
	var app := _real_app()
	var store: Dictionary = app.repository.data.mainline
	store.records["1-1"] = {"completed": true, "collected": 2, "stars": 2}
	store.last_level = "1-2"
	store.runs["1-2"] = {"collected": ["one"], "completed": false}
	app._show_menu()
	await _settle_map()
	var map: Control = app.hud._chapter_map
	_check(map.selected_id == "1-2" and map.chapter == "valley", "saved-last-level-selects-correct-landmark")
	_check(_find_button(map, "继续关卡") != null, "unfinished-save-offers-continue")
	var totals := 0
	for level: Dictionary in _levels:
		if MapView.chapter_id(level) == "valley":
			totals += int(level.get("total", 0))
	_check(map._chapter_progress("valley").total == totals, "chapter-total-comes-from-current-content")
	_check(map._chapter_progress("valley").collected == 3, "record-and-unfinished-run-collections-use-live-save")
	var state_before: Dictionary = app.session.world.snapshot()
	var save_before: Dictionary = app.repository.data.duplicate(true)
	_meta_button(map, "map_level", "1-3").pressed.emit()
	_check(map.selected_id == "1-3" and _find_button(map, "等待前一关苏醒").disabled, "locked-landmark-is-inspectable-with-entry-disabled")
	_find_button(map, "等待前一关苏醒").pressed.emit()
	_same(state_before, app.session.world.snapshot(), "locked-intent-cannot-replace-current-world")
	map.select_level("1-2")
	_press(app, "图鉴", "map/gallery")
	app.hud.navigate_back()
	await _settle_map()
	map = app.hud._chapter_map
	_check(map.selected_id == "1-2" and map.chapter == "valley", "gallery-back-keeps-selected-chapter-and-landmark")
	_paused_modal(app, "map/gallery/back")
	map.show_overview()
	await _settle_map()
	_check(map.overview_open and map._body.is_visible_in_tree(), "world-overview-preserves-live-map-covering-baked-ui")
	_check_inert_backdrop(map._body)
	app.hud.navigate_back()
	_check(not map.overview_open and app.hud.is_modal_open() and app.paused, "back-closes-overview-without-resuming-game")
	map.show_overview()
	_meta_button(map._overview, "map_chapter", "pond").pressed.emit()
	_check(map.chapter == "pond" and not map.overview_open, "overview-chapter-opens-real-illustrated-chapter")
	_check(_find_button(map, "等待前一关苏醒").disabled, "previewing-locked-chapter-does-not-unlock-entry")
	map.select_chapter("cloud")
	_check(map._chapter_entries("cloud").size() == 3 and not map.preferred_focus.disabled, "all-three-independent-cloud-destinations-available")
	_same(save_before, app.repository.data, "inspecting-chapters-and-subpages-never-mutates-save")
	_same(state_before, app.session.world.snapshot(), "inspecting-map-never-mutates-puzzle")
	map.preferred_focus.pressed.emit()
	_check(str(app.session.world.level.id) == "cloud-1" and not app.hud.is_modal_open() and not app.paused, "cloud-enter-reaches-real-controller-and-resumes")
	app.free()


func _check_inert_backdrop(node: Control) -> void:
	_check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, "overview-background-no-pointer-or-keyboard/" + str(node.name))
	if node is Button:
		_check(node.disabled, "overview-background-button-disabled/" + str(node.name))
	for child: Node in node.get_children():
		if child is Control:
			_check_inert_backdrop(child)


func _geometry_and_keyboard() -> void:
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(568, 320)]:
		root.size = dimensions
		var app := _real_app()
		app._show_menu()
		await _settle_map()
		var map: Control = app.hud._chapter_map
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		var label := "%dx%d" % [dimensions.x, dimensions.y]
		for button: Node in map.find_children("*", "Button", true, false):
			if not button.is_visible_in_tree():
				continue
			_check(viewport.grow(1).encloses(button.get_global_rect()), label + "/visible-button-contained/" + str(button.get_meta("map_level", button.text)))
			_check(button.get_global_rect().size.x >= 43.5 and button.get_global_rect().size.y >= 43.5, label + "/minimum-hit-area/" + str(button.get_meta("map_level", button.text)))
		for caption: Node in map.find_children("*", "Label", true, false):
			if not caption.is_visible_in_tree():
				continue
			_check(viewport.grow(1).encloses(caption.get_global_rect()), label + "/caption-contained/" + caption.text + str(caption.get_global_rect()))
			var ancestor: Node = caption.get_parent()
			while ancestor != map:
				if ancestor is Control and ancestor.clip_contents:
					_check(ancestor.get_global_rect().grow(1).encloses(caption.get_global_rect()), label + "/caption-not-clipped/" + caption.text)
				ancestor = ancestor.get_parent()
		_check(root.gui_get_focus_owner() == map.preferred_focus, label + "/initial-keyboard-focus-is-enter")
		var card: Panel = map._body.get_node("MapSelectedCard")
		var card_controls: Array[Control] = []
		for item: Node in card.get_children():
			if item is Label or item is Button:
				card_controls.append(item)
				_check(Rect2(Vector2.ZERO, card.size).grow(0.5).encloses(item.get_rect()), label + "/detail-stays-inside-card/" + item.text)
		for index in card_controls.size():
			for next in range(index + 1, card_controls.size()):
				_check(not card_controls[index].get_rect().intersection(card_controls[next].get_rect()).has_area(), label + "/detail-rows-do-not-overlap/" + card_controls[index].text + "/" + card_controls[next].text)
		map.show_overview()
		await _settle_map()
		_check(map._body.is_visible_in_tree(), label + "/overview-keeps-live-map-visible")
		_check_inert_backdrop(map._body)
		_check(root.gui_get_focus_owner() == map.preferred_focus and map._overview.is_ancestor_of(map.preferred_focus), label + "/overview-focus-stays-in-visible-dialog")
		app.hud.navigate_back()
		await _settle_map()
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = true
		root.push_input(event)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
		await _settle_map()
		_check(not app.hud.is_modal_open() and not app.paused and str(app.session.world.level.id) == "1-1", label + "/real-enter-key-opens-selected-garden")
		app.free()
	root.size = Vector2i(1280, 720)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	_levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	_reference = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	await _navigation()
	await _geometry_and_keyboard()
	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite": "native-chapter-map", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "scope": "Live progress, navigation, pause/save protection, real Enter input and landscape control bounds; GPU artwork and pointer/touch acceptance remain separate."}))
	quit(0 if _failures.is_empty() else 1)
