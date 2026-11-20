class_name ElementAssets
extends RefCounted
## Shared texture slots. Themes change appearance only, never world state.
const THEME_PATH := "res://content/element-theme.json"
const BITMAP_REDRAW_PATH := "res://content/bitmap-redraw.json"
static var _paths: Dictionary = {}
static var _textures: Dictionary = {}
static var _overrides: Dictionary = {}
static var _theme_sources: Dictionary = {}
static var _bitmap_overrides: Dictionary = {}
static var _revision := 0
static var _loaded := false
static var _errors: Array[String] = []

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/visual-assets.json"))
	if manifest is Dictionary:
		for entry: Dictionary in manifest.get("entries", []):
			_paths[str(entry.id)] = str(entry.resource)
	for path: String in ["res://content/prop-elements.json", "res://content/actor-elements.json", "res://content/surface-elements.json"]:
		if not FileAccess.file_exists(path): continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or not data.get("resources", {}) is Dictionary: continue
		for alias: String in data.get("resources", {}):
			var resource: Variant = data.resources[alias]
			if resource is Dictionary: resource = resource.get("resource", "")
			if not resource is String or not resource.begins_with("res://"):
				_errors.append("Invalid element resource: " + alias); continue
			if _paths.has(alias) and _paths[alias] != resource:
				_errors.append("Conflicting element resource: " + alias); continue
			_paths[alias] = resource
	if FileAccess.file_exists(BITMAP_REDRAW_PATH):
		var redraw: Variant = JSON.parse_string(FileAccess.get_file_as_string(BITMAP_REDRAW_PATH))
		if redraw is Dictionary:
			var result := apply_bitmap_redraw(redraw)
			if not result.ok: _errors.append(str(result.error))
		else: _errors.append("Invalid bitmap-redraw.json")
	if FileAccess.file_exists(THEME_PATH):
		var theme: Variant = JSON.parse_string(FileAccess.get_file_as_string(THEME_PATH))
		if theme is Dictionary:
			var result := apply_theme(theme)
			if not result.ok: _errors.append(str(result.error))
		else: _errors.append("Invalid element-theme.json")

static func paths() -> Dictionary:
	_ensure_loaded()
	var result := {}
	for alias: String in _paths: result[alias] = resource_path(alias)
	return result

static func resource_path(alias: String) -> String:
	_ensure_loaded()
	return source_path(str(_paths.get(alias, "")))

static func source_path(original_path: String) -> String:
	_ensure_loaded()
	# UI paths and world aliases share one source identity. A theme is an
	# explicit appearance override; shipped redraws form the default bitmap set.
	return str(_theme_sources.get(original_path, _bitmap_overrides.get(original_path, original_path)))

static func texture_for_source(original_path: String) -> Texture2D:
	return _texture_at(source_path(original_path))

static func texture(alias: String) -> Texture2D:
	return _texture_at(resource_path(alias))

static func _texture_at(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _textures.has(path): _textures[path] = load(path) as Texture2D
	return _textures[path]

static func revision() -> int:
	_ensure_loaded()
	return _revision

static func errors() -> Array[String]:
	_ensure_loaded()
	return _errors.duplicate()

static func apply_theme(theme: Dictionary) -> Dictionary:
	_ensure_loaded()
	if theme.get("schema_version", 0) != 1 or not theme.get("resource_overrides") is Dictionary:
		return {"ok":false,"error":"Theme requires schema_version=1 and resource_overrides"}
	var proposed: Dictionary = theme.resource_overrides.duplicate()
	var sources := {}
	for alias: Variant in proposed:
		if not alias is String or not _paths.has(alias):
			return {"ok":false,"error":"Unknown texture slot: " + str(alias)}
		var path: Variant = proposed[alias]
		if not path is String or not path.begins_with("res://") or not ResourceLoader.exists(path):
			return {"ok":false,"error":"Replacement texture does not exist: " + str(alias)}
		var replacement := load(path) as Texture2D
		var original := load(str(_paths[alias])) as Texture2D
		if replacement == null or original == null:
			return {"ok":false,"error":"Replacement must be Texture2D: " + str(alias)}
		# A path-only swap must retain pixel-anchor meaning. New dimensions,
		# feet or footprints require a complete element/skin definition change.
		if replacement.get_size() != original.get_size():
			return {"ok":false,"error":"Canvas differs; update the element's anchor/footprint definition: " + str(alias)}
		var source := str(_paths[alias])
		if sources.has(source) and sources[source] != path:
			return {"ok":false,"error":"Conflicting replacements for shared bitmap: " + source}
		sources[source] = path
	if proposed != _overrides:
		_overrides = proposed
		_theme_sources = sources
		_textures.clear()
		_revision += 1
	return {"ok":true,"revision":_revision}

static func bitmap_redraw_paths() -> Dictionary:
	_ensure_loaded()
	return _bitmap_overrides.duplicate()

static func apply_bitmap_redraw(redraw: Dictionary) -> Dictionary:
	_ensure_loaded()
	if redraw.get("schema_version", 0) != 1 or not redraw.get("source_overrides") is Dictionary:
		return {"ok":false,"error":"Bitmap redraw requires schema_version=1 and source_overrides"}
	var proposed: Dictionary = redraw.source_overrides.duplicate()
	for source: Variant in proposed:
		var path: Variant = proposed[source]
		if not source is String or not _bitmap_path_allowed(source) or not ResourceLoader.exists(source):
			return {"ok":false,"error":"Original bitmap does not exist: " + str(source)}
		if not path is String or not _bitmap_path_allowed(path) or not ResourceLoader.exists(path):
			return {"ok":false,"error":"Replacement bitmap does not exist: " + str(path)}
		var original := load(str(source)) as Texture2D
		var replacement := load(str(path)) as Texture2D
		if original == null or replacement == null:
			return {"ok":false,"error":"Bitmap replacements must be Texture2D: " + str(source)}
		if replacement.get_size() != original.get_size():
			return {"ok":false,"error":"Bitmap canvas differs; preserve source crop/anchor meaning: " + str(source)}
	if proposed != _bitmap_overrides:
		_bitmap_overrides = proposed
		_textures.clear()
		_revision += 1
	return {"ok":true,"revision":_revision}

static func _bitmap_path_allowed(path: String) -> bool:
	return path.begins_with("res://assets/images/") and path.simplify_path() == path

static func reset_bitmap_redraw() -> void:
	_ensure_loaded()
	if not _bitmap_overrides.is_empty():
		_bitmap_overrides.clear()
		_textures.clear()
		_revision += 1

static func reset_theme() -> void:
	_ensure_loaded()
	if not _overrides.is_empty():
		_overrides.clear()
		_theme_sources.clear()
		_textures.clear()
		_revision += 1
