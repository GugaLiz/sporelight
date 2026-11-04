extends SceneTree

const World = preload("res://core/garden_world.gd")
const View = preload("res://presentation/world/garden_view.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")

var failures: Array[String] = []
var checks := 0
var capture_directory := ""
var _logger := ErrorLogger.new()
var _finished := false

func _initialize() -> void:
	OS.add_logger(_logger)
	create_timer(30).timeout.connect(func() -> void:
		if not _finished:
			push_error("Visual scene test did not reach completion")
			quit(1))
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--capture" and index + 1 < args.size():
			capture_directory = args[index + 1]
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	view.set_visual_time(1200)
	await process_frame
	_check(view.asset_errors().is_empty(), "all visual textures import into the renderer")
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	for level in definitions.levels:
		var model := World.new(str(level.id))
		var stable: Dictionary = model.snapshot()
		view.set_world(model)
		view.set_layout(Rect2())
		view._camera(model.tiles(), model.point_for(str(model.state.actors[model.state.active])))
		_check(is_finite(view.scale_factor) and view.scale_factor > 0, "%s has a valid camera" % level.id)
		if level.id == "1-1":
			_check(absf(view.scale_factor - 1.293833131801693) < 0.00001, "1-1 camera scale matches TypeScript reference at 1280x720")
			_check(view.origin.distance_to(Vector2(566.1579201934704, 363.7258766626361)) < 0.001, "1-1 reference camera origin")
		elif level.id == "1-3":
			_check(absf(view.scale_factor - 0.9587813620071685) < 0.00001, "1-3 camera scale matches TypeScript reference at 1280x720")
			_check(view.origin.distance_to(Vector2(588.8, 368.647311827957)) < 0.001, "1-3 reference camera origin")
			# Captured from the frozen TypeScript gardenScenery(), including equal-depth ties.
			var expected_props := [["red-mushroom", -4.0, -1.24], ["blue-flowers", 1.0, -5.24], ["gold-lotus", -1.24, -3.0], ["bush", -4.0, 1.24], ["berry-bush", 1.24, -3.0], ["fern", -1.24, 3.0], ["small-pebbles", 2.76, -1.0], ["pink-flowers", 1.0, 2.76], ["stone-lantern", -1.24, 5.0], ["yellow-flowers", 5.0, -1.24], ["red-mushroom", 2.76, 1.0], ["blue-flowers", 1.24, 5.0], ["gold-lotus", 5.24, 1.0], ["arch", -5.0, -1.0]]
			_check(view._scenery.size() == expected_props.size(), "1-3 decoration count matches source")
			for index in range(mini(view._scenery.size(), expected_props.size())):
				var prop: Dictionary = view._scenery[index]
				var expected: Array = expected_props[index]
				_check(prop.asset == expected[0] and is_equal_approx(float(prop.x), expected[1]) and is_equal_approx(float(prop.z), expected[2]), "1-3 decoration %d retains source tie order and placement" % index)
		elif level.id in ["2-1", "2-2", "2-3", "2-4"]:
			var outline: Array = view.Landscape.pond_footprint(model.level)
			var expected_count: int = {"2-1": 16, "2-2": 12, "2-3": 14, "2-4": 12}[level.id]
			_check(outline.size() == expected_count, "%s pond hull matches the source vertex count" % level.id)
			_check(absf(float(outline[0].x) - (-4.2 if level.id == "2-2" else -8.2)) < 0.00001 and absf(float(outline[0].z) + 1) < 0.00001, "%s pond hull keeps source seed origin" % level.id)
			_check(absf(float(outline[1].x) - (-3.2627416997969525 if level.id == "2-2" else -7.262741699796953)) < 0.00001 and absf(float(outline[1].z) + 3.262741699796952) < 0.00001, "%s pond hull keeps source winding" % level.id)
		await process_frame
		await process_frame
		_check(model.snapshot() == stable, "%s rendering does not mutate gameplay" % level.id)
		if not capture_directory.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(capture_directory)
			var image := viewport.get_texture().get_image()
			_check(not image.is_empty(), "%s framebuffer available" % level.id)
			_check(image.save_png(capture_directory.path_join("%s-arrival.png" % level.id)) == OK, "%s captured" % level.id)
	var model := World.new("1-3")
	view.set_world(model)
	var before: Dictionary = model.snapshot()
	var after: Dictionary = before.duplicate(true)
	after.turns.garden = 1
	view.set_motion(before, after, 0.5, "turn:garden")
	var old_tile: Dictionary = view._tile_for("m:garden:-1:0", view._from_tiles)
	var new_tile: Dictionary = view._tile_for("m:garden:-1:0", view._to_tiles)
	var midpoint: Dictionary = view._interpolate(old_tile, new_tile)
	_check(absf(float(midpoint.x) + sqrt(0.5)) < 0.00001 and absf(float(midpoint.z) + sqrt(0.5)) < 0.00001, "rotating platform follows an arc, not linear diagonal shrinkage")
	_check(model.snapshot() == before, "motion endpoint previews do not commit model state")
	view.clear_motion()
	var finale := World.new("3-4")
	var finale_state: Dictionary = finale.snapshot()
	finale_state.turns.water = 1
	finale_state.turns.inner = 1
	view.set_world(finale.fork(finale_state))
	var lines: Array = []
	view._add_surface_lines(lines)
	var delivery_count := 0
	for line in lines:
		if line.get("color", "") == "#b4e6e6":
			delivery_count += 1
	_check(delivery_count == 20, "3-4 delivery channels preserve both source consumer paths, split per ground tile")
	view.set_world(model)
	view.set_layout(Rect2(320, 60, 600, 520))
	view._camera(model.tiles(), model.point_for(str(model.state.actors.luvie)))
	for tile in model.tiles():
		_check(Rect2(320, 60, 600, 520).has_point(view.project(tile)), "explicit HUD-safe rectangle contains %s" % tile.id)
	view.set_layout(Rect2())
	viewport.size = Vector2i(390, 844)
	view._camera(model.tiles(), model.point_for(str(model.state.actors.luvie)))
	_check(is_equal_approx(view.scale_factor, 0.92), "default narrow-screen camera keeps original scale")
	await process_frame
	viewport.queue_free()
	await process_frame
	failures.append_array(_logger.captured_errors())
	_finished = true
	if failures.is_empty():
		print("PASS visual scene: %d checks" % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
