extends "res://tests/native_map_menu_capture.gd"
var entered: Array[String] = []

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	outer = SubViewport.new()
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	var progress := {"records":{"1-1":{"completed":true,"collected":2},"1-2":{"completed":true,"collected":3}},"runs":{}}
	for extent: Vector2i in [Vector2i(1880,940),Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844),Vector2i(320,568)]:
		outer.size = extent
		map = MapView.new()
		var hud := HUD.new(); map.theme = hud._paper_theme(); hud.free()
		outer.add_child(map)
		map.configure(levels,progress,{"level":"1-3"})
		map.apply_settings({"lowMotion":true})
		map.level_requested.connect(func(id: String) -> void: entered.append(id))
		await _settle()
		await _capture("valley")
		var panel: Control = map.find_child("MapSelectedCard",true,false)
		var enter: Button = map.find_child("MapEnterLevel",true,false)
		_check(panel.get_global_rect().encloses(enter.get_global_rect()),"enter button within panel / "+str(extent))
		for label: Node in panel.find_children("*","Label",true,false):
			_check(panel.get_global_rect().encloses(label.get_global_rect()),"label within panel / "+str(extent))
		_check(map.find_children("ChapterLock","TextureRect",true,false).size()==2,"two genuinely locked chapters")
		if extent.x > extent.y:
			await _press(enter)
			_check(entered.back()=="1-3","actual enter click retains level identity")
		for chapter: String in ["pond","cave"]:
			map.select_chapter(chapter); await _settle()
			await _capture(chapter)
			_check(map.find_child("MapEnterLevel",true,false).disabled,"locked level remains disabled")
		map.show_overview(); await _settle(); await _capture("overview")
		_check(map._overview.find_children("ChapterCover","TextureRect",true,false).size()==3,"all three covers in overview")
		map.configure(levels,{"unlock_all":true,"records":progress.records,"runs":{}},{"level":"2-1"})
		await _settle()
		_check(map.find_children("ChapterLock","TextureRect",true,false).is_empty(),"testing override removes misleading locks")
		await _capture("unlocked-pond")
		map.queue_free(); await process_frame
	failures.append_array(logger.captured_errors())
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"images":images,"scope":"Five GPU sizes, three chapters and overview, prepared in-memory progress, actual desktop enter click, locked and testing-unlocked states. UI only."},"  "))
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures}))
	outer.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
