extends Control
class_name GardenHUD

signal command_requested(command: String)
signal level_requested(level_id: String)
signal settings_changed(settings: Dictionary)
signal menu_requested()
signal layout_changed()

const INK := Color("786448")
const MUTED := Color("8c7858")
const PAPER := Color("fff5e4")
const LINE := Color("e8cfa8")
const ACCENT := Color("92734c")
const GalleryCatalog := preload("res://ui/gallery_catalog.gd")
const Journey := preload("res://application/journey_view.gd")
const MenuCover := preload("res://ui/menu_cover.gd")
const MenuButtons := preload("res://ui/menu_button_styles.gd")
const ChapterMap := preload("res://ui/chapter_map.gd")
const GameHUDSkin := preload("res://ui/game_hud_skin.gd")
const FourthGuidance := preload("res://ui/fourth_garden_guidance.gd")

var _built := false
var _chrome_layout_pending := false
var _heading: PanelContainer
var _panel: PanelContainer
var _tools: PanelContainer
var _message_panel: PanelContainer
var _title: Label
var _rule: Label
var _status: Label
var _status_row: HBoxContainer
var _collection_count: Label
var _collection_icon: TextureRect
var _game_skin := GameHUDSkin.new()
var _score: Label
var _message: Label
var _hint_button: Button
var _hint_label: Label
var _inline_hint := false
var _commands: GridContainer
var _tool_grid: Control
var _nav: HBoxContainer
var _overlay: Control
var _overlay_paper: PanelContainer
var _overlay_scroll: ScrollContainer
var _map_frame: VBoxContainer
var _map_heading: Label
var _map_description: Label
var _chapter_map: Control
var _map_selection: Dictionary = {}
var _gallery_frame: VBoxContainer
var _gallery_heading: Label
var _gallery_description: Label
var _home_background: TextureRect
var _home_logo: TextureRect
var _home_cover: Control
var _game_interface_visible := true
var _tool_buttons: Array[Button] = []
var _last_command_key := ""
var _world: Variant
var _settings: Dictionary = {}
var _locked := false
var _busy := false
var _overview_available := true
var _message_refreshes := 0
var _message_tween: Tween
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
var _fourth_journey: Dictionary = {}
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
var _context_open := false
var _context_choices: Array = []
var _context_index := 0
var _context_title: Label
var _context_screen := Vector2(-1, -1)
var _primary_id := ""
var _touch_mode := false
var _message_remaining := 0.0
var _mole_conversation := FourthGuidance.new()
var _mole_message_active := false
var _fourth_default_message := false
var _guidance_level := ""
var _dialogue_proximity: Callable
var _interaction_label := "走近物件"
var _nearby_commands: Array = []
var _context_stick := Vector2.ZERO
var _context_repeat_remaining := 0.0
var _context_stick_step := 0
var _page_kind := ""
var _page_restore: Callable
var _page_stack: Array[Dictionary] = []
var _navigating_back := false
var _cloud_catalog: Array = []


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
	_inner_trim.border_color = Color("e6c69d65")
	_inner_trim.set_border_width_all(1)
	_inner_trim.set_corner_radius_all(12)
	theme = _paper_theme()
	_touch_mode = DisplayServer.is_touchscreen_available()
	_home_background = TextureRect.new()
	_home_background.name = "HomeBackground"
	_home_background.texture = _texture("res://assets/images/main/bg.png")
	_home_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_home_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_home_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home_background.visible = false
	add_child(_home_background)

	_heading = _paper_panel(self, "compact")
	_heading.name = "Heading"
	_heading_content = _column(_heading)
	_heading_content.add_theme_constant_override("separation", 4)
	_chapter_label = _label("", 10, MUTED)
	_chapter_label.visible = false
	_heading_content.add_child(_chapter_label)
	_title = _label("微光苔原", 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_heading_content.add_child(_title)
	_status = _label("露薇", 11, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_row = HBoxContainer.new()
	_status_row.name = "GardenStatusAndCollection"
	_status_row.add_theme_constant_override("separation", 5)
	_heading_content.add_child(_status_row)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_row.add_child(_status)
	_collection_icon = TextureRect.new()
	_collection_icon.name = "CollectionSpore"
	_collection_icon.texture = GameHUDSkin.SPORE
	_collection_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_collection_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_collection_icon.custom_minimum_size = Vector2(14, 14)
	_collection_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_row.add_child(_collection_icon)
	_collection_count = _label("0 / 0", 11, Color("a37a38"))
	_collection_count.name = "CollectionCount"
	_collection_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	_collection_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_row.add_child(_collection_count)
	_rule = _label("", 11, MUTED)
	_rule.max_lines_visible = 2
	_rule.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rule.visible = false
	_heading_content.add_child(_rule)
	# Reserve both goal lines using the inherited font, so asynchronous wrapping
	# cannot resize the camera area on the first movement/interaction.
	_rule.custom_minimum_size.y = _rule.get_line_height() * 2 + _rule.get_theme_constant("line_spacing")
	_journey_count = _label("", 11, MUTED)
	_journey_count.visible = false
	_heading_content.add_child(_journey_count)
	_journey_steps = HFlowContainer.new()
	_journey_steps.add_theme_constant_override("h_separation",6)
	_journey_steps.add_theme_constant_override("v_separation",2)
	_journey_steps.visible = false
	_heading_content.add_child(_journey_steps)

	_panel = _paper_panel(self, "compact")
	_panel.name = "NearbyActions"
	_panel.visible = false
	var panel_box := _column(_panel)
	panel_box.add_theme_constant_override("separation", 7)
	var context_header := HBoxContainer.new()
	context_header.add_theme_constant_override("separation", 6)
	panel_box.add_child(context_header)
	_context_title = _label("选择操作", 13)
	_context_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_header.add_child(_context_title)
	var cancel_context := _button("×")
	cancel_context.name = "CloseContext"
	cancel_context.tooltip_text = "取消选择 · Esc"
	_compact_button(cancel_context)
	cancel_context.pressed.connect(close_context_choices)
	context_header.add_child(cancel_context)
	var panel_scroll := ScrollContainer.new()
	panel_scroll.name = "ContextChoicesScroll"
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_scroll.follow_focus = true
	panel_scroll.custom_minimum_size.y = 44
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_box.add_child(panel_scroll)
	_commands = GridContainer.new()
	_commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands.add_theme_constant_override("h_separation", 8)
	_commands.add_theme_constant_override("v_separation", 5)
	panel_scroll.add_child(_commands)
	_panel_header = HBoxContainer.new()
	_panel_header.visible = false
	panel_box.add_child(_panel_header)
	_panel_separator = HSeparator.new()
	_panel_separator.visible = false
	panel_box.add_child(_panel_separator)
	_score_row = HBoxContainer.new()
	_score_row.visible = false
	panel_box.add_child(_score_row)
	_score = _label("", 11, MUTED)
	_score_row.add_child(_score)
	_journey_next = _label("", 11, MUTED)
	_journey_next.visible = false
	panel_box.add_child(_journey_next)

	_tools = _paper_panel(self, "compact")
	_tools.name = "JourneyTools"
	_tool_grid = Control.new()
	_tool_grid.resized.connect(_layout_tool_buttons)
	_tools.add_child(_tool_grid)
	for pair in [["撤销", "undo"], ["走近物件", "primary"], ["切换角色", "switch"], ["提示", "hint"]]:
		var action := String(pair[1])
		var button := _button(String(pair[0]))
		button.name = "Action_" + action
		_compact_button(button)
		button.pressed.connect(func() -> void: command_requested.emit(action))
		button.set_meta("action", action)
		button.set_meta("default_tooltip", String({"undo": "撤销上一次意图 · Z", "primary": "操作当前对象 · E", "switch": "切换角色 · T", "hint": "主动请求一点帮助 · H"}.get(action, "")))
		button.tooltip_text = String(button.get_meta("default_tooltip"))
		_tool_grid.add_child(button)
		_tool_buttons.append(button)
	_follow = _button("同行")
	_follow.name = "CompanionFollow"
	_compact_button(_follow)
	_follow.set_meta("action", "follow")
	_follow.pressed.connect(func() -> void: command_requested.emit("follow"))
	_tool_grid.add_child(_follow)

	_message_panel = _paper_panel(self, "compact")
	_message_panel.name = "JourneyMessage"
	_message = _label("", 12)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var message_scroll := ScrollContainer.new()
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_scroll.add_child(_message)
	_message_panel.add_child(message_scroll)
	_hint_button = Button.new()
	_hint_button.name = "InlineHint"
	_hint_button.flat = true
	_hint_button.tooltip_text = "点击切换下一条提示"
	_hint_button.set_meta("action", "hint_next")
	_hint_button.pressed.connect(func() -> void: command_requested.emit("hint_next"))
	_hint_label = _label("", 13)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint_button.add_child(_hint_label)
	_message_panel.add_child(_hint_button)
	_hint_button.hide()
	_message_panel.visible = false
	_game_skin.attach(_heading, "heading")
	_game_skin.attach(_tools, "tools")
	_game_skin.attach(_message_panel, "message")

	_nav = HBoxContainer.new()
	_nav.name = "Navigation"
	_nav.add_theme_constant_override("separation", 6)
	add_child(_nav)
	var pause_button := _button("Ⅱ")
	pause_button.name = "Pause"
	pause_button.tooltip_text = "暂停与设置 · Esc"
	_compact_button(pause_button)
	pause_button.pressed.connect(func() -> void: command_requested.emit("settings"))
	_nav.add_child(pause_button)
	var map_button := _button("地图")
	map_button.name = "Map"
	map_button.tooltip_text = "选择花园"
	_compact_button(map_button)
	map_button.pressed.connect(func() -> void: menu_requested.emit())
	_nav.add_child(map_button)

	_pad = GridContainer.new()
	_pad.name = "DirectionPad"
	_pad.columns = 3
	_pad.add_theme_constant_override("h_separation", 3)
	_pad.add_theme_constant_override("v_separation", 3)
	add_child(_pad)
	for direction in ["", "up", "", "left", "", "right", "", "down", ""]:
		if String(direction).is_empty():
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(40, 40)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pad.add_child(spacer)
		else:
			var dir := String(direction)
			var button := _button(String({"up": "↑", "right": "→", "down": "↓", "left": "←"}[dir]))
			button.custom_minimum_size = Vector2(40, 40)
			button.tooltip_text = String({"up": "向前", "right": "向右", "down": "向后", "left": "向左"}[dir])
			button.pressed.connect(func() -> void: command_requested.emit("dir:" + dir))
			_compact_button(button)
			_pad.add_child(button)
			_direction_buttons.append(button)
	_overview = _button("全景")
	_overview.name = "Overview"
	_overview.toggle_mode = true
	_overview.tooltip_text = "查看花园 / 回到身边"
	_overview.pressed.connect(func() -> void: command_requested.emit("overview"))
	_compact_button(_overview)
	add_child(_overview)
	_built = true
	# Container minimum sizes settle after text shaping and theme changes.
	# Reapply authored sizes then, rather than waiting for the next game action.
	for control in [_heading, _tools, _nav, _pad, _overview]:
		control.minimum_size_changed.connect(_queue_chrome_layout)
		control.resized.connect(_queue_chrome_layout)
	# Temporary containers can grow beyond the requested size after shaping.
	# Refresh only the camera area here, without resetting their authored size.
	for control in [_message_panel, _panel]:
		control.resized.connect(func() -> void: layout_changed.emit())
	_layout()

func _queue_chrome_layout() -> void:
	if _chrome_layout_pending:
		return
	_chrome_layout_pending = true
	_settle_chrome_layout.call_deferred()

func _settle_chrome_layout() -> void:
	_chrome_layout_pending = false
	_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()


func update_state(world: Variant, locked: bool = false, message: String = "", busy: bool = false) -> void:
	setup()
	_world = world
	_locked = locked
	_busy = busy
	if world == null:
		return
	var level: Dictionary = world.level
	if _guidance_level!=str(level.id):
		_guidance_level=str(level.id);_mole_conversation=FourthGuidance.new();_mole_message_active=false
	var state: Dictionary = world.state
	_title.text = "%s · %s" % [level.get("id", ""), level.get("title", "微光苔原")]
	_rule.text = str(Journey.describe(world).get("goal", level.get("rule", "")))
	_rule.tooltip_text = _rule.text
	var actor := String(state.get("active", "luvie"))
	_status.text = "露薇" if actor == "luvie" else "小苔灵"
	var used := 0
	var budget := 0
	for root in level.get("roots", []):
		budget += int(root.get("budget", 0))
		used += state.get("growth", {}).get(root.get("id", ""), []).size()
	if budget > 0:
		_status.text += "  ·  芽节 %d/%d" % [maxi(0, budget - used), budget]
	if str(level.get("id", "")) == "cloud-1":
		_status.text += "  ·  " + ("花种已收好" if bool(state.get("cloudSeed", false)) else "花种未找到")
	for item_id in state.get("items", {}):
		var item: Dictionary = state.items[item_id]
		if item.get("holder", "") == actor:
			_status.text += "  ·  " + _item_label(String(item_id))
	var collected: int = state.get("collected", []).size()
	_score.text = "%d / %d 沿途微光" % [collected, int(level.get("total", 0))]
	_collection_count.text = "%d / %d" % [collected, int(level.get("total", 0))]
	_collection_count.tooltip_text = _score.text
	_collection_icon.tooltip_text = _score.text
	if bool(level.get("dual", false)) and get_viewport_rect().size.x >= 650:
		_status.text += "  ·  伙伴" + ("同行" if bool(state.get("follow", false)) else "等候")
	if str(level.get("companionMode", "")) == "cloud":
		_status.text += "  ·  " + str({"sleep": "伙伴熟睡", "wait": "伙伴守着踏板", "sit": "伙伴休息", "follow": "伙伴同行"}.get(str(state.get("cloudBuddy", "")), ""))
	_heading.tooltip_text = String(level.get("rule", "")) + "\n" + _score.text
	_status.tooltip_text = _status.text
	_follow.visible = bool(level.get("dual", false))
	_follow.disabled = locked
	_follow.text = "等候" if bool(state.get("follow", false)) else "同行"
	_follow.tooltip_text = "让伙伴在此等待" if bool(state.get("follow", false)) else "邀请伙伴沿已接通的路跟随"
	_nearby_commands = []
	for entry: Dictionary in world.commands():
		if str(entry.get("id", "")) not in ["switch", "follow"]:
			_nearby_commands.append(entry)
	_last_command_key = JSON.stringify(_nearby_commands)
	for button in _tool_buttons:
		var action := String(button.get_meta("action"))
		button.disabled = locked
		button.tooltip_text = str(button.get_meta("default_tooltip", button.text))
		if action == "switch":
			button.visible = bool(level.get("dual", false))
		if action == "undo" and world.has_method("can_undo"):
			button.disabled = locked or (not busy and not world.can_undo())
		if action == "undo" and bool(state.get("completed", false)):
			button.disabled = true
			button.tooltip_text = "花园已修复，浏览时不能撤销；可从暂停菜单重新开始。"
	for button in _direction_buttons:
		button.disabled = locked
	_overview.disabled = locked or not _overview_available
	if _context_open and locked:
		close_context_choices()
	var default_fourth: bool=str(level.id)=="1-4" and not message.is_empty() and message in [str(Journey.describe(world).get("goal","")),str(level.get("intro",""))]
	if default_fourth:
		var current_journey: Dictionary=FourthGuidance.journey(world)
		var current_goal: String=str(current_journey.next) if bool(state.get("completed",false)) else "当前目标："+str(current_journey.next)
		var other_feedback: bool=not _fourth_default_message and _message_remaining>0 and _message.text!=message
		if not _inline_hint and not (_mole_message_active and _message_remaining>0) and not other_feedback and _message.text!=current_goal:
			set_message(current_goal)
			_fourth_default_message=true
	elif not message.is_empty() and _message.text != message:
		set_message(message)
	_layout()

func set_action_label(action: String, text: String) -> void:
	var caption := _display_text(text)
	for button in _tool_buttons:
		if String(button.get_meta("action")) == action:
			button.text = caption
			button.set_meta("default_tooltip", caption)
			button.tooltip_text = "这一步落稳后执行；新的选择会替换等待中的动作。" if _busy and action not in ["menu", "mode", "hint"] else String(button.get_meta("condition_reason", "")) if not String(button.get_meta("condition_reason", "")).is_empty() else caption


func set_action_enabled(action: String, enabled: bool) -> void:
	for button in _tool_buttons:
		if str(button.get_meta("action")) == action:
			button.disabled = not enabled

func set_action_feedback(primary_id: String, states: Dictionary) -> void:
	setup()
	var key := primary_id + JSON.stringify(states) + str(_locked) + str(_busy)
	if key == _feedback_key:
		return
	_feedback_key = key
	for node in _commands.get_children():
		if not node is Button:
			continue
		var id := String(node.get_meta("command_id", ""))
		var state: Dictionary = states.get(id, {"available": true, "reason": ""})
		var available := bool(state.get("available", true))
		node.text = _display_text(String(node.get_meta("base_label", node.text))) + ("" if available else " ·")
		node.tooltip_text = ("这一步落稳后再试。" if _busy else "") + ("" if available else String(state.get("reason", "")))
		_action_styles(node, available, id == primary_id)
	for button in _tool_buttons:
		if button.get_meta("action") == "primary":
			var state: Dictionary = states.get(primary_id, {"available": false, "reason": "走近根台、物件或庭院中心。"})
			var available := bool(state.get("available", false))
			_action_styles(button, available, not primary_id.is_empty())
			var reason := "" if available else String(state.get("reason", ""))
			button.set_meta("condition_reason", reason)
			button.tooltip_text = "这一步落稳后执行；新的选择会替换等待中的动作。" if _busy else reason if not reason.is_empty() else String(button.get_meta("default_tooltip", button.text))


func _action_styles(button: Button, available: bool, primary: bool) -> void:
	if primary and available:
		_game_skin.apply_primary(button)
		return
	button.set_meta("game_action_skin", "secondary" if available else "unavailable")
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
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("b3a38e"))


func set_journey(journey: Dictionary) -> void:
	setup()
	var fourth: bool=_world!=null and str(_world.level.id)=="1-4"
	var display: Dictionary=FourthGuidance.journey(_world) if fourth else journey
	var key:=JSON.stringify(display)+str(fourth)
	if key==_journey_key:return
	_journey_key = key
	_fourth_journey=display if fourth else {}
	_rule.text = str(display.get("goal", _rule.text))
	_journey_next.text = String(display.get("next", ""))
	_journey_count.text = ""
	_journey_step_count = 0
	_current_journey_step = -1
	_journey_steps.visible = false
	_journey_labels.clear()
	for child in _journey_steps.get_children():
		_journey_steps.remove_child(child)
		child.queue_free()
	if fourth:
		_journey_step_count=4
		_current_journey_step=int(display.current)
		for index in display.steps.size():
			var step: Dictionary=display.steps[index]
			var prefix: String="✓ " if step.done else "› " if index==_current_journey_step else "· "
			var label:=_label(prefix+str(step.label),11,Color("78866a") if step.done else INK if index==_current_journey_step else MUTED)
			label.autowrap_mode=TextServer.AUTOWRAP_OFF
			label.custom_minimum_size.x=150
			_journey_steps.add_child(label)
			_journey_labels.append(label)
	# Other gardens retain their existing compact goal; staged help stays opt-in.
	_layout()


func set_touch_mode(enabled: bool) -> void:
	setup()
	_touch_mode = enabled
	_layout()


func apply_settings(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	if is_instance_valid(_home_cover):
		_home_cover.configure(_settings)
	if is_instance_valid(_chapter_map): _chapter_map.apply_settings(_settings)
	_layout()


func set_interaction_context(primary_id: String, label: String, choices: Array = [], screen_position: Vector2 = Vector2(-1, -1)) -> void:
	setup()
	_primary_id = primary_id
	_interaction_label = label if not label.is_empty() else "走近物件"
	_context_screen = screen_position
	set_action_label("primary", _interaction_label + ("" if _touch_mode else " · E"))
	if not choices.is_empty() and not _context_open:
		_context_choices = choices.duplicate(true)
	_layout()


func show_context_choices(choices: Array = [], title: String = "选择操作") -> void:
	setup()
	_context_choices = (_nearby_commands if choices.is_empty() else choices).duplicate(true)
	# Keep every nearby object accessible when the principal target has its
	# own direction/slot choices. The menu does not choose a solution branch.
	var included: Dictionary = {}
	for entry: Dictionary in _context_choices:
		included[str(entry.get("id", ""))] = true
	for entry: Dictionary in _nearby_commands:
		if not included.has(str(entry.get("id", ""))):
			_context_choices.append(entry.duplicate(true))
	_context_open = not _context_choices.is_empty()
	_context_index = 0
	_context_title.text = _display_text(title)
	_render_context_choices()
	_layout()


func close_context_choices() -> void:
	_context_open = false
	_context_stick = Vector2.ZERO
	_context_stick_step = 0
	_context_repeat_remaining = 0.0
	if _panel != null:
		_panel.hide()
	if _built:
		_layout()


func is_context_open() -> bool:
	return _context_open and _game_interface_visible and not is_modal_open()


func context_active() -> bool:
	return is_context_open()


func handle_context_event(event: InputEvent) -> bool:
	if not is_context_open():
		return false
	if event is InputEventKey:
		return handle_context_key(event)
	if event is InputEventJoypadButton:
		if not event.pressed:
			return event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
		if event.button_index == JOY_BUTTON_B:
			close_context_choices()
			return true
		if event.button_index == JOY_BUTTON_A:
			var confirm := InputEventKey.new()
			confirm.keycode = KEY_ENTER
			confirm.pressed = true
			return handle_context_key(confirm)
		if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT]:
			_navigate_context(-1 if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT] else 1)
			return true
		# Context menus own gameplay buttons until closed. Start is left to
		# the application's pause/navigation handler.
		return event.button_index in [JOY_BUTTON_X, JOY_BUTTON_Y]
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		if event.axis == JOY_AXIS_LEFT_X:
			_context_stick.x = event.axis_value
		else:
			_context_stick.y = event.axis_value
		var strongest: float = _context_stick.x if absf(_context_stick.x) > absf(_context_stick.y) else _context_stick.y
		var step := int(signf(strongest)) if absf(strongest) >= 0.6 else 0
		if step != _context_stick_step:
			_context_stick_step = step
			_context_repeat_remaining = 0.32
			if step != 0:
				_navigate_context(step)
		return true
	return false


