extends Control
## A read-only collection book. All content and hit areas are native controls.
signal dismissed()
signal resumed()
signal category_changed(category: String)
const Catalog := preload("res://ui/gallery_catalog.gd")
const Assets := preload("res://elements/element_assets.gd")
const INK := Color("795a39")
const MUTED := Color("9c8665")
const GOLD := Color("c3944f")
var store: Dictionary
var category := "全部"
var selected_id := ""
var story_mode := false
var compact := false
var detail_open := false
var scroll: ScrollContainer
var detail_scroll: ScrollContainer
var categories: HBoxContainer
var cards: GridContainer
var title: Label
var _canvas: Control
var _book: TextureRect
var _paper: Panel
var _subtitle: Label
var _count: Label
var _page_number: Label
var _detail: VBoxContainer
var _back: Button
var _resume: Button
var _modes: BoxContainer
var _tabs: Dictionary = {}
var _card_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _items: Array = []
var _silhouette: Shader
var _levels: Array = []

func configure(data: Dictionary, initial_category: String = "全部") -> void:
	name = "GalleryBook"
	store = data.duplicate(true)
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).get("levels",[])
	category = initial_category if initial_category in Catalog.CATEGORIES else "全部"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	var forest := _image(self,"res://assets/images/gallery-book-20261119/forest.jpg")
	forest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	forest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas = Control.new()
	add_child(_canvas)
	_book = _image(_canvas,"res://assets/images/gallery-book-20261119/book-blank.png")
	_book.stretch_mode = TextureRect.STRETCH_SCALE
	_book.size = Vector2(1280,720)
	_paper = Panel.new()
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.add_theme_stylebox_override("panel",_surface(Color("f8e9ce"),Color("d2b687"),18))
	_canvas.add_child(_paper)
	_back = _button("←", "BackFromGallery")
	_back.tooltip_text = "返回上一页"
	_back.pressed.connect(func() -> void:
		if not close_detail(): dismissed.emit())
	_canvas.add_child(_back)
	_resume = _button("继续当前关卡","ResumeFromGallery")
	_resume.hide()
	_resume.pressed.connect(func() -> void: resumed.emit())
	_canvas.add_child(_resume)
	title = _label(_canvas,"图鉴 / 画册",30)
	_subtitle = _label(_canvas,"微 光 苔 原  ·  S p o r e l i g h t",11,MUTED)
	_count = _label(_canvas,"已收集  %d / %d" % [_unlocked_count(Catalog.ITEMS),Catalog.ITEMS.size()],14)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	categories = HBoxContainer.new()
	categories.name = "GalleryCategories"
	categories.add_theme_constant_override("separation",3)
	_canvas.add_child(categories)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for value: String in Catalog.CATEGORIES:
		var tab := _button(value,"Category_"+value)
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(select_category.bind(value))
		categories.add_child(tab)
		_tabs[value] = tab
	scroll = _scroller(_canvas,"GalleryCardsScroll")
	cards = GridContainer.new()
	cards.add_theme_constant_override("h_separation",12)
	cards.add_theme_constant_override("v_separation",12)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)
	detail_scroll = _scroller(_canvas,"GalleryDetailScroll")
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation",8)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)
	_modes = BoxContainer.new()
	_modes.add_theme_constant_override("separation",12)
	_canvas.add_child(_modes)
	var mode_group := ButtonGroup.new()
	for value: String in ["图鉴","故事"]:
		var tab := _button(value,"GalleryMode_"+value)
		tab.toggle_mode = true
		tab.button_group = mode_group
		tab.pressed.connect(func() -> void:
			story_mode = value == "故事"
			_refresh_detail())
		_modes.add_child(tab)
		_mode_buttons[value] = tab
	_page_number = _label(_canvas,"",11,MUTED)
	_page_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_silhouette = Shader.new()
	_silhouette.code = "shader_type canvas_item; void fragment(){ vec4 t=texture(TEXTURE,UV); COLOR=vec4(vec3(0.57,0.52,0.41),t.a*0.38); }"
	_refresh_cards()
	resized.connect(relayout)
	relayout()

func _unlocked_count(items: Array) -> int:
	var count := 0
	for item: Dictionary in items: count += int(Catalog.unlocked(item,store))
	return count

func select_category(value: String) -> void:
	if value == category: return
	category = value
	detail_open = false
	story_mode = false
	_refresh_cards()
	scroll.scroll_vertical = 0
	_tabs[value].grab_focus()
	category_changed.emit(value)
	relayout()

