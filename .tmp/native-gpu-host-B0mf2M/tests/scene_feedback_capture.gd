extends SceneTree
## Prepared native snapshots, not browser automation or real-input completion.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Journey = preload("res://application/journey_view.gd")
const Repository = preload("res://services/save_repository.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var phase := "before"
var source_sha := ""
var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(844, 390)]
var rows: Array = []
var failures: Array[String] = []
var logger := ErrorLogger.new()
var finished := false
var selected_cases: PackedStringArray = []
var normal_only := false
var starting_hashes: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	# Captures must not depend on write access to the interactive user's GPU
	# cache. This changes the QA process only, never the project configuration.
	ProjectSettings.set_setting("rendering/shader_compiler/shader_cache/enabled", false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
		elif argument.begins_with("--cases="): selected_cases = argument.trim_prefix("--cases=").split(",")
		elif argument == "--normal-only": normal_only = true
	create_timer(180).timeout.connect(func() -> void:
		if not finished:
			push_error("Native scene capture timed out")
			quit(2))
	_run.call_deferred()

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Explicit output and native Windows/OpenGL GPU rendering are required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	starting_hashes = _source_hashes()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fourth: Dictionary
	for entry: Dictionary in fixture.cases:
		if str(entry.name) == "authored/1-4": fourth = entry
	var specs: Array = []
	var third: Dictionary = World.new("1-3").snapshot()
	for turn in range(4):
		var snapshot := third.duplicate(true)
		snapshot.turns.garden = turn
		specs.append({"level":"1-3", "label":"turn-%d" % turn, "snapshot":snapshot})
	var turn_after := third.duplicate(true)
	turn_after.turns.garden = 1
	specs.append({"level":"1-3", "label":"turn-0-midpoint", "snapshot":third, "after":turn_after, "command":"turn:garden"})
	specs.append({"level":"1-4", "label":"initial", "snapshot":fourth.initial.snapshot})
	specs.append({"level":"1-4", "label":"hold-midpoint-prepared", "snapshot":fourth.initial.snapshot, "after":fourth.steps[0].snapshot, "command":"use:hold"})
	for selection: Array in [[0,"hold-after"],[17,"latch-before"],[18,"latch-after"],[28,"home-open"],[48,"inside-sanctuary"],[49,"completed-sanctuary"]]:
		specs.append({"level":"1-4", "label":selection[1], "snapshot":fourth.steps[int(selection[0])].snapshot})
	for dimensions: Vector2i in sizes:
		for spec: Dictionary in specs:
			if not selected_cases.is_empty() and not str(spec.label) in selected_cases: continue
			await _capture(dimensions, spec)
	var framebuffers_saved := failures.is_empty() and not rows.is_empty()
	failures.append_array(logger.captured_errors())
	var hashes := _source_hashes()
	var stable := starting_hashes == hashes
	if not stable: failures.append("Production sources changed during the capture batch")
	var report := {"phase":phase,"sourceSha256":source_sha,"scope":"Prepared native snapshots and presentation interpolation; no browser or real-input completion claim. Root window is hidden by the launcher; real OpenGL SubViewports supply pixels. Framebuffer availability and clean runtime are reported separately.","display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"initialSourceFiles":starting_hashes,"sourceFiles":hashes,"sourceFilesStable":stable,"framebuffersSaved":framebuffers_saved,"rows":rows,"failures":failures,"passed":failures.is_empty() and not rows.is_empty()}
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ") + "\n")
	file.close()
	finished = true
	print(JSON.stringify({"suite":"scene-feedback-native-gpu","phase":phase,"frames":rows.size(),"failures":failures,"passed":report.passed}))
	quit(0 if report.passed else 1)

func _capture(dimensions: Vector2i, spec: Dictionary) -> void:
	var outer := SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	var stage := Stage.new()
	outer.add_child(stage)
	var hud := HUD.new()
	outer.add_child(hud)
	var settings := Repository.default_settings()
	stage.set_settings(settings)
	hud.apply_settings(settings)
	stage.set_visual_time(1200)
	var world := World.new(str(spec.level), spec.snapshot.duplicate(true))
	stage.set_world(world)
	stage.refresh_world(world, false)
	hud.set_game_interface_visible(true)
	hud.update_state(world, false, "")
	hud.set_journey(Journey.describe(world))
	hud.set_overview_available(true)
	for frame in range(8): await process_frame
	if spec.has("after"):
		stage.set_motion(spec.snapshot, spec.after, 0.5, str(spec.command))
	for overview: bool in [false, true]:
		if overview and normal_only: continue
		stage.overview = overview
		hud.set_overview(overview)
		stage.set_layout(hud.overview_world_rect() if overview else hud.safe_world_rect())
		stage.set_ui_regions(hud.layout_regions())
		stage._fit_camera(true)
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var image := outer.get_texture().get_image()
		var name := "%s-%s-%dx%d-%s.png" % [spec.level,spec.label,dimensions.x,dimensions.y,"overview" if overview else "normal"]
		if image == null or image.is_empty() or image.get_size() != dimensions:
			failures.append("Missing native GPU image " + name)
			continue
		var error := image.save_png(output.path_join(name))
		if error != OK: failures.append("Unable to save " + name)
		var props: Array = []
		for node: Node3D in stage._props.get_children():
			if (str(spec.level)=="1-3" and int(node.get_meta("original_scenery_index",-1))==13) or str(node.name) in ["SanctuaryFountain","MoleResident","OriginalSanctuaryGateFrame","OriginalSanctuaryGateSeal"] or str(node.name).begins_with("OriginalWall_"):
				var item := {"node":str(node.name),"position":_v3(node.global_position),"visible":node.is_visible_in_tree()}
				if node is Sprite3D:
					item["canvasWidth"] = node.pixel_size * node.texture.get_width()
					item["offset"] = [node.offset.x,node.offset.y]
					item["depthTest"] = not node.no_depth_test
				props.append(item)
		rows.append({"file":name,"level":spec.level,"state":spec.label,"snapshot":spec.snapshot,"motionProgress":0.5 if spec.has("after") else null,"viewport":[dimensions.x,dimensions.y],"overview":overview,"cameraSize":stage._camera.size,"cameraFocus":_v3(stage._focus),"props":props,"renderStatistics":stage.render_statistics()})
		print("CAPTURE " + name)
	outer.queue_free()
	await process_frame

func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in ["presentation/native/native_garden_stage.gd","presentation/native/native_surface.gd","presentation/native/original_sanctuary_dressing.gd","presentation/native/original_scenery_positions.gd","presentation/native/original_scenery_placement.gd","presentation/native/original_garden_dressing.gd","presentation/native/original_prop_ratios.gd","presentation/native/original_wall_props.gd","presentation/native/native_arch_footprint.gd","presentation/native/native_prop_obstacles.gd","presentation/native/mechanism_props.gd","content/levels.json"]:
		if FileAccess.file_exists("res://" + path): result[path] = FileAccess.get_sha256("res://" + path)
	return result