func _navigate_context(step: int) -> void:
	if _context_choices.is_empty():
		return
	for unused in _context_choices.size():
		_context_index = posmod(_context_index + step, _context_choices.size())
		if not bool(_context_choices[_context_index].get("disabled", false)):
			break
	_focus_context_choice()


func handle_context_key(event: InputEventKey) -> bool:
	if not is_context_open() or not event.pressed or event.echo:
		return false
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == KEY_ESCAPE:
		close_context_choices()
		return true
	if code == KEY_TAB:
		_navigate_context(-1 if event.shift_pressed else 1)
		return true
	var direction := str({KEY_UP: "up", KEY_W: "up", KEY_RIGHT: "right", KEY_D: "right", KEY_DOWN: "down", KEY_S: "down", KEY_LEFT: "left", KEY_A: "left"}.get(code, ""))
	if not direction.is_empty():
		for entry: Dictionary in _context_choices:
			var id := str(entry.get("id", ""))
			if id.begins_with("grow:") and id.ends_with(":" + direction):
				if bool(entry.get("disabled", false)):
					set_message(str(entry.get("reason", "现在还不能这样做。")))
					return true
				close_context_choices()
				command_requested.emit(id)
				return true
		_navigate_context(-1 if direction in ["up", "left"] else 1)
		return true
	if code in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		var entry: Dictionary = _context_choices[_context_index]
		if bool(entry.get("disabled", false)):
			set_message(str(entry.get("reason", "现在还不能这样做。")))
			return true
		close_context_choices()
		command_requested.emit(str(entry.get("id", "")))
		return true
	if code >= KEY_1 and code <= KEY_9:
		var index := code - KEY_1
		if index < _context_choices.size():
			var entry: Dictionary = _context_choices[index]
			if bool(entry.get("disabled", false)):
				set_message(str(entry.get("reason", "现在还不能这样做。")))
				return true
			close_context_choices()
			command_requested.emit(str(entry.get("id", "")))
		return true
	return false


