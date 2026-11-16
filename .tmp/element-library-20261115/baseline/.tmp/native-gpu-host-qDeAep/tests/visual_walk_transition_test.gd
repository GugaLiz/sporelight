extends SceneTree

const World = preload("res://core/garden_world.gd")
const View = preload("res://presentation/world/garden_view.gd")
const Motion = preload("res://presentation/actors/character_motion.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var _logger := ErrorLogger.new()
var failures: Array[String] = []
var checks := 0
var output_directory := ""
var samples: Array = []
var _done := false

func _initialize() -> void:
	OS.add_logger(_logger)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_directory = argument.trim_prefix("--output=")
	create_timer(45).timeout.connect(func() -> void:
		if not _done:
			push_error("Walk transition test timed out")
			quit(1))
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var model := World.new("1-1")
	var view := View.new()
	viewport.add_child(view)
	view.set_world(model)
	view.set_visual_time(1000)
	await process_frame
	var before: Dictionary = model.snapshot()
	var probe: RefCounted = model.fork(before)
	_check(probe.move("f:-1:0").ok, "first source move is legal")
	var first: Dictionary = probe.snapshot()
	view.set_motion(before, first, 0, "move")
	for elapsed in [0, 35, 70, 110, 165, 204]:
		view.set_visual_time(1000 + elapsed)
		view.set_motion(before, first, elapsed / 205.0, "move")
		await _sample(view, viewport, "walk-first-%03d" % elapsed)
		var data: Dictionary = view.character_presentation()
		_check(data.walk_started == 1000, "first segment does not restart its clock")
		_check(data.pose.get("walk_group", "") == "side" and data.facing == "left", "flat leftward movement retains a side-facing frame")
		_check(data.pose.offset_y == 0, "walking body bounce keeps the authored foot pivot")
	view.set_visual_time(1205)
	view.set_motion(before, first, 1, "move")
	_check(model.move("f:-1:0").ok, "first move commits exactly at its target")
	probe = model.fork(first)
	_check(probe.move("f:-2:0").ok, "second source move is legal")
	var second: Dictionary = probe.snapshot()
	var end_pose: Dictionary = view.character_presentation()
	view.set_motion(first, second, 0, "move")
	var next_pose: Dictionary = view.character_presentation()
	_check(next_pose.walk_started == 1000, "same-frame next segment keeps the original walk clock")
	_check(next_pose.key == end_pose.key, "segment boundary preserves the current gait frame")
	_check(next_pose.screen_footpoint == end_pose.screen_footpoint, "shared-tile stance offset resolves within the segment instead of popping on commit")
	_check(not next_pose.stop_blend_active, "continuous movement does not enter a stop blend")
	for elapsed in [0, 55, 110, 165, 205]:
		view.set_visual_time(1205 + elapsed)
		view.set_motion(first, second, elapsed / 205.0, "move")
		await _sample(view, viewport, "walk-second-%03d" % elapsed)
	var arrival: Dictionary = view.character_presentation()
	var arrival_foot: Dictionary = arrival.footpoint.duplicate()
	var arrival_screen: Dictionary = arrival.screen_footpoint.duplicate()
	_check(model.move("f:-2:0").ok, "second move commits exactly at its target")
	view.clear_motion()
	var final_state: Dictionary = model.snapshot()
	var stopped: Dictionary = view.character_presentation()
	var logical_anchor: Dictionary = stopped.anchor
	var final_anchor: Dictionary = stopped.footpoint.duplicate()
	_check(logical_anchor.x == -2 and logical_anchor.z == 0 and logical_anchor.h == 0, "stop retains the exact committed logical grid center")
	# The whole first garden has one declared art stance. It is independent of
	# stop blending and never feeds the logical grid or camera anchor.
	_check(final_anchor.x == -2.02 and final_anchor.z == -0.18 and final_anchor.h == 0, "stop retains the declared constant world foot offset from the grid center")
	_check(final_anchor == arrival_foot, "p1 and clear_motion preserve the identical actual world foot")
	_check(stopped.screen_footpoint == arrival_screen, "p1 and clear_motion preserve the identical actual screen foot")
	for elapsed in [0, 20, 40, 60, 80, 100, 120, 180]:
		view.set_visual_time(1410 + elapsed)
		await _sample(view, viewport, "stop-%03d" % elapsed)
		var data: Dictionary = view.character_presentation()
		_check(data.footpoint == final_anchor, "stop never adds world position inertia")
		_check(data.pose.offset_y == 0, "settling never translates the planted foot pivot")
		_check(data.facing == "left", "stop does not snap to a front-facing pose")
		_check(data.stop_blend_active == (elapsed < 100), "stop blend lasts the configured 100ms")
		_check(model.snapshot() == final_state, "visual settling cannot mutate puzzle state")
	view.set_visual_time(1460)
	view.resume_visual_time()
	view.set_paused(true)
	var frozen := view.visual_time
	var frozen_pose: Dictionary = view.character_presentation()
	view._process(0.05)
	_check(view.visual_time == frozen and view.character_presentation().weight == frozen_pose.weight, "pause freezes the settling clock and blend weight")
	view.set_visual_time(1460)
	view.clear_motion(false)
	_check(not view.character_presentation().stop_blend_active and not view.character_presentation().blend, "undo/QA reset immediately removes a visual transition")
	view.set_settings({"lowMotion": true})
	view.set_motion(first, second, 1, "move")
	view.clear_motion()
	_check(not view.character_presentation().blend and not view.character_presentation().stop_blend_active, "low motion uses an immediate stable pose")
	view.set_settings({"lowMotion": false})
	view.set_world(World.new("1-3"))
	_check(not view.character_presentation().blend and view.character_presentation().facing == "front", "changing levels clears the old stance and direction")
	for facing in ["front", "left", "right", "back"]:
		for time in range(0, 1320, 11):
			var pose := Motion.pose(time, facing, false, false, {"started_at": 0, "progress": 0.5})
			var group: String = Motion.walk_group(facing)
			_check(pose.key in _keys(Motion.WALK_CLIPS[group]), "directional clips never select a different source viewpoint")
	viewport.queue_free()
	await process_frame
	failures.append_array(_logger.captured_errors())
	if not output_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(output_directory)
		var report := FileAccess.open(output_directory.path_join("checks.json"), FileAccess.WRITE)
		if report != null:
			report.store_string(JSON.stringify({"checks": checks, "failures": failures, "samples": samples, "walkClips": Motion.WALK_CLIPS}, "\t") + "\n")
	_done = true
	if failures.is_empty():
		print("PASS walk transitions: %d checks, %d multi-frame samples" % [checks, samples.size()])
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _keys(definition: Dictionary) -> Array:
	var result: Array = []
	for index in definition.frames:
		result.append("%s%d" % [definition.prefix, index])
	return result

func _sample(view: Node2D, viewport: SubViewport, name: String) -> void:
	await process_frame
	await process_frame
	var data: Dictionary = view.character_presentation()
	data["sample"] = name
	data["time"] = view.visual_time
	samples.append(data)
	if not output_directory.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(output_directory)
		_check(viewport.get_texture().get_image().save_png(output_directory.path_join(name + ".png")) == OK, "capture " + name)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
