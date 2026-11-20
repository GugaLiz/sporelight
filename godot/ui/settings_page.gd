extends Control
## Illustrated native settings: real sliders/buttons retain keyboard and touch.
signal changed(settings: Dictionary)
signal dismissed()
const Assets := preload("res://elements/element_assets.gd")
const Defaults := preload("res://services/save_repository.gd")
const PaperStar := preload("res://ui/art/paper-star.svg")
const PaperLeaves := preload("res://ui/art/paper-leaves.svg")
const INK := Color("52664e")
const MUTED := Color("8b9b78")
const GREEN := Color("8fa773")
var values: Dictionary = {}
var scroll: ScrollContainer
var footer: HFlowContainer
var extra: VBoxContainer
var _header: VBoxContainer
var _columns: GridContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _close: Button
var _frame := Rect2()
var _paper: Texture2D
var _sliders: Dictionary = {}
var _toggles: Dictionary = {}
var _quality: Dictionary = {}
var _title: Label
var _updating := false

func configure(settings: Dictionary) -> void:
	name = "QuietSettingsPage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	values = settings.duplicate(true)
	_paper = Assets.texture_for_source("res://assets/images/gallery-journal/paper-texture.jpg")
	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation",10)
	add_child(_header)
	_label(_header,"A  M O M E N T  O F  Q U I E T",10,MUTED)
	_title = _label(_header,"让旅程，舒服一点。",27,INK)
	var description := _label(_header,"设置会自动保存。休息时，微光也会等你。",12,MUTED)
	description.size.x = 280
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_close = button("×")
	_close.name = "CloseSettings"
	_close.custom_minimum_size = Vector2(44,44)
	_close.tooltip_text = "返回上一页"
	_close.pressed.connect(func() -> void: dismissed.emit())
	add_child(_close)
	scroll = ScrollContainer.new()
	scroll.name = "SettingsBodyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",12)
	scroll.add_child(content)
	_columns = GridContainer.new()
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("h_separation",44)
	_columns.add_theme_constant_override("v_separation",20)
	content.add_child(_columns)
	_left = VBoxContainer.new()
	_right = VBoxContainer.new()
	for column in [_left,_right]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",4)
		_columns.add_child(column)
	_label(_left,"听见微光",16,INK)
	for pair in [["bgm","背景旋律"],["sfx","互动音效"],["ambient","环境底音"]]: _volume(str(pair[0]),str(pair[1]))
	var sound_note := _label(_left,"首次点击后，轻柔的声音会慢慢响起。",11,MUTED)
	sound_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_left,"画面细节",16,INK)
	var quality_row := HBoxContainer.new()
	quality_row.add_theme_constant_override("separation",10)
	_left.add_child(quality_row)
	for pair in [["soft","柔和"],["standard","标准"],["hd","高清"]]:
		var id := str(pair[0])
		var option := button(str(pair[1]))
		option.custom_minimum_size.x = 0
		option.name = "Setting_quality_"+id
		option.set_meta("setting_id","quality")
		option.set_meta("quality_id",id)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.pressed.connect(func() -> void: _change("quality",id); _refresh_quality())
		quality_row.add_child(option)
		_quality[id] = option
	_refresh_quality()
	_label(_right,"按自己的节奏",16,INK)
	for pair in [["dynamicLight","柔和光晕"],["particles","漂浮孢子"],["lowMotion","减少动态，雨滴无需等待"],["touchControls","显示触屏方向键"]]: _toggle(str(pair[0]),str(pair[1]))
	_label(_right,"移动始终保持连续。",11,MUTED)
	_label(_right,"简体中文 · 本地自动存档",11,MUTED)
	extra = VBoxContainer.new()
	extra.add_theme_constant_override("separation",8)
	content.add_child(extra)
	footer = HFlowContainer.new()
	footer.add_theme_constant_override("h_separation",10)
	footer.add_theme_constant_override("v_separation",8)
	add_child(footer)
	var reset := button("恢复默认")
	reset.name = "ResetComfortSettings"
	reset.tooltip_text = "恢复音量、画质和显示设置，旅程进度会保留。"
	reset.pressed.connect(_reset)
	footer.add_child(reset)
	resized.connect(relayout)
	relayout()