func _render_context_choices() -> void:
	_commands.columns = 2 if _context_choices.size() == 2 and not _context_choices.any(func(entry: Dictionary) -> bool: return bool(entry.get("disabled", false))) else 1
	for child in _commands.get_children():
		_commands.remove_child(child)
		child.queue_free()
	for index in _context_choices.size():
		var entry: Dictionary = _context_choices[index]
		var command_id := str(entry.get("id", ""))
		var button := _button(str(entry.get("label", command_id)))
		_compact_button(button)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("command_id", command_id)
		button.set_meta("base_label", button.text)
		button.focus_entered.connect(func() -> void: _context_index = index)
		button.disabled = bool(entry.get("disabled", false))
		button.tooltip_text = str(entry.get("reason", ""))
		button.pressed.connect(func() -> void:
			close_context_choices()
			command_requested.emit(command_id))
		_commands.add_child(button)
		button.focus_mode = Control.FOCUS_ALL
		if button.disabled and not button.tooltip_text.is_empty():
			_commands.add_child(_label(button.tooltip_text, 11, MUTED))
	_focus_context_choice.call_deferred()
	_layout.call_deferred()


func _focus_context_choice() -> void:
	if not is_context_open() or _commands.get_child_count() == 0:
		return
	var buttons: Array[Button] = []
	for child in _commands.get_children():
		if child is Button:
			buttons.append(child)
	if buttons.is_empty():
		return
	_context_index = clampi(_context_index, 0, buttons.size() - 1)
	if not buttons[_context_index].disabled:
		buttons[_context_index].grab_focus()


