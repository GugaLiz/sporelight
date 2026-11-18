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
const MenuButtons := preload("res://ui/menu_button_styles.gd")
const LivingInk := preload("res://ui/chapter_map_effects.gd")
const DetailArt := preload("res://ui/chapter_map_detail_art.gd")
const Assets := preload("res://elements/element_assets.gd")

var entries: Array[Dictionary] = []
var chapter := "valley"
var selected_id := ""
var overview_open := false
var can_resume := false
var can_save := false
var story_labels: Dictionary = {}
var preferred_focus: Button
var _map_scroll: ScrollContainer
var _map_content: Control
var _canvas: Control
var _body: Control
var _chrome: Control
var _tools_open := false
var _extent := Vector2(1280, 720)
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

func set_paused(value: bool) -> void:
	_paused=value
	if is_instance_valid(_living_ink): _living_ink.set_paused(value or overview_open)


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
	var portrait := extent.x < 700 and extent.y > extent.x
	var enter_height := 56.0 if extent.y > 500 else 48.0
	_enter_rect = Rect2(Vector2((extent.x - minf(280, extent.x - 32)) * .5, extent.y - enter_height - 12), Vector2(minf(280, extent.x - 32), enter_height))
	var card_height := 88.0 if extent.y > 500 else 62.0 if extent.y > 340 else 44.0
	var card_bottom := _enter_rect.position.y - (64 if portrait else 12)
	_card_rect = Rect2(Vector2((extent.x - minf(282, extent.x - 144)) * .5, card_bottom - card_height), Vector2(minf(282, extent.x - 144), card_height))
	var scene_top := 72.0 if extent.y > 500 else 54.0
	var scene_height := maxf(132, _card_rect.position.y - scene_top - 8)
	_scale = extent.x / SCENERY_RECT.size.x
	var scene_display_height := minf(scene_height, SCENERY_RECT.size.y * _scale)
	var backdrop := ColorRect.new()
	backdrop.color = Color("b7c7c0")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_canvas = Control.new()
	# The supplied illustration contains baked UI outside this scenic crop.
	# Both artwork and live landmarks share this transform; no bitmap is stretched.
	var atmosphere := _picture(self, "main/bg.png", Rect2(Vector2.ZERO, extent))
	atmosphere.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	atmosphere.modulate = Color("cad5c0a0")
	_canvas.name = "ChapterSceneryViewport"
	_canvas.size = Vector2(extent.x, scene_display_height)
	_canvas.position = Vector2(0, scene_top + (scene_height - scene_display_height) * .5)
	_canvas.clip_contents = true
	add_child(_canvas)
	_map_scroll = ScrollContainer.new()
	_map_scroll.name = "MapSceneryScroll"
	_map_scroll.size = _canvas.size
	_map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_map_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_map_scroll.follow_focus = true
	_canvas.add_child(_map_scroll)
	_map_content = Control.new()
	_map_content.custom_minimum_size = SCENERY_RECT.size * _scale
	_map_content.clip_contents = true
	_map_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_map_scroll.add_child(_map_content)
	_body = Control.new()
	_body.size = Vector2(1280, 720)
	_body.scale = Vector2.ONE * _scale
	_body.position = -SCENERY_RECT.position * _scale
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_map_content.add_child(_body)
	# Exclude every baked button/counter from the opaque picture. Foreground
	# landmarks may extend into the small mist margin above its scenic crop.
	var scenery := _picture(_body, "reference-scenes/map-%s.jpg" % ("valley" if chapter == "cloud" else chapter), Rect2(0,112,876,496), false)
	var scenic_crop := AtlasTexture.new()
	scenic_crop.atlas = scenery.texture
	scenic_crop.region = Rect2(0,112,876,496)
	scenery.texture = scenic_crop

	_chrome = Control.new()
	_chrome.name = "MapNavigation"
	_chrome.size = extent
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chrome)
	_scenery_overlays()
	_living_ink=LivingInk.new()
	_body.add_child(_living_ink)
	_living_ink.configure(chapter,_chapter_entries(chapter),TERRACES)
	_living_ink.clock=_illustration_clock
	_living_ink.apply_settings(_settings)
	_living_ink.set_paused(_paused or overview_open)
	_header()
	if SCENERY_RECT.size.y * _scale > _canvas.size.y + 1:
		_label(_chrome, "上下滑动地图选关", Rect2(extent.x - 150, _canvas.position.y + 4, 140, 24), 12, Color("fff7e4"), true)
	_markers()
	_detail()
	_utilities()
	_build_tools()
	if overview_open:
		# The illustration contains old baked counters/buttons. Keep our live
		# presentation covering them while the overview owns all interaction.
		_make_backdrop_inert(_body)
		_make_backdrop_inert(_chrome)
		_build_overview()
	_center_selected.call_deferred()
	if had_focus:
		_focus_selected.call_deferred()


