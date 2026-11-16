extends "res://tests/native_guardian_capture.gd"
## Prepared original step94 plus actual care; fixed QA framing is explicit.
var receiver_cases: Array = []

func _capture(label: String) -> void:
	app._update_layout()
	app.view._fit_camera(true)
	var was_processing: bool = app.view.is_processing()
	app.view.set_process(false)
	var camera: Camera3D = app.view._camera
	var core: Node3D = app.view._props_nodes["mark:core"]
	var right := Vector3(0.70710678,0,-0.70710678)
	var up := Vector3(-0.35355339,0.8660254,-0.35355339)
	var screen_size := Vector2(app.view._viewport.size)
	var offset: Vector2 = app.view._safe_rect().get_center()-screen_size/2
	var density: float = screen_size.y/camera.size
	var aim: Vector3 = core.global_position+Vector3(0,1.2,0)-right*offset.x/density+up*offset.y/density
	camera.position=aim+app.view.CAMERA_RAY*60
	camera.look_at(aim,Vector3.UP)
	for unused in range(8): await RenderingServer.frame_post_draw
	var pixels: Image = outer.get_texture().get_image()
	var file := "%s-%s-%dx%d.png" % [branch,label,dimensions.x,dimensions.y]
	_check(pixels!=null and pixels.save_png(output.path_join(file))==OK,"fixed receiver GPU original "+file)
	var words: Array=[]
	_find_scene_words(app.view._props,words)
	_check(words.is_empty(),"receiver remains natural scene geometry without Label3D")
	images.append({"file":file,"viewport":[dimensions.x,dimensions.y],"snapshot":app.session.world.snapshot(),"camera":"QA fixed core center +1.2m, existing normal camera size and safe area; identical framing across states","cameraSize":camera.size,"status":app.status_message,"prepared":true})
	app.view.set_process(was_processing)
	print("CAPTURE "+file)

func _hashes() -> Dictionary:
	var result: Dictionary=super._hashes()
	for path: String in ["tests/native_guardian_receiver_capture.gd","presentation/native/original_prop_ratios.gd","presentation/native/native_prop_obstacles.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	return result

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("Explicit output and actual GPU required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before:=_hashes()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if str(entry.name)=="authored/3-4": original=entry
	current_level="3-4"
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions=size; branch="guardian-receiver"
		if await _start():
			await _capture("cold-original-initial")
			await _prepared_state(original.steps[45].snapshot,"original-step45-before-light")
			if await _prepared_state(original.steps[94].snapshot,"original-step94-lit-before-care"):
				_check(app.session.world.ready() and not app.session.world.state.completed,"original step94 is ready and incomplete")
				var accepted:=await _e_action("repair","actual-e-final-care")
				_check(accepted and app.session.world.state.completed,"real E care completes at resized planter")
				var stay:=_find_stay(app.hud)
				if stay!=null: stay.pressed.emit()
				await _capture("actual-e-care-bloom")
				receiver_cases.append({"viewport":[size.x,size.y],"preparedFrom":94,"actualAction":"E press/release and actual menu signal","completed":bool(app.session.world.state.completed)})
			await _dispose()
	var after:=_hashes()
	_check(before==after,"receiver sources stable")
	failures.append_array(logger.captured_errors())
	var report: Dictionary={"suite":"guardian-receiver-capture","passed":failures.is_empty(),"checks":checks,"failures":failures,"sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"cases":receiver_cases,"images":images,"events":events,"scope":"Explicit original initial/45/94 snapshots; step94 followed by actual E care. QA camera centered on core at existing normal size, frozen during capture. Not complete journey, browser, audio or performance acceptance."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"failures":failures,"cases":receiver_cases,"images":images.size()}))
	quit(0 if report.passed else 1)
