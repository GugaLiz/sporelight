extends SceneTree

const View = preload("res://presentation/world/garden_view.gd")
const World = preload("res://core/garden_world.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var _logger := ErrorLogger.new()
var _finished := false
var checks := 0

func _initialize() -> void:
	OS.add_logger(_logger)
	create_timer(90).timeout.connect(func() -> void:
		if not _finished:
			push_error("Dynamic visual sampling did not complete")
			quit(1))
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	for dimensions in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(844, 390), Vector2i(738, 672)]:
		viewport.size = dimensions
		for id in ["1-1", "1-4", "2-1", "2-2", "2-3", "2-4", "3-4"]:
			var world := World.new(id)
			view.set_world(world)
			for time in [0, 1200, 5020, 6005, 6020, 6100, 6201, 13000]:
				view.set_visual_time(time)
				await process_frame
				await process_frame
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
				checks += 1
	viewport.queue_free()
	await process_frame
	_finished = true
	var errors := _logger.captured_errors()
	if errors.is_empty():
		print("PASS dynamic visual rendering: %d size/level/time samples" % checks)
		quit(0)
	else:
		for message in errors:
			push_error(message)
		quit(1)