func show_hint(world: Variant, tier: int = 0) -> void:
	show_hint_content(FourthGuidance.hint(world,tier) if str(world.level.id)=="1-4" else str(Journey.hint(world, tier).get("message", "")), tier)

func show_hint_content(message: String, tier: int = 0) -> void:
	setup()
	_mole_message_active=false
	_fourth_default_message=false
	close_context_choices()
	_inline_hint = true
	_message_remaining = 0.0
	_hint_label.text = "%s\n提示 %d / 3 · 点击切换" % [message, tier + 1]
	_message.get_parent().hide()
	_hint_button.show()
	_message_panel.visible = _game_interface_visible
	_layout()

func is_hint_visible() -> bool:
	return _inline_hint and _message_panel.visible

func hide_hint() -> void:
	_inline_hint = false
	_hint_button.hide()
	_message_remaining = 0.0
	_message_panel.hide()
	layout_changed.emit()


func set_dialogue_proximity(provider: Callable) -> void:
	_dialogue_proximity=provider

func _process(delta: float) -> void:
	if is_context_open() and _context_stick_step != 0:
		_context_repeat_remaining -= delta
		if _context_repeat_remaining <= 0.0:
			_navigate_context(_context_stick_step)
			_context_repeat_remaining = 0.18
	if _message_remaining > 0.0 and _game_interface_visible and not is_modal_open():
		_message_remaining = maxf(0.0, _message_remaining - delta)
		if _message_remaining <= 0.0:
			_message_panel.hide()
			layout_changed.emit()
	if _world!=null and _guidance_level=="1-4" and _game_interface_visible and not is_modal_open() and not _locked:
		var physical_near: Variant=_dialogue_proximity.call() if _dialogue_proximity.is_valid() else null
		var speech: Dictionary=_mole_conversation.poll(_world,delta,not _inline_hint and not _busy and not _context_open and (_message_remaining<=0 or _mole_message_active),physical_near)
		if bool(speech.get("hide",false)) and _mole_message_active:
			_mole_message_active=false;_message_remaining=0;_message_panel.hide();layout_changed.emit()
		elif speech.has("text"):
			set_message("鼹鼠："+str(speech.text))
			_mole_message_active=true;_message_remaining=float(speech.seconds)

func set_overview(value: bool) -> void:
	setup()
	_overview.button_pressed = value
	_overview.text = "跟随" if value else "全景"
	layout_changed.emit()

func set_overview_available(value: bool) -> void:
	_overview_available = value
	_overview.disabled = _locked or not value
	_overview.tooltip_text = "查看整片花园 / 回到身边" if value else "当前已展示整片花园；全景切换适用于小屏跟随镜头。"


func set_message(text: String) -> void:
	setup()
	_mole_message_active=false
	_fourth_default_message=false
	_inline_hint = false
	_hint_button.hide()
	_message.get_parent().show()
	_message_refreshes += 1
	_message_remaining = 5.0
	# Refresh the visible message even when its words match the last rejection.
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message.modulate = Color(1.0, 0.94, 0.82)
	_message_tween = create_tween()
	_message_tween.tween_property(_message, "modulate", Color.WHITE, 0.18)
	setup()
	_message.text = _display_text(text)
	_message_panel.visible = _game_interface_visible and not text.is_empty()
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
	# Temporary feedback and object menus must not resize/recenter the world.
	# They still appear in layout_regions() for pointer blocking.
	return _uncovered_world_rect([_heading, _tools, _nav, _pad, _overview])


func overview_world_rect() -> Rect2:
	setup()
	# Overview promises the whole garden, including its foreground. Keep hints
	# and local choices usable, but frame the map clear of their visible panels.
	return _uncovered_world_rect([_heading, _tools, _nav, _pad, _overview, _message_panel, _panel])


func _uncovered_world_rect(blockers: Array) -> Rect2:
	var viewport_size := get_viewport_rect().size
	var free: Array[Rect2] = [Rect2(Vector2(14, 14), viewport_size - Vector2(28, 28))]
	for blocker: Control in blockers:
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


func set_game_interface_visible(value: bool) -> void:
	setup()
	close_context_choices()
	_game_interface_visible = value
	for control in [_heading, _panel, _tools, _nav, _pad, _overview]:
		control.visible = value
	if not value: _inline_hint = false
	_message_panel.visible = value and (_inline_hint or (_message_remaining > 0 and not _message.text.is_empty()))
	_home_background.visible = not value
	_layout()


func is_game_interface_visible() -> bool:
	return _game_interface_visible


