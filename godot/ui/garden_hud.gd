extends Control
class_name GardenHUD

signal command_requested(command: String)
signal level_requested(level_id: String)
signal settings_changed(settings: Dictionary)
signal menu_requested()

const INK := Color("786448")
const MUTED := Color("8c7858")
const PAPER := Color("fff5e4")
const LINE := Color("e8cfa8")
const ACCENT := Color("92734c")
const GalleryCatalog := preload("res://ui/gallery_catalog.gd")

var _built := false
var _heading: PanelContainer
var _panel: PanelContainer
var _tools: PanelContainer
var _message_panel: PanelContainer
var _title: Label
var _rule: Label
var _status: Label
var _score: Label
var _message: Label
var _commands: VBoxContainer
var _tool_grid: Control
var _nav: HBoxContainer
var _overlay: Control
var _tool_buttons: Array[Button] = []
var _last_command_key := ""
var _world: Variant
var _settings: Dictionary = {}
var _locked := false
var _repository: Variant
var _import_candidate: Dictionary = {}
var _paper_texture: Texture2D
var _ornament_texture: Texture2D
var _inner_trim: StyleBoxFlat
var _pad: GridContainer
var _overview: Button
var _follow: Button
var _direction_buttons: Array[Button] = []
var _journey_count: Label
var _journey_steps: HFlowContainer
var _journey_next: Label
var _journey_key := ""
var _chapter_label: Label
var _short_landscape := false
var _heading_content: VBoxContainer
var _journey_step_count := 0
var _feedback_key := ""
var _journey_labels: Array[Control] = []
var _current_journey_step := -1
var _panel_header: HBoxContainer
var _panel_separator: HSeparator
var _score_row: HBoxContainer


func _ready() -> void:
	setup()


