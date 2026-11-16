extends SceneTree
## Deterministic raster export of the repository-authored SVG icon system.
var failed := false

func _initialize() -> void:
	var directory := ProjectSettings.globalize_path("res://../assets/branding/")
	var icon := FileAccess.get_file_as_string(directory.path_join("icon.svg"))
	var favicon := FileAccess.get_file_as_string(directory.path_join("favicon.svg"))
	if icon.is_empty() or favicon.is_empty():
		push_error("Brand icon SVG sources are missing")
		quit(1)
		return
	var rounded := '<rect id="background" width="512" height="512" rx="110"'
	if not icon.contains(rounded):
		push_error("Brand icon background contract changed; review maskable export")
		quit(1)
		return
	var square := icon.replace(rounded, '<rect id="background" width="512" height="512" rx="0"')
	for size: int in [16, 24, 32, 48, 64, 128, 256, 512]:
		_render(icon, 512, size, directory.path_join("desktop-%d.png" % size))
	_render(icon, 512, 192, directory.path_join("icon-192.png"))
	_render(icon, 512, 512, directory.path_join("icon-512.png"))
	_render(square, 512, 180, directory.path_join("apple-touch-icon.png"))
	_render(square, 512, 192, directory.path_join("maskable-192.png"))
	_render(square, 512, 512, directory.path_join("maskable-512.png"))
	for size: int in [16, 24, 32, 48, 64, 128, 256]:
		_render(favicon, 64, size, directory.path_join("favicon-%d.png" % size))
	quit(1 if failed else 0)

func _render(source: String, base: int, size: int, path: String) -> void:
	var image := Image.new()
	var error := image.load_svg_from_string(source, float(size * 4) / base)
	if error != OK:
		failed = true
		push_error("Unable to render brand SVG: " + path)
		return
	image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if image.save_png(path) != OK:
		failed = true
		push_error("Unable to save brand PNG: " + path)
