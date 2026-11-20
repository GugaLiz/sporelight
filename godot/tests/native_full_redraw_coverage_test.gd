extends SceneTree
## Final installed bitmap resolution plus actual SpriteFrames/UI bindings.
## Path and state checks do not certify pixels, pointer input or aesthetics.
const Assets = preload("res://elements/element_assets.gd")
const Actors = preload("res://elements/actor_definitions.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Factory = preload("res://core/world_factory.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Map = preload("res://ui/chapter_map.gd")
const Detail = preload("res://ui/chapter_map_detail_art.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var requirements := ""
var output := ""
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var actor_rows: Array = []
var logger := ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	requirements = "res://tests/fixtures/full_redraw_required_paths.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--requirements="): requirements = arg.trim_prefix("--requirements=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	if not FileAccess.file_exists(requirements):
		push_error("Frozen full-redraw source requirements are missing")
		quit(2); return
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(requirements))
	check(spec.get("schema_version",0) == 1, "Requirements schema")
	for entry: Dictionary in spec.sourcePaths:
		var source := str(entry.source)
		var effective := Assets.source_path(source)
		var original: Texture2D = load(source)
		var installed: Texture2D = Assets.texture_for_source(source)
		check(effective != source, "Old cutout redirected: " + source)
		check(original != null and installed != null, "Both textures resolve: " + source)
		if original == null or installed == null: continue
		check(installed.get_size() == original.get_size(), "Logical canvas preserved: " + source)
		check(installed.resource_path == effective, "Actual loaded texture follows source resolver: " + source)
		check(installed.get_image().get_mipmap_count() > 0, "Actual imported redraw has mipmaps: " + source)
		for alias: String in entry.get("aliases", []):
			var alias_texture := Assets.texture(alias)
			if alias_texture != null: check(alias_texture == installed, "Alias and direct source share texture: " + alias)
		rows.append({"source":source,"installed":effective,"size":str(installed.get_size()),"mipmapCount":installed.get_image().get_mipmap_count(),"kinds":entry.kinds})
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	for level: String in ["1-1", "cloud-1"]:
		var world := Factory.create(level)
		var before: Dictionary = world.snapshot().duplicate(true)
		stage.set_world(world)
		for who: String in ["luvie", "buddy"]:
			var body := stage.get_actor_body(who)
			var art: AnimatedSprite3D = body.get_node("Visual/Art")
			var definition := Actors.skin(Actors.default_skin(who))
			for clip_name: String in definition.clips:
				var clip: Dictionary = definition.clips[clip_name]
				check(art.sprite_frames.has_animation(clip_name), level + "/" + who + "/" + clip_name + " exists")
				check(art.sprite_frames.get_frame_count(clip_name) == clip.frames.size(), "Frame count retained: " + clip_name)
				check(is_equal_approx(art.sprite_frames.get_animation_speed(clip_name),float(clip.fps)), "Frame rate retained: " + clip_name)
				check(art.sprite_frames.get_animation_loop(clip_name) == bool(clip.loop), "Loop retained: " + clip_name)
				for index in clip.frames.size():
					var alias := str(clip.frames[index])
					var actual := art.sprite_frames.get_frame_texture(clip_name,index)
					if alias == "@procedural_buddy":
						check(actual != null, "Original procedural buddy retained")
						continue
					check(actual == Assets.texture(alias), "Actual animation uses redirected frame: " + alias)
					actor_rows.append({"level":level,"actor":who,"clip":clip_name,"frame":index,"alias":alias,"resource":actual.resource_path})
		check(world.snapshot() == before, "Texture construction preserves complete puzzle state: " + level)
	var hud := HUD.new()
	root.add_child(hud)
	hud.setup()
	check(hud._collection_icon.texture == Assets.texture("spore"), "HUD counter shares new collectible")
	for entry: Dictionary in spec.sourcePaths:
		if "ui" in entry.kinds:
			check(hud._texture(str(entry.source)) == Assets.texture_for_source(str(entry.source)), "Gallery loader follows installed bitmap: " + str(entry.source))
	var detail := Detail.new()
	root.add_child(detail)
	for id: String in Detail.ART:
		detail.configure(id)
		var index := 0
		for item: Array in Detail.ART[id]:
			check(detail._art[index].texture == Assets.texture_for_source(Detail.ROOT+str(item[0])), "Actual selected-level detail texture follows resolver: " + id + "/" + str(index))
			index += 1
	stage.queue_free(); hud.queue_free(); detail.queue_free()
	await process_frame
	check(Assets.errors().is_empty(), "No source/theme binding errors")
	failures.append_array(logger.captured_errors())
	var result := {"suite":"native-full-redraw-coverage","passed":failures.is_empty(),"checks":checks,"requirements":requirements,"failures":failures,"sources":rows,"actualActorFrames":actor_rows,"scope":"Headless actual textures, native SpriteFrames and UI bindings. No GPU/visual, pointer, route or performance claim."}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  ")+"\n")
	print(JSON.stringify({"suite":result.suite,"checks":checks,"passed":result.passed,"sourcePaths":rows.size(),"actualFrameBindings":actor_rows.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