func setup() -> void:
	if _built:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper_texture = _texture("res://assets/images/gallery-journal/paper-texture.jpg")
	_ornament_texture = _texture("res://assets/images/material-ready/panel-paper.png")
	_inner_trim = StyleBoxFlat.new()
	_inner_trim.bg_color = Color(0, 0, 0, 0)
	_inner_trim.border_color = Color("e6c69d85")
	_inner_trim.set_border_width_all(1)
	_inner_trim.set_corner_radius_all(20)
	theme = _paper_theme()
	_heading = _paper_panel(self)
	_heading.name = "Heading"
	var heading_scroll := ScrollContainer.new()
	heading_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_heading.add_child(heading_scroll)
	var heading_box := _column(heading_scroll)
	_heading_content = heading_box
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_box.add_theme_constant_override("separation", 8)
	_chapter_label = _label("苔藓山谷 · MOSS & BLOOM", 11, MUTED)
	heading_box.add_child(_chapter_label)
	_title = _label("微光苔原", 23)
	heading_box.add_child(_title)
	_rule = _label("把一粒微光，种成回家的路。", 12, MUTED)
	heading_box.add_child(_rule)
	heading_box.add_child(HSeparator.new())
	_journey_count = _label("修复旅程", 11, MUTED)
	heading_box.add_child(_journey_count)
	_journey_steps = HFlowContainer.new()
	_journey_steps.add_theme_constant_override("h_separation", 3)
	_journey_steps.add_theme_constant_override("v_separation", 3)
	heading_box.add_child(_journey_steps)
	_panel = _paper_panel(self)
	_panel.name = "NearbyActions"
	var panel_scroll := ScrollContainer.new()
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(panel_scroll)
	var panel_box := _column(panel_scroll)
	panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel_header := HBoxContainer.new()
	_panel_header = panel_header
	panel_box.add_child(panel_header)
	var panel_title := _label("此刻可以做", 15)
	panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_header.add_child(panel_title)
	_follow = _button("同行")
	_follow.custom_minimum_size.x = 54
	_compact_button(_follow)
	_follow.toggle_mode = true
	_follow.add_theme_font_size_override("font_size", 11)
	_follow.pressed.connect(func() -> void: command_requested.emit("follow"))
	panel_header.add_child(_follow)
	_status = _label("露薇", 12, MUTED)
	panel_box.add_child(_status)
	_panel_separator = HSeparator.new()
	panel_box.add_child(_panel_separator)
	_commands = VBoxContainer.new()
	_commands.add_theme_constant_override("separation", 8)
	panel_box.add_child(_commands)
	var score_row := HBoxContainer.new()
	_score_row = score_row
	score_row.add_theme_constant_override("separation", 7)
	var spore_icon := TextureRect.new()
	spore_icon.texture = _texture("res://assets/images/material-ready/icon-spore.png")
	spore_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spore_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spore_icon.custom_minimum_size = Vector2(26, 26)
	spore_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.add_child(spore_icon)
	_score = _label("0 / 0   沿途收集", 13)
	_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(_score)
	panel_box.add_child(score_row)
	_journey_next = _label("", 11, MUTED)
	panel_box.add_child(_journey_next)
	_tools = _paper_panel(self, "tools")
	_tools.name = "JourneyTools"
	_tool_grid = Control.new()
	_tool_grid.resized.connect(_layout_tool_buttons)
	_tools.add_child(_tool_grid)
	for pair in [["返回", "menu"], ["退回一格 · Z", "undo"], ["行走", "mode"], ["播种 / 互动 · E", "primary"], ["换手 · T", "switch"], ["跳跃", "jump"], ["提示 · H", "hint"], ["重来", "restart"]]:
		var action := String(pair[1])
		var button := _button(String(pair[0]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			if action == "menu":
				menu_requested.emit()
			else:
				command_requested.emit(action))
		button.set_meta("action", action)
		var icon_path := String({"menu": "material-ready/icon-back.png", "undo": "material-ready/icon-undo.png", "mode": "material-ready/icon-roll.png", "primary": "material-ready/icon-sow.png", "switch": "character-refined/portrait-front.png", "jump": "character-refined/jump.png", "hint": "material-ready/icon-hint.png", "restart": "material-ready/icon-retry.png"}.get(action, ""))
		_set_button_icon(button, "res://assets/images/" + icon_path, true)
		_tool_grid.add_child(button)
		_tool_buttons.append(button)
	_message_panel = _paper_panel(self, "message")
	_message_panel.name = "JourneyMessage"
	_message = _label("", 12)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var message_scroll := ScrollContainer.new()
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_scroll.add_child(_message)
	_message_panel.add_child(message_scroll)
	_message_panel.visible = false
	_nav = HBoxContainer.new()
	_nav.add_theme_constant_override("separation", 8)
	add_child(_nav)
	var pause_button := _button("Ⅱ")
	pause_button.tooltip_text = "暂停与设置"
	_set_button_icon(pause_button, "res://assets/images/material-ready/icon-pause.png")
	pause_button.pressed.connect(func() -> void: command_requested.emit("settings"))
	_nav.add_child(pause_button)
	var map_button := _button("地图")
	_set_button_icon(map_button, "res://assets/images/material-ready/icon-map.png")
	map_button.pressed.connect(func() -> void: menu_requested.emit())
	_nav.add_child(map_button)
	_pad = GridContainer.new()
	_pad.name = "DirectionPad"
	_pad.columns = 3
	_pad.add_theme_constant_override("h_separation", 2)
	_pad.add_theme_constant_override("v_separation", 2)
	add_child(_pad)
	for direction in ["", "up", "", "left", "", "right", "", "down", ""]:
		if String(direction).is_empty():
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(42, 42)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pad.add_child(spacer)
		else:
			var dir := String(direction)
			var button := _button(String({"up": "↑", "right": "→", "down": "↓", "left": "←"}[dir]))
			button.custom_minimum_size = Vector2(42, 42)
			button.tooltip_text = String({"up": "向前一格", "right": "向右一格", "down": "向后一格", "left": "向左一格"}[dir])
			button.pressed.connect(func() -> void: command_requested.emit("dir:" + dir))
			_compact_button(button)
			_pad.add_child(button)
			_direction_buttons.append(button)
	_overview = _button("全景")
	_overview.name = "Overview"
	_overview.toggle_mode = true
	_overview.pressed.connect(func() -> void: command_requested.emit("overview"))
	_set_button_icon(_overview, "res://assets/images/material-ready/icon-map.png")
	add_child(_overview)
	_built = true
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


func update_state(world: Variant, locked: bool = false, message: String = "") -> void:
	setup()
	_world = world
	_locked = locked
	if world == null:
		return
	var level: Dictionary = world.level
	var state: Dictionary = world.state
	_chapter_label.text = String({"valley": "苔藓山谷 · MOSS & BLOOM", "pond": "雨滴池塘 · RAIN & RIPPLE", "cave": "星光洞穴 · LIGHT & SHADOW"}.get(level.get("chapter", "valley"), "微光苔原 · SPORELIGHT"))
	_title.text = "%s · %s" % [level.get("id", ""), level.get("title", "微光苔原")]
	_rule.text = String(level.get("rule", ""))
	var actor := String(state.get("active", "luvie"))
	_status.text = "露薇" if actor == "luvie" else "小苔灵"
	_follow.visible = bool(level.get("dual", false))
	_follow.disabled = locked
	_follow.button_pressed = bool(state.get("follow", false))
	_follow.text = "同行" if state.get("follow", false) else "等候"
	if not level.get("roots", []).is_empty():
		var used := 0
		var budget := 0
		for root in level.get("roots", []):
			budget += int(root.get("budget", 0))
			used += state.get("growth", {}).get(root.get("id", ""), []).size()
		_status.text += " · 芽节余 %s" % maxi(0, budget - used)
	for item_id in state.get("items", {}):
		var item: Dictionary = state.items[item_id]
		if item.get("holder", "") == actor:
			_status.text += " · 带着%s" % _item_label(String(item_id))
	_score.text = "%d / %d   沿途收集" % [state.get("collected", []).size(), int(level.get("total", 0))]
	var commands: Array = world.commands()
	var command_key := JSON.stringify(commands) + str(locked)
	if command_key != _last_command_key:
		_last_command_key = command_key
		_feedback_key = ""
		for child in _commands.get_children():
			_commands.remove_child(child)
			child.queue_free()
		var local_index := 0
		for index in commands.size():
			var entry: Dictionary = commands[index]
			var command_id := String(entry.get("id", ""))
			if command_id == "switch":
				continue
			var prefix := ""
			if command_id != "follow":
				local_index += 1
				prefix = "%s  " % local_index
			var button := _button(prefix + String(entry.get("label", command_id)))
			_compact_button(button)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.disabled = locked
			button.set_meta("command_id", command_id)
			button.set_meta("base_label", button.text)
			if entry.has("selected"):
				button.toggle_mode = true
				button.button_pressed = bool(entry.selected)
			button.pressed.connect(func() -> void: command_requested.emit(command_id))
			_commands.add_child(button)
		if _commands.get_child_count() == 0:
			_commands.add_child(_label("走近根台、物件或庭院中心，\n看看此刻可以做什么。", 12, MUTED))
	for button in _tool_buttons:
		var action := String(button.get_meta("action"))
		button.disabled = locked and action != "menu"
		if action == "switch":
			button.visible = bool(level.get("dual", false))
		if action == "undo" and world.has_method("can_undo"):
			button.disabled = locked or not world.can_undo()
	for button in _direction_buttons:
		button.disabled = locked
	if not message.is_empty():
		set_message(message)
	_layout()


func set_action_label(action: String, text: String) -> void:
	for button in _tool_buttons:
		if String(button.get_meta("action")) == action:
			button.text = text
			button.set_meta("default_tooltip", text)
			button.tooltip_text = String(button.get_meta("condition_reason", "")) if not String(button.get_meta("condition_reason", "")).is_empty() else text


func set_action_feedback(primary_id: String, states: Dictionary) -> void:
	setup()
	var key := primary_id + JSON.stringify(states) + str(_locked)
	if key == _feedback_key:
		return
	_feedback_key = key
	for node in _commands.get_children():
		if not node is Button:
			continue
		var id := String(node.get_meta("command_id", ""))
		var state: Dictionary = states.get(id, {"available": true, "reason": ""})
		var available := bool(state.get("available", true))
		node.text = String(node.get_meta("base_label", node.text)) + ("" if available else " ·")
		node.tooltip_text = "" if available else String(state.get("reason", ""))
		_action_styles(node, available, id == primary_id)
	for button in _tool_buttons:
		if button.get_meta("action") == "primary":
			var state: Dictionary = states.get(primary_id, {"available": false, "reason": "走近根台、物件或庭院中心。"})
			var available := bool(state.get("available", false))
			_action_styles(button, available, not primary_id.is_empty())
			var reason := "" if available else String(state.get("reason", ""))
			button.set_meta("condition_reason", reason)
			button.tooltip_text = reason if not reason.is_empty() else String(button.get_meta("default_tooltip", button.text))


func _action_styles(button: Button, available: bool, primary: bool) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var background := Color("f7e8cf")
		if primary and available:
			background = Color("f2dfbd")
		elif not available:
			background = Color("fff6e8")
		if state_name == "hover":
			background = Color("fffaf0")
		elif state_name == "pressed":
			background = Color("e7d1ab")
		elif state_name == "disabled":
			background = Color("f3ebdf")
		var style := _paper_style(background, 12)
		style.border_color = Color("c6a170") if primary and available else LINE
		style.set_border_width_all(2 if primary and available else 1)
		style.content_margin_left = 5
		style.content_margin_right = 5
		style.content_margin_top = 9 if state_name == "pressed" else 7
		style.content_margin_bottom = 5 if state_name == "pressed" else 7
		style.shadow_size = 0 if state_name == "pressed" else 3
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_color_override("font_color", INK if available else MUTED)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)


