extends SceneTree

const HUD := preload("res://ui/garden_hud.gd")
var _checks := 0
var _failures: Array[String] = []
var _events: Array[String] = []
var _settings_events: Array[Dictionary] = []

class SampleWorld:
	extends RefCounted
	var level := {"id": "1-1", "title": "初生的孢子", "rule": "引一节芽，决定第一段路", "roots": [], "total": 3, "dual": true, "story": "小花重新醒来了。"}
	var state := {"active": "luvie", "growth": {}, "items": {}, "collected": [], "completed": false}
	func commands() -> Array:
		return [{"id": "switch", "label": "换手"}, {"id": "follow", "label": "一起走", "selected": true}, {"id": "grow:root:right", "label": "引芽 →"}]
	func ready() -> bool:
		return false
	func can_undo() -> bool:
		return false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hud := HUD.new()
	root.add_child(hud)
	hud.command_requested.connect(func(command: String) -> void: _events.append(command))
	hud.settings_changed.connect(func(settings: Dictionary) -> void: _settings_events.append(settings))
	var world := SampleWorld.new()
	hud.update_state(world)
	hud.set_journey({"done": 0, "total": 3, "current": 0, "next": "走近根台。", "steps": [{"label": "接通根路", "done": false}, {"label": "抵达花床", "done": false}, {"label": "种下微光", "done": false}]})
	hud.set_message("小花在缺口那边等你。点亮根台，再选择根须向哪里长。")
	await process_frame
	await process_frame
	_expect(not hud.is_modal_open(), "HUD starts without a modal or implicit import")
	var buttons := _buttons(hud)
	var growth := _find(buttons, "1  引芽 →")
	_expect(growth != null, "Numeric shortcut labels exclude switch and follow")
	if growth != null:
		growth.pressed.emit()
	_expect(_events.has("grow:root:right"), "HUD emits the original rule command")
	hud.set_action_feedback("grow:root:right", {"grow:root:right": {"available": false, "reason": "根芽预算不足"}})
	_expect(not growth.disabled and growth.text.ends_with(" ·") and growth.tooltip_text == "根芽预算不足", "Unavailable actions remain clickable and explain their rule-derived condition")
	var primary_tool := _find_contains(buttons, "播种 / 互动")
	hud.set_action_label("primary", "引芽 → · E")
	_expect(primary_tool.tooltip_text == "根芽预算不足", "Updating the primary caption does not discard its cached unavailable reason")
	hud.set_action_feedback("grow:root:right", {"grow:root:right": {"available": true, "reason": ""}})
	_expect(growth.text == "1  引芽 →" and growth.get_theme_stylebox("normal").border_width_left == 2, "The available primary action is marked without changing its shortcut number")
	_expect(primary_tool.tooltip_text == "引芽 → · E", "A newly available primary action clears the old failure reason")
	_expect(hud.get_node("JourneyMessage").size.y < 90, "First wrapped message cannot expand over the tool bar")
	var weight_tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	_expect(hud.theme.default_font is FontVariation and hud.theme.default_font.variation_opentype.get(weight_tag) == 400.0, "Variable font uses the actual OpenType weight tag at regular weight")
	_expect(hud.get_node("Heading").size.y <= 260, "Journey chips cannot grow the title panel down the entire screen")
	_expect(growth.get_theme_stylebox("normal") is StyleBoxFlat and growth.get_theme_stylebox("normal").bg_color == Color("f2dfbd"), "Primary action retains the warm paper theme")
	var overview: Button = hud.get_node("Overview")
	_expect(overview.get_theme_stylebox("normal") is StyleBoxFlat and overview.get_theme_stylebox("normal").bg_color == Color("f7e8cf"), "Detached icon buttons do not capture the default dark theme")
	overview.pressed.emit()
	_expect(_events.has("overview"), "Overview control emits the coordinator action")
	var direction: Button = _find(buttons, "↑")
	direction.pressed.emit()
	_expect(_events.has("dir:up"), "Virtual direction pad emits a typed direction intent")
	_find(buttons, "等候").pressed.emit()
	_expect(_events.has("follow"), "Companion follow toggle remains available")
	_expect(_find(buttons, "退回一格 · Z").disabled, "Undo is disabled when no history exists")
	_expect(_safe_from_hud(hud), "Desktop safe rectangle excludes actual HUD panels")
	root.size = Vector2i(738, 672)
	hud.set_journey({"done": 0, "total": 6, "current": 0, "steps": [{"label": "固定叶阶"}, {"label": "水托花台"}, {"label": "光回到家"}, {"label": "接通归途"}, {"label": "两位到花床"}, {"label": "种下微光"}]})
	await process_frame
	await process_frame
	var medium_header: Rect2 = hud.get_node("Heading").get_rect()
	_expect(medium_header == Rect2(24, 24, 292, 142), "Medium-height windows fold the title before it reaches the starting island")
	var finale_actor := Rect2(291.88 - 38 * 0.453333, 272.14666 - 100 * 0.453333, 76 * 0.453333, 100 * 0.453333)
	_expect(not medium_header.intersects(finale_actor) and not medium_header.has_point(Vector2(307.74667, 278.72)), "The actual 3-4 738x672 start protects the controlled character and companion foot")
	_expect(not medium_header.intersects(hud.get_node("Overview").get_rect()), "Medium-height title no longer covers the overview button")
	var medium_step_count := 0
	for chip in hud._journey_labels:
		if chip.visible:
			medium_step_count += 1
	_expect(medium_step_count == 1 and not hud._rule.visible and not hud._journey_count.visible, "Medium-height title retains one current objective and folds supplementary text")
	for medium_width in [900, 901]:
		root.size = Vector2i(medium_width, 700)
		await process_frame
		await process_frame
		_expect(hud.get_node("Heading").size == Vector2(292, 142) and not hud.get_node("Heading").get_rect().has_point(Vector2(296, 267.04)), "The 900/901 breakpoint releases the distant 1-4 flower marker")
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	_expect(hud.get_node("Heading").size.y == 261 and hud._rule.visible and hud._journey_count.visible, "Leaving medium-height windows restores the original desktop title")
	root.size = Vector2i(390, 844)
	await process_frame
	await process_frame
	_expect(_safe_from_hud(hud), "Portrait safe rectangle excludes actual HUD panels")
	root.size = Vector2i(320, 568)
	await process_frame
	await process_frame
	_expect(hud.get_node("Heading").size.y <= 120 and hud.get_node("NearbyActions").size.x <= 144, "Compact portrait folds its header and keeps the action card outside the actor protection area")
	_expect(not hud.get_node("Heading").get_rect().intersects(hud.get_node("NearbyActions").get_rect()), "Compact portrait title and action text never overlap")
	var focus := Vector2(320 * 0.38 + 8 * 0.92, 568 * 0.5 + 7 * 0.92)
	var focus_clear := true
	for region in hud.layout_regions():
		var bounds: Array = region.rect
		focus_clear = focus_clear and not Rect2(bounds[0], bounds[1], bounds[2], bounds[3]).has_point(focus)
	_expect(focus_clear, "Default compact-portrait character foot anchor is outside HUD chrome")
	var actor_clear := true
	var protected_actor := Rect2(focus.x - 38 * 0.92, focus.y - 100 * 0.92, 76 * 0.92, 100 * 0.92)
	for region in hud.layout_regions():
		var bounds: Array = region.rect
		actor_clear = actor_clear and not protected_actor.intersects(Rect2(bounds[0], bounds[1], bounds[2], bounds[3]))
	_expect(actor_clear, "Compact portrait protects the entire character head-to-foot rectangle")
	_expect(hud.get_node("DirectionPad").size.y <= 44, "Compact portrait directions use one accessible row")
	root.size = Vector2i(390, 844)
	await process_frame
	await process_frame
	var phone_foot := Vector2(390 * 0.38 + 8 * 0.92, 844 * 0.5 + 7 * 0.92)
	var phone_actor := Rect2(phone_foot.x - 38 * 0.92, phone_foot.y - 100 * 0.92, 76 * 0.92, 100 * 0.92)
	var phone_clear := true
	for region in hud.layout_regions():
		var bounds: Array = region.rect
		phone_clear = phone_clear and not phone_actor.intersects(Rect2(bounds[0], bounds[1], bounds[2], bounds[3]))
	_expect(phone_clear, "Normal phone moves HUD into the upper blank area and protects the character")
	root.size = Vector2i(844, 390)
	await process_frame
	await process_frame
	_expect(hud.get_node("JourneyTools").size.y <= 75, "Short landscape uses one compact toolbar row")
	_expect(hud.get_node("Overview").position.y >= 0, "Short landscape overview stays inside the screen")
	_expect(not hud.get_node("Heading").get_rect().intersects(hud.get_node("DirectionPad").get_rect()), "Short landscape title and direction pad do not overlap")
	_expect(hud.get_node("NearbyActions").size.x == 211 and hud.get_node("NearbyActions").position.y == 72, "Short landscape restores the source right-panel geometry")
	root.size = Vector2i(568, 320)
	await process_frame
	await process_frame
	var top_level_inside := true
	for child in hud.get_children():
		if child is Control and child.visible:
			var bounds: Rect2 = child.get_rect()
			top_level_inside = top_level_inside and bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= 569 and bounds.end.y <= 321
	_expect(top_level_inside, "Tiny landscape keeps every top-level HUD control inside the viewport")
	_expect(hud.get_node("Heading").size.x <= 200 and hud.get_node("NearbyActions").size.x <= 170, "Tiny landscape uses compact paper panels")
	_expect(not hud.get_node("Heading").get_rect().intersects(Rect2(180.88, 74.44, 69.92, 92)), "Tiny landscape title stays clear of the strictest character protection rectangle")
	world.level.id = "3-4"
	world.level.title = "沉睡的守护者"
	hud.update_state(world)
	for settle_frame in 8:
		await process_frame
	_expect(hud._title.get_line_count() == 1, "The longest authored title remains on one line in the narrower tiny-landscape card: %s" % {"lines": hud._title.get_line_count(), "width": hud._title.size.x, "text_width": hud._title.get_theme_font("font").get_string_size(hud._title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hud._title.get_theme_font_size("font_size")).x})
	world.level.id = "1-1"
	world.level.title = "初生的孢子"
	hud.update_state(world)
	var tiny_tool_contained := true
	var tiny_tools: Rect2 = hud.get_node("JourneyTools").get_global_rect()
	for tiny_button in _buttons(hud.get_node("JourneyTools")):
		if tiny_button.visible:
			tiny_tool_contained = tiny_tool_contained and tiny_tools.encloses(tiny_button.get_global_rect())
	_expect(tiny_tool_contained, "Tiny landscape paper toolbar encloses the actual button minimum heights")
	_expect(not hud.get_node("DirectionPad").get_rect().intersects(hud.get_node("JourneyTools").get_rect()), "Tiny landscape directions do not overlap the toolbar")
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	var actor_switch := _find_contains(_buttons(hud), "换手")
	_expect(actor_switch.get_rect().end.y <= actor_switch.get_parent().size.y + 1, "Tall portrait icons do not expand dual-character buttons out of the toolbar")
	var levels := [{"id": "1-1", "title": "一"}, {"id": "1-2", "title": "二"}, {"id": "1-3", "title": "三"}]
	hud.show_menu(levels, {"records": {"1-1": {"completed": true}}})
	buttons = _buttons(hud)
	_expect(not _find_contains(buttons, "1-2").disabled, "Completing the previous level unlocks the next")
	_expect(_find_contains(buttons, "1-3").disabled, "Later levels remain locked")
	hud.show_menu(levels, {"unlock_all": true})
	_expect(not _find_contains(_buttons(hud), "1-3").disabled, "Explicit QA unlock enables representative levels")
	hud.show_settings({"bgm": 0.35, "sfx": 0.6, "ambient": 0.25})
	_expect(hud.is_modal_open() and _events.has("pause"), "Settings pauses through the coordinator signal")
	var toggles: Array = hud.find_children("*", "CheckButton", true, false)
	var continuous: CheckButton
	var safe_camera: CheckButton
	for toggle: CheckButton in toggles:
		if toggle.text == "按住方向键连续行走":
			continuous = toggle
		elif toggle.text == "镜头避开界面面板":
			safe_camera = toggle
	_expect(continuous != null and safe_camera != null and not continuous.button_pressed and not safe_camera.button_pressed, "Two experience experiments are independently visible and disabled by default")
	if continuous != null:
		continuous.button_pressed = true
	_expect(not _settings_events.is_empty() and _settings_events[-1].get("continuousInput", false) and not _settings_events[-1].get("safeCamera", false), "Enabling continuous movement leaves camera framing unchanged")
	hud.show_ending(world, {"collected": 2, "total": 3})
	var next := _find_contains(_buttons(hud), "去下一片")
	_expect(next != null, "Completion accepts numeric collected stats")
	if next != null:
		next.pressed.emit()
	_expect(_events.has("next") and _events.has("resume"), "Next action closes the modal and emits navigation")
	hud.show_journal(levels, {"records": {"1-1": {"completed": true}}})
	_expect(_find_contains(_buttons(hud), "看看修复后的花园") == null, "A record without a completion snapshot has no fabricated revisit action")
	hud.show_journal(levels, {"records": {"1-1": {"completed": true}}, "memories": {"1-1": {"completed": true}}})
	var review := _find_contains(_buttons(hud), "看看修复后的花园")
	_expect(review != null, "A real completion memory enables revisit")
	if review != null:
		review.pressed.emit()
	_expect(_events.has("review:1-1"), "Revisit identifies the preserved completion level")
	var catalog: Script = load("res://ui/gallery_catalog.gd")
	_expect(catalog.ITEMS.size() == 8, "Gallery retains all eight original entries")
	_expect(catalog.unlocked(catalog.ITEMS[0], {"mainline": {"records": {"1-1": {"completed": true}}}}), "Mainline records derive the original gallery reward")
	_expect(not catalog.unlocked(catalog.ITEMS[7], {"mainline": {"records": {}}}), "Unseen gallery entries stay locked")
	hud.show_gallery({"mainline": {"records": {"1-1": {"completed": true}}}})
	_expect(_find_contains(_buttons(hud), "读一段微光故事") != null, "Unlocked gallery entries expose their retained story")
	hud.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "service_hud", "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _safe_from_hud(hud: Control) -> bool:
	var safe: Rect2 = hud.safe_world_rect()
	if not safe.has_area():
		return false
	for node_name in ["Heading", "NearbyActions", "JourneyTools", "JourneyMessage", "DirectionPad", "Overview"]:
		var node: Control = hud.get_node(node_name)
		if node.visible and safe.intersects(node.get_rect().grow(11)):
			return false
	return true


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


func _find(buttons: Array[Button], text: String) -> Button:
	for button in buttons:
		if button.text == text:
			return button
	return null


func _find_contains(buttons: Array[Button], text: String) -> Button:
	for button in buttons:
		if button.text.contains(text):
			return button
	return null


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error(description)