func _center_selected() -> void:
	if not is_inside_tree(): return
	var tree := get_tree()
	var scroll := _map_scroll
	await tree.process_frame
	if not is_inside_tree() or not is_instance_valid(scroll) or scroll != _map_scroll: return
	await tree.process_frame
	if not is_inside_tree() or not is_instance_valid(scroll) or scroll != _map_scroll: return
	var list := _chapter_entries(chapter)
	for index in list.size():
		if str(list[index].id) != selected_id: continue
		var source_y: float = (TERRACES[index].y - 54 - SCENERY_RECT.position.y) * _scale
		_map_scroll.scroll_vertical = roundi(maxf(0, source_y - _map_scroll.size.y * .5))
		break


func _scenery_overlays() -> void:
	# Restore the same authored step/moss layer used by levelSelectScene.ts.
	# Background flowerpots without numbered controls remain scenery.
	for placement: Vector3 in [Vector3(357, 486, 88), Vector3(309, 302, 83), Vector3(668, 464, 86), Vector3(667, 317, 85), Vector3(838, 160, 82)]:
		_picture(_body, "reference-scenes/terrain-steps.png", Rect2(placement.x, placement.y, placement.z, placement.z))
	_picture(_body, "production/light.png", Rect2(670, 406, 78, 78))
	_picture(_body, "production/moss.png", Rect2(675, 264, 73, 73))
	_picture(_body, "production/moss.png", Rect2(847, 112, 66, 66))


func _header() -> void:
	var short := _extent.y <= 500
	var bar := _panel(_chrome, Rect2(0, 0, _extent.x, 62 if short else 70), Color("fff5e5e8"), 0)
	bar.name = "MapHeader"
	var back := _button(_chrome, "返回", Rect2(12, 9, 60, 44), func() -> void: action_requested.emit("home"))
	back.set_meta("action", "home")
	var total := 0
	for entry: Dictionary in entries:
		if entry.chapter != "cloud": total += int(entry.collected_count)
	var title_width := 140.0 if _extent.x < 500 else 300.0
	var title_x := 80.0 if _extent.x < 500 else (_extent.x - title_width) * .5
	_label(_chrome, TITLES[chapter], Rect2(title_x, 8, title_width, 28 if short else 31), 19 if short else 23)
	if _extent.x >= 700 and not short:
		_label(_chrome, DESCRIPTIONS[chapter], Rect2(title_x - 45, 38, title_width + 90, 23), 12, MUTED)
	var count_width := 72.0 if _extent.x < 500 else 122.0
	var counter := _panel(_chrome, Rect2(_extent.x - count_width - 82, 9, count_width, 44), Color("f4ebd6"), 18)
	counter.tooltip_text = "旅程中已收集的微光"
	_label(counter, "☀ %d" % total, Rect2(3, 0, count_width - 6, 44), 17)
	var settings := _button(_chrome, "设置", Rect2(_extent.x - 72, 9, 60, 44), func() -> void: action_requested.emit("settings"))
	settings.set_meta("action", "settings")


func _markers() -> void:
	var list := _chapter_entries(chapter)
	for index in list.size():
		var entry := list[index]
		var at: Vector2 = TERRACES[index % TERRACES.size()]
		var id := str(entry.id)
		var visual_origin := at - Vector2(63, 117)
		var hit_width := maxf(126, 44 / _scale)
		var hit_height := maxf(158, 44 / _scale)
		var hit_origin := Vector2(clampf(at.x - hit_width * .5, SCENERY_RECT.position.x, SCENERY_RECT.end.x - hit_width), maxf(SCENERY_RECT.position.y, at.y - 117))
		var marker := _button(_body, "", Rect2(hit_origin, Vector2(hit_width, hit_height)), select_level.bind(id), true)
		var art_origin := visual_origin - hit_origin
		# The fourth authored landmark sits behind the chapter heading. Inset
		# only its feedback paint, preserving the original art and hit rectangle.
		if index==3:
			for state: String in ["normal","hover","pressed","disabled"]:
				var surface:=marker.get_theme_stylebox(state) as StyleBoxFlat
				surface.expand_margin_top=-50.0
			marker.add_theme_stylebox_override("hover_pressed",marker.get_theme_stylebox("pressed"))
		marker.name = "MapMarker_" + id
		marker.set_meta("map_level", id)
		marker.tooltip_text = "%s · %s\n%s" % [id, entry.get("title", ""), "已复苏" if entry.completed else "可以进入" if entry.unlocked else "先让前一关苏醒"]
		if LivingInk.CAPTIONS.has(id): marker.tooltip_text += "\n"+str(LivingInk.CAPTIONS[id])
		var art := "plant-bloom" if entry.completed else "plant-bud" if entry.unlocked else "plant-dormant"
		if entry.completed and chapter in ["pond", "cave"]:
			art = "plant-%s-bloom" % chapter
		_picture(marker, "reference-scenes/%s.png" % art, Rect2(art_origin + Vector2(-7, -4), Vector2(140, 140)))
		if not entry.unlocked:
			_label(marker, "待唤醒", Rect2(art_origin + Vector2(9, 60), Vector2(108, 36)), 13, Color("fff6df"), true)
		if id == selected_id and entry.unlocked:
			_picture(marker, "character-refined/idle-front.png", Rect2(art_origin + Vector2(18, 10), Vector2(89, 89)))
		_panel(marker, Rect2(art_origin + Vector2(8, 118), Vector2(110, 38)), Color("fff2d8"), 18)
		_label(marker, id + (" ✓" if entry.completed else ""), Rect2(art_origin + Vector2(8, 118), Vector2(110, 38)), 17)
		if id == selected_id:
			if index==3:
				# Keep the same resource captured by focus_like_hover so leaving
				# keyboard focus restores this selected style, with its inset.
				var selected_surface:=marker.get_theme_stylebox("normal") as StyleBoxFlat
				selected_surface.bg_color=Color("fff4b12b")
				selected_surface.border_color=Color("fff1b6")
				selected_surface.set_corner_radius_all(34)
			else:
				marker.add_theme_stylebox_override("normal", _style(Color("fff4b12b"), Color("fff1b6"), 34))
			if not entry.unlocked:
				preferred_focus = marker