func show_home(levels: Array, progress: Dictionary, can_continue: bool, explore_open: bool = false) -> void:
	set_game_interface_visible(false)
	_open_page("home", "微光苔原", show_home.bind(levels, progress, can_continue, explore_open))
	_overlay.name = "HomeScreen"
	_overlay.set_meta("screen", "home")
	# Keep the page/navigation contract; replace only the generic modal artwork.
	for child in _overlay.get_children():
		_overlay.remove_child(child)
		child.queue_free()
	_overlay_paper = null
	_home_cover = MenuCover.new()
	_overlay.add_child(_home_cover)
	_home_cover.setup()
	_home_cover.configure(_settings)
	_home_logo = _home_cover.logo
	_overlay_scroll = _home_cover.invitation
	var box: VBoxContainer = _home_cover.content
	var completed := 0
	var total := 0
	var has_cloud := false
	for level: Dictionary in levels:
		var id := str(level.get("id", ""))
		if id.begins_with("cloud-"):
			has_cloud = true
			continue
		total += 1
		if bool(progress.get("records", {}).get(id, {}).get("completed", false)):
			completed += 1
	box.add_child(_label("一段温柔的冒险", 11, MUTED))
	var greeting := _label("微光，还在等你。" if completed > 0 else "你好，小小的旅人。", 29)
	greeting.set_meta("cover_heading", true)
	box.add_child(greeting)
	var player := "露薇"
	if _repository != null:
		player = str(_repository.data.get("player", {}).get("name", "露薇"))
	box.add_child(_label("%s，这里没有需要赶上的时间。\n走一走，让沉睡的生命重新发光。" % player, 13, MUTED))
	var start := _button("选择花园" if can_continue else "开始旅程")
	start.set_meta("action", "map")
	start.pressed.connect(func() -> void: command_requested.emit("map"))
	var resume := _button("继续上次的微光")
	resume.set_meta("action", "continue")
	resume.disabled = not can_continue
	resume.focus_mode = Control.FOCUS_ALL if can_continue else Control.FOCUS_NONE
	resume.tooltip_text = "继续已保存的旅程。" if can_continue else "先开始一段旅程，再回来继续。"
	resume.pressed.connect(func() -> void: command_requested.emit("continue"))
	if can_continue:
		_home_cover.style_primary(resume)
		_home_cover.style_secondary(start, true)
		box.add_child(resume)
		box.add_child(start)
	else:
		_home_cover.style_primary(start)
		_home_cover.style_secondary(resume, true)
		box.add_child(start)
		box.add_child(resume)
	box.add_child(_label("已唤醒 %d / %d 片微光" % [completed, total], 12, MUTED))
	if not str(progress.get("storage_warning", "")).is_empty():
		box.add_child(_label(str(progress.storage_warning), 12, MUTED))
	var divider := HSeparator.new()
	divider.modulate = Color(1, 1, 1, 0.35)
	box.add_child(divider)
	var utilities := HBoxContainer.new()
	utilities.name = "CoverUtilityEntries"
	utilities.add_theme_constant_override("separation", 12)
	box.add_child(utilities)
	var explore := _button("探索与收藏  −" if explore_open else "探索与收藏  ＋")
	explore.name = "CoverExploreToggle"
	explore.set_meta("action", "home_explore")
	explore.toggle_mode = true
	explore.button_pressed = explore_open
	explore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_cover.style_secondary(explore, true)
	utilities.add_child(explore)
	var settings_button := _button("设置")
	settings_button.set_meta("action", "settings")
	settings_button.custom_minimum_size.x = 76
	settings_button.pressed.connect(func() -> void: command_requested.emit("settings"))
	_home_cover.style_secondary(settings_button, true)
	utilities.add_child(settings_button)
	var collection := VBoxContainer.new()
	collection.name = "CoverExplorationEntries"
	collection.add_theme_constant_override("separation", 6)
	collection.visible = explore_open
	box.add_child(collection)
	explore.toggled.connect(func(open: bool) -> void:
		collection.visible = open
		explore.text = "探索与收藏  −" if open else "探索与收藏  ＋"
		# Back from a collection page restores the expanded group. A fresh
		# home destination still starts compact with just four entry points.
		_page_restore = show_home.bind(levels, progress, can_continue, open)
		if open:
			_overlay_scroll.ensure_control_visible.call_deferred(collection))
	if has_cloud:
		var cloud := _button("云庭微光 · 独立花园")
		cloud.name = "CoverCloudEntry"
		cloud.set_meta("action", "cloud_map")
		cloud.tooltip_text = "和小苔灵修复空中花园。"
		cloud.pressed.connect(func() -> void:
			command_requested.emit("map")
			_focus_cloud_entry.call_deferred())
		_home_cover.style_secondary(cloud)
		collection.add_child(cloud)
	var secondary := HBoxContainer.new()
	secondary.name = "CoverCollectionEntries"
	secondary.add_theme_constant_override("separation", 6)
	collection.add_child(secondary)
	var journal := _button("花园纪事")
	journal.pressed.connect(func() -> void: show_journal(levels, progress))
	var gallery := _button("图鉴")
	gallery.pressed.connect(func() -> void: show_gallery(_repository.data if _repository != null else {"mainline": progress}))
	for button: Button in [gallery, journal]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_home_cover.style_secondary(button)
		secondary.add_child(button)
	_resize_overlay()
	_focus_modal.call_deferred()


func _focus_cloud_entry() -> void:
	if _page_kind != "map" or not is_instance_valid(_overlay):
		return
	if is_instance_valid(_chapter_map):
		_chapter_map.select_chapter("cloud")
		return
	for node in _overlay.find_children("*", "Button", true, false):
		if str(node.get_meta("level_id", "")).begins_with("cloud-"):
			_overlay.set_meta("preferred_focus", node)
			node.grab_focus()
			if is_instance_valid(_overlay_scroll):
				_reveal_map_focus.call_deferred(node)
			return


func _reveal_map_focus(button: Button) -> void:
	# Container dimensions settle after the modal opens. Align the focused row
	# explicitly; ensure_control_visible and follow_focus may otherwise race
	# across the newly fixed header/footer on compact viewports.
	if not is_instance_valid(button) or not is_instance_valid(_overlay_scroll):
		return
	var scroll := _overlay_scroll
	# A wheel event over the old cover can still be delivered after its button
	# has opened the map. Let that input and the container pass settle first.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(button) or not is_instance_valid(scroll) or scroll != _overlay_scroll or _overlay.get_meta("preferred_focus") != button:
		return
	scroll.ensure_control_visible(button)
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + roundi(button.get_global_rect().position.y - scroll.get_global_rect().position.y))
	# Focus following and the opening click can enqueue another sort pass.
	# Reconcile against the final geometry once; later user scrolling is free.
	await get_tree().create_timer(0.12).timeout
	if not is_instance_valid(button) or not is_instance_valid(scroll) or scroll != _overlay_scroll or _overlay.get_meta("preferred_focus") != button:
		return
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + roundi(button.get_global_rect().position.y - scroll.get_global_rect().position.y))


func _add_return_buttons(box: VBoxContainer) -> void:
	if not _page_stack.is_empty():
		var source := str(_page_stack.back().get("kind", ""))
		if source not in ["home", ""]:
			var back := _button(str({"map": "返回地图", "settings": "返回设置", "gallery": "返回图鉴", "journal": "返回花园纪事"}.get(source, "返回上一页")))
			back.set_meta("action", "back")
			back.pressed.connect(navigate_back)
			box.add_child(back)
	if _game_interface_visible:
		var resume := _button("继续当前关卡")
		resume.set_meta("action", "resume")
		resume.pressed.connect(close_overlay)
		box.add_child(resume)
	var home := _button("返回主界面")
	home.set_meta("action", "home")
	home.pressed.connect(func() -> void: command_requested.emit("home"))
	box.add_child(home)


func show_menu(levels: Array, progress: Dictionary = {}) -> void:
	if not _navigating_back:
		_map_selection.clear()
	_open_page("map", "花园地图", show_menu.bind(levels, progress))
	# Keep the existing modal lifecycle and page stack, replacing only its body.
	_overlay_paper.get_parent().hide()
	_chapter_map = ChapterMap.new()
	_chapter_map.apply_settings(_settings)
	_chapter_map.can_resume = _game_interface_visible
	_chapter_map.can_save = _repository != null
	for level: Dictionary in levels:
		var id := str(level.get("id", ""))
		if not id.begins_with("cloud-"):
			continue
		var total := 0
		for mark: Dictionary in _cloud_level(id).get("marks", []):
			if not str(mark.get("text", "")).is_empty():
				total += 1
		_chapter_map.story_labels[id] = "口袋里的小事 · %d/%d" % [_cloud_found(id).size(), total]
	_overlay.add_child(_chapter_map)
	_chapter_map.selection_changed.connect(func(chapter: String, id: String) -> void:
		_map_selection = {"chapter": chapter, "level": id})
	_chapter_map.level_requested.connect(func(id: String) -> void:
		close_overlay(false)
		level_requested.emit(id))
	_chapter_map.cloud_story_requested.connect(show_cloud_stories)
	_chapter_map.action_requested.connect(func(action: String) -> void:
		match action:
			"resume": close_overlay()
			"journal": show_journal(levels, progress)
			"gallery": show_gallery(_repository.data if _repository != null else {"mainline": progress})
			"save": show_save_tools(_repository)
			_:
				command_requested.emit(action)
	)
	_chapter_map.configure(levels, progress, _map_selection)
	_map_selection = {"chapter": _chapter_map.chapter, "level": _chapter_map.selected_id}
	_overlay.set_meta("preferred_focus", _chapter_map.preferred_focus)
	_resize_overlay()


func _reset_map_scroll(scroll: ScrollContainer, button: Button) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(scroll) or scroll != _overlay_scroll or not is_instance_valid(_overlay) or _overlay.get_meta("preferred_focus") != button:
		return
	scroll.scroll_vertical = 0
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(scroll) and scroll == _overlay_scroll and is_instance_valid(_overlay) and _overlay.get_meta("preferred_focus") == button:
		scroll.scroll_vertical = 0


