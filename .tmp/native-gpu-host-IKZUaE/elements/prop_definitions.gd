extends RefCounted
## Shared prop data; layouts/rules remain in their authored level adapters.
static var _data: Dictionary = {}
static var _rectangles: Dictionary = {}
static var _revision := 0

static func _ensure_loaded() -> void:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://content/prop-elements.json"))

static func definitions() -> Dictionary:
	_ensure_loaded()
	return _data.duplicate(true)

static func section(name: String) -> Dictionary:
	# Internal read-only view. Renderers must not mutate shared definition data.
	# The public definitions() returns an isolated copy for editor inspection.
	_ensure_loaded()
	return _data.get(name, {})

static func revision() -> int:
	return _revision

static func reload_definitions() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/prop-elements.json"))
	if not validate_definition(parsed): return false
	_merge_live(_data, parsed)
	# Existing renderer aliases keep references to these converted dictionaries.
	for cache_key: String in _rectangles:
		var parts := cache_key.split("/")
		var rects: Dictionary = _rectangles[cache_key]
		rects.clear()
		rects.merge(_convert_rectangles(parts[0], parts[1]))
	_revision += 1
	return true

static func validate_definition(parsed: Variant) -> bool:
	_ensure_loaded()
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 1: return false
	if not _matches_shape(parsed, _data): return false
	for key: String in ["planters", "scale", "core_layout", "scenery", "visual_scale", "natural_assets", "semantic_overrides"]:
		if not parsed.get(key) is Dictionary: return false
	var terminal: Variant = parsed.planters.get("terminal")
	if not terminal is Dictionary or float(terminal.get("reference_canvas_width", 0)) <= 0: return false
	if not terminal.get("states") is Dictionary: return false
	for key: String in ["empty", "completed"]:
		if not terminal.states.get(key) is String or str(terminal.states[key]).is_empty(): return false
	for pair: Array in [["anchor",3], ["ground_span",2], ["ground_center",3], ["painted_foot",2]]:
		if not terminal.get(pair[0]) is Array or terminal[pair[0]].size() != int(pair[1]): return false
		for value: Variant in terminal[pair[0]]:
			if not (value is int or value is float) or not is_finite(float(value)): return false
	if float(terminal.ground_span[0]) <= 0 or float(terminal.ground_span[1]) <= 0: return false
	if float(parsed.scale.get("tile_pixels",0)) <= 0 or float(parsed.scale.get("tile_projected_world",0)) <= 0: return false
	if not parsed.scale.get("source_widths") is Dictionary or not parsed.scale.get("body_bounds") is Dictionary: return false
	if float(terminal.support_clearance) < 0 or float(terminal.contact_height) < 0: return false
	if float(terminal.contact_opacity) < 0 or float(terminal.contact_opacity) > 1: return false
	for family: Dictionary in parsed.natural_assets.values():
		for spec: Dictionary in family.values():
			if float(spec.pixelSize) <= 0: return false
			if float(spec.atlasAlpha8[2]) <= 0 or float(spec.atlasAlpha8[3]) <= 0: return false
			if float(spec.atlasAlpha8[0]) < 0 or float(spec.atlasAlpha8[1]) < 0: return false
			if float(spec.atlasAlpha8[0]) + float(spec.atlasAlpha8[2]) > float(spec.canvas[0]): return false
			if float(spec.atlasAlpha8[1]) + float(spec.atlasAlpha8[3]) > float(spec.canvas[1]): return false
	for adapter: Dictionary in parsed.renderer_adapters.values():
		if not FileAccess.file_exists(str(adapter.script)) or str(adapter.entry).is_empty(): return false
	return true

static func _matches_shape(value: Variant, template: Variant) -> bool:
	if template is Dictionary:
		# Live reload edits existing families. Structural library migrations
		# require a restart so renderer registration cannot become half-updated.
		if not value is Dictionary or value.size() != template.size(): return false
		for key: Variant in template:
			if not value.has(key) or not _matches_shape(value[key], template[key]): return false
		return true
	if template is Array:
		if not value is Array or value.size() != template.size(): return false
		for index in template.size():
			if not _matches_shape(value[index], template[index]): return false
		return true
	if template is float or template is int:
		return (value is float or value is int) and is_finite(float(value))
	return typeof(value) == typeof(template)

static func _merge_live(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in target.keys():
		if not source.has(key): target.erase(key)
	for key: Variant in source:
		if source[key] is Dictionary and target.get(key) is Dictionary:
			_merge_live(target[key], source[key])
		elif source[key] is Array and target.get(key) is Array:
			target[key].clear()
			target[key].append_array(source[key])
		else: target[key] = source[key]

static func vector2(values: Array) -> Vector2:
	return Vector2(float(values[0]), float(values[1]))

static func vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func rectangles(group: String, key: String) -> Dictionary:
	var cache_key := group + "/" + key
	if not _rectangles.has(cache_key): _rectangles[cache_key] = _convert_rectangles(group, key)
	return _rectangles[cache_key]

static func _convert_rectangles(group: String, key: String) -> Dictionary:
	var result := {}
	var values: Dictionary = section(group)[key]
	for id: String in values:
		var value: Array = values[id]
		result[id] = Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return result

static func planter_spec() -> Dictionary:
	return section("planters").terminal

static func planter_alias(completed: bool) -> String:
	return str(planter_spec().states.completed if completed else planter_spec().states.empty)

static func planter_anchor(width: float) -> Vector3:
	var spec := planter_spec()
	return vector3(spec.anchor) * (width / float(spec.reference_canvas_width))

static func planter_span(width: float) -> Vector2:
	var spec := planter_spec()
	return vector2(spec.ground_span) * (width / float(spec.reference_canvas_width))

static func planter_center() -> Vector3:
	return vector3(planter_spec().ground_center)

static func canvas_width(kind: String, level := "") -> float:
	var spec := section("scale")
	if kind == "core" and level == "3-4": kind = "final_core"
	return float(spec.source_widths.get(kind, 0.0)) * float(spec.tile_projected_world) / float(spec.tile_pixels)

static func core_override(level: String) -> Dictionary:
	var result: Dictionary = section("core_layout").fixed.get(level, {}).duplicate(true)
	if not result.is_empty(): result.shift = vector3(result.shift)
	return result

static func rear_placements() -> Dictionary:
	var result: Dictionary = section("core_layout").rear_placements.duplicate(true)
	for id: String in result: result[id] = vector3(result[id])
	return result

static func natural_spec(group: String, id: String) -> Dictionary:
	return section("natural_assets")[group][id]

static func semantic_for_mark(level: String, mark: Dictionary) -> String:
	var id := str(mark.get("id", ""))
	var overrides := section("semantic_overrides")
	if overrides.has(level + "/" + id): return str(overrides[level + "/" + id])
	var kind := str(mark.get("kind", ""))
	if kind == "core": return "planter-terminal"
	if kind == "flower": return "planter-task"
	return kind
