extends SceneTree
const View = preload("profile_view.gd")
const Paint = preload("profile_paint.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var logger = ErrorLogger.new()
class TrackedWorld:
	extends "res://core/garden_world.gd"
	var counts: Dictionary = {}
	func track(label: String, start: int) -> void:
		var value: Dictionary = counts.get(label, {"calls": 0, "usec": 0})
		value.calls += 1
		value.usec += Time.get_ticks_usec() - start
		counts[label] = value
	func tiles() -> Array:
		var start := Time.get_ticks_usec()
		var value := super.tiles()
		track("world.tiles", start)
		return value
	func ready() -> bool:
		var start := Time.get_ticks_usec()
		var value := super.ready()
		track("world.ready", start)
		return value
	func commands() -> Array:
		var start := Time.get_ticks_usec()
		var value := super.commands()
		track("world.commands", start)
		return value
	func visible(tile: Dictionary) -> bool:
		var start := Time.get_ticks_usec()
		var value := super.visible(tile)
		track("world.visible", start)
		return value
	func rays() -> Array:
		var start := Time.get_ticks_usec()
		var value := super.rays()
		track("world.rays", start)
		return value
	func beam_hits(x: float, z: float) -> bool:
		var start := Time.get_ticks_usec()
		var value := super.beam_hits(x,z)
		track("world.beam_hits", start)
		return value
func _initialize() -> void:
	OS.add_logger(logger)
	create_timer(45).timeout.connect(func() -> void: quit(2))
	call_deferred("_run")
func _merge(into: Dictionary, source: Dictionary) -> void:
	for label in source:
		var current: Dictionary = into.get(label, {"calls": 0, "usec": 0})
		current.calls += source[label].calls
		current.usec += source[label].usec
		into[label] = current
func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	var reports: Array = []
	for level_id in ["1-1", "2-2"]:
		var world := TrackedWorld.new(level_id)
		view.set_world(world)
		view.set_visual_time(1200)
		for unused in range(12):
			await process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
		var initial_caches := {"soft": Paint._soft_cache.size(), "linear": Paint._linear_cache.size(), "halo": Paint._halo_cache.size(), "glow": Paint._glow_cache.size(), "oval": Paint._oval_fans.size()}
		view.profile_data = {}
		world.counts = {}
		var paint_counts: Dictionary = {}
		var frames := 30
		for unused in range(frames):
			await process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
			if view._profile_paint != null:
				_merge(paint_counts, view._profile_paint.profile_data)
		var data: Dictionary = view.profile_data.duplicate(true)
		_merge(data, world.counts)
		_merge(data, paint_counts)
		var draw_count: int = data.get("view._draw", {}).get("calls", 0)
		var normalized: Dictionary = {}
		for label in data:
			normalized[label] = {"callsPerDraw": float(data[label].calls) / max(1,draw_count), "inclusiveMsPerDraw": float(data[label].usec) / max(1,draw_count) / 1000.0}
		var final_caches := {"soft": Paint._soft_cache.size(), "linear": Paint._linear_cache.size(), "halo": Paint._halo_cache.size(), "glow": Paint._glow_cache.size(), "oval": Paint._oval_fans.size()}
		reports.append({"levelId": level_id, "draws": draw_count, "tiles": world.tiles().size(), "profile": normalized, "initialCaches": initial_caches, "finalCaches": final_caches})
	var output: String = get_script().resource_path.get_base_dir().path_join("current-" + DisplayServer.get_name() + ".json")
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"display": DisplayServer.get_name(), "note": "Inclusive CPU timing; nested rows overlap; wrapper overhead included; fixed time1200 and1280x720; no HUD", "reports": reports, "errors": logger.captured_errors()}, "\t"))
	print("DRAW_PROFILE " + output)
	for report in reports:
		print(report.levelId + " " + JSON.stringify(report.profile))
	quit(0 if logger.captured_errors().is_empty() else 1)

