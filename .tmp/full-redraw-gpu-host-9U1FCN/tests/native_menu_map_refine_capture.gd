extends SceneTree
const HUD := preload("res://ui/garden_hud.gd")
const Repository := preload("res://services/save_repository.gd")
var output := ""
var rows: Array = []
var failures: Array = []
var checks := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func settle() -> void:
	for unused in 5: await process_frame
	for unused in 3: await RenderingServer.frame_post_draw

func capture(viewport: SubViewport, label: String) -> void:
	await settle()
	var pixels := viewport.get_texture().get_image()
	var name_value := "%dx%d-%s.png" % [viewport.size.x,viewport.size.y,label]
	check(pixels != null and pixels.save_png(output.path_join(name_value)) == OK,"capture " + name_value)
	rows.append({"file":name_value,"viewport":[viewport.size.x,viewport.size.y]})

func click(viewport: SubViewport, point: Vector2) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event,true)
	await settle()

func run() -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1565,881),Vector2i(844,390),Vector2i(390,844)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var hud := HUD.new()
		viewport.add_child(hud)
		var repository := Repository.new()
		repository.configure_levels(levels)
		hud.set_repository(repository)
		hud.show_home(levels,repository.data.mainline,false)
		await capture(viewport,"home-new")
		hud.show_menu(levels,repository.data.mainline)
		await capture(viewport,"map-new")
		var progress: Dictionary = repository.data.mainline
		progress.records = {"1-1":{"completed":true,"collected":3},"1-2":{"completed":true,"collected":2}}
		progress.last_level = "1-2"
		hud.show_home(levels,progress,true)
		await capture(viewport,"home-returning")
		hud.show_menu(levels,progress)
		await capture(viewport,"map-valley")
		var map: Control = hud._chapter_map
		var marker: Button = map._body.get_node("MapMarker_1-3")
		await click(viewport,marker.get_global_rect().get_center())
		check(map.selected_id == "1-3","actual node pointer selects unlocked garden " + str(dimensions))
		map.select_level("1-2")
		await settle()
		var art: Control = map._body.get_node("MapMarker_1-2/RegisteredMapNodeArt")
		check(art.completed and art.selected and art.is_processing(),"completed selected map character has live firefly animation")
		map.set_paused(true)
		check(not art.is_processing(),"pause freezes node motion")
		map.set_paused(false)
		map.apply_settings({"lowMotion":true,"particles":false})
		check(not art.is_processing() and not art.particles,"reduced motion and particles settings reach map node")
		map.apply_settings({"lowMotion":false,"particles":true})
		if dimensions == Vector2i(1280,720):
			map.set_paused(true)
			art.clock = .07
			art.queue_redraw()
			await capture(viewport,"map-wing-a")
			var before := viewport.get_texture().get_image()
			art.clock = .15
			art.queue_redraw()
			await capture(viewport,"map-wing-b")
			var after := viewport.get_texture().get_image()
			var crop := Rect2i(art.get_global_rect()).intersection(Rect2i(Vector2i.ZERO,dimensions))
			var changed := 0
			for y in range(crop.position.y,crop.end.y):
				for x in range(crop.position.x,crop.end.x):
					if before.get_pixel(x,y) != after.get_pixel(x,y): changed += 1
			check(changed > 20,"GPU pixels change with firefly wing phase on the selected node")
			map.set_paused(false)
		for id: String in ["2-2","3-2"]:
			for level: Dictionary in levels:
				if str(level.id).begins_with("cloud-"): continue
				progress.records[str(level.id)] = {"completed":true,"collected":1}
			hud.show_menu(levels,progress)
			map = hud._chapter_map
			map.select_level(id)
			await capture(viewport,"map-"+id)
		viewport.queue_free()
		await process_frame
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"scope":"Actual GPU, HUD and map pointer input using a repository object without disk IO; sample progress only. Not browser input, audio or performance acceptance."}
	var file := FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":report.passed,"checks":checks,"images":rows.size(),"failures":failures}))
	quit(0 if report.passed else 1)
