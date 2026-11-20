from pathlib import Path
p=Path('godot/ui/chapter_map.gd')
s=p.read_text(encoding='utf-8')
s=s.replace('const MapMenuSkin :=', 'const CardArt := preload("res://ui/chapter_card_art.gd")\nconst CoverShader := preload("res://ui/chapter_cover.gdshader")\nconst MapMenuSkin :=',1)
start=s.index('\tvar width := panel.size.x',s.index('func _detail()'))
end=s.index('\n\n\n\nfunc _enter_selected',start)
s=s[:start]+'''\tvar width := panel.size.x
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
	var eyebrow := _label(panel,"已唤醒的微光" if entry.completed else "下一段旅程" if entry.unlocked else "沉睡中的微光",Rect2(margin,height*.057,inner,20*factor),roundi(11*factor),Color("8b9978"))
	eyebrow.name = "MapEntryState"
	eyebrow.visible = not short
	_label(panel,TITLES[chapter],Rect2(margin,height*.137 if not short else 9,inner,38*factor),roundi(26*factor) if not short else 18)
	_label(panel,"%s  ·  %s" % [selected_id,entry.get("title","")],Rect2(margin,height*.323 if not short else 39,inner,24*factor),roundi(15*factor) if not short else 12)
	if not short:
		_label(panel,str(entry.get("rule",entry.get("subtitle",""))),Rect2(margin,height*.395,inner,22*factor),roundi(11*factor),MUTED)
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
'''+s[end:]
start=s.index('\tvar compact :=',s.index('func _chapter_card('))
end=s.index('\n\treturn card',start)
s=s[:start]+'''\tvar compact := height < 130
	var factor := clampf(width/177.0,.8,1.4)
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		var frame := MapMenuSkin.surface(Color("fbefdc") if state == "normal" else Color("fff6e4"),Color("c5b58f"),29)
		frame.set_border_width_all(2)
		card.add_theme_stylebox_override(state,frame)
	var artwork := "chapter-covers-20261119/%s.png" % id if id != "cloud" else "production/bug.png"
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
'''+s[end:]
p.write_text(s,encoding='utf-8')