func _detail() -> void:
	var entry := _entry(selected_id)
	if entry.is_empty(): return
	var panel := _panel(_chrome, _card_rect, Color("fff2dfed"), 26)
	panel.name = "MapSelectedCard"
	var compact := _card_rect.size.y < 70
	var title := "%s · %s" % [selected_id, entry.get("title", "")]
	_label(panel, title, Rect2(8, 2, panel.size.x - 16, 24 if compact else 32), 16 if compact else 19)
	var status := "微光 %d / %d" % [entry.collected_count, int(entry.get("total", 0))]
	if not entry.unlocked: status = "先让前一关苏醒"
	elif entry.completed: status += "  ·  已唤醒"
	if _card_rect.size.y > 48:
		_label(panel, status, Rect2(8, 28 if compact else 36, panel.size.x - 16, 24), 12, MUTED)
	if not compact:
		var values := _chapter_progress(chapter)
		_label(panel, "本章已唤醒 %d / %d" % [values.completed, values.count], Rect2(8, 62, panel.size.x - 16, 20), 11, MUTED)
	var enter := _button(_chrome, "继续关卡" if entry.has_run else "重访关卡" if entry.completed else "开始冒险" if entry.unlocked else "等待前一关苏醒", _enter_rect, _enter_selected, false, true)
	enter.name = "MapEnterLevel"
	enter.set_meta("level_id", selected_id)
	enter.tooltip_text = "继续关卡" if entry.has_run else "重访关卡" if entry.completed else "进入关卡" if entry.unlocked else "先让前一关苏醒"
	enter.disabled = not entry.unlocked
	enter.focus_mode = Control.FOCUS_NONE if enter.disabled else Control.FOCUS_ALL
	if entry.unlocked: preferred_focus = enter
	var list := _chapter_entries(chapter)
	var current := 0
	for index in list.size():
		if str(list[index].id) == selected_id: current = index
	for direction in [-1,1]:
		var target_index: int = current + direction
		var x := _card_rect.position.x - 54 if direction < 0 else _card_rect.end.x + 10
		var previous_next := _button(_chrome, "‹" if direction < 0 else "›", Rect2(x,_card_rect.position.y + (_card_rect.size.y - 44) * .5,44,44), func() -> void:
			if target_index >= 0 and target_index < list.size(): select_level(str(list[target_index].id)))
		previous_next.name = "MapPreviousLevel" if direction < 0 else "MapNextLevel"
		previous_next.set_meta("action", "map_previous" if direction < 0 else "map_next")
		previous_next.tooltip_text = "上一座花园" if direction < 0 else "下一座花园"
		previous_next.disabled = target_index < 0 or target_index >= list.size()
		previous_next.focus_mode = Control.FOCUS_NONE if previous_next.disabled else Control.FOCUS_ALL


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
		_chapter_card(_body, others[index], Rect2(878 + index * 185, 522, 177, 169), false)


