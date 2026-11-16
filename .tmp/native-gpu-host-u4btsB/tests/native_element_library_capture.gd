extends SceneTree
## Deterministic GPU scene comparison. Prepared snapshots are NOT playthroughs.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Repository = preload("res://services/save_repository.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var dimensions := Vector2i(1280,720)
var stage: Node2D
var outer: SubViewport
var rows: Array = []
var failures: Array[String] = []
var logger := ErrorLogger.new()
var finished := false
func _initialize() -> void:
	OS.add_logger(logger)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--source-sha="): source_sha=arg.trim_prefix("--source-sha=")
	create_timer(240).timeout.connect(func() -> void:
		if not finished: push_error("Element GPU capture timed out"); quit(2))
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func source_hashes() -> Dictionary:
	var hashes := {}
	for folder: String in ["application","core","presentation","elements","content"]:
		_collect_hashes("res://"+folder,hashes)
	return hashes
func _collect_hashes(path: String, hashes: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension() in ["gd","gdshader","json","tscn"]: hashes[path.path_join(file)]=FileAccess.get_sha256(path.path_join(file))
	for folder: String in DirAccess.get_directories_at(path): _collect_hashes(path.path_join(folder),hashes)
func open_scene(id: String, snapshot: Dictionary={}) -> void:
	outer=SubViewport.new()
	outer.size=dimensions
	outer.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	stage=Stage.new()
	outer.add_child(stage)
	var settings: Dictionary=Repository.default_settings()
	settings.lowMotion=true
	stage.set_settings(settings)
	stage.set_visual_time(1200)
	stage.set_world(World.new(id,snapshot))
	stage.set_process(false)
	stage.set_layout(Rect2(Vector2.ZERO,Vector2(dimensions)))
	stage._resize()
	stage._fit_camera(true)
	for who: String in ["luvie","buddy"]:
		var art: AnimatedSprite3D=stage.get_actor_body(who).get_node("Visual/Art")
		art.pause()
		art.set_frame_and_progress(0,0)
		var player: AnimationPlayer=stage.get_actor_body(who).get_node("Visual/AnimationPlayer")
		player.stop()
		# Normal runtime updates actor depth after the camera is fitted. Explicitly
		# do the same before freezing the scene so skin refresh uses identical axes.
		stage.update_actor_visual(who,Vector3.ZERO)
	for unused in range(4): await RenderingServer.frame_post_draw
func capture(label: String, prepared: bool=false) -> void:
	for unused in range(3): await RenderingServer.frame_post_draw
	check(stage._viewport.size==dimensions,label+" actual 3D viewport dimensions")
	var world_pixels: Image=stage._viewport.get_texture().get_image()
	var visible:=0
	for y in range(0,world_pixels.get_height(),12):
		for x in range(0,world_pixels.get_width(),12):
			if world_pixels.get_pixel(x,y).a>.1: visible+=1
	check(visible>60,label+" has nontransparent world pixels")
	var pixels:=outer.get_texture().get_image()
	var file:=label+".png"
	check(pixels.get_size()==dimensions and pixels.save_png(output.path_join(file))==OK,label+" saved GPU pixels")
	rows.append({"file":file,"level":stage.world.level.id,"preparedSnapshot":prepared,"viewport":[dimensions.x,dimensions.y],"visibleWorldSamples":visible,"snapshot":stage.world.snapshot(),"cameraPosition":str(stage._camera.position),"cameraSize":stage._camera.size})
	print("CAPTURE "+file)
func close_scene() -> void:
	outer.queue_free()
	await process_frame
func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("GPU and output directory required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var initial_sources := source_hashes()
	for chapter in range(1,4):
		for level in range(1,5):
			var id:="%d-%d" % [chapter,level]
			await open_scene(id)
			await capture(id+"-cold")
			await close_scene()
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id: String in ["1-4","2-2","3-2","3-3","3-4"]:
		for fixture: Dictionary in reference.cases:
			if str(fixture.levelId)!=id: continue
			var last: Dictionary=fixture.steps.back().snapshot
			await open_scene(id,last)
			await capture(id+"-prepared-final",true)
			await close_scene()
			break
	await open_scene("3-2")
	if stage.has_method("set_actor_skin"):
		var definitions: Script=load("res://elements/actor_definitions.gd")
		var variant: Dictionary=definitions.skin("luvie.original").duplicate(true)
		variant.allowed_actors=["buddy"]
		variant.standing.pixel_size=float(variant.standing.pixel_size)*.7
		variant.carry_scale=.66
		var before: Dictionary=stage.world.snapshot().duplicate(true)
		var body: CharacterBody3D=stage.get_actor_body("buddy")
		var at:=body.transform
		var shape: Shape3D=body.get_node("Collision").shape
		check(definitions.register_skin("qa.small-mushroom",variant).ok,"register test-only companion appearance")
		check(stage.set_actor_skin("buddy","qa.small-mushroom").ok,"apply test-only companion appearance")
		check(stage.world.snapshot()==before and body.transform==at and body.get_node("Collision").shape==shape,"GPU companion swap retains world and physical identity")
		await capture("3-2-test-only-companion-skin")
		check(stage.set_actor_skin("buddy","buddy.original").ok,"restore companion")
		await capture("3-2-companion-restored")
	await close_scene()
	var errors:=logger.captured_errors()
	check(errors.is_empty(),"no Godot script/render errors")
	var final_sources := source_hashes()
	check(initial_sources==final_sources,"production sources stable during capture")
	var report:={"suite":"element-library-native-gpu","sourceSha":source_sha,"initialSources":initial_sources,"finalSources":final_sources,"sourceFilesStable":initial_sources==final_sources,"passed":failures.is_empty(),"failures":failures,"errors":errors,"images":rows,"scope":"12 newly constructed level scenes and five prepared historical final snapshots at 1280x720. Prepared snapshots are visual fixtures, not route completion. Actor skin QA uses existing hero art only; no shipped new costume."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":failures.is_empty(),"captures":rows.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