func set_journey(journey: Dictionary) -> void:
	setup()
	var key := JSON.stringify(journey)
	if key == _journey_key:
		return
	_journey_key = key
	_journey_count.text = "修复旅程  ·  %d / %d" % [int(journey.get("done", 0)), int(journey.get("total", journey.get("steps", []).size()))]
	_journey_next.text = String(journey.get("next", ""))
	for child in _journey_steps.get_children():
		_journey_steps.remove_child(child)
		child.queue_free()
	var steps: Array = journey.get("steps", [])
	_journey_step_count = steps.size()
	_current_journey_step = int(journey.get("current", -1))
	_journey_labels.clear()
	for index in steps.size():
		var step: Dictionary = steps[index]
		var done := bool(step.get("done", false))
		var current := index == int(journey.get("current", -1))
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chip_style := _paper_style(Color("f7e8cf") if current else Color(0, 0, 0, 0), 5)
		chip_style.set_content_margin_all(4)
		chip_style.shadow_size = 0
		chip_style.set_border_width_all(1 if current else 0)
		chip.add_theme_stylebox_override("panel", chip_style)
		var label := _label("%s %s" % ["✓" if done else "%02d" % (index + 1), step.get("label", "")], 10, ACCENT if current else MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chip.custom_minimum_size.x = minf(130, label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8)
		chip.add_child(label)
		_journey_steps.add_child(chip)
		_journey_labels.append(chip)
	_layout()


func set_overview(value: bool) -> void:
	setup()
	_overview.button_pressed = value
	_overview.text = "跟随" if value else "全景"


func set_message(text: String) -> void:
	setup()
	_message.text = text
	_message_panel.visible = not text.is_empty()
	_layout()


func layout_regions() -> Array[Dictionary]:
	setup()
	var regions: Array[Dictionary] = []
	if is_instance_valid(_overlay) and _overlay.is_visible_in_tree():
		var overlay_rect := _overlay.get_global_rect()
		return [{"name": "ModalOverlay", "rect": [overlay_rect.position.x, overlay_rect.position.y, overlay_rect.size.x, overlay_rect.size.y]}]
	for entry in [["Heading", _heading], ["NearbyActions", _panel], ["JourneyTools", _tools], ["JourneyMessage", _message_panel], ["Navigation", _nav], ["DirectionPad", _pad], ["Overview", _overview]]:
		var control: Control = entry[1]
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		regions.append({"name": String(entry[0]), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	return regions


func safe_world_rect() -> Rect2:
	setup()
	var viewport_size := get_viewport_rect().size
	var free: Array[Rect2] = [Rect2(Vector2(14, 14), viewport_size - Vector2(28, 28))]
	for blocker in [_heading, _panel, _tools, _message_panel, _nav, _pad, _overview]:
		if not blocker.visible:
			continue
		var blocked: Rect2 = blocker.get_rect().grow(12)
		var next: Array[Rect2] = []
		for available in free:
			if not available.intersects(blocked):
				next.append(available)
				continue
			var cut := available.intersection(blocked)
			var candidates: Array[Rect2] = [
				Rect2(available.position, Vector2(available.size.x, cut.position.y - available.position.y)),
				Rect2(Vector2(available.position.x, cut.end.y), Vector2(available.size.x, available.end.y - cut.end.y)),
				Rect2(Vector2(available.position.x, cut.position.y), Vector2(cut.position.x - available.position.x, cut.size.y)),
				Rect2(Vector2(cut.end.x, cut.position.y), Vector2(available.end.x - cut.end.x, cut.size.y))]
			for candidate in candidates:
				if candidate.size.x > 0 and candidate.size.y > 0:
					next.append(candidate)
		free = next
	var best := Rect2(Vector2(20, 20), Vector2(maxf(80, viewport_size.x - 40), maxf(80, viewport_size.y - 40)))
	var best_area := -1.0
	for available in free:
		var area := available.get_area()
		if area > best_area:
			best = available
			best_area = area
	return best


func show_menu(levels: Array, progress: Dictionary = {}) -> void:
	var box := _open_overlay("微光苔原 · SPORELIGHT")
	box.add_child(_label("把一粒微光，种成回家的路。", 17, MUTED))
	box.add_child(_label("探索 · 播种 · 共生", 12, MUTED))
	for index in levels.size():
		var level: Dictionary = levels[index]
		var id := String(level.get("id", ""))
		var completed := bool(progress.get("records", {}).get(id, {}).get("completed", false))
		var previous_id := String(levels[index - 1].get("id", "")) if index > 0 else ""
		var unlocked := index == 0 or completed or bool(progress.get("unlock_all", false)) or bool(progress.get("records", {}).get(previous_id, {}).get("completed", false))
		var button := _button("%s  %s%s" % [id, level.get("title", ""), " · 已修复" if completed else ("" if unlocked else " · 尚未苏醒")])
		button.disabled = not unlocked
		button.pressed.connect(func() -> void:
			close_overlay()
			level_requested.emit(id))
		box.add_child(button)
	var settings_button := _button("设置")
	settings_button.pressed.connect(func() -> void: show_settings(_settings))
	box.add_child(settings_button)
	var journal_button := _button("花园纪事")
	journal_button.pressed.connect(func() -> void: show_journal(levels, progress))
	box.add_child(journal_button)
	var gallery_button := _button("图鉴")
	gallery_button.pressed.connect(func() -> void: show_gallery(_repository.data if _repository != null else {"mainline": progress}))
	box.add_child(gallery_button)
	if _repository != null:
		var saves_button := _button("导入 / 导出旅程")
		saves_button.pressed.connect(func() -> void: show_save_tools(_repository))
		box.add_child(saves_button)
	var resume := _button("回到花园")
	resume.pressed.connect(close_overlay)
	box.add_child(resume)


func show_settings(settings: Dictionary = {}) -> void:
	_settings = settings.duplicate(true)
	var box := _open_overlay("暂停与设置")
	for item in [["bgm", "音乐"], ["sfx", "音效"], ["ambient", "环境声"]]:
		var key := String(item[0])
		box.add_child(_label(String(item[1]), 13))
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = float(_settings.get(key, {"bgm": 0.35, "sfx": 0.6, "ambient": 0.25}.get(key, 0.5)))
		slider.custom_minimum_size.y = 28
		slider.value_changed.connect(func(value: float) -> void:
			_settings[key] = value
			settings_changed.emit(_settings.duplicate(true)))
		box.add_child(slider)
	for item in [["lowMotion", "低动态"], ["dynamicLight", "柔和光效"], ["particles", "环境粒子"], ["continuousInput", "按住方向键连续行走"], ["safeCamera", "镜头避开界面面板"]]:
		var key := String(item[0])
		var toggle := CheckButton.new()
		toggle.text = String(item[1])
		toggle.button_pressed = bool(_settings.get(key, key in ["dynamicLight", "particles"]))
		toggle.toggled.connect(func(value: bool) -> void:
			_settings[key] = value
			settings_changed.emit(_settings.duplicate(true)))
		box.add_child(toggle)
	var back := _button("回到花园")
	back.pressed.connect(close_overlay)
	box.add_child(back)


func set_repository(repository: Variant) -> void:
	_repository = repository


func show_save_tools(repository: Variant) -> void:
	_repository = repository
	_import_candidate = {}
	var box := _open_overlay("保存这段旅程")
	box.add_child(_label("导出旅程可以备份进度，或带到另一台设备。导入前会先检查并显示内容。", 13, MUTED))
	var text := TextEdit.new()
	text.custom_minimum_size = Vector2(0, 140)
	text.placeholder_text = "将旅程 JSON 粘贴在这里，或选择文件。"
	box.add_child(text)
	var status := _label("当前进度尚未改变。", 12, MUTED)
	box.add_child(status)
	var confirm := _button("确认导入")
	confirm.disabled = true
	var show_preview := func(result: Dictionary) -> void:
		_import_candidate = {}
		confirm.disabled = true
		if not result.get("ok", false):
			status.text = "无法读取这份旅程，当前进度没有改变。"
			return
		if result.get("duplicate", false):
			status.text = "这份旅程已经导入，无需重复保存。"
			return
		_import_candidate = result.data.duplicate(true)
		var mainline: Dictionary = _import_candidate.mainline
		status.text = "检查通过：%s 条记录、%s 段进行中旅程、%s 份完成纪念。确认后保存，较好的成绩会保留。" % [mainline.records.size(), mainline.runs.size(), mainline.memories.size()]
		confirm.disabled = false
	var preview := _button("检查粘贴的旅程")
	preview.pressed.connect(func() -> void: show_preview.call(repository.preview_import_json(text.text)))
	box.add_child(preview)
	if OS.has_feature("web"):
		var old_save := _button("读取本网站的旧旅程（先预览）")
		old_save.pressed.connect(func() -> void: show_preview.call(repository.read_web_legacy_preview()))
		box.add_child(old_save)
	else:
		var choose_file := _button("选择旅程 JSON 文件")
		choose_file.pressed.connect(func() -> void:
			var dialog := FileDialog.new()
			dialog.access = FileDialog.ACCESS_FILESYSTEM
			dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			dialog.filters = PackedStringArray(["*.json ; 旅程 JSON"])
			_overlay.add_child(dialog)
			dialog.file_selected.connect(func(source: String) -> void:
				show_preview.call(repository.preview_import_file(source))
				dialog.queue_free())
			dialog.canceled.connect(dialog.queue_free)
			dialog.popup_centered_ratio(0.8))
		box.add_child(choose_file)
	confirm.pressed.connect(func() -> void:
		if _import_candidate.is_empty():
			return
		var result: Dictionary = repository.persist(_import_candidate)
		status.text = "旅程已导入。返回地图后可以继续。" if result.get("ok", false) else "这次未能保存，当前旅程没有被替换。"
		if result.get("ok", false):
			_import_candidate = {}
			confirm.disabled = true
			command_requested.emit("save_imported"))
	box.add_child(confirm)
	var export_button := _button("导出当前旅程")
	export_button.pressed.connect(func() -> void:
		text.text = repository.export_json()
		if OS.has_feature("web"):
			repository.download_web_export()
			status.text = "旅程已准备下载，也可以复制上方的 JSON。"
		else:
			var dialog := FileDialog.new()
			dialog.access = FileDialog.ACCESS_FILESYSTEM
			dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			dialog.current_file = "sporelight-save.json"
			dialog.filters = PackedStringArray(["*.json ; 旅程 JSON"])
			_overlay.add_child(dialog)
			dialog.file_selected.connect(func(target: String) -> void:
				var result: Dictionary = repository.export_file(target)
				status.text = "旅程已导出。" if result.get("ok", false) else "未能导出，请换一个保存位置。"
				dialog.queue_free())
			dialog.canceled.connect(dialog.queue_free)
			dialog.popup_centered_ratio(0.8))
	box.add_child(export_button)
	var back := _button("回到花园")
	back.pressed.connect(close_overlay)
	box.add_child(back)


func show_ending(world: Variant, stats: Dictionary = {}) -> void:
	var level: Dictionary = world if world is Dictionary else world.level
	var snapshot: Dictionary = stats if not stats.is_empty() else ({} if world is Dictionary else world.state)
	var collected: Variant = snapshot.get("collected", [])
	var count: int = collected.size() if collected is Array else int(collected)
	var box := _open_overlay("这里，又可以成为家。")
	box.add_child(_label(String(level.get("story", "这片花园，因你而安定。")), 16))
	box.add_child(_label("%d / %d 粒微光已收集 · 纪事已点亮" % [count, int(snapshot.get("total", level.get("total", 0)))], 13, MUTED))
	var next := _button("去下一片微光 ↗")
	next.pressed.connect(func() -> void:
		close_overlay()
		command_requested.emit("next"))
	box.add_child(next)
	var stay := _button("留下看看")
	stay.pressed.connect(func() -> void:
		close_overlay()
		command_requested.emit("stay"))
	box.add_child(stay)
	var back := _button("返回地图")
	back.pressed.connect(func() -> void:
		close_overlay()
		menu_requested.emit())
	box.add_child(back)


func show_journal(levels: Array, progress: Dictionary = {}) -> void:
	var box := _open_overlay("花园纪事")
	box.add_child(_label("每一次帮助，都在这里留下了一页。", 13, MUTED))
	for level in levels:
		var id := String(level.get("id", ""))
		var earned := bool(progress.get("records", {}).get(id, {}).get("completed", false))
		box.add_child(_label("%s · %s" % [id, level.get("title", "")], 17))
		box.add_child(_label(String(level.get("story", "")) if earned else "这片花园还在等你慢慢发现。", 13, MUTED))
		if earned and progress.get("memories", {}).has(id) and progress.memories[id].get("completed", false):
			var review := _button("看看修复后的花园")
			review.pressed.connect(func() -> void:
				close_overlay()
				command_requested.emit("review:" + id))
			box.add_child(review)
	var back := _button("回到花园")
	back.pressed.connect(close_overlay)
	box.add_child(back)


func show_gallery(store: Dictionary = {}, category: String = "全部") -> void:
	var box := _open_overlay("微光图鉴")
	box.add_child(_label("每一种生命，都有自己的微光。", 13, MUTED))
	var categories := HBoxContainer.new()
	box.add_child(categories)
	for category_name in GalleryCatalog.CATEGORIES:
		var selected := String(category_name)
		var filter_button := _button(selected)
		filter_button.toggle_mode = true
		filter_button.button_pressed = selected == category
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_compact_button(filter_button)
		filter_button.pressed.connect(func() -> void: show_gallery(store, selected))
		categories.add_child(filter_button)
	for item in GalleryCatalog.ITEMS:
		if category != "全部" and item.category != category:
			continue
		var unlocked := GalleryCatalog.unlocked(item, store)
		box.add_child(HSeparator.new())
		box.add_child(_label(String(item.title) if unlocked else "尚未相遇的微光", 19))
		if unlocked:
			var picture := TextureRect.new()
			picture.texture = _texture("res://assets/images/" + String(item.image))
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.custom_minimum_size = Vector2(0, 150)
			box.add_child(picture)
			box.add_child(_label(String(item.habitat), 11, MUTED))
			box.add_child(_label(String(item.desc), 13))
			var story_button := _button("读一段微光故事")
			var entry: Dictionary = item.duplicate(true)
			story_button.pressed.connect(func() -> void: _show_gallery_story(entry, store, category))
			box.add_child(story_button)
		else:
			box.add_child(_label("在 %s 完成一次新的相遇。" % item.levels[0], 13, MUTED))
	var back := _button("回到花园")
	back.pressed.connect(close_overlay)
	box.add_child(back)


func _show_gallery_story(item: Dictionary, store: Dictionary, category: String) -> void:
	var box := _open_overlay(String(item.title))
	var name_value := String(store.get("player", {}).get("name", "露薇"))
	for paragraph in item.story:
		box.add_child(_label(String(paragraph).replace("{name}", name_value), 15))
	box.add_child(_label(String(item.poem), 14, ACCENT))
	var back := _button("返回图鉴")
	back.pressed.connect(func() -> void: show_gallery(store, category))
	box.add_child(back)


func close_overlay() -> void:
	if is_instance_valid(_overlay):
		remove_child(_overlay)
		_overlay.queue_free()
	_overlay = null
	command_requested.emit("resume")


func is_modal_open() -> bool:
	return is_instance_valid(_overlay)


func _open_overlay(title: String) -> VBoxContainer:
	setup()
	if is_instance_valid(_overlay):
		remove_child(_overlay)
		_overlay.queue_free()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.17, 0.14, 0.52)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var paper := _paper_panel(center)
	paper.custom_minimum_size = Vector2(minf(560, get_viewport_rect().size.x - 28), minf(580, get_viewport_rect().size.y - 28))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = paper.custom_minimum_size - Vector2(42, 42)
	paper.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	box.add_child(_label(title, 25))
	command_requested.emit("pause")
	return box


func _layout() -> void:
	if not _built:
		return
	var extent := get_viewport_rect().size
	var narrow := extent.x < 650
	_short_landscape = extent.y <= 400 or (extent.y <= 560 and extent.x > extent.y)
	var tiny_landscape := _short_landscape and extent.x < 650
	var compact_portrait := extent.x <= 360 and extent.y <= 700 and not _short_landscape
	var phone_portrait := narrow and extent.y > extent.x and not compact_portrait and not _short_landscape
	var medium_height := extent.x >= 650 and extent.x <= 1050 and extent.y > 560 and extent.y <= 700
	_rule.visible = not compact_portrait and not phone_portrait and not tiny_landscape and not medium_height
	_journey_count.visible = not compact_portrait and not phone_portrait and not tiny_landscape and not medium_height
	_panel_header.visible = not compact_portrait
	_panel_separator.visible = not compact_portrait
	_status.visible = not compact_portrait
	_score_row.visible = not compact_portrait
	_journey_next.visible = not compact_portrait
	for index in _journey_labels.size():
		_journey_labels[index].visible = not (compact_portrait or phone_portrait or medium_height) or index == clampi(_current_journey_step, 0, maxi(0, _journey_labels.size() - 1))
	_pad.columns = 4 if compact_portrait else 3
	for button in _direction_buttons:
		button.custom_minimum_size = Vector2(44, 44) if compact_portrait or tiny_landscape else Vector2(42, 42)
	_pad.add_theme_constant_override("h_separation", 0 if tiny_landscape else 2)
	_pad.add_theme_constant_override("v_separation", 0 if tiny_landscape else 2)
	for child in _pad.get_children():
		if not child is Button:
			child.visible = not compact_portrait
	if compact_portrait:
		var order := ["↑", "←", "↓", "→"]
		for index in order.size():
			for button in _direction_buttons:
				if button.text == order[index]:
					_pad.move_child(button, index)
	else:
		# Restore the familiar cross after leaving the compact-only layout.
		var cross: Array = []
		for text in ["", "↑", "", "←", "", "→", "", "↓", ""]:
			for child in _pad.get_children():
				if child in cross:
					continue
				if (text.is_empty() and not child is Button) or (child is Button and child.text == text):
					cross.append(child)
					break
		for index in cross.size():
			_pad.move_child(cross[index], index)
	_heading_content.add_theme_constant_override("separation", 5 if _short_landscape or narrow else 8)
	_chapter_label.add_theme_font_size_override("font_size", 9 if _short_landscape or narrow else 11)
	_title.add_theme_font_size_override("font_size", 20 if narrow or _short_landscape else 23)
	_rule.add_theme_font_size_override("font_size", 11 if narrow else (10 if _short_landscape else 12))
	_journey_steps.visible = not _short_landscape
	_heading.position = Vector2(12, 12) if narrow else Vector2(24, 24)
	var extra_step_height := 26.0 if _journey_step_count > 3 else 0.0
	_heading.size = Vector2(minf(292, extent.x - 124), (185 if narrow else 235) + extra_step_height)
	_panel.position = Vector2(extent.x - 193, extent.y - 454) if narrow else Vector2(extent.x - 278, 108)
	var preferred_panel_height := 348.0 if _commands.get_child_count() <= 2 else _commands.get_child_count() * 52 + 270.0
	_panel.size = Vector2(181 if narrow else 254, 230 if narrow else minf(preferred_panel_height, maxf(348, extent.y - 230)))
	var tools_height := 144.0 if extent.x < 900 else 92.0
	if _short_landscape:
		tools_height = 74 if tiny_landscape else 70
	var visible_tools := 0
	for tool in _tool_buttons:
		if tool.visible:
			visible_tools += 1
	_tool_grid.custom_minimum_size.y = 44 if _short_landscape else (120 if extent.x < 900 else 60)
	_tools.position = Vector2(12, extent.y - tools_height - 20)
	_tools.size = Vector2(maxf(100, extent.x - 24), tools_height)
	if extent.x > 1050:
		var tool_width := 800.0 if visible_tools > 7 else 660.0
		_tools.position.x = (extent.x - tool_width) / 2
		_tools.size.x = tool_width
	_message_panel.position = Vector2(maxf(12, (extent.x - 570) / 2), _tools.position.y - 62)
	var natural_message_width := _message.get_theme_font("font").get_string_size(_message.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 36
	var message_width := minf(maxf(180, natural_message_width), minf(570, extent.x - 24))
	_message_panel.position.x = (extent.x - message_width) / 2
	_message_panel.size = Vector2(message_width, 46)
	_nav.position = Vector2(extent.x - 115, 20)
	_nav.size = Vector2(100, 44)
	_pad.position = Vector2(12 if narrow else 25, extent.y - 356 if extent.x <= 900 else extent.y - 172)
	_pad.size = Vector2(130, 130)
	_overview.position = Vector2(_pad.position.x, _pad.position.y - 65)
	_overview.size = Vector2(90, 44)
	var heading_style: StyleBox = _heading.get_theme_stylebox("panel").duplicate()
	heading_style.content_margin_left = 8 if tiny_landscape else 18
	heading_style.content_margin_right = 8 if tiny_landscape else 18
	heading_style.content_margin_top = 16 if _short_landscape else (23 if narrow else 34)
	heading_style.content_margin_bottom = 16 if _short_landscape else (27 if narrow else 36)
	_heading.add_theme_stylebox_override("panel", heading_style)
	var action_style: StyleBox = _panel.get_theme_stylebox("panel").duplicate()
	action_style.content_margin_top = 34
	action_style.content_margin_bottom = 10 if compact_portrait else 36
	_panel.add_theme_stylebox_override("panel", action_style)
	if _short_landscape:
		if tiny_landscape:
			var title_width := _title.get_theme_font("font").get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			_title.add_theme_font_size_override("font_size", 16 if title_width > 146 else 17)
		_heading.position = Vector2(10 if tiny_landscape else 14, 10)
		_heading.size = Vector2(170 if tiny_landscape else 238, 92 if tiny_landscape else 142)
		_panel.position = Vector2(extent.x - (180 if tiny_landscape else 225), 64 if tiny_landscape else 72)
		_panel.size = Vector2(170 if tiny_landscape else 211, maxf(90, extent.y - (154 if tiny_landscape else 165)))
		_tools.position = Vector2(8 if tiny_landscape else 12, extent.y - tools_height - (8 if tiny_landscape else 14))
		_tools.size = Vector2(extent.x - (16 if tiny_landscape else 24), tools_height)
		var compact_message_width := minf(180, maxf(100, extent.x - 260)) if tiny_landscape else maxf(180, extent.x - 462)
		_message_panel.position = Vector2((extent.x - compact_message_width) / 2, _tools.position.y - 42 if tiny_landscape else extent.y - 130)
		_message_panel.size = Vector2(compact_message_width, 38)
		_message.add_theme_font_size_override("font_size", 10)
		_pad.position = Vector2(10 if tiny_landscape else 15, _tools.position.y - 132 if tiny_landscape else maxf(15, extent.y - 225))
		if tiny_landscape:
			_pad.size = Vector2(132, 132)
		_overview.position = Vector2(extent.x - 216, 10 if tiny_landscape else 13)
		_overview.size = Vector2(90, 44)
		_nav.position = Vector2(extent.x - 115, 13)
	else:
		_message.add_theme_font_size_override("font_size", 12)
	if medium_height:
		# Keep the current objective while releasing the starting island below the title.
		_heading.size = Vector2(292, 142)
		_heading_content.add_theme_constant_override("separation", 5)
		_chapter_label.add_theme_font_size_override("font_size", 9)
		_title.add_theme_font_size_override("font_size", 20)
		var medium_heading_style: StyleBox = _heading.get_theme_stylebox("panel").duplicate()
		medium_heading_style.content_margin_top = 16
		medium_heading_style.content_margin_bottom = 20
		_heading.add_theme_stylebox_override("panel", medium_heading_style)
	if phone_portrait:
		_heading.position = Vector2(12, 12)
		_heading.size = Vector2(minf(292, extent.x - 124), 134)
		var phone_heading_style: StyleBox = _heading.get_theme_stylebox("panel").duplicate()
		phone_heading_style.content_margin_top = 20
		phone_heading_style.content_margin_bottom = 23
		_heading.add_theme_stylebox_override("panel", phone_heading_style)
		_panel.position = Vector2(extent.x - 193, 156)
		_panel.size = Vector2(181, 230)
		_pad.position = Vector2(12, 156)
		_overview.position = Vector2(12, 296)
	if compact_portrait:
		_title.add_theme_font_size_override("font_size", 17)
		_heading.position = Vector2(12, 12)
		_heading.size = Vector2(196, 112)
		var compact_heading_style: StyleBox = _heading.get_theme_stylebox("panel").duplicate()
		compact_heading_style.content_margin_top = 15
		compact_heading_style.content_margin_bottom = 18
		_heading.add_theme_stylebox_override("panel", compact_heading_style)
		_heading_content.add_theme_constant_override("separation", 4)
		var actor_right := extent.x * 0.38 + 8 * 0.92 + 38 * 0.92
		var card_width := minf(158, floorf(extent.x - 12 - actor_right - 4))
		_panel.position = Vector2(extent.x - 12 - card_width, 174)
		_panel.size = Vector2(card_width, 96)
		_pad.position = Vector2(12, maxf(334, _tools.position.y - 54))
		_pad.size = Vector2(182, 44)
		_overview.position = Vector2(extent.x - 106, 78)
		_message_panel.position = Vector2(12, 130)
		_message_panel.size = Vector2(extent.x - 24, 38)
		_message.add_theme_font_size_override("font_size", 10)
	_layout_tool_buttons.call_deferred()


func _layout_tool_buttons() -> void:
	if _tool_grid == null:
		return
	var visible: Array[Button] = []
	for button in _tool_buttons:
		if button.visible:
			visible.append(button)
	var narrow := get_viewport_rect().size.x < 900 and not _short_landscape
	for button in visible:
		var compact_height := 44 if _short_landscape else 60
		button.custom_minimum_size.y = compact_height
		button.add_theme_font_size_override("font_size", 10 if _short_landscape else 11)
		var icon_limit := 22.0 if _short_landscape else 28.0
		if button.icon != null:
			button.add_theme_constant_override("icon_max_width", int(minf(icon_limit, icon_limit * button.icon.get_width() / button.icon.get_height())))
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			var button_style: StyleBox = button.get_theme_stylebox(state_name).duplicate()
			var base_margin := 3 if _short_landscape else 7
			button_style.content_margin_top = base_margin + (2 if state_name == "pressed" else 0)
			button_style.content_margin_bottom = base_margin - (2 if state_name == "pressed" else 0)
			button.add_theme_stylebox_override(state_name, button_style)
	if narrow:
		var width := maxf(44, (_tool_grid.size.x - 21) / 4)
		for index in visible.size():
			visible[index].position = Vector2((index % 4) * (width + 7), (index / 4) * 60)
			visible[index].size = Vector2(width, 58)
	else:
		var weight := float(visible.size()) + 0.8
		var unit := maxf(44, (_tool_grid.size.x - 7 * max(0, visible.size() - 1)) / weight)
		var offset := 0.0
		for button in visible:
			var width := unit * (1.8 if button.get_meta("action") == "primary" else 1.0)
			button.position = Vector2(offset, 0)
			button.size = Vector2(width, 44 if _short_landscape else 60)
			offset += width + 7


func _paper_panel(parent: Node, kind: String = "card") -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _paper_style(PAPER, 42 if kind == "tools" else 24)
	if kind == "card":
		style.content_margin_top = 34
		style.content_margin_bottom = 36
	elif kind == "tools":
		style.content_margin_top = 8
		style.content_margin_bottom = 8
	else:
		style.content_margin_top = 10
		style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.set_meta("paper_kind", kind)
	panel.draw.connect(func() -> void: _draw_paper_surface(panel))
	parent.add_child(panel)
	return panel


func _draw_paper_surface(panel: PanelContainer) -> void:
	var extent := panel.size
	if extent.x < 20 or extent.y < 20:
		return
	if _paper_texture != null:
		panel.draw_texture_rect(_paper_texture, Rect2(Vector2(8, 8), extent - Vector2(16, 16)), true, Color(1, 1, 1, 0.18))
	var kind := String(panel.get_meta("paper_kind", "card"))
	var trim: StyleBoxFlat = _inner_trim.duplicate()
	trim.set_corner_radius_all(36 if kind == "tools" else 20)
	panel.draw_style_box(trim, Rect2(Vector2(5, 5), extent - Vector2(10, 10)))
	if _ornament_texture != null:
		# Exact source regions used by garden-journey.css, separated from resize.
		if kind != "message":
			panel.draw_texture_rect_region(_ornament_texture, Rect2((extent.x - 136) / 2, -6 if kind == "tools" else 6, 136, 24), Rect2(180, 16.6667, 226.6667, 40), Color(1, 1, 1, 0.9))
		if kind == "card":
			panel.draw_texture_rect_region(_ornament_texture, Rect2(7, extent.y - 47, 38, 40), Rect2(8.8889, 262.2222, 84.4444, 88.8889), Color(1, 1, 1, 0.82))
			panel.draw_texture_rect_region(_ornament_texture, Rect2(extent.x - 45, extent.y - 47, 38, 40), Rect2(500, 262.2222, 84.4444, 88.8889), Color(1, 1, 1, 0.82))


func _texture(resource: String) -> Texture2D:
	return load(resource) if ResourceLoader.exists(resource) else null


func _set_button_icon(button: Button, resource: String, above: bool = false) -> void:
	var icon := _texture(resource)
	if icon == null:
		return
	button.icon = icon
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", int(minf(28, 28.0 * icon.get_width() / icon.get_height())))
	_compact_button(button)
	if above:
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 11)
		button.custom_minimum_size.y = 60


func _compact_button(button: Button) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		# Buttons are not parented yet here. Reading their inherited style would
		# capture Godot's default dark theme permanently as a local override.
		var style: StyleBox = theme.get_stylebox(state_name, "Button").duplicate()
		style.content_margin_left = 5
		style.content_margin_right = 5
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		button.add_theme_stylebox_override(state_name, style)


func _column(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	return box


func _label(text: String, font_size: int = 13, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.theme = theme
	button.text = text
	button.custom_minimum_size = Vector2(44, 44)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _paper_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_top = 17
	style.content_margin_right = 18
	style.content_margin_bottom = 17
	style.shadow_color = Color(0.42, 0.32, 0.2, 0.12)
	style.shadow_size = 8
	return style


func _paper_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 13
	for font_path in ["res://assets/fonts/NotoSansSC-Variable.ttf", "res://assets/fonts/NotoSansSC-Regular.ttf", "res://assets/fonts/NotoSansCJKsc-Regular.otf"]:
		if ResourceLoader.exists(font_path):
			var variation := FontVariation.new()
			variation.base_font = load(font_path)
			variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 400.0}
			result.default_font = variation
			break
	if result.default_font == null and OS.has_feature("windows"):
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Microsoft YaHei", "SimSun"])
		result.default_font = system_font
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	for color_name in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		result.set_color(color_name, "Button", INK)
	result.set_color("font_disabled_color", "Button", Color("b3a38e"))
	result.set_stylebox("normal", "Button", _paper_style(Color("f7e8cf"), 12))
	result.set_stylebox("hover", "Button", _paper_style(Color("fffaf0"), 12))
	result.set_stylebox("pressed", "Button", _paper_style(Color("e6d2ad"), 12))
	result.set_stylebox("disabled", "Button", _paper_style(Color("f3ebdf"), 12))
	var focus := _paper_style(Color(0, 0, 0, 0), 12)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	result.set_stylebox("focus", "Button", focus)
	return result


func _item_label(id: String) -> String:
	if id.begins_with("mirror"):
		return "镜叶"
	return {"dew": "清露", "lamp": "暖灯", "bell": "门铃", "sunPost": "日影柱", "moonPost": "月影柱", "bug": "光虫"}.get(id, id)
