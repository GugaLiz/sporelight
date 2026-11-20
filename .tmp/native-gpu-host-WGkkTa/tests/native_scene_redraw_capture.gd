extends SceneTree
## Prepared GPU comparison; this does not claim a playthrough or UI input test.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Journey = preload("res://application/journey_view.gd")
const Assets = preload("res://elements/element_assets.gd")
const Repository = preload("res://services/save_repository.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
const TARGETS := ["arch", "spore", "blue-flowers", "gold-lotus", "ivory-lotus", "flower", "bloom"]
var output := ""
var source_sha := ""
var failures: Array[String] = []
var rows: Array = []
var logger := ErrorLogger.new()
var finished := false

func _initialize() -> void:
	OS.add_logger(logger)
	ProjectSettings.set_setting("rendering/shader_compiler/shader_cache/enabled", false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	create_timer(300).timeout.connect(func() -> void:
		if not finished: push_error("Scene redraw capture timed out"); quit(2))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func source_hashes() -> Dictionary:
	var result := {}
	for folder: String in ["application", "core", "presentation", "elements", "content"]:
		_collect_hashes("res://" + folder, result)
	for alias: String in TARGETS:
		var resource := Assets.resource_path(alias)
		result[resource] = FileAccess.get_sha256(resource)
	return result

func _collect_hashes(path: String, result: Dictionary) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension() in ["gd", "gdshader", "json", "tscn"]: result[path.path_join(file)] = FileAccess.get_sha256(path.path_join(file))
	for folder: String in DirAccess.get_directories_at(path): _collect_hashes(path.path_join(folder), result)

func final_snapshot(id: String) -> Dictionary:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in reference.cases:
		if str(fixture.name) == "authored/" + id: return fixture.steps.back().snapshot.duplicate(true)
	check(false, "Missing historical final fixture: " + id)
	return {}

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": push_error("Native GPU and explicit output required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var theme: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.THEME_PATH))
	check(theme.resource_overrides.size() >= 7, "Seven redraw aliases installed")
	var initial_sources := source_hashes()
	var cleared := final_snapshot("3-3")
	cleared.actors = {"luvie":"f:1:5", "buddy":"f:0:5"}
	var cases: Array = [{"level":"1-1","state":"initial","snapshot":{}}, {"level":"1-1","state":"completed","snapshot":final_snapshot("1-1")}, {"level":"1-3","state":"initial","snapshot":{}}, {"level":"2-3","state":"initial","snapshot":{}}, {"level":"1-4","state":"completed","snapshot":final_snapshot("1-4")}, {"level":"3-3","state":"completed","snapshot":final_snapshot("3-3")}, {"level":"3-3","state":"completed-cleared-prepared","snapshot":cleared}]
	for dimensions: Vector2i in [Vector2i(1280,720), Vector2i(844,390)]:
		for spec: Dictionary in cases:
			Assets.reset_theme()
			var camera := await capture(dimensions, spec, "before", {})
			check(Assets.apply_theme(theme).ok, "Apply redraw theme")
			await capture(dimensions, spec, "after", camera)
	Assets.apply_theme(theme)
	var final_sources := source_hashes()
	check(initial_sources == final_sources, "Production sources stable during capture")
	var errors := logger.captured_errors()
	check(errors.is_empty(), "No native script/render errors")
	var report := {"suite":"scene-redraw-native-gpu", "sourceSha":source_sha,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"initialSources":initial_sources,"finalSources":final_sources,"sourceFilesStable":initial_sources==final_sources,"framebuffersSaved":not rows.is_empty(),"captureChecksPassed":failures.is_empty(),"visualAcceptance":"Requires manual review of saved original pixels; not inferred from frame availability or geometry assertions.","failures":failures,"errors":errors,"images":rows,"scope":"Seven representative prepared scenes, two normal viewports, original versus redraw theme, identical world snapshot/actor pose/time and paired camera. One additional completed 3-3 snapshot moves both actors to valid neighboring same-height permanent shore tiles solely to reveal the flowerbed; completed remains true. No user save, browser input, route completion or performance claims."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	finished = true
	print(JSON.stringify({"captureChecksPassed":failures.is_empty(),"captures":rows.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func capture(dimensions: Vector2i, spec: Dictionary, phase: String, paired_camera: Dictionary) -> Dictionary:
	var outer := SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	var stage := Stage.new()
	outer.add_child(stage)
	var hud := HUD.new()
	outer.add_child(hud)
	var settings := Repository.default_settings()
	settings.lowMotion = true
	stage.set_settings(settings)
	hud.apply_settings(settings)
	stage.set_visual_time(1200)
	var world := World.new(str(spec.level), spec.snapshot.duplicate(true))
	if str(spec.state).begins_with("completed"):
		check(bool(world.state.completed), "Completed snapshot is not reset: " + str(spec.level) + "/" + str(spec.state))
		check(world.state.actors == spec.snapshot.actors, "Prepared actor supports retained: " + str(spec.level) + "/" + str(spec.state))
	stage.set_world(world)
	stage.refresh_world(world, false)
	hud.set_game_interface_visible(true)
	hud.update_state(world, false, "")
	hud.set_journey(Journey.describe(world))
	hud.set_overview_available(true)
	for unused in range(5): await process_frame
	stage.overview = false
	stage.set_layout(hud.safe_world_rect())
	stage.set_ui_regions(hud.layout_regions())
	stage._resize()
	stage._fit_camera(true)
	for who: String in ["luvie","buddy"]:
		stage.update_actor_visual(who, Vector3.ZERO)
		var art: AnimatedSprite3D = stage.get_actor_body(who).get_node("Visual/Art")
		art.pause()
		art.set_frame_and_progress(0,0)
		stage.get_actor_body(who).get_node("Visual/AnimationPlayer").stop()
	stage.set_process(false)
	if not paired_camera.is_empty():
		stage._camera.transform = paired_camera.transform
		stage._camera.size = paired_camera.size
		stage._focus = paired_camera.focus
	for unused in range(4): await RenderingServer.frame_post_draw
	var pixels := outer.get_texture().get_image()
	var label := "%s-%s-%dx%d-%s" % [spec.level,spec.state,dimensions.x,dimensions.y,phase]
	check(pixels != null and pixels.get_size() == dimensions, "Native pixels: " + label)
	check(pixels.save_png(output.path_join(label + ".png")) == OK, "Save native pixels: " + label)
	var camera := {"transform":stage._camera.transform,"size":stage._camera.size,"focus":stage._focus}
	var props: Array = []
	var cropped: Array[String] = []
	var resource_aliases := {}
	var imported_textures := {}
	for alias: String in TARGETS:
		resource_aliases[Assets.resource_path(alias)] = alias
		var imported: Texture2D = Assets.texture(alias)
		var imported_image := imported.get_image()
		imported_textures[alias] = {"resource":Assets.resource_path(alias),"size":str(imported.get_size()),"mipmapCount":imported_image.get_mipmap_count()}
		if phase == "after": check(imported_image.get_mipmap_count() > 0, "Imported mipmaps available: " + alias)
	for card: Node in stage._props.find_children("*", "Sprite3D", true, false):
		if card.texture == null or not card.is_visible_in_tree(): continue
		var texture: Texture2D = card.texture.atlas if card.texture is AtlasTexture else card.texture
		if not resource_aliases.has(texture.resource_path): continue
		var alias: String = resource_aliases[texture.resource_path]
		var projected: Rect2 = stage._occlusion_projection(card, card.texture).rect
		var rect: Rect2i = Rect2i(projected.grow(8)).intersection(Rect2i(Vector2i.ZERO, dimensions))
		var crop_file := ""
		if not alias in cropped and rect.size.x > 12 and rect.size.y > 12:
			crop_file = label + "-detail-" + alias + ".png"
			check(pixels.get_region(rect).save_png(output.path_join(crop_file)) == OK, "Save 1:1 pixel crop: " + crop_file)
			cropped.append(alias)
		props.append({"path":str(stage._props.get_path_to(card)),"alias":alias,"position":str(card.global_position),"pixelSize":card.pixel_size,"offset":str(card.offset),"textureSize":str(card.texture.get_size()),"visibleScreenRect":str(projected),"pixelCrop":crop_file,"pixelCropRect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"depthTest":not card.no_depth_test,"alphaCut":card.alpha_cut,"filter":card.texture_filter})
	rows.append({"file":label+".png","level":spec.level,"state":spec.state,"theme":phase,"viewport":[dimensions.x,dimensions.y],"dpr":1,"overview":false,"cameraSize":stage._camera.size,"cameraPosition":str(stage._camera.position),"cameraFocus":str(stage._focus),"snapshot":world.snapshot(),"completed":bool(world.state.completed),"pose":"idle frame 0, zero velocity","visualTime":1200,"lowMotion":true,"resourcePaths":Assets.paths(),"importedTextures":imported_textures,"props":props,"assetErrors":stage.asset_errors()})
	check(stage.asset_errors().is_empty(), "All textures resolve: " + label)
	print("CAPTURE " + label)
	outer.queue_free()
	await process_frame
	return camera
