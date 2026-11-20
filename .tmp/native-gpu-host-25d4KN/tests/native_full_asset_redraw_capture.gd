extends SceneTree
## Fixed prepared scene/UI/pose pixels. This is not a route or pointer test.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Factory = preload("res://core/world_factory.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Journey = preload("res://application/journey_view.gd")
const Assets = preload("res://elements/element_assets.gd")
const Repository = preload("res://services/save_repository.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var theme_file := "res://content/element-theme.json"
var bitmap_file := "res://content/bitmap-redraw.json"
var source_sha := ""
var finished := false
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var pose_rows: Array = []
var logger := ErrorLogger.new()
var final_theme: Dictionary = {}
var final_bitmap: Dictionary = {}
var levels: Array = []
var progress: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	ProjectSettings.set_setting("rendering/shader_compiler/shader_cache/enabled", false)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--source-sha="): source_sha = arg.trim_prefix("--source-sha=")
		elif arg.begins_with("--theme="): theme_file = arg.trim_prefix("--theme=")
		elif arg.begins_with("--bitmap="): bitmap_file = arg.trim_prefix("--bitmap=")
	create_timer(360).timeout.connect(func() -> void:
		if not finished: push_error("Full asset capture timed out"); quit(2))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _theme(phase: String) -> void:
	Assets.reset_theme(); Assets.reset_bitmap_redraw()
	if phase == "after":
		check(Assets.apply_bitmap_redraw(final_bitmap).ok, "Apply full bitmap candidate atomically")
		check(Assets.apply_theme(final_theme).ok, "Apply full shared theme atomically")

func _collect(path: String, hashes: Dictionary) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension() in ["gd","gdshader","json","tscn"]: hashes[path.path_join(file)] = FileAccess.get_sha256(path.path_join(file))
	for folder: String in DirAccess.get_directories_at(path): _collect(path.path_join(folder), hashes)

func _sources() -> Dictionary:
	var hashes := {}
	for folder: String in ["application","core","presentation","elements","content"]: _collect("res://"+folder,hashes)
	for source: String in final_bitmap.get("source_overrides",{}):
		hashes[source] = FileAccess.get_sha256(source)
		var target := str(final_bitmap.source_overrides[source])
		hashes[target] = FileAccess.get_sha256(target)
	for target: String in final_theme.get("resource_overrides",{}).values(): hashes[target] = FileAccess.get_sha256(target)
	return hashes

func _final(id: String) -> Dictionary:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if str(fixture.name) == "authored/"+id: return fixture.steps.back().snapshot.duplicate(true)
	return {}

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Real native GPU and explicit output required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	final_theme = JSON.parse_string(FileAccess.get_file_as_string(theme_file))
	final_bitmap = JSON.parse_string(FileAccess.get_file_as_string(bitmap_file))
	levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	progress = {"records":{},"runs":{},"memories":{},"last_level":"1-3"}
	for level: Dictionary in levels: progress.records[str(level.id)] = {"completed":true,"collected":3,"stars":3}
	var source_before := _sources()
	var cases: Array = [
		{"kind":"scene","id":"1-1","state":"initial","snapshot":{}},
		{"kind":"scene","id":"1-3","state":"initial","snapshot":{}},
		{"kind":"scene","id":"1-4","state":"closed","snapshot":{}},
		{"kind":"scene","id":"1-4","state":"completed","snapshot":_final("1-4")},
		{"kind":"scene","id":"2-1","state":"initial","snapshot":{}},
		{"kind":"scene","id":"2-4","state":"initial","snapshot":{}},
		{"kind":"scene","id":"3-3","state":"completed","snapshot":_final("3-3")},
		{"kind":"scene","id":"cloud-1","state":"initial","snapshot":{}},
		{"kind":"home","id":"home","state":"cover"},
		{"kind":"map","id":"valley","state":"chapter","selected":"1-3"},
		{"kind":"map","id":"pond","state":"chapter","selected":"2-4"},
		{"kind":"map","id":"cave","state":"chapter","selected":"3-4"},
		{"kind":"gallery","id":"gallery","state":"unlocked"}
	]
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390)]:
		for spec: Dictionary in cases:
			_theme("before")
			var camera := await _capture(spec,dimensions,"before",{})
			_theme("after")
			await _capture(spec,dimensions,"after",camera)
	_theme("after")
	var source_after := _sources()
	check(source_before == source_after,"Production and referenced bitmap bytes stable during capture")
	var errors := logger.captured_errors()
	check(errors.is_empty(),"No script/render errors")
	var report := {"suite":"full-asset-redraw-native-gpu","sourceSha":source_sha,"theme":theme_file,"bitmap":bitmap_file,"checks":checks,"passed":failures.is_empty(),"captureChecksPassed":failures.is_empty(),"sourceFilesStable":source_before==source_after,"initialSources":source_before,"finalSources":source_after,"failures":failures,"errors":errors,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"images":rows,"actorPoseCrops":pose_rows,"visualAcceptance":"Requires manual inspection of original saved pixels, not inferred from successful captures.","scope":"13 prepared native scenes/UI pages at 1280x720 and844x390, base resource library vs installed/candidate redraw, paired scene cameras and fixed time/idle. Initial 1-1 also captures actual native pose overrides on first/mid/last action frames. Gallery uses completed in-memory records; all captures avoid user saves. Not a playthrough, browser/pointer test, audio or performance benchmark."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished = true
	print(JSON.stringify({"suite":report.suite,"captures":rows.size(),"poseCrops":pose_rows.size(),"checks":checks,"passed":report.passed,"failures":failures}))
	quit(0 if report.passed else 1)

func _scan(node: Node, root_node: Node, textures: Array) -> void:
	var texture: Texture2D
	if node is TextureRect or node is Sprite2D or node is Sprite3D: texture = node.texture
	elif node is AnimatedSprite3D and node.sprite_frames != null:
		texture = node.sprite_frames.get_frame_texture(node.animation,node.frame)
	if texture != null:
		var actual: Texture2D = texture.atlas if texture is AtlasTexture else texture
		if not actual.resource_path.is_empty(): textures.append({"node":str(root_node.get_path_to(node)),"texture":actual.resource_path,"size":str(actual.get_size()),"visible":node.is_visible_in_tree() if node.has_method("is_visible_in_tree") else true})
	for child: Node in node.get_children(): _scan(child,root_node,textures)

func _save(viewport: SubViewport, file: String) -> Image:
	for unused in range(3): await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	check(pixels != null and pixels.get_size()==viewport.size,"Actual framebuffer size: "+file)
	check(pixels.save_png(output.path_join(file))==OK,"Saved original GPU pixels: "+file)
	return pixels

func _capture(spec: Dictionary, dimensions: Vector2i, phase: String, paired: Dictionary) -> Dictionary:
	var outer := SubViewport.new()
	outer.size=dimensions; outer.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	var hud := HUD.new()
	outer.add_child(hud)
	var settings := Repository.default_settings(); settings.lowMotion=true
	hud.apply_settings(settings)
	var stage: Node2D
	var world: RefCounted
	var camera := {}
	if spec.kind == "scene":
		stage=Stage.new(); outer.add_child(stage); outer.move_child(stage,0)
		stage.set_settings(settings); stage.set_visual_time(1200)
		world=Factory.create(str(spec.id),spec.snapshot.duplicate(true))
		stage.set_world(world)
		hud.set_game_interface_visible(true); hud.update_state(world,false,"")
		hud.set_journey(Journey.describe(world)); hud.set_overview_available(true)
		for unused in range(5): await process_frame
		stage.overview=false; stage.set_layout(hud.safe_world_rect()); stage.set_ui_regions(hud.layout_regions())
		stage._resize(); stage._fit_camera(true)
		for who: String in ["luvie","buddy"]:
			stage.update_actor_visual(who,Vector3.ZERO)
			var art: AnimatedSprite3D=stage.get_actor_body(who).get_node("Visual/Art")
			art.pause(); art.set_frame_and_progress(0,0)
			stage.get_actor_body(who).get_node("Visual/AnimationPlayer").stop()
		stage.set_process(false)
		if not paired.is_empty(): stage._camera.transform=paired.transform; stage._camera.size=paired.size; stage._focus=paired.focus
		camera={"transform":stage._camera.transform,"size":stage._camera.size,"focus":stage._focus}
		if spec.state == "completed": check(bool(world.state.completed),"Prepared completed state retained: "+str(spec.id))
	elif spec.kind == "home":
		hud.show_home(levels,progress,false)
		for unused in range(5): await process_frame
		hud._home_cover.scenery.elapsed_ms=1200; hud._home_cover.scenery.refresh_pose(); hud._home_cover.scenery.set_process(false)
	elif spec.kind == "map":
		hud.show_menu(levels,progress)
		hud._chapter_map.select_chapter(str(spec.id)); hud._chapter_map.select_level(str(spec.selected))
		hud._chapter_map.set_paused(true)
	else:
		hud.show_gallery({"mainline":progress})
	for unused in range(5): await process_frame
	var name_value := "%s-%s-%dx%d-%s" % [spec.id,spec.state,dimensions.x,dimensions.y,phase]
	await _save(outer,name_value+".png")
	var textures: Array=[]; _scan(outer,outer,textures)
	rows.append({"file":name_value+".png","kind":spec.kind,"id":spec.id,"state":spec.state,"phase":phase,"viewport":[dimensions.x,dimensions.y],"dpr":1,"overview":false,"visualTime":1200,"cameraPosition":str(stage._camera.position) if stage!=null else "","cameraSize":stage._camera.size if stage!=null else 0,"snapshot":world.snapshot() if world!=null else {},"textures":textures,"assetErrors":Assets.errors()})
	if spec.kind=="scene" and spec.id=="1-1": await _poses(outer,stage,dimensions,phase,name_value)
	outer.queue_free(); await process_frame
	return camera

func _poses(outer: SubViewport, stage: Node2D, dimensions: Vector2i, phase: String, prefix: String) -> void:
	var art: AnimatedSprite3D=stage.get_actor_body("luvie").get_node("Visual/Art")
	for clip: String in ["walk_front","walk_back","walk_left","jump","sow","interact","complete"]:
		var count := art.sprite_frames.get_frame_count(clip)
		var indices := [0,count/2,count-1]
		var seen: Array[int]=[]
		for value: int in indices:
			if value in seen: continue
			seen.append(value); art.play(clip); art.pause(); art.set_frame_and_progress(value,0)
			for unused in range(3): await RenderingServer.frame_post_draw
			var actual := art.sprite_frames.get_frame_texture(clip,value)
			var rect := Rect2i(stage._occlusion_projection(art,actual).rect.grow(8)).intersection(Rect2i(Vector2i.ZERO,dimensions))
			check(rect.size.x>8 and rect.size.y>8,"Pose remains on screen: "+clip)
			var file := prefix+"-pose-"+clip+"-"+str(value)+".png"
			check(outer.get_texture().get_image().get_region(rect).save_png(output.path_join(file))==OK,"Save actual calibrated action pose: "+file)
			pose_rows.append({"file":file,"phase":phase,"clip":clip,"frame":value,"texture":actual.resource_path,"pixelSize":art.pixel_size,"offset":str(art.offset),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"viewport":[dimensions.x,dimensions.y],"scope":"Actual native pose_overrides active; original framebuffer crop, no resampling."})
