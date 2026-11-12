extends "res://tests/native_route_test.gd"
## Local application regression: click shifted petals, physically approach,
## then explicitly repair. Reuses the route harness without replaying all levels.
const Picking = preload("res://presentation/native/native_prop_picking.gd")
func _run() -> void:
	root.size = Vector2i(1280,720)
	_setup()
	app.view.tile_selected.connect(app._go)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/1-4":
			app.repository.data.mainline.runs["1-4"] = entry.steps[-2].snapshot.duplicate(true)
	app._enter_level("1-4")
	await _tick(); await _tick()
	# The old mistaken target f:-8:-1 is inside the restored hard stone base.
	# Approach from another diagonal legal support; repair proximity is unchanged.
	_check(await _walk_to("f:-8:1","approach displaced flower"),"walk to a legal support outside the flower base")
	_check(not app.session.world.near("f:-9:0"),"diagonal approach tile is outside unchanged repair proximity")
	var clicked := Vector2.ZERO
	for overview: bool in [false,true]:
		clicked = Vector2.ZERO
		app.view.overview = overview; app.view._fit_camera(true)
		var parent: Node3D = app.view._props_nodes["mark:core"]
		var flower: Sprite3D = parent.get_child(0)
		var picture := flower.texture.get_image()
		var picks := 0
		for y in range(20,160,10):
			for x in range(20,240,10):
				if picture.get_pixel(x,y).a<.75: continue
				var local := Vector3(x+.5-flower.texture.get_width()*.5+flower.offset.x,flower.texture.get_height()*.5+flower.offset.y-y-.5,0)*flower.pixel_size
				var screen: Vector2 = app.view.world_to_screen(flower.to_global(local))
				var picked := Picking.core_support(app.view,screen)
				if picked.is_empty(): continue # Terrain-occluded pixels are not targets.
				_check(picked == "f:-9:0" and app.view.hit_test(screen) == "f:-9:0","opaque flower selects original repair support in "+str(overview))
				picks += 1
				var clear: bool = app.view.get_viewport_rect().has_point(screen)
				for region: Rect2 in app.view._regions:
					if region.has_point(screen): clear = false
				if clear: clicked = screen
		_check(picks>=3,"multiple visible petals are clickable in "+str(overview))
		_check(not clicked.is_zero_approx(),"current camera has unblocked flower input in "+str(overview))
		var corner := flower.to_global(Vector3(-flower.texture.get_width()*.5+flower.offset.x,flower.texture.get_height()*.5+flower.offset.y,0)*flower.pixel_size)
		_check(Picking.core_support(app.view,app.view.world_to_screen(corner)).is_empty(),"transparent sprite margin cannot steal ground clicks")
	_check(not clicked.is_zero_approx(),"flower has visible unblocked actual input point")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = clicked
	app.view._unhandled_input(click)
	_check(await _drain(),"actual flower click physical approach settles")
	_check(str(app.session.world.state.actors.luvie) == "f:-9:0","actual flower input routes to authorized core tile")
	_check(app.session.world.near("f:-9:0") and app.session.world.ready(),"normal repair proximity and mechanism preconditions now satisfied")
	_check(not bool(app.session.world.state.completed),"clicking flowers does not auto-complete puzzle")
	app._on_command("repair")
	_check(await _drain(),"explicit repair transaction settles")
	_check(bool(app.session.world.state.completed),"explicit original repair completes after flower click")
	# Hidden art must never override underlying ground input.
	var parent: Node3D = app.view._props_nodes["mark:core"]
	parent.visible = false
	_check(Picking.core_support(app.view,clicked).is_empty(),"hidden core art has no click target")
	await _all_shifted_cores(reference)
	print(JSON.stringify({"suite":"native-core-click","checks":checks,"passed":failures.is_empty(),"failures":failures,"samples":samples,"maxBodySurfaceGap":max_body_surface_gap,"gpuPixelsVerified":false}))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func _all_shifted_cores(reference: Dictionary) -> void:
	var covered := 0
	var levels: Array[String] = []
	for entry: Dictionary in reference.cases:
		if not str(entry.name).begins_with("authored/"): continue
		var id := str(entry.levelId)
		for state: Dictionary in [entry.initial.snapshot,entry.steps[-1].snapshot]:
			app.repository.data.mainline.runs[id] = state.duplicate(true)
			app.repository.data.mainline.memories[id] = state.duplicate(true)
			app._enter_level(id,bool(state.completed))
			await _tick(); await _tick()
			var saved: Dictionary = app.session.world.snapshot()
			var parent: Node3D = app.view._props_nodes.get("mark:core")
			if parent == null or not parent.is_visible_in_tree(): continue
			var flower: Sprite3D
			for child: Node in parent.get_children():
				if child is Sprite3D and child.has_meta("core_planter"): flower = child
			if flower == null: continue
			var shift: Vector3 = flower.get_meta("ground_footprint_center")-Vector3(0,0,.07)
			if id == "1-1" or shift.is_zero_approx():
				_check(Picking.core_support(app.view,app.view.world_to_screen(flower.global_position)).is_empty(),id+" unshifted/baseline core preserves original ground picking")
				continue
			covered += 1
			if not levels.has(id): levels.append(id)
			var support := str(parent.get_meta("tile_id"))
			for overview: bool in [false,true]:
				app.view.overview = overview; app.view._fit_camera(true)
				var picture := flower.texture.get_image()
				var count := 0
				var visible := Vector2.ZERO
				var at := Vector3.ZERO
				for y in range(20,200,12):
					for x in range(20,240,12):
						if picture.get_pixel(x,y).a<.75: continue
						var local := Vector3(x+.5-flower.texture.get_width()*.5+flower.offset.x,flower.texture.get_height()*.5+flower.offset.y-y-.5,0)*flower.pixel_size
						var point := flower.to_global(local)
						var screen: Vector2 = app.view.world_to_screen(point)
						if Picking.core_support(app.view,screen).is_empty(): continue
						_check(app.view.hit_test(screen) == support,id+" opaque shifted core maps to original support "+str(overview))
						count += 1; visible = screen; at = point
				_check(count>=3,id+" multiple exposed core pixels remain usable "+str(overview)+"/"+str(state.completed))
				if count == 0: continue
				# A synthetic foreground card probes opaque/transparent depth
				# behavior without changing real scenery or enlarging hitboxes.
				var obstruction := Sprite3D.new()
				var image := Image.create(8,8,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
				var texture := ImageTexture.create_from_image(image)
				obstruction.texture = texture; obstruction.pixel_size = .05
				app.view._props.add_child(obstruction)
				obstruction.global_basis = app.view._camera.global_basis
				obstruction.global_position = at-app.view._camera.project_ray_normal(visible)*.3
				_check(Picking.core_support(app.view,visible).is_empty(),id+" foreground opaque art blocks core click")
				image.fill(Color.TRANSPARENT); obstruction.texture = ImageTexture.create_from_image(image)
				_check(Picking.core_support(app.view,visible) == support,id+" foreground transparent pixel allows visible core click")
				obstruction.free()
				var block: MeshInstance3D = app.view._box(app.view._props,Vector3(.15,.15,.15),Vector3.ZERO,Color.WHITE)
				block.global_position = at-app.view._camera.project_ray_normal(visible)*.3
				_check(Picking.core_support(app.view,visible).is_empty(),id+" opaque mesh triangle blocks core click")
				block.free()
			_check(app.session.world.snapshot() == saved,id+" pixel picking preserves rules and completion")
	print(JSON.stringify({"shiftedCoreStates":covered,"shiftedCoreLevels":levels}))
	for id: String in ["1-3","1-4","2-1","2-2","2-3","2-4","3-1","3-2","3-3","3-4"]:
		_check(levels.has(id),id+" shifted core covered")
