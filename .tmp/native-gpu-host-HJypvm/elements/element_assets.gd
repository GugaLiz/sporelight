class_name ElementAssets
extends RefCounted
## Shared texture slots. Themes change appearance only, never world state.
const THEME_PATH := "res://content/element-theme.json"
static var _paths: Dictionary = {}
static var _textures: Dictionary = {}
static var _overrides: Dictionary = {}
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
	if FileAccess.file_exists(THEME_PATH):
		var theme: Variant = JSON.parse_string(FileAccess.get_file_as_string(THEME_PATH))
		if theme is Dictionary:
			var result := apply_theme(theme)
			if not result.ok: _errors.append(str(result.error))
		else: _errors.append("Invalid element-theme.json")

static func paths() -> Dictionary:
	_ensure_loaded()
	var result := _paths.duplicate()
	result.merge(_overrides, true)
	return result

static func resource_path(alias: String) -> String:
	_ensure_loaded()
	return str(_overrides.get(alias, _paths.get(alias, "")))

static func texture(alias: String) -> Texture2D:
	var path := resource_path(alias)
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
	if proposed != _overrides:
		_overrides = proposed
		_textures.clear()
		_revision += 1
	return {"ok":true,"revision":_revision}

static func reset_theme() -> void:
	_ensure_loaded()
	if not _overrides.is_empty():
		_overrides.clear()
		_textures.clear()
		_revision += 1