func _first_map_level(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and child.has_meta("level_id") and not child.disabled:
			return child
		var found := _first_map_level(child)
		if found != null:
			return found
	return null


func _configure_map_frame(box: VBoxContainer) -> HFlowContainer:
	return _configure_fixed_menu_frame(box, "MapFrame", "选择一片花园，慢慢发现它的联系。")


func _configure_fixed_menu_frame(box: VBoxContainer, frame_name: String, description: String) -> HFlowContainer:
	# Headers, filters and return actions share one bounded native frame.
	# Only the body follows scrolling or later keyboard focus navigation.
	var frame := VBoxContainer.new()
	frame.name = frame_name
	frame.add_theme_constant_override("separation", 8)
	_overlay_paper.remove_child(_overlay_scroll)
	_overlay_paper.add_child(frame)
	var heading := box.get_child(0) as Label
	box.remove_child(heading)
	frame.add_child(heading)
	var caption := _label(description, 12, MUTED)
	frame.add_child(caption)
	var toolbar := HFlowContainer.new()
	toolbar.name = "MapUtilities" if frame_name == "MapFrame" else "GalleryCategories"
	toolbar.add_theme_constant_override("h_separation", 4)
	toolbar.add_theme_constant_override("v_separation", 4)
	frame.add_child(toolbar)
	frame.add_child(HSeparator.new())
	_overlay_scroll.custom_minimum_size = Vector2.ZERO
	_overlay_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_overlay_scroll)
	frame.add_child(HSeparator.new())
	if frame_name == "MapFrame":
		_map_frame = frame
		_map_heading = heading
		_map_description = caption
	else:
		_gallery_frame = frame
		_gallery_heading = heading
		_gallery_description = caption
	return toolbar