func _refresh_cards() -> void:
	for child: Node in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	_card_buttons.clear()
	_items = []
	for item: Dictionary in Catalog.ITEMS:
		if category == "全部" or item.category == category: _items.append(item)
	var retained := false
	for item: Dictionary in _items: retained = retained or item.id == selected_id
	if not retained:
		selected_id = str(_items[0].id)
		for item: Dictionary in _items:
			if Catalog.unlocked(item,store):
				selected_id = str(item.id)
				break
	for item: Dictionary in _items:
		var found := Catalog.unlocked(item,store)
		var card := _button("","Collectible_"+str(item.id))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = str(item.title)+(" · 已发现" if found else " · 未发现")
		card.set_meta("item_id",item.id)
		card.set_meta("unlocked",found)
		cards.add_child(card)
		var paper := _image(card,"res://assets/images/gallery-book-20261119/card-paper.png")
		paper.stretch_mode = TextureRect.STRETCH_SCALE
		paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		paper.offset_left = 4; paper.offset_top = 4; paper.offset_right = -4; paper.offset_bottom = -4
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(body)
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		body.offset_left = 12; body.offset_top = 15; body.offset_right = -12; body.offset_bottom = -12
		body.add_theme_constant_override("separation",2)
		var caption := _label(body,str(item.title),16,INK if found else MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var ornament := _label(body,"─ ◇ ─",11,GOLD)
		ornament.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var art := _image(body,"res://assets/images/"+str(item.image))
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if not found:
			var material := ShaderMaterial.new()
			material.shader = _silhouette
			art.material = material
		var status := _label(body,_marks(item) if found else "未 发 现",14,GOLD if found else MUTED)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.pressed.connect(select_item.bind(str(item.id)))
		_card_buttons[item.id] = card
	for value: String in Catalog.CATEGORIES:
		_tabs[value].button_pressed = value == category
		_style(_tabs[value],value == category)
	_refresh_selection()
	_refresh_detail()

func select_item(id: String) -> void:
	selected_id = id
	detail_open = true
	_refresh_selection()
	_refresh_detail()
	relayout()
	if compact: _mode_buttons["图鉴"].grab_focus()

func _refresh_selection() -> void:
	for id: String in _card_buttons:
		var selected := id == selected_id
		var button: Button = _card_buttons[id]
		button.add_theme_stylebox_override("normal",_surface(Color("f8e7c9"),Color("d9a44f") if selected else Color("ead5b3"),18,2 if selected else 1))
		button.add_theme_stylebox_override("hover",_surface(Color("fff1d5"),GOLD,18,2))
		button.add_theme_stylebox_override("pressed",_surface(Color("f8e7c9"),GOLD,18,2))
		button.get_child(0).modulate.a = .78 if selected else .57
	_page_number.text = "%02d / %02d" % [_items.find(_selected())+1,_items.size()]

func _selected() -> Dictionary:
	for item: Dictionary in _items:
		if item.id == selected_id: return item
	return _items[0]

func _marks(item: Dictionary) -> String:
	# Five observation marks follow collection completeness, not level's 3-star score.
	var best := 0.0
	var records: Dictionary = store.get("mainline",store).get("records",{})
	for level: Dictionary in _levels:
		if level.id not in item.levels: continue
		var record: Dictionary = records.get(level.id,{})
		if not record.get("completed",false): continue
		var total: int = level.get("total",level.get("collectibles",[]).size())
		if total > 0: best = maxf(best,clampf(float(record.get("collected",0))/total,0,1))
	var marks := 1+floori(best*4)
	return "★".repeat(marks)+"☆".repeat(5-marks)

func _refresh_detail() -> void:
	for child: Node in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	detail_scroll.scroll_vertical = 0
	var item := _selected()
	var found := Catalog.unlocked(item,store)
	for mode: String in _mode_buttons:
		var active := (mode == "故事") == story_mode
		_mode_buttons[mode].button_pressed = active
		_style(_mode_buttons[mode],active)
	var heading := _label(_detail,str(item.title),26)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(_detail,("一 段 微 光 故 事" if story_mode else _marks(item)) if found else "尚 未 发 现",14,GOLD)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if story_mode and found:
		_label(_detail,"─ ◇ ─",15,GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for paragraph: String in item.story:
			_paragraph(str(paragraph).replace("{name}",str(store.get("player",{}).get("name","露薇"))))
		_paragraph(str(item.poem),GOLD)
	else:
		var art := _image(_detail,"res://assets/images/"+str(item.image))
		art.custom_minimum_size.y = 165
		if not found:
			var material := ShaderMaterial.new()
			material.shader = _silhouette
			art.material = material
		_paragraph(str(item.desc) if found else "这页故事，还在等待一次温柔的相遇。",INK)
		_label(_detail,"──── ◇ ────",12,GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_paragraph("栖息环境\n"+str(item.habitat),MUTED)
		var discovered := ""
		for level: String in item.levels:
			if store.get("mainline",store).get("records",{}).get(level,{}).get("completed",false):
				discovered = level
				break
		_paragraph(("相遇足迹\n关卡 "+discovered if not discovered.is_empty() else "相遇足迹\n记于微光旅程") if found else "发现线索\n在关卡 %s 完成一次新的相遇。" % item.levels[0],MUTED)

func close_detail() -> bool:
	if story_mode:
		story_mode = false
		_refresh_detail()
		return true
	if compact and detail_open:
		detail_open = false
		relayout()
		_card_buttons[selected_id].grab_focus()
		return true
	return false

func relayout() -> void:
	if not is_instance_valid(_canvas): return
	compact = size.x < 1000 or size.y < 600
	_book.visible = not compact
	_paper.visible = compact
	if not compact:
		var factor := minf(size.x/1280.0,size.y/720.0)
		_canvas.scale = Vector2.ONE*factor
		_canvas.position = (size-Vector2(1280,720)*factor)*.5
		_canvas.size = Vector2(1280,720)
		_place(_back,Rect2(32,24,48,48))
		_place(title,Rect2(126,70,470,44))
		title.add_theme_font_size_override("font_size",30)
		_place(_subtitle,Rect2(128,117,460,24)); _subtitle.show()
		_place(_count,Rect2(600,91,220,32))
		_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_place(categories,Rect2(124,153,700,44))
		_place(scroll,Rect2(124,207,700,434))
		cards.columns = 4
		for card: Button in _card_buttons.values(): card.custom_minimum_size = Vector2(0,210)
		_place(detail_scroll,Rect2(884,132,278,511))
		_modes.vertical = true
		_place(_modes,Rect2(1201,170,58,168))
		for mode: Button in _mode_buttons.values(): mode.custom_minimum_size = Vector2(58,74)
		_place(_page_number,Rect2(300,641,550,22))
		_place(_resume,Rect2(124,652,160,44))
		scroll.show(); detail_scroll.show(); _modes.show(); categories.show()
	else:
		_canvas.scale = Vector2.ONE
		_canvas.position = Vector2.ZERO
		_canvas.size = size
		_place(_paper,Rect2(8,8,size.x-16,size.y-16))
		_place(_back,Rect2(18,18,44,44))
		_back.tooltip_text = "返回藏品" if detail_open else "返回上一页"
		title.add_theme_font_size_override("font_size",22)
		_place(title,Rect2(74,18,size.x-92,32))
		_subtitle.hide()
		_place(_count,Rect2(74,53,size.x-96,26))
		_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_place(categories,Rect2(20,88,size.x-40,44))
		_place(scroll,Rect2(20,144,size.x-40,size.y-182))
		cards.columns = 2 if size.x < 600 else 3
		for card: Button in _card_buttons.values(): card.custom_minimum_size = Vector2(0,200)
		_modes.vertical = false
		_place(_modes,Rect2(20,88,size.x-40,44))
		for mode: Button in _mode_buttons.values(): mode.custom_minimum_size = Vector2(90,44)
		_place(detail_scroll,Rect2(30,144,size.x-60,size.y-182))
		_place(_page_number,Rect2(24,size.y-32,size.x-48,22))
		if _resume.visible:
			_place(_resume,Rect2(20,size.y-62,size.x-40,44))
			scroll.size.y -= 32
			detail_scroll.size.y -= 32
		scroll.visible = not detail_open
		categories.visible = not detail_open
		detail_scroll.visible = detail_open
		_modes.visible = detail_open
	_page_number.visible = not (compact and _resume.visible)
	for value: String in Catalog.CATEGORIES:
		var entries: Array = []
		for item: Dictionary in Catalog.ITEMS:
			if value == "全部" or item.category == value: entries.append(item)
		_tabs[value].text = value if compact else "%s  %d/%d" % [value,_unlocked_count(entries),entries.size()]
		_tabs[value].tooltip_text = "%s · 已收集 %d / %d" % [value,_unlocked_count(entries),entries.size()]

func _paragraph(text: String, color: Color = INK) -> Label:
	var label := _label(_detail,text,14,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing",4)
	return label

func _label(parent: Node, text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
	return label

func _image(parent: Node, source: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = Assets.texture_for_source(source)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _scroller(parent: Node, node_name: String) -> ScrollContainer:
	var result := ScrollContainer.new()
	result.name = node_name
	result.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result.follow_focus = true
	parent.add_child(result)
	return result

func _button(caption: String, node_name: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.name = node_name
	button.custom_minimum_size = Vector2(44,44)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size",14)
	_style(button,false)
	return button

func _style(button: Button, selected: bool) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		button.add_theme_stylebox_override(state,_surface(Color("80906a") if selected else Color("f3dfbd"),Color("bda278"),16,1))
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:
		button.add_theme_color_override(state,Color("fff2d8") if selected else INK)
	var focus := _surface(Color(1,1,1,0),GOLD,16,2)
	button.add_theme_stylebox_override("focus",focus)

func _surface(fill: Color, border: Color, radius: int, width: int = 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(radius)
	return result

func _place(control: Control, bounds: Rect2) -> void:
	control.position = bounds.position
	control.size = bounds.size
