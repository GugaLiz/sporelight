extends SceneTree
const HUD := preload("res://ui/garden_hud.gd")
const Stage := preload("res://presentation/native/native_garden_stage.gd")
const Factory := preload("res://core/world_factory.gd")
const Repository := preload("res://services/save_repository.gd")
const Picking := preload("res://presentation/native/native_prop_picking.gd")
var output := ""
var rows: Array = []
var bindings: Array = []
var failures: Array = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	run.call_deferred()
func settle() -> void:
	for unused in 5: await process_frame
	for unused in 3: await RenderingServer.frame_post_draw
func save(viewport: SubViewport, label: String) -> void:
	await settle()
	var filename := "%dx%d-%s.png" % [viewport.size.x,viewport.size.y,label]
	if viewport.get_texture().get_image().save_png(output.path_join(filename)) != OK: failures.append(filename)
	rows.append(filename)
func run() -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	for level: Dictionary in levels:
		var outer := SubViewport.new()
		outer.size = Vector2i(1280,720)
		outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(outer)
		var stage := Stage.new()
		outer.add_child(stage)
		stage.set_settings(Repository.default_settings())
		stage.set_visual_time(1200)
		var world := Factory.create(str(level.id))
		stage.set_world(world)
		stage.set_layout(Rect2(0,80,1280,600))
		stage.overview = true
		stage._resize(); stage._fit_camera(true)
		stage.set_process(false)
		var snapshot: Dictionary = world.snapshot()
		for item: Dictionary in stage._garden_effects.collectibles.values():
			bindings.append({"level":level.id,"tile":item.tile,"texture":item.sprite.texture.resource_path,"depth":not item.sprite.no_depth_test})
			check(item.sprite.texture.resource_path == "res://assets/images/scene-redraw-20261116/spore.png",str(level.id)+"/redrawn/"+str(item.tile))
			check(not item.sprite.no_depth_test,str(level.id)+"/actual-depth/"+str(item.tile))
			check(absf(item.offset.x) < .5 and absf(item.offset.z) < .5,str(level.id)+"/offset-stays-on-support/"+str(item.tile))
		check(world.snapshot() == snapshot,str(level.id)+"/presentation-preserves-world")
		await save(outer,str(level.id))
		if str(level.id) == "2-1":
			var target: Vector3 = (stage._garden_effects.collectibles["spore-0"].node.global_position + stage._garden_effects.collectibles["spore-2"].node.global_position) * .5
			var shift: Vector3 = target - stage._camera.project_position(Vector2(640,360),20)
			stage._camera.position += stage._camera.global_basis.x * shift.dot(stage._camera.global_basis.x) + stage._camera.global_basis.y * shift.dot(stage._camera.global_basis.y)
			stage._camera.size *= .42
			await save(outer,"2-1-close")
			await physics_frame
			for id: String in ["spore-0","spore-1"]:
				var entry: Dictionary = stage._garden_effects.collectibles[id]
				var screen: Vector2 = stage._camera.unproject_position(entry.sprite.global_position)
				check(Picking.collectible_support(stage,screen) == str(entry.tile),"2-1/visible-shifted-orb-click/"+id)
			stage.set_visual_time(2200)
			stage._garden_effects.update()
			await save(outer,"2-1-phase-b")
			stage._props.visible = false
			await save(outer,"2-1-diagnostic-no-props")
		outer.queue_free()
		await process_frame
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		var outer := SubViewport.new()
		outer.size = dimensions
		outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(outer)
		var hud := HUD.new()
		outer.add_child(hud)
		var repository := Repository.new()
		repository.configure_levels(levels)
		hud.set_repository(repository)
		hud.show_home(levels,repository.data.mainline,false)
		hud.show_settings(Repository.default_settings())
		await save(outer,"settings-home")
		hud._settings_page.scroll.scroll_vertical = 9999
		await save(outer,"settings-home-scrolled")
		hud.close_overlay(false)
		hud.set_game_interface_visible(true)
		hud.show_settings(Repository.default_settings())
		await save(outer,"settings-game")
		outer.queue_free()
		await process_frame
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"bindings":bindings,"scope":"Actual GPU, initial states in memory; diagnostic hidden-prop image is not delivered gameplay."}
	FileAccess.open(output.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":report.passed,"images":rows.size(),"bindings":bindings.size()}))
	quit(0 if failures.is_empty() else 1)
