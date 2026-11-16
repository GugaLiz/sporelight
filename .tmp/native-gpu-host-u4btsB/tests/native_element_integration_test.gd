extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Assets = preload("res://elements/element_assets.gd")
const Surfaces = preload("res://elements/surface_definitions.gd")
const Props = preload("res://elements/prop_definitions.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	stage.set_paused(true)
	for chapter: int in range(1,4):
		for index: int in range(1,5):
			var id := "%d-%d" % [chapter,index]
			var world := World.new(id)
			stage.set_world(world)
			var state: Dictionary = world.snapshot().duplicate(true)
			var tiles: Array = world.tiles().duplicate(true)
			var bodies := {}
			for who: String in ["luvie","buddy"]:
				var body := stage.get_actor_body(who)
				bodies[who] = {"id":body.get_instance_id(),"pose":body.transform,"shape":body.get_node("Collision").shape}
			var old_texture := stage._texture("flower")
			check(stage.apply_element_theme({"schema_version":1,"resource_overrides":{"flower":Assets.resource_path("bloom")}}).ok,id+" live global art replacement")
			check(stage._texture("flower") != old_texture and stage._texture("flower")==Assets.texture("bloom"),id+" actual image cache invalidated")
			var chapter_id := str(world.level.chapter)
			check(Surfaces.set_theme_overrides(chapter_id,{"stone":"paving-pond","grass":"paving-pond","moss":"paving-pond","terrainTop":"paving-pond","wallLeft":"wall-left","wallRight":"wall-right","terrainSide":"wall-left"}),id+" chapter theme accepted")
			stage.refresh_world(world,true)
			var top: Material = stage._terrain_materials().top
			check(top.albedo_texture==Assets.texture("paving-pond"),id+" live terrain material rebuilt")
			var changed_wall: Material = stage._terrain_materials().side
			var wall_texture: Texture2D = changed_wall.get_shader_parameter("wall_art") if changed_wall is ShaderMaterial else changed_wall.albedo_texture
			check(wall_texture==Assets.texture("wall-left"),id+" live wallpaper rebuilt")
			var obstacle_revision: int = stage.prop_obstacle_revision
			check(Props.reload_definitions(),id+" definition reload accepted")
			stage.refresh_world(world,true)
			check(stage.prop_obstacle_revision>obstacle_revision,id+" footprint cache rebuilt with prop revision")
			for who: String in bodies:
				var body := stage.get_actor_body(who)
				check(body.get_instance_id()==bodies[who].id and body.transform==bodies[who].pose and body.get_node("Collision").shape==bodies[who].shape,id+" preserves "+who+" physical body")
			check(world.snapshot()==state and world.tiles()==tiles,id+" preserves complete puzzle and support state")
			Assets.reset_theme()
			Surfaces.reset()
			stage.reload_element_visuals()
			check(stage._texture("flower")==old_texture,id+" restore refreshes live art")
	# Editor theme transactions must not tear an in-flight moving platform.
	stage._motion_geometry_active = true
	var revision := Assets.revision()
	check(not stage.apply_element_theme({"schema_version":1,"resource_overrides":{"flower":Assets.resource_path("bloom")}}).ok and Assets.revision()==revision,"moving geometry rejects art transaction before mutation")
	stage._motion_geometry_active = false
	check(stage.asset_errors().is_empty(),"all resolved stage resources exist")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"element-integration","checks":checks,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