func _add_fixed_return_buttons(frame: VBoxContainer, node_name: String) -> void:
	var returns := VBoxContainer.new()
	_add_return_buttons(returns)
	var footer := HBoxContainer.new()
	footer.name = node_name
	footer.add_theme_constant_override("separation", 8)
	frame.add_child(footer)
	for button: Button in returns.get_children():
		returns.remove_child(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MenuButtons.utility(button, false)
		footer.add_child(button)
	returns.free()

func show_settings(settings: Dictionary = {}) -> void:
	_settings = settings.duplicate(true)
	var box := _open_page("settings", "暂停与设置" if _game_interface_visible else "设置", show_settings.bind(_settings))
	for item in [["bgm", "音乐"], ["sfx", "音效"], ["ambient", "环境声"]]:
		var key := String(item[0])
		box.add_child(_label(String(item[1]), 13))
		var slider := HSlider.new()
		slider.name = "Setting_" + key
		slider.set_meta("setting_id", key)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = float(_settings.get(key, {"bgm": 0.35, "sfx": 0.6, "ambient": 0.25}.get(key, 0.5)))
		slider.custom_minimum_size.y = 28
		slider.value_changed.connect(func(value: float) -> void:
			_settings[key] = value
			settings_changed.emit(_settings.duplicate(true)))
		box.add_child(slider)
	for item in [["lowMotion", "减少动态效果"], ["dynamicLight", "柔和光效"], ["particles", "环境粒子"], ["touchControls", "显示触屏方向键"]]:
		var key := String(item[0])
		var toggle := CheckButton.new()
		toggle.name = "Setting_" + key
		toggle.set_meta("setting_id", key)
		toggle.text = String(item[1])
		toggle.button_pressed = bool(_settings.get(key, key in ["dynamicLight", "particles", "continuousInput"]))
		toggle.toggled.connect(func(value: bool) -> void:
			_settings[key] = value
			settings_changed.emit(_settings.duplicate(true))
			_layout())
		box.add_child(toggle)
	box.add_child(_label("移动始终保持连续；镜头会自动为当前操作留出空间。", 12, MUTED))
	if _repository != null and not _game_interface_visible:
		box.add_child(HSeparator.new())
		box.add_child(_label("旅程管理", 16))
		var saves := _button("导入 / 导出旅程")
		saves.set_meta("action", "save_tools")
		saves.pressed.connect(func() -> void: show_save_tools(_repository))
		box.add_child(saves)
	if _game_interface_visible:
		box.add_child(HSeparator.new())
		for pair in [["变成蘑菇球 / 站起来", "mode"], ["轻轻跳跃", "jump"], ["重新开始本关", "restart"]]:
			var action := str(pair[1])
			var button := _button(str(pair[0]))
			button.set_meta("action", action)
			button.pressed.connect(func() -> void:
				close_overlay()
				command_requested.emit(action))
			box.add_child(button)
	_add_return_buttons(box)


func set_repository(repository: Variant) -> void:
	_repository = repository


func _cloud_level(id: String) -> Dictionary:
	if _cloud_catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json"))
		if parsed is Dictionary:
			_cloud_catalog = parsed.get("levels", [])
	for level: Dictionary in _cloud_catalog:
		if str(level.get("id", "")) == id:
			return level
	return {}


func _cloud_found(id: String) -> Array[String]:
	var result: Array[String] = []
	if _repository == null:
		return result
	var history: Variant = _repository.data.get("cloud_discoveries", {})
	if not history is Dictionary or not history.get(id, []) is Array:
		return result
	var values: Array = history.get(id, [])
	for mark: Dictionary in _cloud_level(id).get("marks", []):
		var mark_id := str(mark.get("id", ""))
		if not str(mark.get("text", "")).is_empty() and mark_id in values:
			result.append(mark_id)
	return result


func _add_cloud_story_entry(box: VBoxContainer, id: String) -> void:
	var known := _cloud_found(id)
	var total := 0
	for mark: Dictionary in _cloud_level(id).get("marks", []):
		if not str(mark.get("text", "")).is_empty():
			total += 1
	var button := _button("口袋里的小事 · %d/%d" % [known.size(), total])
	button.name = "CloudStories_" + id
	button.set_meta("cloud_story_level", id)
	button.tooltip_text = "看看曾经发现的故事；重新探索也会为你保留。"
	if _page_kind == "map":
		MenuButtons.utility(button)
	button.pressed.connect(func() -> void: show_cloud_stories(id))
	box.add_child(button)


func show_cloud_stories(id: String) -> void:
	var level := _cloud_level(id)
	if level.is_empty():
		return
	var box := _open_page("cloud_stories", "口袋里的小事", show_cloud_stories.bind(id))
	box.add_child(_label(str(level.get("title", "云庭微光")), 18))
	box.add_child(_label("路边的小事，会为你留在这里。", 12, MUTED))
	var found := _cloud_found(id)
	for mark: Dictionary in level.get("marks", []):
		var story := str(mark.get("text", ""))
		if story.is_empty():
			continue
		box.add_child(HSeparator.new())
		if str(mark.get("id", "")) in found:
			box.add_child(_label(str(mark.get("label", "一件小事")), 16))
			box.add_child(_label(story, 14))
		else:
			box.add_child(_label("尚未遇见的小事", 15, MUTED))
			box.add_child(_label("在花园里慢慢发现。", 12, MUTED))
	_add_return_buttons(box)


func show_save_tools(repository: Variant) -> void:
	_repository = repository
	_import_candidate = {}
	var box := _open_page("saves", "保存这段旅程", show_save_tools.bind(repository))
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
	_add_return_buttons(box)


func show_ending(world: Variant, stats: Dictionary = {}) -> void:
	var level: Dictionary = world if world is Dictionary else world.level
	var snapshot: Dictionary = stats if not stats.is_empty() else ({} if world is Dictionary else world.state)
	var collected: Variant = snapshot.get("collected", [])
	var count: int = collected.size() if collected is Array else int(collected)
	var box := _open_page("ending", "这里，又可以成为家。", show_ending.bind(world, stats))
	box.add_child(_label(String(level.get("story", "这片花园，因你而安定。")), 16))
	box.add_child(_label("%d / %d 粒微光已收集 · 纪事已点亮" % [count, int(snapshot.get("total", level.get("total", 0)))], 13, MUTED))
	var next := _button("去下一片微光 ↗" if bool(level.get("has_next_garden", true)) else "看看一路的纪事 ↗")
	next.set_meta("action", "next")
	next.pressed.connect(func() -> void:
		close_overlay(false)
		command_requested.emit("next"))
	box.add_child(next)
	var stay := _button("留下看看")
	stay.pressed.connect(func() -> void:
		close_overlay()
		command_requested.emit("stay"))
	box.add_child(stay)
	var back := _button("返回地图")
	back.pressed.connect(func() -> void:
		close_overlay(false)
		menu_requested.emit())
	box.add_child(back)


func show_journal(levels: Array, progress: Dictionary = {}) -> void:
	var box := _open_page("journal", "花园纪事", show_journal.bind(levels, progress))
	box.add_child(_label("每一次帮助，都在这里留下了一页。", 13, MUTED))
	for level in levels:
		var id := String(level.get("id", ""))
		var earned := bool(progress.get("records", {}).get(id, {}).get("completed", false))
		box.add_child(_label("%s · %s" % [id, level.get("title", "")], 17))
		box.add_child(_label(String(level.get("story", "")) if earned else "这片花园还在等你慢慢发现。", 13, MUTED))
		if id.begins_with("cloud-"):
			_add_cloud_story_entry(box, id)
		if earned and progress.get("memories", {}).has(id) and progress.memories[id].get("completed", false):
			var review := _button("看看修复后的花园")
			review.pressed.connect(func() -> void:
				close_overlay(false)
				command_requested.emit("review:" + id))
			box.add_child(review)
	_add_return_buttons(box)


func show_gallery(store: Dictionary = {}, category: String = "全部") -> void:
	var box := _open_page("gallery", "微光图鉴", show_gallery.bind(store, category))
	var categories := _configure_fixed_menu_frame(box, "GalleryFrame", "每一种生命，都有自己的微光。")
	var group := ButtonGroup.new()
	group.allow_unpress = false
	_overlay.set_meta("gallery_category", category)
	for category_name in GalleryCatalog.CATEGORIES:
		var selected := String(category_name)
		var filter_button := _button(selected)
		filter_button.toggle_mode = true
		filter_button.button_group = group
		filter_button.button_pressed = selected == category
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		MenuButtons.category_tab(filter_button)
		filter_button.pressed.connect(func() -> void:
			if selected != category:
				show_gallery(store, selected))
		categories.add_child(filter_button)
		if selected == category:
			_overlay.set_meta("preferred_focus", filter_button)
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
	_add_fixed_return_buttons(_gallery_frame, "GalleryReturnActions")
	_resize_overlay()
	if not _navigating_back:
		_request_scroll_position(0)


func _show_gallery_story(item: Dictionary, store: Dictionary, category: String) -> void:
	var box := _open_page("story", String(item.title), _show_gallery_story.bind(item, store, category))
	var name_value := String(store.get("player", {}).get("name", "露薇"))
	for paragraph in item.story:
		box.add_child(_label(String(paragraph).replace("{name}", name_value), 15))
	box.add_child(_label(String(item.poem), 14, ACCENT))
	var back := _button("返回图鉴")
	back.pressed.connect(navigate_back)
	box.add_child(back)


func close_overlay(resume_game: bool = true) -> void:
	if is_instance_valid(_overlay):
		remove_child(_overlay)
		_overlay.queue_free()
	_overlay = null
	_overlay_paper = null
	_overlay_scroll = null
	_map_frame = null
	_map_heading = null
	_map_description = null
	_chapter_map = null
	_gallery_frame = null
	_gallery_heading = null
	_gallery_description = null
	_home_logo = null
	_home_cover = null
	layout_changed.emit()
	if resume_game:
		_page_kind = ""
		_page_restore = Callable()
		_page_stack.clear()
		command_requested.emit("resume")


func navigate_back() -> void:
	if is_context_open():
		close_context_choices()
		return
	if is_instance_valid(_chapter_map) and _chapter_map.close_overview():
		return
	if not is_modal_open():
		return
	if not _page_stack.is_empty():
		var previous: Dictionary = _page_stack.pop_back()
		var restore: Callable = previous.get("restore", Callable())
		if restore.is_valid():
			_navigating_back = true
			restore.call()
			_navigating_back = false
			_restore_scroll.call_deferred(int(previous.get("scroll", 0)))
			return
	if _page_kind == "home" or not _game_interface_visible:
		command_requested.emit("home")
	else:
		close_overlay()


func _restore_scroll(offset: int) -> void:
	_request_scroll_position(offset)


func _request_scroll_position(offset: int) -> void:
	if not is_instance_valid(_overlay_scroll) or not is_instance_valid(_overlay):
		return
	_overlay.set_meta("requested_scroll_offset", maxi(0, offset))
	_position_menu_scroll(_overlay_scroll, _overlay, maxi(0, offset))


func _position_menu_scroll(scroll: ScrollContainer, page: Control, offset: int) -> void:
	# A newly built page has not received its final content bounds yet.
	# Set the requested position after container layout, rather than letting
	# the first interactive child decide the initial reading position.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(page) or page != _overlay or not is_instance_valid(scroll) or scroll != _overlay_scroll or int(page.get_meta("requested_scroll_offset", -1)) != offset:
		return
	scroll.scroll_vertical = offset
	await get_tree().process_frame
	if is_instance_valid(page) and page == _overlay and is_instance_valid(scroll) and scroll == _overlay_scroll and int(page.get_meta("requested_scroll_offset", -1)) == offset:
		scroll.scroll_vertical = offset


func _open_page(kind: String, title: String, restore: Callable) -> VBoxContainer:
	if not _navigating_back:
		if not is_modal_open() or kind in ["home", "map", "ending"]:
			_page_stack.clear()
		elif _page_kind != kind and _page_restore.is_valid():
			_page_stack.append({"kind": _page_kind, "restore": _page_restore, "scroll": _overlay_scroll.scroll_vertical if is_instance_valid(_overlay_scroll) else 0})
	_page_kind = kind
	_page_restore = restore
	return _open_overlay(title)


func is_modal_open() -> bool:
	return is_instance_valid(_overlay)


func _open_overlay(title: String) -> VBoxContainer:
	setup()
	close_context_choices()
	close_overlay(false)
	_overlay = Control.new()
	_overlay.name = "ModalOverlay"
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
	paper.name = "ModalPaper"
	_overlay_paper = paper
	var scroll := ScrollContainer.new()
	scroll.name = "ModalScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_overlay_scroll = scroll
	paper.add_child(scroll)
	_resize_overlay()
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	box.add_child(_label(title, 25))
	command_requested.emit("pause")
	_focus_modal.call_deferred()
	layout_changed.emit()
	return box


func _focus_modal() -> void:
	if is_instance_valid(_overlay):
		var preferred: Variant = _overlay.get_meta("preferred_focus") if _overlay.has_meta("preferred_focus") else null
		if is_instance_valid(preferred) and preferred is Button and preferred.is_visible_in_tree() and not preferred.disabled:
			preferred.grab_focus()
			return
		_focus_first_control(_overlay)


func _focus_first_control(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is Control and child.is_visible_in_tree() and child.focus_mode == Control.FOCUS_ALL:
			if child is BaseButton and child.disabled:
				continue
			if child is BaseButton or child is Slider or child is LineEdit or child is TextEdit:
				child.grab_focus()
				return true
		if _focus_first_control(child):
			return true
	return false


func _resize_overlay() -> void:
	if is_instance_valid(_chapter_map):
		_chapter_map._schedule_layout()
		return
	if is_instance_valid(_home_cover):
		_home_cover.relayout()
		return
	if not is_instance_valid(_overlay_paper) or not is_instance_valid(_overlay_scroll):
		return
	if is_instance_valid(_home_logo):
		_home_logo.custom_minimum_size.y = 64 if get_viewport_rect().size.y <= 400 else 104
	var available := (get_viewport_rect().size - Vector2(28, 28)).max(Vector2.ZERO)
	var outer := Vector2(minf(560, available.x), minf(580, available.y))
	var fixed_frame := _map_frame if is_instance_valid(_map_frame) else _gallery_frame
	if is_instance_valid(fixed_frame):
		var short := get_viewport_rect().size.y <= 420
		var heading := _map_heading if is_instance_valid(_map_frame) else _gallery_heading
		var description := _map_description if is_instance_valid(_map_frame) else _gallery_description
		heading.add_theme_font_size_override("font_size", 18 if short else 22)
		description.visible = not short
		var panel_style := _overlay_paper.get_theme_stylebox("panel") as StyleBoxFlat
		var top := 16.0 if short else 34.0
		if panel_style.content_margin_top != top:
			panel_style = panel_style.duplicate() as StyleBoxFlat
			panel_style.content_margin_top = top
			panel_style.content_margin_bottom = 16 if short else 36
			_overlay_paper.add_theme_stylebox_override("panel", panel_style)
			_overlay_paper.set_meta("paper_kind", "compact" if short else "card")
			_overlay_paper.queue_redraw()
	var inset := _overlay_paper.get_theme_stylebox("panel").get_minimum_size()
	var content := (outer - inset).max(Vector2.ZERO)
	var target: Control = fixed_frame if is_instance_valid(fixed_frame) else _overlay_scroll
	if target.custom_minimum_size != content:
		target.custom_minimum_size = content
		_overlay_paper.get_parent().queue_sort()


func _layout() -> void:
	if not _built:
		return
	_resize_overlay()
	var extent := get_viewport_rect().size
	_short_landscape = extent.y <= 420
	var margin := 6.0 if _short_landscape else 12.0 if extent.x >= 360 else 8.0
	_heading.visible = _game_interface_visible
	_tools.visible = _game_interface_visible
	_nav.visible = _game_interface_visible
	_overview.visible = _game_interface_visible
	_panel.visible = _game_interface_visible and _context_open and not is_modal_open()
	_pad.visible = _game_interface_visible and _touch_mode and bool(_settings.get("touchControls", false)) and not _context_open
	var fourth_stages: bool=not _fourth_journey.is_empty() and _guidance_level=="1-4"
	_rule.visible = extent.y > 500 and not fourth_stages
	_chapter_label.hide()
	_journey_count.visible=fourth_stages
	_journey_steps.visible=fourth_stages and not _short_landscape
	if fourth_stages:
		var progress_text: String="%d/4 · %s" % [int(_fourth_journey.done),str(_fourth_journey.next)] if _short_landscape else "归家旅程  %d / 4" % int(_fourth_journey.done)
		if _journey_count.text!=progress_text:_journey_count.text=progress_text
		_set_layout_font(_journey_count,10 if _short_landscape else 11)
	_panel_header.hide()
	_panel_separator.hide()
	_score_row.hide()
	_journey_next.hide()
	_heading.position = Vector2(margin, margin)
	_set_panel_inset(_heading, 4 if _short_landscape else 8)
	var separation:=2 if _short_landscape else 4
	if _heading_content.get_theme_constant("separation")!=separation:_heading_content.add_theme_constant_override("separation",separation)
	var heading_height: float=(62 if _short_landscape else 124) if fourth_stages else (46 if _short_landscape else 82 if extent.y > 500 else 62)
	_heading.size = Vector2(minf(360, maxf(120, extent.x - 196 - margin)), heading_height)
	_set_layout_font(_title,13 if _short_landscape else 14 if extent.x < 650 else 16)
	_set_layout_font(_status,9 if _short_landscape else 10 if extent.x < 650 else 11)
	_set_layout_font(_collection_count,9 if _short_landscape else 10 if extent.x < 650 else 11)
	_collection_icon.custom_minimum_size = Vector2(12, 12) if _short_landscape else Vector2(14, 14)
	_nav.position = Vector2(extent.x - margin - 94, margin)
	_nav.size = Vector2(94, 44)
	for child in _nav.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(44, 44)
	_overview.position = Vector2(_nav.position.x - 66, margin)
	_overview.size = Vector2(60, 44)
	var tools_width := minf(520 if _follow.visible else 410, extent.x - margin * 2)
	var tools_height := 50.0 if _short_landscape else 60.0
	_set_panel_inset(_tools, 3 if _short_landscape else 8)
	_tools.position = Vector2((extent.x - tools_width) / 2, extent.y - margin - tools_height)
	_tools.size = Vector2(tools_width, tools_height)
	_tool_grid.custom_minimum_size.y = 44
	_layout_tool_buttons.call_deferred()
	var message_width := minf(520, extent.x - margin * 2)
	_set_panel_inset(_message_panel, 3 if _short_landscape else 8)
	_message_panel.position = Vector2((extent.x - message_width) / 2, _tools.position.y - (34 if _short_landscape else 58))
	_message_panel.size = Vector2(message_width, 28 if _short_landscape else 48)
	if _inline_hint:
		var font := _hint_label.get_theme_font("font")
		var text_size := font.get_multiline_string_size(_hint_label.text, HORIZONTAL_ALIGNMENT_CENTER, message_width - 32, 13, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
		var line_count := ceili(text_size.y / maxf(1, font.get_height(13)))
		var text_height := text_size.y + maxi(0, line_count - 1) * _hint_label.get_theme_constant("line_spacing")
		var hint_height := maxf(72, text_height + 40)
		_message_panel.position.y = _tools.position.y - hint_height - 8
		_message_panel.size.y = hint_height
	_set_layout_font(_message,10 if _short_landscape else 11 if extent.x < 650 else 12)
	_message.max_lines_visible = 1 if _short_landscape else 3
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.tooltip_text = _message.text
	if not _inline_hint and _short_landscape and _world != null and _message.text == str(_world.level.get("intro", "")):
		_message_panel.hide()
	_pad.position = Vector2(margin, maxf(80, _tools.position.y - 144))
	_pad.size = Vector2(132, 132)
	if _panel.visible:
		var panel_width := minf(410, extent.x - margin * 2)
		# Account for the actual 44px close button, gaps, content and insets.
		# The old estimate cut the second direction off even in a two-item menu.
		var content_height := maxf(44, _commands.get_combined_minimum_size().y)
		var panel_height := minf(67 + content_height, maxf(111, _tools.position.y - 86))
		var preferred := Vector2((extent.x - panel_width) / 2, _tools.position.y - panel_height - 10)
		_panel.position = Vector2(clampf(preferred.x, margin, maxf(margin, extent.x - margin - panel_width)), clampf(preferred.y, 80, maxf(80, _tools.position.y - panel_height - 10)))
		_panel.size = Vector2(panel_width, panel_height)
		_message_panel.visible = false
	layout_changed.emit()


func _set_layout_font(label: Label,font_size: int) -> void:
	if label.get_theme_font_size("font_size")!=font_size:
		label.add_theme_font_size_override("font_size",font_size)

func _set_panel_inset(panel: PanelContainer, inset: float) -> void:
	var existing: StyleBox = panel.get_theme_stylebox("panel")
	if is_equal_approx(existing.content_margin_left, inset):
		return
	var style: StyleBox = existing.duplicate()
	style.set_content_margin_all(inset)
	panel.add_theme_stylebox_override("panel", style)


func _layout_tool_buttons() -> void:
	if _tool_grid == null or _tools == null:
		return
	var visible: Array[Button] = []
	for button in _tool_buttons:
		if button.visible:
			visible.append(button)
	if _follow != null and _follow.visible:
		visible.append(_follow)
	if visible.is_empty():
		return
	var gap := 5.0
	var available := maxf(44, _tool_grid.size.x - gap * (visible.size() - 1))
	var secondary := minf(64, maxf(44, (available - 112) / maxf(1, visible.size() - 1)))
	var offset := 0.0
	for button in visible:
		var width := available - secondary * (visible.size() - 1) if button.get_meta("action", "") == "primary" else secondary
		button.custom_minimum_size = Vector2(0, 44)
		button.position = Vector2(offset, 0)
		button.size = Vector2(maxf(44, width), 44)
		button.add_theme_font_size_override("font_size", 11 if get_viewport_rect().size.x < 650 else 12)
		offset += button.size.x + gap

func _paper_panel(parent: Node, kind: String = "card") -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _paper_style(PAPER, 14 if kind == "compact" else 42 if kind == "tools" else 24)
	if kind == "compact":
		style.set_content_margin_all(8)
		style.shadow_size = 3
	elif kind == "card":
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
	trim.set_corner_radius_all(11 if kind == "compact" else 36 if kind == "tools" else 20)
	panel.draw_style_box(trim, Rect2(Vector2(5, 5), extent - Vector2(10, 10)))
	if _ornament_texture != null:
		# Exact source regions used by garden-journey.css, separated from resize.
		if kind in ["card", "tools"]:
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


func _display_text(text: String) -> String:
	# These auxiliary glyphs are absent from the shipped CJK
	# font. Preserve the original rule labels and IDs; sanitize display only.
	for symbol: String in ["↻", "↺", "⇄", "⇆", "✧"]:
		text = text.replace(symbol, "")
	return text.strip_edges()


func _label(text: String, font_size: int = 13, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = _display_text(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.theme = theme
	button.text = _display_text(text)
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