func _volume(key: String, caption: String) -> void:
	var row := HBoxContainer.new()
	_left.add_child(row)
	var label := _label(row,caption,13,INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var amount := _label(row,"%d%%" % roundi(float(values.get(key,0)) * 100),12,MUTED)
	amount.custom_minimum_size.x = 48
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.name = "Setting_"+key
	slider.set_meta("setting_id",key)
	slider.min_value = 0; slider.max_value = 1; slider.step = .05
	slider.value = float(values.get(key,Defaults.default_settings()[key]))
	slider.custom_minimum_size = Vector2(0,44)
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.add_theme_stylebox_override("slider",surface(Color("e5d3a9"),Color("cbb78d"),3,5))
	slider.add_theme_stylebox_override("grabber_area",surface(Color("b8c59c"),Color("a2b482"),3,5))
	slider.add_theme_stylebox_override("grabber_area_highlight",surface(Color("a0b682"),Color("91a774"),3,5))
	slider.add_theme_icon_override("grabber",_knob())
	slider.add_theme_icon_override("grabber_highlight",_knob())
	slider.add_theme_icon_override("grabber_disabled",_knob())
	slider.value_changed.connect(func(value: float) -> void:
		amount.text = "%d%%" % roundi(value*100)
		_change(key,value))
	_left.add_child(slider)
	_sliders[key] = slider

func _toggle(key: String, caption: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 46
	_right.add_child(row)
	var label := _label(row,caption,13,INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var toggle := CheckButton.new()
	toggle.name = "Setting_"+key
	toggle.set_meta("setting_id",key)
	toggle.tooltip_text = caption
	toggle.custom_minimum_size = Vector2(54,44)
	toggle.button_pressed = bool(values.get(key,Defaults.default_settings()[key]))
	for state in ["normal","hover","pressed","hover_pressed"]:
		toggle.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	toggle.add_theme_stylebox_override("focus",surface(Color("f7ecd7"),Color("bca477"),12))
	for state in ["checked","checked_disabled"]: toggle.add_theme_icon_override(state,_switch(true))
	for state in ["unchecked","unchecked_disabled"]: toggle.add_theme_icon_override(state,_switch(false))
	toggle.toggled.connect(func(value: bool) -> void: _change(key,value))
	row.add_child(toggle)
	_toggles[key] = toggle
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator",surface(Color("e8d9bf"),Color.TRANSPARENT,0,1))
	_right.add_child(line)

func _change(key: String, value: Variant) -> void:
	values[key] = value
	if not _updating: changed.emit(values.duplicate(true))

func _reset() -> void:
	_updating = true
	values = Defaults.default_settings()
	for key in _sliders: _sliders[key].value = values[key]
	for key in _toggles: _toggles[key].button_pressed = values[key]
	_refresh_quality()
	_updating = false
	changed.emit(values.duplicate(true))

func _refresh_quality() -> void:
	for id in _quality: style_button(_quality[id],id == str(values.get("quality","standard")))

func button(caption: String, primary := false) -> Button:
	var result := Button.new()
	result.text = caption
	result.custom_minimum_size = Vector2(96,44)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	style_button(result,primary)
	return result

func style_button(node: Button, primary := false) -> void:
	node.clip_text = false
	node.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	node.add_theme_font_size_override("font_size",13)
	node.add_theme_color_override("font_color",Color("fffbe9") if primary else Color("856743"))
	node.add_theme_color_override("font_hover_color",Color("fffbe9") if primary else INK)
	node.add_theme_color_override("font_pressed_color",INK)
	node.add_theme_stylebox_override("normal",surface(GREEN if primary else Color("faecd6"),Color("b8bd8f") if primary else Color("d6b48c"),11))
	node.add_theme_stylebox_override("hover",surface(Color("9db681") if primary else Color("fff6e6"),Color("b9a174"),11))
	node.add_theme_stylebox_override("pressed",surface(Color("d9dfbe"),Color("a0ad82"),11))
	node.add_theme_stylebox_override("focus",surface(Color.TRANSPARENT,Color("ac8a50"),11))

static func surface(color: Color, border: Color, radius: int, height := 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color; style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 7; style.content_margin_bottom = 7
	if height > 0:
		style.content_margin_top = height * .5; style.content_margin_bottom = height * .5
	return style

func _label(parent: Node, text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _knob() -> Texture2D:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><circle cx="10" cy="11" r="8" fill="#d9c69e" opacity=".35"/><circle cx="10" cy="9" r="7" fill="#8fa773" stroke="#fbf5df" stroke-width="2"/></svg>'
	return _svg(svg)

func _switch(enabled: bool) -> Texture2D:
	return _svg('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="26"><rect x="2" y="2" width="44" height="22" rx="11" fill="%s" stroke="%s"/><circle cx="%d" cy="13" r="10" fill="#fbf5e5" stroke="#d6b98f"/></svg>' % ["#91a970" if enabled else "#eed8b8","#8ca06e" if enabled else "#d6b98f",35 if enabled else 13])

func _svg(source: String) -> Texture2D:
	var picture := Image.new()
	picture.load_svg_from_string(source)
	return ImageTexture.create_from_image(picture)

func relayout() -> void:
	if _header == null: return
	var extent := size if size.x > 0 else get_viewport_rect().size
	var width := minf(900,extent.x-24)
	var height := minf(690,extent.y-24)
	_frame = Rect2((extent-Vector2(width,height))*.5,Vector2(width,height))
	var narrow := width < 660
	var short := height < 480
	var margin := 24.0 if narrow or short else 44.0
	var header_height := 92.0 if short else 122.0
	var inner := width-margin*2
	_header.position = _frame.position + Vector2(margin,24 if short else 48)
	_header.size = Vector2(inner-36,header_height)
	_title.add_theme_font_size_override("font_size",21 if short else 25 if narrow else 27)
	_close.position = _frame.position + Vector2(width-58,14)
	_close.size = Vector2(44,44)
	_columns.columns = 1 if narrow else 2
	for column in [_left,_right]: column.custom_minimum_size.x = inner-12 if narrow else (inner-56)*.5
	footer.position = _frame.position + Vector2(margin, height-24-footer.get_combined_minimum_size().y)
	footer.size.x = inner
	scroll.position = _frame.position + Vector2(margin,header_height + (18 if short else 40))
	scroll.size = Vector2(inner,maxf(40,footer.position.y-scroll.position.y-22))
	scroll.get_child(0).custom_minimum_size.x = inner-12
	queue_redraw()

func _draw() -> void:
	if _frame.size.x <= 0: return
	draw_style_box(surface(Color("faf1db"),Color("fff9e7"),28),_frame)
	if _paper != null: draw_texture_rect(_paper,_frame.grow(-12),true,Color(1,1,1,.14))
	draw_style_box(surface(Color.TRANSPARENT,Color("e6c9a264"),44),_frame.grow(-16))
	draw_style_box(surface(Color.TRANSPARENT,Color("fff9e895"),48),_frame.grow(-21))
	var center := _frame.position+Vector2(_frame.size.x*.5,34)
	if _frame.size.x >= 660 and _frame.size.y >= 480:
		draw_texture_rect(PaperStar,Rect2(center-Vector2(110,17),Vector2(220,34)),false)
	var line_y := footer.position.y-12
	draw_line(Vector2(_frame.position.x+36,line_y),Vector2(_frame.end.x-36,line_y),Color("dfceab"),1,true)
	# Small shaded leaves sit in the margins, clear of controls and labels.
	var extent := 50.0 if _frame.size.x >= 660 else 28.0
	draw_texture_rect(PaperLeaves,Rect2(_frame.position+Vector2(9,_frame.size.y-extent-10),Vector2.ONE*extent),false,Color(1,1,1,.8))
	draw_set_transform(_frame.end-Vector2(9,extent+10),0,Vector2(-1,1))
	draw_texture_rect(PaperLeaves,Rect2(Vector2.ZERO,Vector2.ONE*extent),false,Color(1,1,1,.8))
	draw_set_transform(Vector2.ZERO)
