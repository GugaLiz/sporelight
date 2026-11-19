extends Control
## Original illustrated chapter composition with live Godot progress and buttons.
## This view emits navigation intents only; it never writes saves or world state.
signal level_requested(id: String)
signal action_requested(action: String)
signal selection_changed(chapter: String, level_id: String)
signal cloud_story_requested(id: String)

const INK := Color("69553e")
const MUTED := Color("8c8064")
const CHAPTERS := ["valley", "pond", "cave", "cloud"]
const TITLES := {"valley": "苔藓山谷", "pond": "雨滴池塘", "cave": "星光洞穴", "cloud": "云庭微光"}
const DESCRIPTIONS := {"valley": "借一粒种子，让不同的生命相遇。", "pond": "选好落点，让光、雨与伙伴带路。", "cave": "在光影之间，找回星空的记忆。", "cloud": "和小苔灵一起，唤醒三座独立花园。"}
const TERRACES := [Vector2(112, 441), Vector2(260, 390), Vector2(561, 485), Vector2(799, 201)]
const CardArt := preload("res://ui/chapter_card_art.gd")
const CoverShader := preload("res://ui/chapter_cover.gdshader")
const MapMenuSkin := preload("res://ui/map_menu_skin.gd")
const MapMenuPaper := preload("res://ui/map_menu_paper.gd")
const CleanupShader := preload("res://ui/map_left_cleanup.gdshader")
const MenuButtons := preload("res://ui/menu_button_styles.gd")
const LivingInk := preload("res://ui/chapter_map_effects.gd")
const DetailArt := preload("res://ui/chapter_map_detail_art.gd")
const Assets := preload("res://elements/element_assets.gd")
const NodeArt := preload("res://ui/chapter_map_node_art.gd")

var entries: Array[Dictionary] = []
var chapter := "valley"
var selected_id := ""
var overview_open := false
var can_resume := false
var can_save := false
var story_labels: Dictionary = {}
var preferred_focus: Button
var _canvas: Control
var _body: Control
var _chrome: Control
var _screen_chrome: Control
var _more_panel: Panel
var _tools_layer: Control
var _tools_open := false
var _extent := Vector2(1280, 720)
var _layout_extent := Vector2(1280,720)
var _placement_scale := Vector2.ONE
var _card_rect := Rect2()
var _enter_rect := Rect2()
const SCENERY_RECT := Rect2(0, 80, 876, 528)
var _overview: Control
var _scale := 1.0
var _pending_layout := false
var _settings: Dictionary = {}
var _living_ink: Control
var _paused := false
var _illustration_clock := 0.0

func apply_settings(settings: Dictionary) -> void:
	_settings=settings.duplicate(true)
	if is_instance_valid(_living_ink): _living_ink.apply_settings(_settings)
	for art: Node in find_children("RegisteredMapNodeArt", "Control", true, false): art.apply_settings(_settings)

func set_paused(value: bool) -> void:
	_paused=value
	if is_instance_valid(_living_ink): _living_ink.set_paused(value or overview_open)
	for art: Node in find_children("RegisteredMapNodeArt", "Control", true, false): art.set_paused(value or overview_open)


static func chapter_id(level: Dictionary) -> String:
	var id := str(level.get("id", ""))
	if id.begins_with("cloud-"):
		return "cloud"
	var value := str(level.get("chapter", id.get_slice("-", 0)))
	return str({"1": "valley", "2": "pond", "3": "cave"}.get(value, value))


