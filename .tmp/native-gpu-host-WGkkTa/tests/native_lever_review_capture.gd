extends "res://tests/native_route_test.gd"
## Real application entry/commands and native GPU pixels. Fixture commands are
## intentions only; snapshots never stand in for a cold start or a route.
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var prototype := false
var timing_only := false
var shader_cache_enabled := false
var outer: SubViewport
var viewport_size := Vector2i(1280,720)
var phase := "setup"
var images: Array = []
var timings: Array = []
var gaps: Array = []
var source_start: Dictionary = {}
var logger := ErrorLogger.new()
var last_draw_us := 0
var skip_gap := true
var capturing := false
var pull_begin_saved := false
var pull_mid_saved := false
var pending_draw_timings: Array = []
var rendered_count := 0

func _initialize() -> void:
	OS.add_logger(logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="):source_sha=argument.trim_prefix("--source-sha=")
		elif argument=="--prototype":prototype=true
		elif argument=="--timing-only":timing_only=true
		elif argument=="--shader-cache":shader_cache_enabled=true
	ProjectSettings.set_setting("rendering/shader_compiler/shader_cache/enabled",shader_cache_enabled)
	RenderingServer.frame_post_draw.connect(_rendered)
	create_timer(240).timeout.connect(func()->void:push_error("Lever GPU review timeout");quit(2))
	_run.call_deferred()

func _rendered() -> void:
	var now := Time.get_ticks_usec()
	rendered_count+=1
	for timing: Dictionary in pending_draw_timings:
		timing["commandToNextDrawMs"]=float(now-int(timing.dispatchUsec))/1000.0
		timing["actualDrawGapMs"]=float(now-last_draw_us)/1000.0 if last_draw_us>0 else null
	pending_draw_timings.clear()
	if last_draw_us>0 and not capturing and not skip_gap and app!=null and is_instance_valid(app):
		gaps.append({"phase":phase,"viewport":[viewport_size.x,viewport_size.y],"gapMs":float(now-last_draw_us)/1000.0})
	last_draw_us=now
	skip_gap=capturing

func _tick() -> void:
	await super._tick()
	if not prototype and phase=="pull" and not app.motion.is_empty() and str(app.motion.kind)=="use:hold":
		var progress: float=float(app.motion.elapsed)/float(app.motion.duration)
		if not pull_begin_saved:
			pull_begin_saved=true
			await _capture("hold-begin")
		if progress>=.5 and not pull_mid_saved:
			pull_mid_saved=true
			await _capture("hold-mid")

func _settle(limit: int=600) -> bool:
	for unused in range(limit):
		await _tick()
		if app.motion.is_empty() and not app.native_movement.is_moving() and not app.waiting_repair and not app._approaching_heavy_lever:return true
	return false

func _command(id: String) -> void:
	# Two real draws after any PNG readback/encoding establish an uncontaminated
	# previous-draw timestamp. The first draw after dispatch records the stall.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var started := Time.get_ticks_usec()
	app._on_command(id)
	var timing := {"phase":phase,"command":id,"viewport":[viewport_size.x,viewport_size.y],"dispatchUsec":started,"synchronousMs":float(Time.get_ticks_usec()-started)/1000.0}
	timings.append(timing)
	pending_draw_timings.append(timing)
	# Finish the first rendered frame before any caller can prepare a snapshot,
	# resize HUD/camera or encode a PNG. That work cannot contaminate this metric.
	await RenderingServer.frame_post_draw

func _capture(label: String) -> void:
	capturing=true
	skip_gap=true
	app._update_layout()
	app.view._fit_camera(true)
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels := outer.get_texture().get_image()
	var filename := "%s-%dx%d.png"%[label,viewport_size.x,viewport_size.y]
	_check(pixels!=null and not pixels.is_empty() and pixels.get_size()==viewport_size,"GPU framebuffer "+filename)
	if pixels!=null and not pixels.is_empty():_check(pixels.save_png(output.path_join(filename))==OK,"save "+filename)
	var controls := {}
	for id: String in ["hold","latch"]:
		var node: Node3D=app.view._props_nodes.get("mark:"+id)
		if node==null:continue
		var row := {"instanceId":node.get_instance_id(),"position":_v(node.global_position),"state":str(node.get_meta("mechanism_state","")),"children":[]}
		for child: Node3D in node.get_children():
			row.children.append({"name":str(child.name),"position":_v(child.global_position)})
		controls[id]=row
	var body: CharacterBody3D=app.view.get_actor_body("luvie")
	images.append({"file":filename,"label":label,"viewport":[viewport_size.x,viewport_size.y],"snapshot":app.session.world.snapshot(),"actualHeld":app.session.world.lever_held(),"presentationHeld":app.view.world.lever_held(),"active":app.session.world.actor(),"heroBody":_v(body.position),"controls":controls,"motion":{} if app.motion.is_empty() else {"kind":str(app.motion.kind),"progress":float(app.motion.elapsed)/float(app.motion.duration)},"status":app.status_message,"render":app.view.render_statistics()})
	print("CAPTURE "+filename)
	capturing=false
	skip_gap=true

func _cold_enter() -> void:
	app.repository.data=Repository.empty_store()
	_check(app.repository.data.mainline.runs.is_empty(),"memory repository is empty before real entry")
	var started := Time.get_ticks_usec()
	var first_draw_count := rendered_count
	var preparation_expected: bool = not app.view._bridge_materials_prepared
	app._enter_level("1-4")
	var entry_timing := {"phase":phase,"command":"_enter_level(empty repository)","viewport":[viewport_size.x,viewport_size.y],"synchronousMs":float(Time.get_ticks_usec()-started)/1000.0}
	timings.append(entry_timing)
	var supports: Array=app.view._surfaces.keys()
	supports.sort()
	var obstacles: int=app.view._prop_obstacles.size()
	var prep: SubViewport=app.view.get_node_or_null("BridgeMaterialPreparation")
	_check((prep!=null)==preparation_expected,"first 1-4 entry prepares materials once per view")
	if prep!=null:
		_check(prep.find_world_3d()!=null and prep.find_world_3d()!=app.view._scene.get_world_3d(),"preparation owns a separate physical world")
		_check(prep.find_children("*","CollisionObject3D",true,false).is_empty(),"preparation contains no physical collision/support bodies")
	# Include first-use GPU preparation in total entry readiness. Count actual
	# post-draw events, and separately prove two-draw cleanup before screenshots.
	capturing=true
	while rendered_count-first_draw_count<2:
		await RenderingServer.frame_post_draw
	var retiring: Node=app.view.get_node_or_null("BridgeMaterialPreparation")
	_check(retiring==null or retiring.is_queued_for_deletion(),"preparation retires after two actual draws")
	await process_frame
	await _tick()
	await _tick()
	while rendered_count-first_draw_count<8:
		await RenderingServer.frame_post_draw
	entry_timing["readyAfterActualDrawsMs"]=float(Time.get_ticks_usec()-started)/1000.0
	entry_timing["actualDrawsBeforeReady"]=rendered_count-first_draw_count
	_check(app.view.get_node_or_null("BridgeMaterialPreparation")==null,"entry is ready without any preparation viewport left")
	var final_supports: Array=app.view._surfaces.keys()
	final_supports.sort()
	_check(supports==final_supports and obstacles==app.view._prop_obstacles.size(),"preparation leaves support and hard-prop registries unchanged")
	capturing=false
	skip_gap=true
	_check(not app.session.world.flag("hold") and not app.session.world.flag("latch") and not app.session.world.lever_held(),"real cold entry has neither hold nor latch")

func _route_latch(fixture: Dictionary, first: int) -> void:
	var expected: Dictionary=fixture.initial.snapshot if first==0 else fixture.steps[first-1].snapshot
	for index in range(first,19):
		phase="route-%d"%index
		var command: Dictionary=fixture.steps[index].command
		if str(command.kind)=="move":
			if not await _walk_to(str(command.value),"lever review/%d"%index):return
		else:
			var who: String=app.session.world.actor()
			var intended: String=str(expected.actors[who])
			if intended!=str(app.session.world.state.actors[who]) and not await _walk_to(intended,"lever review approach/%d"%index):return
			await _command(str(command.value))
			if not _check(await _settle(),"real route action settles/%d"%index):return
		expected=fixture.steps[index].snapshot
		if index==17 and not prototype:
			await _capture("latch-before")
			var original: Vector3=app.view.get_actor_body("luvie").position
			var front: Vector3=app.view.tile_position(app.session.world.point_for("f:-3:5"))+Vector3(0,0,.38)
			_check(app.native_movement.request_local_target(front),"front doorway stance is reachable without entering any hard base")
			_check(await _settle(),"hero walks to front doorway stance")
			app.view.update_actor_visual("luvie",Vector3.ZERO,"right")
			await _capture("latch-front-before")
			_check(app.native_movement.request_local_target(original),"original latch side stance remains reachable")
			_check(await _settle(),"hero walks back to side operation stance")
	_check(app.session.world.flag("latch") and not app.session.world.flag("hold") and not app.session.world.lever_held(),"real latch clears transient hold")
	await _capture("latched")
	if not prototype:
		var front: Vector3=app.view.tile_position(app.session.world.point_for("f:-3:5"))+Vector3(0,0,.38)
		_check(app.native_movement.request_local_target(front),"locked latch leaves front doorway stance reachable")
		_check(await _settle(),"hero walks to locked doorway front")
		app.view.update_actor_visual("luvie",Vector3.ZERO,"right")
		await _capture("latch-front-locked")

func _run_size(fixture: Dictionary) -> void:
	outer=SubViewport.new()
	outer.size=viewport_size
	outer.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	phase="cold"
	await _cold_enter()
	await _capture("cold")
	phase="pull"
	pull_begin_saved=false
	pull_mid_saved=false
	await _command("use:hold")
	_check(await _settle(),"real approach/pull settles")
	_check(app.session.world.lever_held(),"real command enters held state")
	await _capture("held")
	if not prototype:
		phase="held-switch"
		await _command("switch")
		_check(await _settle(),"switch settles")
		_check(app.session.world.actor()=="buddy" and app.session.world.lever_held(),"switch preserves actual hero hold")
		await _capture("held-switch")
		await _command("switch")
		await _settle()
		phase="release"
		await _command("release:hold")
		_check(await _settle(),"release settles")
		_check(not app.session.world.lever_held(),"release clears actual hold")
		await _capture("released")
		phase="undo"
		await _command("undo")
		_check(await _settle(),"undo settles")
		_check(app.session.world.lever_held(),"undo restores actual hold")
		await _capture("undo-held")
		app.native_movement.capture()
		var old_saved: Dictionary=app.session.world.snapshot()
		old_saved.runtime.poses.luvie.offset=[-.4,0,.4]
		_check(bool(app._normalize_snapshot(old_saved).get("ok",false)),"abnormal held runtime is otherwise a legal save")
		app.repository.data.mainline.runs["1-4"]=old_saved
		phase="held-runtime-restore"
		app._enter_level("1-4")
		await _tick()
		var station: Vector3=app.view.actor_rest_position(app.session.world.point_for("f:-3:0"),"luvie")
		var body: CharacterBody3D=app.view.get_actor_body("luvie")
		_check(app.session.world.lever_held() and Vector2(body.position.x-station.x,body.position.z-station.z).length()<=.06,"held save restores to real grip station")
		await _capture("held-runtime-restored")
		phase="route-cold-restart"
		await _cold_enter()
	await _route_latch(fixture,1 if prototype else 0)
	app.queue_free()
	app=null
	outer.queue_free()
	await process_frame
	skip_gap=true

func _run_timing_size() -> void:
	outer=SubViewport.new()
	outer.size=viewport_size
	outer.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	phase="timing-cold"
	await _cold_enter()
	for operation: Array in [["timing-first-hold","use:hold"],["timing-release","release:hold"],["timing-second-hold","use:hold"]]:
		phase=str(operation[0])
		await _command(str(operation[1]))
		_check(await _settle(),phase+" settles without any snapshot preparation")
		_check(app.session.world.lever_held()==(str(operation[1])=="use:hold"),phase+" final flag matches command")
	app.queue_free()
	app=null
	outer.queue_free()
	await process_frame
	skip_gap=true

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="gl_compatibility":
		push_error("Explicit output and actual native OpenGL rendering required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	source_start=_hashes()
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary={}
	for entry: Dictionary in reference.cases:
		if str(entry.name)=="authored/1-4":fixture=entry
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		viewport_size=dimensions
		if timing_only:await _run_timing_size()
		else:await _run_size(fixture)
	var source_end := _hashes()
	_check(source_start==source_end,"related production sources stable throughout actual input capture")
	failures.append_array(logger.captured_errors())
	var report := {"suite":"native-lever-real-app-gpu","sourceSha256":source_sha,"captureScriptSha256":FileAccess.get_sha256("res://tests/native_lever_review_capture.gd"),"baseRouteTestSha256":FileAccess.get_sha256("res://tests/native_route_test.gd"),"shaderCacheEnabled":bool(ProjectSettings.get_setting("rendering/shader_compiler/shader_cache/enabled")),"commandFirstDrawBeforeSnapshotPreparation":true,"timingOnlyNoSnapshotCalls":timing_only,"prototype":prototype,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"initialSources":source_start,"finalSources":source_end,"sourceFilesStable":source_start==source_end,"images":images,"commandTimings":timings,"renderedFrameGaps":gaps,"checks":checks,"failures":failures,"passed":failures.is_empty(),"scope":"Empty MemoryRepository and actual app entry/commands; authored route uses intentions only. App ticks manually once per physics frame at 1/60. Command-specific first-draw metrics wait two clean draws before dispatch and finish the first draw before snapshot preparation. Shader-cache condition is explicit; results are not extrapolated to Web or ordinary warm-cache play. PNG readback/encoding is excluded from general gaps; timing-only mode never calls capture. Old-held-runtime injection is explicitly adversarial and is not called cold start."}
	var file := FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	print(JSON.stringify({"suite":report.suite,"images":images.size(),"checks":checks,"passed":report.passed,"failures":failures}))
	quit(0 if report.passed else 1)

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["application/main.gd","application/native_movement.gd","application/game_session.gd","services/save_repository.gd","services/snapshot_normalizer.gd","core/garden_world.gd","presentation/native/mechanism_props.gd","presentation/native/native_garden_stage.gd","presentation/native/native_prop_obstacles.gd","presentation/native/native_surface.gd","presentation/native/native_growth_prepare.gd","presentation/native/native_growth_prepare.gd.uid","presentation/native/native_world.tscn","presentation/native/garden_growth_top.gdshader","content/levels.json"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	return result

func _v(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
