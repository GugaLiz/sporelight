extends SceneTree
## Observe the actual home controls, rather than copying their layout formulas.
## Sizes are native canvas backing pixels; the browser maps them to CSS pixels.
const HUD := preload("res://ui/garden_hud.gd")
const Store := preload("res://services/save_repository.gd")
var _sizes := "1280x720,390x844,320x568,568x320,594x462,2560x1440,3440x1440"
var _output := ""
var _failures: Array[String] = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sizes="):
			_sizes = argument.trim_prefix("--sizes=")
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	_run.call_deferred()


func _settle() -> void:
	for frame in 6:
		await process_frame


func _rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


func _run() -> void:
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	var hud := HUD.new()
	root.add_child(hud)
	hud.set_repository(Store.new("user://unused-brand-layout-contract.json"))
	var results: Array = []
	for size_key in _sizes.split(",", false):
		var components := size_key.split("x")
		if components.size() != 2 or not components[0].is_valid_int() or not components[1].is_valid_int():
			_failures.append("Invalid backing size: " + size_key)
			continue
		var extent := Vector2i(int(components[0]), int(components[1]))
		if extent.x <= 0 or extent.y <= 0:
			_failures.append("Non-positive backing size: " + size_key)
			continue
		root.size = extent
		hud.show_home(levels, {"records": {}, "runs": {}, "memories": {}}, false)
		await _settle()
		var cover: Control = hud._home_cover
		var logo: TextureRect = cover.logo
		var tagline: Label = cover.tagline
		var container := logo.get_global_rect()
		var texture_size := logo.texture.get_size()
		var fit := minf(container.size.x / texture_size.x, container.size.y / texture_size.y)
		var painted_size := texture_size * fit
		var painted := Rect2(container.position + (container.size - painted_size) * 0.5, painted_size)
		if logo.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			_failures.append(size_key + ": update the observer for the new TextureRect stretch mode")
		if not cover.size.is_equal_approx(Vector2(extent)):
			_failures.append(size_key + ": the real cover does not fill the requested native viewport")
		if not Rect2(Vector2.ZERO, Vector2(extent)).encloses(painted):
			_failures.append(size_key + ": painted logo escapes the viewport")
		var font := tagline.get_theme_font("font")
		var font_size := tagline.get_theme_font_size("font_size")
		var line_size := font.get_string_size(tagline.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		results.append({
			"size": [extent.x, extent.y],
			"key": size_key,
			"viewport": [cover.size.x, cover.size.y],
			"logoRect": _rect(container),
			"paintedRect": _rect(painted),
			"textureSize": [texture_size.x, texture_size.y],
			"texturePath": logo.texture.resource_path,
			"stretchMode": logo.stretch_mode,
			"taglineRect": _rect(tagline.get_global_rect()),
			"fontSize": font_size,
			"fontAscent": font.get_ascent(font_size),
			"fontDescent": font.get_descent(font_size),
			"lineSize": [line_size.x, line_size.y],
			"taglineHorizontalAlignment": tagline.horizontal_alignment,
			"taglineVerticalAlignment": tagline.vertical_alignment,
		})
	hud.queue_free()
	await _settle()
	var report := {"suite": "native-brand-layout", "passed": _failures.is_empty() and not results.is_empty(), "results": results, "failures": _failures, "scope": "Geometry observed from real GardenHUD home controls. paintedRect applies the actual TextureRect centered-contain mode; not GPU raster or browser evidence."}
	var encoded := JSON.stringify(report, "  ") + "\n"
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output.get_base_dir())
		var file := FileAccess.open(_output, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write brand layout report: " + _output)
			quit(1)
			return
		file.store_string(encoded)
	print(JSON.stringify(report))
	quit(0 if report.passed else 1)
