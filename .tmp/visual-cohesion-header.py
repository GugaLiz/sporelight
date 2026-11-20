from pathlib import Path
p=Path('godot/ui/chapter_map.gd')
s=p.read_text(encoding='utf-8').replace('chapter-covers-20261119/%s.png','chapter-covers-20261119-v2/%s.png')
a=s.index('\tvar brand :=',s.index('func _header()'))
b=s.index('\n\tvar total :=',a)
s=s[:a]+'''	if not small:
		var logo := _picture(_screen_chrome,"material-ready/menu-logo.png",Rect2(128,8,236,115))
		logo.name = "MapHomeLogo"
'''+s[b:]
a=s.index('\t_label(_body, "第 %s 章"',s.index('func _header()'))
b=s.index('\n\n\n\nfunc _markers()',a)
s=s[:a]+'''	var night := chapter == "cave"
	var title := _label(_body,TITLES[chapter],Rect2(center-165,70,330,37),27,Color("fff1d1") if night else INK)
	title.name = "MapChapterTitle"
	var number := _label(_body,"第 %s 章" % str(CHAPTERS.find(chapter)+1) if chapter != "cloud" else "独立花园",Rect2(center-165,44,330,24),12,Color("eee0bf") if night else MUTED)
	var description := _label(_body,DESCRIPTIONS[chapter],Rect2(center-210,107,420,25),12,Color("eee0bf") if night else MUTED)
	if night:
		for label: Label in [title,number,description]:
			label.add_theme_color_override("font_shadow_color",Color("242431dd"))
			label.add_theme_constant_override("shadow_offset_x",0)
			label.add_theme_constant_override("shadow_offset_y",2)
			label.add_theme_constant_override("shadow_outline_size",3)
'''+s[b:]
p.write_text(s,encoding='utf-8')