static func progress_entries(levels: Array, progress: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var previous := ""
	var records: Dictionary = progress.get("records", {})
	for level: Dictionary in levels:
		var entry := level.duplicate(true)
		var id := str(entry.get("id", ""))
		entry["chapter"] = chapter_id(entry)
		var record: Dictionary = records.get(id, {})
		var run: Dictionary = progress.get("runs", {}).get(id, {})
		entry["completed"] = bool(record.get("completed", false))
		entry["unlocked"] = entry.chapter == "cloud" or previous.is_empty() or entry.completed or bool(progress.get("unlock_all", false)) or bool(records.get(previous, {}).get("completed", false))
		entry["collected_count"] = mini(int(entry.get("total", 0)), maxi(int(record.get("collected", 0)), run.get("collected", []).size()))
		entry["has_run"] = not run.is_empty() and not bool(run.get("completed", false))
		result.append(entry)
		if entry.chapter != "cloud":
			previous = id
	return result


func configure(levels: Array, progress: Dictionary, selection: Dictionary = {}) -> void:
	entries = progress_entries(levels, progress)
	var wanted := str(selection.get("level", progress.get("last_level", "1-1")))
	var entry := _entry(wanted)
	chapter = str(selection.get("chapter", entry.get("chapter", "valley")))
	if chapter not in CHAPTERS:
		chapter = "valley"
	selected_id = wanted if str(entry.get("chapter", "")) == chapter else ""
	_choose_default()
	name = "IllustratedChapterMap"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if not resized.is_connected(_schedule_layout):
		resized.connect(_schedule_layout)
	relayout()


func _entry(id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.id) == id:
			return entry
	return {}


func _chapter_entries(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if str(entry.chapter) == id:
			result.append(entry)
	return result


func _choose_default() -> void:
	var list := _chapter_entries(chapter)
	if list.is_empty() or str(_entry(selected_id).get("chapter", "")) == chapter:
		return
	selected_id = str(list[0].id)
	for entry: Dictionary in list:
		if entry.unlocked and not entry.completed:
			selected_id = str(entry.id)
			break


func select_level(id: String) -> void:
	var entry := _entry(id)
	if entry.is_empty():
		return
	chapter = str(entry.chapter)
	selected_id = id
	overview_open = false
	selection_changed.emit(chapter, selected_id)
	relayout()
	_focus_selected.call_deferred()


func select_chapter(id: String) -> void:
	if id not in CHAPTERS or _chapter_entries(id).is_empty():
		return
	chapter = id
	_choose_default()
	overview_open = false
	selection_changed.emit(chapter, selected_id)
	relayout()
	_focus_selected.call_deferred()


func close_overview() -> bool:
	if _tools_open:
		_tools_open = false
		relayout()
		_focus_selected.call_deferred()
		return true
	if not overview_open:
		return false
	overview_open = false
	relayout()
	_focus_selected.call_deferred()
	return true


func show_overview() -> void:
	_tools_open = false
	overview_open = true
	relayout()
	_focus_selected.call_deferred()


func _focus_selected() -> void:
	if is_instance_valid(preferred_focus) and preferred_focus.is_visible_in_tree():
		preferred_focus.grab_focus()


func _schedule_layout() -> void:
	if _pending_layout:
		return
	_pending_layout = true
	_relayout_deferred.call_deferred()


func _relayout_deferred() -> void:
	_pending_layout = false
	if is_inside_tree():
		relayout()


func relayout() -> void:
	if is_instance_valid(_living_ink): _illustration_clock=float(_living_ink.clock)
	var focused: Variant = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus := is_instance_valid(focused) and is_ancestor_of(focused)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	preferred_focus = null
	var extent := size if size.x > 0 and size.y > 0 else Vector2(1280, 720)
	_extent = extent
	var portrait := extent.y > extent.x
	_scale = extent.x / 876.0 if portrait else minf(extent.x / 1280.0, extent.y / 720.0)
	_layout_extent = Vector2(1280,720) if portrait else extent/_scale
	_placement_scale = _layout_extent/Vector2(1280,720)
	var backdrop := ColorRect.new()
	backdrop.color = Color("d4d0bb")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_canvas = Control.new()
	_canvas.size = Vector2(876, 528) if portrait else _layout_extent
	_canvas.scale = Vector2.ONE * _scale
	_canvas.position = Vector2(0, 90) if portrait else Vector2.ZERO
	_canvas.clip_contents = portrait
	_body = Control.new()
	_body.size = _layout_extent
	_body.position = Vector2(0,-80) if portrait else Vector2.ZERO
	_canvas.add_child(_body)
	if portrait:
		var page := ScrollContainer.new()
		page.name = "PortraitMapPage"
		page.size = extent
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.follow_focus = true
		add_child(page)
		_chrome = Control.new()
		_chrome.custom_minimum_size = Vector2(extent.x, maxf(844, extent.y))
		_chrome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_chrome.mouse_filter = Control.MOUSE_FILTER_PASS
		page.add_child(_chrome)
		_chrome.add_child(_canvas)
		var scenery := _picture(_body, "reference-scenes/map-%s.jpg" % ("valley" if chapter == "cloud" else chapter), Rect2(0,112,876,496), false)
		var crop := AtlasTexture.new()
		crop.atlas = scenery.texture
		crop.region = Rect2(0,112,876,496)
		scenery.texture = crop
	else:
		add_child(_canvas)
		var scenery := _picture(_body, "reference-scenes/map-%s.jpg" % ("valley" if chapter == "cloud" else chapter), Rect2(Vector2.ZERO,_layout_extent), false)
		scenery.name = "FullBleedMapScenery"
		_body.move_child(scenery, 0)
		_chrome = _body
	_screen_chrome = Control.new()
	_screen_chrome.name = "MapScreenControls"
	_screen_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_chrome)
	if not portrait: _clean_left_background()
	_scenery_overlays()
	_living_ink=LivingInk.new()
	_body.add_child(_living_ink)
	var terraces: Array = []
	for at: Vector2 in TERRACES: terraces.append(at*_placement_scale)
	_living_ink.configure(chapter,_chapter_entries(chapter),terraces,_placement_scale)
	_living_ink.clock=_illustration_clock
	_living_ink.apply_settings(_settings)
	_living_ink.set_paused(_paused or overview_open)
	_header()
	_markers()
	_detail()
	_previews()
	_utilities()
	_build_tools()
	if overview_open:
		# The illustration contains old baked counters/buttons. Keep our live
		# presentation covering them while the overview owns all interaction.
		_make_backdrop_inert(_screen_chrome)
		_make_backdrop_inert(_body)
		if _chrome != _body: _make_backdrop_inert(_chrome)
		_build_overview()
	if had_focus:
		_focus_selected.call_deferred()




func _scenery_overlays() -> void:
	# Restore the same authored step/moss layer used by levelSelectScene.ts.
	# Background flowerpots without numbered controls remain scenery.
	for placement: Vector3 in [Vector3(357, 486, 88), Vector3(309, 302, 83), Vector3(668, 464, 86), Vector3(667, 317, 85), Vector3(838, 160, 82)]:
		_picture(_body, "reference-scenes/terrain-steps.png", Rect2(Vector2(placement.x,placement.y)*_placement_scale,Vector2.ONE*placement.z))
	_picture(_body, "production/light.png", Rect2(Vector2(670,406)*_placement_scale,Vector2(78,78)))
	_picture(_body, "production/moss.png", Rect2(Vector2(675,264)*_placement_scale,Vector2(73,73)))
	_picture(_body, "production/moss.png", Rect2(Vector2(847,112)*_placement_scale,Vector2(66,66)))


func _clean_left_background() -> void:
	# Sample only the removed left UI; preserve every terrain/node pixel elsewhere.
	var source := Assets.texture_for_source("res://assets/images/map-menu-20261119/clean-left-map.png")
	for rect: Rect2 in [Rect2(0,0,440,135),Rect2(8,605,115,109)]:
		var patch := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		atlas.region = Rect2(rect.position*source.get_size()/Vector2(1280,720),rect.size*source.get_size()/Vector2(1280,720))
		patch.texture = atlas
		patch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		patch.stretch_mode = TextureRect.STRETCH_SCALE
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		patch.position = rect.position*_placement_scale
		patch.size = rect.size*_placement_scale
		var material := ShaderMaterial.new()
		material.shader = CleanupShader
		material.set_shader_parameter("atlas_region",Vector4(rect.position.x/1280.0,rect.position.y/720.0,rect.size.x/1280.0,rect.size.y/720.0))
		# Original pond/cave files are affine color grades of the same valley art.
		# Measured RGB transform preserves their hue at the patch boundaries.
		material.set_shader_parameter("chapter_multiplier",Vector3(.7695,.7679,.7664) if chapter == "pond" else Vector3(.3998,.4010,.3987) if chapter == "cave" else Vector3.ONE)
		material.set_shader_parameter("chapter_offset",Vector3(.0832,.1322,.1272) if chapter == "pond" else Vector3(.0798,.0961,.1469) if chapter == "cave" else Vector3.ZERO)
		patch.material = material
		_body.add_child(patch)

func _screen_button(parent: Control, caption: String, action: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var button := MapMenuSkin.button(caption,action,primary)
	button.set_meta("action",action)
	button.pressed.connect(callback)
	parent.add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button

func _header() -> void:
	var back := _screen_button(_screen_chrome,"返回","home",Rect2(18,18,96,48),func() -> void: action_requested.emit("home"))
	back.tooltip_text = "返回主界面"
	if _extent.y > _extent.x:
		back.size.x = 82
		_label(_screen_chrome,TITLES[chapter],Rect2(110,18,_extent.x-128,32),21)
		_label(_screen_chrome,DESCRIPTIONS[chapter],Rect2(18,58,_extent.x-36,25),12,MUTED)
		return
	var small := _extent.x < 1000 or _extent.y < 500
	if not small:
		var logo := _picture(_screen_chrome,"material-ready/menu-logo.png",Rect2(128,8,236,115))
		logo.name = "MapHomeLogo"

	var total := 0
	for entry: Dictionary in entries:
		if entry.chapter != "cloud": total += int(entry.collected_count)
	var counter := _panel(_body,Rect2(Vector2(1110,29)*_placement_scale,Vector2(150,51)*_placement_scale),Color("807f6ce8"),25)
	_label(counter,"☀ %d  旅程微光" % total,Rect2(5,2,counter.size.x-10,counter.size.y-4),17,Color("fff6dc"))
	var center := _layout_extent.x*.49
	var night := chapter == "cave"
	var title := _label(_body,TITLES[chapter],Rect2(center-165,70,330,37),27,Color("fff1d1") if night else INK)
	title.name = "MapChapterTitle"
	var number := _label(_body,"第 %s 章" % str(CHAPTERS.find(chapter)+1) if chapter != "cloud" else "独立花园",Rect2(center-165,44,330,24),12,Color("eee0bf") if night else MUTED)
	var description := _label(_body,DESCRIPTIONS[chapter],Rect2(center-210,107,420,25),12,Color("eee0bf") if night else MUTED)
	if night:
		for label: Label in [title,number,description]:
			label.add_theme_color_override("font_shadow_color",Color("24243188"))
			label.add_theme_constant_override("shadow_offset_x",0)
			label.add_theme_constant_override("shadow_offset_y",2)
			label.add_theme_constant_override("shadow_outline_size",1)




func _markers() -> void:
	var list := _chapter_entries(chapter)
	for index in list.size():
		var entry := list[index]
		var at: Vector2 = TERRACES[index % TERRACES.size()]*_placement_scale
		var id := str(entry.id)
		var visual_origin := at - Vector2(63, 117)
		var hit_width := maxf(126, 44 / _scale)
		var hit_height := maxf(178, 44 / _scale)
		var hit_origin := Vector2(clampf(at.x - hit_width * .5, SCENERY_RECT.position.x, SCENERY_RECT.end.x * _placement_scale.x - hit_width), maxf(SCENERY_RECT.position.y, at.y - 117))
		var marker := _button(_body, "", Rect2(hit_origin, Vector2(hit_width, hit_height)), select_level.bind(id), true)
		var art_origin := visual_origin - hit_origin
		marker.name = "MapMarker_" + id
		marker.set_meta("map_level", id)
		marker.tooltip_text = "%s · %s\n%s" % [id, entry.get("title", ""), "已复苏" if entry.completed else "可以进入" if entry.unlocked else "先让前一关苏醒"]
		if LivingInk.CAPTIONS.has(id): marker.tooltip_text += "\n"+str(LivingInk.CAPTIONS[id])
		var art := NodeArt.new()
		marker.add_child(art)
		art.position = art_origin + Vector2(-7, -4)
		art.configure(entry, chapter, id == selected_id, _settings, _illustration_clock, _paused or overview_open)
		_panel(marker, Rect2(art_origin + Vector2(8, 136), Vector2(110, 34)), Color("fff2d8"), 17)
		_label(marker, id + (" ✓" if entry.completed else ""), Rect2(art_origin + Vector2(8, 136), Vector2(110, 34)), 17)
		if id == selected_id and not entry.unlocked: preferred_focus = marker


func _detail() -> void:
	var entry := _entry(selected_id)
	if entry.is_empty(): return
	_card_rect = Rect2(18,350,_extent.x-36,350) if _extent.y>_extent.x else Rect2(Vector2(930,165)*_placement_scale,Vector2(318,350)*_placement_scale)
	var parent_scale := _control_scale(_chrome)
	var panel := _panel(_chrome,_card_rect,Color("fbefdc"),24)
	panel.name = "MapSelectedCard"
	panel.scale = Vector2.ONE/parent_scale
	panel.size = _card_rect.size*parent_scale
	panel.set_meta("screen_card",true)
	var width := panel.size.x
	var height := panel.size.y
	var short := height < 285
	var margin := 18.0 if short else width*.095
	var inner := width-margin*2
	var factor := clampf(width/318.0, .8, 1.35)
	var frame := MapMenuSkin.surface(Color("fbefdc"),Color("c8b38d"),29)
	frame.set_border_width_all(2)
	frame.shadow_color = Color("49392025"); frame.shadow_size = 7
	panel.add_theme_stylebox_override("panel",frame)
	panel.add_child(CardArt.new())
	var art := CardArt.new()
	art.kind = "detail"; art.stages = _chapter_entries(chapter); art.selected = selected_id
	art.visible = not short
	panel.add_child(art)
	if not short:
		var eyebrow := _label(panel,"已唤醒的微光" if entry.completed else "下一段旅程" if entry.unlocked else "沉睡中的微光",Rect2(margin,height*.057,inner,20*factor),roundi(11*factor),Color("8b9978"))
		eyebrow.name = "MapEntryState"
	_label(panel,TITLES[chapter],Rect2(margin,height*.137 if not short else 9,inner,38*factor if not short else 26),roundi(26*factor) if not short else 18)
	_label(panel,"%s  ·  %s" % [selected_id,entry.get("title","")],Rect2(margin,height*.323 if not short else 39,inner,minf(24*factor,height*.07) if not short else 24),roundi(15*factor) if not short else 12)
	if not short:
		_label(panel,str(entry.get("rule",entry.get("subtitle",""))),Rect2(margin,height*.402,inner,height*.063),roundi(11*factor),MUTED)
	var count_y := height*.465 if not short else 70.0
	var count_h := height*.125 if not short else 30.0
	var collection := _panel(panel,Rect2(margin,count_y,inner,count_h),Color("fff5e3"),14)
	collection.add_theme_stylebox_override("panel",MapMenuSkin.surface(Color("fff5e3"),Color("eedec1"),14))
	var row_width := minf(inner,164*factor)
	var left := (inner-row_width)*.5
	_label(collection,"收集",Rect2(left,0,46*factor,count_h),roundi(15*factor))
	var light := TextureRect.new()
	light.texture = Assets.texture("spore")
	light.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	light.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	collection.add_child(light)
	light.position = Vector2(left+49*factor,3)
	light.size = Vector2(32*factor,count_h-6)
	_label(collection,"%d  /  %d" % [entry.collected_count,int(entry.get("total",0))],Rect2(left+84*factor,0,80*factor,count_h),roundi(15*factor))
	var enter_height := maxf(44,height*.125)
	var enter_y := height*.76 if not short else height-56
	_enter_rect = Rect2(panel.position+Vector2(margin,enter_y)/parent_scale,Vector2(inner,enter_height)/parent_scale)
	var caption := "继续关卡" if entry.has_run else "重访关卡" if entry.completed else "进入关卡" if entry.unlocked else "等待前一关苏醒"
	var enter := MapMenuSkin.button(caption,"resume",true)
	enter.icon = null
	enter.custom_minimum_size = Vector2(0,44)
	enter.add_theme_font_size_override("font_size",roundi(22*factor) if not short else 13)
	panel.add_child(enter)
	enter.position = Vector2(margin,enter_y); enter.size = Vector2(inner,enter_height)
	var flower := CardArt.new(); flower.kind = "button"
	flower.visible = not short
	enter.add_child(flower)
	enter.name = "MapEnterLevel"; enter.set_meta("level_id",selected_id)
	enter.pressed.connect(_enter_selected)
	enter.disabled = not entry.unlocked
	enter.focus_mode = Control.FOCUS_NONE if enter.disabled else Control.FOCUS_ALL
	if entry.unlocked: preferred_focus = enter
	var values := _chapter_progress(chapter)
	if not short: _label(panel,"本章微光 %d / %d  ·  已唤醒 %d / %d" % [values.collected,values.total,values.completed,values.count],Rect2(margin,height*.923,inner,18*factor),roundi(10*factor),MUTED)




func _enter_selected() -> void:
	if bool(_entry(selected_id).get("unlocked", false)):
		level_requested.emit(selected_id)


func _chapter_progress(id: String) -> Dictionary:
	var values := {"collected": 0, "total": 0, "completed": 0, "count": 0, "unlocked": false}
	for entry: Dictionary in _chapter_entries(id):
		values.collected += int(entry.collected_count)
		values.total += int(entry.get("total", 0))
		values.completed += int(entry.completed)
		values.count += 1
		values.unlocked = values.unlocked or entry.unlocked
	return values


func _previews() -> void:
	var others: Array[String] = []
	for id: String in CHAPTERS:
		if id != chapter and id != "cloud" and not _chapter_entries(id).is_empty():
			others.append(id)
	for index in mini(2, others.size()):
		var rect := Rect2(Vector2(878+index*185,522)*_placement_scale,Vector2(177,169)*_placement_scale)
		if _extent.y > _extent.x:
			var width := (_extent.x - 48) * .5
			rect = Rect2(18 + index * (width + 12), 714, width, 118)
		_chapter_card(_chrome, others[index], rect, false)


func _chapter_card(parent: Control, id: String, rect: Rect2, large: bool) -> Button:
	var parent_scale := _control_scale(parent)
	var card := MapMenuSkin.button("","gallery")
	card.icon = null
	parent.add_child(card)
	card.position = rect.position
	card.scale = Vector2.ONE/parent_scale
	card.size = rect.size*parent_scale
	card.set_meta("screen_card",true)
	card.set_meta("map_chapter",id)
	card.pressed.connect(select_chapter.bind(id))
	card.clip_contents = true
	card.name = "ChapterPreview_"+id
	var width := card.size.x
	var height := card.size.y
	var compact := height < 130
	var factor := clampf(width/177.0,.8,1.4)
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		var frame := MapMenuSkin.surface(Color("fbefdc") if state == "normal" else Color("fff6e4"),Color("c5b58f"),29)
		frame.set_border_width_all(2)
		card.add_theme_stylebox_override(state,frame)
	var focus := MapMenuSkin.surface(Color.TRANSPARENT,Color("b98a40"),29)
	focus.set_border_width_all(2)
	card.add_theme_stylebox_override("focus",focus)
	var artwork := "chapter-covers-20261119-v2/%s.png" % id if id != "cloud" else "production/bug.png"
	var values := _chapter_progress(id)
	var image_height := height*.75 if large else height*.70
	var image := _picture(card,artwork,Rect2(8,8,width-16,image_height),false)
	image.name = "ChapterCover"
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var material := ShaderMaterial.new()
	material.shader = CoverShader
	material.set_shader_parameter("extent",image.size)
	image.material = material
	if not values.unlocked:
		var lock := TextureRect.new()
		lock.texture = MapMenuSkin.icon("lock",true)
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(lock)
		lock.name = "ChapterLock"
		lock.position = Vector2(width*.5-14,image_height*.4)
		lock.size = Vector2(28,32)
	card.add_child(CardArt.new())
	var title_y := height*.70 if large else height*.64
	_label(card,TITLES[id],Rect2(8,title_y,width-16,30*factor if not compact else 22),24 if large else roundi(19*factor) if not compact else 13)
	if height >= 100: _label(card,"已唤醒 %d / %d" % [values.completed,values.count] if values.unlocked else "静待微光唤醒",Rect2(8,height-27*factor,width-16,20*factor),13 if large else 11,MUTED)

	return card


func _utilities() -> void:
	var y := 300.0 if _extent.y > _extent.x else _extent.y-66
	_screen_button(_screen_chrome,"世界总览","world_overview",Rect2(18,y,134,48),show_overview)
	var more := _screen_button(_screen_chrome,"更多","map_tools",Rect2(164,y,100,48),func() -> void:
		_tools_open = not _tools_open
		relayout()
		_focus_selected.call_deferred())
	more.tooltip_text = "打开旅途手记"

func _tool_label(parent: Node, text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_tools() -> void:
	_tools_layer = Control.new()
	_tools_layer.name = "MapToolsLayer"
	_tools_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tools_layer.visible = _tools_open and not overview_open
	add_child(_tools_layer)
	if _tools_open and not overview_open:
		_make_backdrop_inert(_body)
		_make_backdrop_inert(_screen_chrome)
		if _chrome != _body: _make_backdrop_inert(_chrome)
	var shade := Button.new()
	shade.name = "DismissMapToolsBackdrop"
	shade.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal","hover","pressed","focus"]:
		shade.add_theme_stylebox_override(state,MapMenuSkin.surface(Color("29362d55"),Color.TRANSPARENT,0))
	_tools_layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.pressed.connect(func() -> void: close_overview())
	var width := minf(382,_extent.x-32)
	var height := minf(490 if chapter == "cloud" else 434,_extent.y-40)
	_more_panel = Panel.new()
	_more_panel.name = "MapMoreActions"
	var paper := MapMenuSkin.surface(Color("fbefda"),Color("d3bb90"),22)
	paper.shadow_color = Color("17231944"); paper.shadow_size = 14; paper.shadow_offset = Vector2(0,7)
	_more_panel.add_theme_stylebox_override("panel",paper)
	_more_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_tools_layer.add_child(_more_panel)
	_more_panel.size = Vector2(width,height)
	_more_panel.position = Vector2(18,maxf(20,_extent.y-height-82)) if _extent.x >= 700 else (_extent-_more_panel.size)*.5
	_more_panel.add_child(MapMenuPaper.new())
	var header := _tool_label(_more_panel,"旅途手记",23)
	header.position = Vector2(24,20)
	var subtitle := _tool_label(_more_panel,"歇一歇，也看看沿途的发现。",12,MUTED)
	subtitle.position = Vector2(24,54)
	var close := _screen_button(_more_panel,"","close_map_tools",Rect2(width-64,16,44,44),func() -> void: close_overview())
	close.tooltip_text = "收起旅途手记"
	var scroller := ScrollContainer.new()
	scroller.name = "MapToolsScroll"
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.follow_focus = true
	_more_panel.add_child(scroller)
	scroller.position = Vector2(20,88)
	scroller.size = Vector2(width-40,height-126)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	scroller.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",10)
	body.add_child(grid)
	var actions := [{"id":"settings","text":"设置","hint":"声音与画面"},{"id":"gallery","text":"图鉴","hint":"珍藏每次相遇"},{"id":"journal","text":"花园纪事","hint":"翻阅旅程故事"}]
	if not _chapter_entries("cloud").is_empty(): actions.append({"id":"cloud","text":"云庭微光","hint":"三座独立花园"})
	for action: Dictionary in actions:
		var target := str(action.id)
		var tile := MapMenuSkin.button(str(action.text),target)
		tile.custom_minimum_size = Vector2(0,80)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tile.set_meta("action",target)
		for state: String in ["normal","hover","pressed","hover_pressed"]:
			var style := tile.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.content_margin_bottom = 30
			tile.add_theme_stylebox_override(state,style)
		var hint := _tool_label(tile,str(action.hint),11,MUTED)
		hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		hint.offset_left = 14; hint.offset_top = -29; hint.offset_bottom = -9
		tile.pressed.connect(func() -> void:
			if target == "cloud":
				_tools_open = false
				select_chapter("cloud")
			else: action_requested.emit(target))
		grid.add_child(tile)
		if target == "settings" and _tools_open: preferred_focus = tile
	if can_resume:
		var resume := MapMenuSkin.button("继续当前关卡","resume",true)
		resume.set_meta("action","resume")
		resume.pressed.connect(func() -> void: action_requested.emit("resume"))
		body.add_child(resume)
	if can_save:
		var save := MapMenuSkin.button("导入 / 导出旅程","save")
		save.set_meta("action","save")
		save.pressed.connect(func() -> void: action_requested.emit("save"))
		body.add_child(save)
	if chapter == "cloud":
		var story := MapMenuSkin.button(str(story_labels.get(selected_id,"口袋里的小事")),"cloud_story")
		story.set_meta("action","cloud_story")
		story.set_meta("cloud_story_level",selected_id)
		story.pressed.connect(func() -> void: cloud_story_requested.emit(selected_id))
		body.add_child(story)
	var footer := _tool_label(_more_panel,"把一粒微光，种成回家的路。",11,MUTED)
	footer.position = Vector2(24,height-28)



func _make_backdrop_inert(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.focus_mode = Control.FOCUS_NONE
	node.tooltip_text = ""
	if node is Button:
		# Preserve the current appearance, including a genuinely locked entry.
		if not node.disabled:
			node.add_theme_stylebox_override("disabled", node.get_theme_stylebox("normal"))
			node.add_theme_color_override("font_disabled_color", node.get_theme_color("font_color"))
			node.disabled = true
	for child: Node in node.get_children():
		if child is Control:
			_make_backdrop_inert(child)


func _build_overview() -> void:
	_overview = Control.new()
	_overview.name = "WorldOverview"
	_overview.size = Vector2(1280, 720)
	var dialog_scale := minf(_extent.x / 1280.0, _extent.y / 720.0)
	_overview.scale = Vector2.ONE * dialog_scale
	_overview.position = (_extent - Vector2(1280,720) * dialog_scale) * .5
	add_child(_overview)
	var shade := ColorRect.new()
	shade.color = Color("324335bb")
	shade.size = _extent
	add_child(shade)
	move_child(shade, _overview.get_index())
	_panel(_overview, Rect2(110, 84, 1060, 552), Color("fbefdb"), 32)
	_label(_overview, "微光走过的地方", Rect2(240, 102, 800, 60), 30)
	var close := _button(_overview, "返回地图", Rect2(955, 100, 190, maxf(50, 44 / _scale)), close_overview)
	close.set_meta("action", "close_overview")
	var index := 0
	for id: String in ["valley","pond","cave"]:
		if _chapter_entries(id).is_empty():
			continue
		var card := _chapter_card(_overview, id, Rect2(220 + index * 285, 209, 260, 330), true)
		if id == chapter:
			preferred_focus = card
		index += 1
	_label(_overview, "选择一张地图，看看微光走过的地方。", Rect2(170, 555, 940, 54), 15, MUTED)


func _picture(parent: Control, file: String, rect: Rect2, keep_aspect: bool = true) -> TextureRect:
	var node := TextureRect.new()
	node.texture = Assets.texture_for_source("res://assets/images/" + file)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if keep_aspect else TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node


func _control_scale(parent: Control) -> float:
	var ancestor: Node = parent
	while ancestor != null and ancestor != self:
		if ancestor.has_meta("screen_card"): return 1.0
		ancestor = ancestor.get_parent()
	if is_instance_valid(_screen_chrome) and (parent == _screen_chrome or _screen_chrome.is_ancestor_of(parent)): return 1.0
	if _extent.y > _extent.x and is_instance_valid(_chrome) and (parent == _chrome or _chrome.is_ancestor_of(parent)) and not _body.is_ancestor_of(parent): return 1.0
	if is_instance_valid(_overview) and (parent == _overview or _overview.is_ancestor_of(parent)): return _overview.scale.x
	return _scale



func _label(parent: Control, value: String, rect: Rect2, font_size: int, color: Color = INK, backing: bool = false) -> Label:
	if backing:
		_panel(parent, rect, Color("81796bcc"), 14)
	var node := Label.new()
	# Give wrapping its real width before text enters the tree. Otherwise its
	# initial zero-width minimum height can remain as an oversized fixed rect.
	node.size = rect.size
	node.text = value
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", maxi(font_size, ceili(11 / _control_scale(parent))))
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node


func _style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


func _panel(parent: Control, rect: Rect2, color: Color, radius: int) -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _style(color, Color("e5d0b0"), radius))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	return panel


func _button(parent: Control, value: String, rect: Rect2, callback: Callable, transparent: bool = false, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.add_theme_font_size_override("font_size", maxi(17, ceili(12 / _control_scale(parent))))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT if transparent else Color("f8ecd5"), Color.TRANSPARENT if transparent else Color("ddc6a0"), 22))
	button.add_theme_stylebox_override("hover", _style(Color("fff4d762") if transparent else Color("fff5e1"), Color("f0d9a4"), 22))
	button.add_theme_stylebox_override("pressed", _style(Color("ead7b780"), Color("cfb887"), 22))
	button.add_theme_stylebox_override("disabled", _style(Color("e5dfd0"), Color("d1c6ae"), 22))
	if primary:
		button.add_theme_stylebox_override("normal", _style(Color("96aa72"), Color("748854"), 26))
		button.add_theme_stylebox_override("hover", _style(Color("acbf89"), Color("748854"), 26))
		button.add_theme_color_override("font_color", Color("fff9e1"))
		button.add_theme_color_override("font_hover_color", Color("fff9e1"))
		button.add_theme_color_override("font_pressed_color", Color("fff9e1"))
		button.add_theme_stylebox_override("pressed", _style(Color("7f965f"), Color("657b49"), 26))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	MenuButtons.focus_like_hover(button)
	parent.add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button