func _chapter_card(parent: Control, id: String, rect: Rect2, large: bool) -> Button:
	var card := _button(parent, "", rect, select_chapter.bind(id))
	card.set_meta("map_chapter", id)
	card.clip_contents = true
	var art := "valley" if id == "cloud" else id
	var picture := _picture(card, "reference-scenes/chapter-%s.jpg" % art, Rect2(12, 12, rect.size.x - 24, rect.size.y * 0.50), false)
	var crop := AtlasTexture.new()
	crop.atlas = picture.texture
	crop.region = Rect2(80, 85, 310, 175)
	picture.texture = crop
	card.name = "ChapterPreview_" + id
	_label(card, TITLES[id], Rect2(4, rect.size.y * 0.57, rect.size.x - 8, rect.size.y * 0.22), 23 if large else 18)
	var values := _chapter_progress(id)
	_label(card, "已唤醒 %d / %d" % [values.completed, values.count] if values.unlocked else "静待微光唤醒", Rect2(4, rect.size.y * 0.77, rect.size.x - 8, rect.size.y * 0.21), 13 if large else 12, MUTED)
	return card


func _utilities() -> void:
	var toolbar := Control.new()
	toolbar.name = "MapUtilities"
	toolbar.size = _extent
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(toolbar)
	var actions := [{"id":"world_overview","text":"世界总览"},{"id":"gallery","text":"图鉴"},{"id":"journal","text":"花园纪事"},{"id":"map_tools","text":"更多"}]
	var portrait := _extent.x < 700 and _extent.y > _extent.x
	var gap := 8.0
	var width := (_extent.x - 40) / 4 if portrait else minf(140, (_extent.x - _enter_rect.size.x - 64) / 4)
	var height := 46.0 if _extent.y <= 500 else 52.0
	var y := _enter_rect.position.y - height - 10 if portrait else _enter_rect.position.y + (_enter_rect.size.y - height) * .5
	for index in actions.size():
		var action: Dictionary = actions[index]
		var x := 8 + index * (width + gap) if portrait else 12 + index * (width + gap) if index < 2 else _extent.x - 12 - (4 - index) * width - (3 - index) * gap
		var target := str(action.id)
		var button := _button(toolbar, action.text, Rect2(x, y, width, height), func() -> void:
			if target == "world_overview": show_overview()
			elif target == "map_tools":
				_tools_open = not _tools_open
				relayout()
			else: action_requested.emit(target))
		button.add_theme_font_size_override("font_size", 13 if width < 110 else 16)
		button.set_meta("action", target)


func _build_tools() -> void:
	var actions := []
	if can_resume: actions.append({"id":"resume","text":"继续当前关卡"})
	if can_save: actions.append({"id":"save","text":"导入 / 导出旅程"})
	if not _chapter_entries("cloud").is_empty(): actions.append({"id":"cloud","text":"云庭微光"})
	if chapter == "cloud": actions.append({"id":"cloud_story","text":str(story_labels.get(selected_id, "口袋里的小事"))})
	var width := minf(300, _extent.x - 32)
	var height := 50.0 + actions.size() * 48
	var panel := _panel(_chrome, Rect2(_extent.x - width - 16, maxf(64, _enter_rect.position.y - height - 12), width, height), Color("fff5e8"), 22)
	panel.name = "MapMoreActions"
	panel.visible = _tools_open
	var close := _button(panel, "收起", Rect2(width - 76, 6, 68, 44), func() -> void: _tools_open = false; relayout())
	close.set_meta("action", "close_map_tools")
	for index in actions.size():
		var action: Dictionary = actions[index]
		var target := str(action.id)
		var button := _button(panel, action.text, Rect2(10, 46 + index * 48, width - 20, 44), func() -> void:
			if target == "cloud":
				_tools_open = false
				select_chapter("cloud")
			elif target == "cloud_story": cloud_story_requested.emit(selected_id)
			else: action_requested.emit(target))
		button.set_meta("action", target)
		if target == "cloud_story": button.set_meta("cloud_story_level", selected_id)
		if index == 0 and _tools_open: preferred_focus = button


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
	for id: String in CHAPTERS:
		if _chapter_entries(id).is_empty():
			continue
		var card := _chapter_card(_overview, id, Rect2(140 + index * 255, 209, 235, 330), true)
		if id == chapter:
			preferred_focus = card
		index += 1
	_label(_overview, "可以查看尚未苏醒的章节；进入关卡仍遵守旅程进度。", Rect2(170, 555, 940, 54), 15, MUTED)


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
	if is_instance_valid(_chrome) and (parent == _chrome or _chrome.is_ancestor_of(parent)): return 1.0
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
		button.add_theme_stylebox_override("normal", _style(Color("dda24b"), Color("b98036"), 26))
		button.add_theme_stylebox_override("hover", _style(Color("ecc071"), Color("b98036"), 26))
		button.add_theme_color_override("font_color", Color("fff9e1"))
		button.add_theme_color_override("font_hover_color", Color("fff9e1"))
		button.add_theme_color_override("font_pressed_color", Color("fff9e1"))
		button.add_theme_stylebox_override("pressed", _style(Color("c58c39"), Color("a5722d"), 26))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	MenuButtons.focus_like_hover(button)
	parent.add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button
