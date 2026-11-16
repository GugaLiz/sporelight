extends SceneTree

const World = preload("res://core/garden_world.gd")
const View = preload("res://presentation/world/garden_view.gd")
const HUD = preload("res://ui/garden_hud.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
const Journey = preload("res://application/journey_view.gd")

var manifest_path := ""
var output_directory := ""
var with_hud := false
var failures: Array[String] = []
var checks := 0
var _logger := ErrorLogger.new()
var _finished := false

func _initialize() -> void:
	OS.add_logger(_logger)
	create_timer(90).timeout.connect(func() -> void:
		if not _finished:
			push_error("Visual reference test did not reach completion")
			quit(1))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")
		elif argument.begins_with("--output="):
			output_directory = argument.trim_prefix("--output=")
		elif argument == "--with-hud":
			with_hud = true
	if manifest_path.is_empty():
		manifest_path = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("docs/qa-godot-migration/reference/manifest.json")
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(manifest_path):
		push_error("Missing source visual reference manifest: " + manifest_path)
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		push_error("Invalid source visual reference manifest")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	view.set_settings(parsed.get("settings", {}))
	var hud: Control = null
	if with_hud:
		hud = HUD.new()
		viewport.add_child(hud)
		view.label_font = hud.theme.default_font
	await process_frame
	var actual: Array = []
	for capture in parsed.get("captures", []):
		var dimensions: Array = capture.get("viewport", [1280, 720])
		viewport.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		var model := World.new(str(capture.levelId), capture.snapshot)
		var normalized_actual: Variant = _normalize(model.snapshot())
		var normalized_reference: Variant = _normalize(capture.snapshot)
		var difference := _first_difference(normalized_actual, normalized_reference)
		_check(difference.is_empty(), "%s/%s restores the frozen rule state %s" % [capture.levelId, capture.stage, JSON.stringify(difference) if not difference.is_empty() else ""])
		view.set_world(model)
		view.set_visual_time(float(capture.get("visualTimeMs", 1200)))
		view.set_layout(Rect2())
		view._camera(model.tiles(), model.point_for(str(model.state.actors[model.state.active])))
		_check(absf(view.scale_factor - float(capture.scale)) < 0.00001, "%s/%s source camera scale" % [capture.levelId, capture.stage])
		_check(view.origin.distance_to(Vector2(float(capture.origin[0]), float(capture.origin[1]))) < 0.002, "%s/%s source camera origin" % [capture.levelId, capture.stage])
		if hud != null:
			hud.close_overlay()
			hud.update_state(model, false, str(model.level.get("intro", "")))
			hud.set_journey(Journey.describe(model))
			if model.state.get("completed", false):
				hud.show_ending(model)
		await process_frame
		await process_frame
		var record := {"levelId": capture.levelId, "stage": capture.stage, "file": capture.file, "visualTimeMs": view.visual_time, "scale": view.scale_factor, "origin": [view.origin.x, view.origin.y], "snapshotUnchanged": _normalize(model.snapshot()) == _normalize(capture.snapshot)}
		if not output_directory.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(output_directory)
			var image := viewport.get_texture().get_image()
			var error := image.save_png(output_directory.path_join(str(capture.file)))
			_check(error == OK, "capture " + str(capture.file))
			record["sha256"] = FileAccess.get_sha256(output_directory.path_join(str(capture.file))) if error == OK else ""
		actual.append(record)
	_check(view.asset_errors().is_empty(), "all referenced visuals load")
	viewport.queue_free()
	await process_frame
	failures.append_array(_logger.captured_errors())
	if not output_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(output_directory)
		var report := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
		if report != null:
			report.store_string(JSON.stringify({"format": "sporelight.godot-visual", "version": 1, "withHud": with_hud, "display": DisplayServer.get_name(), "captures": actual, "failures": failures}, "\t") + "\n")
	_finished = true
	if failures.is_empty():
		print("PASS source visual reference: %d captures / %d checks (pixel equality is not asserted)" % [actual.size(), checks])
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _normalize(value: Variant, key := "") -> Variant:
	# JSON parses numbers as floats; native defaults use ints. Compare semantic values.
	if value is int or value is float:
		return float(value)
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_normalize(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for name in value:
			result[name] = _normalize(value[name], str(name))
		return result
	if key == "trial" and value is String:
		var trial: Variant = JSON.parse_string(value)
		if trial != null:
			return _normalize(trial)
	return value

func _first_difference(actual: Variant, expected: Variant, path := "$") -> Dictionary:
	if actual is Dictionary and expected is Dictionary:
		for key in expected:
			if not actual.has(key):
				return {"path": path + "." + str(key), "actual": "<missing>", "expected": expected[key]}
			var difference := _first_difference(actual[key], expected[key], path + "." + str(key))
			if not difference.is_empty():
				return difference
		for key in actual:
			if not expected.has(key):
				return {"path": path + "." + str(key), "actual": actual[key], "expected": "<missing>"}
		return {}
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			return {"path": path + ".length", "actual": actual.size(), "expected": expected.size()}
		for index in range(actual.size()):
			var difference := _first_difference(actual[index], expected[index], path + "[%d]" % index)
			if not difference.is_empty():
				return difference
		return {}
	return {} if actual == expected else {"path": path, "actual": actual, "expected": expected}
