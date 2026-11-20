extends SceneTree
## Actual generated fountain pixels must consume the shared stone slot and
## invalidate with an appearance transaction, without changing physical data.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Assets = preload("res://elements/element_assets.gd")
const Sanctuary = preload("res://presentation/native/original_sanctuary_dressing.gd")
const FIXTURE_PATH := "res://.godot/fountain-theme-stone-fixture.tres"
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func fountain(stage: Node) -> Sprite3D:
	return stage._props.get_node("SanctuaryFountain") as Sprite3D
func shape(sprite: Sprite3D) -> Dictionary:
	return {"transform":sprite.transform,"pixelSize":sprite.pixel_size,"offset":sprite.offset,"centre":sprite.get_meta("original_sanctuary_ground_center"),"outline":sprite.get_meta("original_sanctuary_ground_outline"),"depth":sprite.no_depth_test,"alphaCut":sprite.alpha_cut}
func _run() -> void:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.THEME_PATH))
	check(Assets.apply_theme(shipped).ok,"shipped appearance fixture applies")
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var world := World.new("1-4")
	stage.set_world(world)
	await process_frame
	var before_world := world.snapshot().duplicate(true)
	var before_tiles := world.tiles().duplicate(true)
	var before_texture := fountain(stage).texture
	var before_pixels := before_texture.get_image().get_data()
	var before_shape := shape(fountain(stage))
	var source := Assets.texture("stone")
	var painted := Image.create(source.get_width(),source.get_height(),false,Image.FORMAT_RGBA8)
	painted.fill(Color("3745e5"))
	check(ResourceSaver.save(ImageTexture.create_from_image(painted),FIXTURE_PATH)==OK,"same-canvas stone fixture saved outside production assets")
	var changed := shipped.duplicate(true)
	changed["resource_overrides"]["stone"] = FIXTURE_PATH
	var rasterizations: int = Sanctuary.rasterizations
	var result: Dictionary = stage.apply_element_theme(changed)
	check(result.ok,"shared stone appearance transaction applies: "+str(result))
	var after_texture := fountain(stage).texture
	check(after_texture != before_texture,"existing fountain receives a newly generated texture")
	check(after_texture.get_image().get_data()!=before_pixels,"actual fountain pixels consume the replaced stone grain")
	check(Sanctuary.rasterizations==rasterizations+1,"stone transaction invalidates the fountain raster once")
	check(Sanctuary.fountain_texture()==after_texture and Sanctuary.rasterizations==rasterizations+1,"warm fountain lookup reuses the new raster")
	check(shape(fountain(stage))==before_shape,"appearance replacement retains full fountain pose, foot, scale, depth and ground outline")
	check(world.snapshot()==before_world and world.tiles()==before_tiles,"appearance replacement retains complete puzzle and support data")
	check(stage.apply_element_theme(shipped).ok,"shipped appearance restores")
	check(fountain(stage).texture.get_image().get_data()==before_pixels,"restoration regenerates the original fountain pixels")
	check(shape(fountain(stage))==before_shape and world.snapshot()==before_world,"restoration preserves the same physical and rule identity")
	stage.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	print(JSON.stringify({"suite":"fountain-shared-theme","checks":checks,"passed":failures.is_empty(),"failures":failures,"scope":"Headless source-generated pixel/cache/physical contracts; GPU art acceptance is separate."}))
	quit(0 if failures.is_empty() else 1)
