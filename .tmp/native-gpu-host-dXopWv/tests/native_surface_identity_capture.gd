extends SceneTree
## Prepared native GPU evidence for rigid texture identity; no gameplay bypass claim.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Repository = preload("res://services/save_repository.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var stage: Node2D
var outer: SubViewport
var dimensions := Vector2i(1280,720)
var focus := Vector3.ZERO
var rows: Array = []
var failures: Array[String] = []
var checks := 0
var finished := false
var logger := ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	ProjectSettings.set_setting("rendering/shader_compiler/shader_cache/enabled", false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--source-sha="): source_sha=argument.trim_prefix("--source-sha=")
	create_timer(240).timeout.connect(func() -> void:
		if not finished: push_error("Surface identity GPU capture timed out"); quit(2))
	_run.call_deferred()

func _check(value: bool,label: String) -> bool:
	checks+=1
	if not value: failures.append(label); push_error(label)
	return value

func _hashes() -> Dictionary:
	var hashes := {}
	for path: String in ["presentation/native/native_garden_stage.gd","presentation/native/native_surface.gd","presentation/native/garden_island_stone.gdshader","presentation/native/island_foundations.gd","presentation/native/chapter_surface_materials.gd","core/garden_world.gd","content/levels.json","tests/native_surface_identity_capture.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	return hashes

func _open(world: RefCounted,module: String) -> void:
	outer=SubViewport.new()
	outer.size=dimensions
	outer.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	stage=Stage.new()
	outer.add_child(stage)
	stage.set_settings(Repository.default_settings())
	stage.set_visual_time(1200)
	stage.set_world(world)
	stage.set_process(false)
	stage.set_layout(Rect2(Vector2.ZERO,Vector2(dimensions)))
	var pivot: Dictionary=world.module_point(module,[0,0])
	focus=Vector3(float(pivot.x),float(pivot.h)*.65,float(pivot.z))
	for unused in range(3): await process_frame

func _close() -> void:
	outer.queue_free()
	await process_frame

func _capture(label: String,module: String,progress: float=-1.0) -> void:
	# Freeze the camera across all samples, including fresh instances.
	stage._camera.size=7.0
	stage._camera.position=focus+Stage.CAMERA_RAY*60
	stage._camera.look_at(focus,Vector3.UP)
	stage.set_visual_time(1200)
	for unused in range(4): await RenderingServer.frame_post_draw
	var pixels:=outer.get_texture().get_image()
	var file:="%s-%dx%d.png" % [label,dimensions.x,dimensions.y]
	_check(pixels!=null and not pixels.is_empty() and pixels.save_png(output.path_join(file))==OK,"native GPU image "+file)
	var surfaces: Array=[]
	for id: String in stage._surfaces:
		if not id.begins_with("m:"+module+":"): continue
		var surface: Node3D=stage._surfaces[id]
		surfaces.append({"id":id,"position":str(surface.position),"rotation":str(surface.rotation),"rebuilds":surface.geometry_rebuilds})
	_check(not surfaces.is_empty(),label+" has visible module supports")
	rows.append({"file":file,"level":stage.world.level.id,"module":module,"progress":progress,"cameraPosition":str(stage._camera.position),"cameraSize":stage._camera.size,"focus":str(focus),"viewport":[dimensions.x,dimensions.y],"prepared":true,"surfaces":surfaces})
	print("CAPTURE "+file)

func _rotations() -> void:
	var world:=World.new("3-4")
	world.state.active="buddy"
	world.state.actors.buddy="m:water:0:0"
	var initial: Dictionary=world.snapshot().duplicate(true)
	await _open(world,"water")
	await _capture("3-4-water-initial","water")
	for turn in range(4):
		var before: Dictionary=world.snapshot().duplicate(true)
		var after:=before.duplicate(true)
		after.turns.water=(turn+1)%4
		for progress: float in ([0.0,.15,.5,.9999,1.0] if turn==0 else [.9999,1.0]):
			stage.set_motion(before,after,progress,"valve:water")
			await _capture("3-4-water-%d-%s" % [turn,"start" if progress==0 else "early" if progress==.15 else "middle" if progress==.5 else "near-end" if progress<1 else "settled"],"water",progress)
		stage.clear_motion(false)
		world=World.new("3-4",after)
		stage.set_world(world)
	await _capture("3-4-water-four-turns","water")
	var reverse:=initial.duplicate(true)
	reverse.turns.water=3
	stage.set_motion(initial,reverse,1.0,"undo")
	await _capture("3-4-water-undo","water",1)
	stage.clear_motion(false)
	stage.set_world(World.new("3-4",initial))
	var next:=initial.duplicate(true)
	next.turns.water=1
	stage.set_motion(initial,next,.5,"valve:water")
	stage.clear_motion(false)
	stage.set_world(World.new("3-4",initial))
	await _capture("3-4-water-cancel-restored","water")
	await _close()
	await _open(World.new("3-4",initial),"water")
	await _capture("3-4-water-fresh-stage","water")
	await _close()

func _representative(level: String,module: String,command: String) -> void:
	var world:=World.new(level)
	var before: Dictionary=world.snapshot().duplicate(true)
	var after:=before.duplicate(true)
	after.turns[module]=1
	await _open(world,module)
	var destination:=World.new(level,after)
	var end: Dictionary=destination.module_point(module,[0,0])
	focus=focus.lerp(Vector3(float(end.x),float(end.h)*.65,float(end.z)),.5)
	await _capture(level+"-"+module+"-initial",module)
	for progress: float in [.9999,1.0]:
		stage.set_motion(before,after,progress,command)
		await _capture(level+"-"+module+("-near-end" if progress<1 else "-settled"),module,progress)
	await _close()

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("Actual native GPU and output required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before:=_hashes()
	for size: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		dimensions=size
		await _rotations()
	dimensions=Vector2i(1280,720)
	await _representative("1-3","garden","turn:garden")
	await _representative("2-4","boat","move:boat")
	await _representative("3-4","lift","valve:lift")
	var after:=_hashes()
	_check(before==after,"capture and production files stable")
	failures.append_array(logger.captured_errors())
	var report:={"suite":"surface-identity-native-gpu","sourceSha256":source_sha,"sourceFilesStable":before==after,"initialSources":before,"finalSources":after,"passed":failures.is_empty(),"checks":checks,"images":rows,"failures":failures,"scope":"Prepared snapshots and exact presentation progress, fixed isometric camera, real native GPU. No actual gameplay input, collision travel, browser, performance or audio claim; UV invariants checked separately by CPU suite."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished=true
	print(JSON.stringify({"passed":report.passed,"checks":checks,"images":rows.size(),"failures":failures}))
	quit(0 if report.passed else 1)
