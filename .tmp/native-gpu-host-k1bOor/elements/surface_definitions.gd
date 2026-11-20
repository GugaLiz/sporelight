class_name SurfaceDefinitions
extends RefCounted
## Appearance-only catalog. Geometry, support and puzzle state stay with their
## existing owners; editor compositions must not derive collision from textures.
const CatalogPath := "res://content/surface-elements.json"
const Assets = preload("res://elements/element_assets.gd")
static var _catalog: Dictionary = {}
static var _overrides: Dictionary = {}
static var _revision := 0

static func _data() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CatalogPath))
		if parsed is Dictionary: _catalog = parsed
	return _catalog

static func definitions() -> Dictionary:
	var result := _data().duplicate(true)
	for chapter: String in _overrides: result.themes[chapter] = theme(chapter)
	return result

static func revision() -> int: return _revision

static func reset() -> void:
	_catalog = {}
	_overrides = {}
	_revision += 1

## For editor previews: resource aliases stay logical names resolved by ElementAssets.
## Invalid themes/slots are rejected atomically instead of partially applying a skin.
static func set_theme_overrides(chapter: String, values: Dictionary) -> bool:
	var themes: Dictionary = _data().get("themes",{})
	if not themes.has(chapter): return false
	for key: Variant in values:
		if not themes[chapter].has(key): return false
		if key == "wallPixelsPerUnit":
			if not values[key] is Array or values[key].size()!=2: return false
			for n: Variant in values[key]:
				if not (n is int or n is float) or not is_finite(float(n)) or float(n)<=0: return false
		elif not values[key] is String or str(values[key]).strip_edges().is_empty(): return false
		elif key=="wallWash" and not Color.html_is_valid(values[key]): return false
		elif key!="wallWash" and (Assets.resource_path(str(values[key])).is_empty() or Assets.texture(str(values[key])) == null): return false
	_overrides[chapter] = values.duplicate(true)
	_revision += 1
	return true

static func theme(chapter: String) -> Dictionary:
	var themes: Dictionary = _data().get("themes",{})
	var result: Dictionary = themes.get(chapter,themes.get("valley",{})).duplicate(true)
	result.merge(_overrides.get(chapter,{}),true)
	return result

static func terrace_spec(profile: String, tile: Dictionary, width: float = 1.0) -> Dictionary:
	var style := theme("valley")
	var authored: Dictionary = _data().profiles[profile]
	var connector := str(tile.id).begins_with("g:")
	var paving := str(style.stone)
	if (profile=="first" and str(tile.get("kind",""))=="root") or (profile=="second" and connector): paving = str(style.moss)
	elif str(tile.id) in authored.grassTiles: paving = str(style.grass)
	var key := str(authored.keyPrefix)+paving
	if profile=="first": key += "_connector" if connector else ""
	else: key += ("_root" if connector else "")+("_wide" if width>1.0 else "")
	var result := material_spec("valley",paving,connector,key)
	if profile=="second":
		result.top_scale = Vector3(width,1,1)
		result.face_repeat = width
	return result

static func material_spec(chapter: String, paving: String, connector: bool, key: String) -> Dictionary:
	var style := theme(chapter)
	return {"paving":paving,"connector":connector,"key":key,"wall_art":str(style.wallLeft),"wall_art_right":str(style.wallRight),"wall_wash":Color(str(style.wallWash)),"wall_pixels_per_unit":Vector2(float(style.wallPixelsPerUnit[0]),float(style.wallPixelsPerUnit[1])),"stair_paint":str(style.stairPaint),"stone_grain":str(style.stairGrain)}

static func paving_for(level: Dictionary,tile: Dictionary) -> String:
	var chapter := str(level.get("chapter","valley"))
	var style := theme(chapter)
	var policy: Dictionary = _data().patchPolicy
	var stone := str(style.stone)
	if str(tile.get("kind","")) in policy.stoneKinds: return stone
	if bool(tile.get("small",false)) or str(tile.get("kind","")) in policy.softKinds: return str(style.grass)
	for mark: Dictionary in level.get("marks",[]):
		if str(mark.get("tile",""))==str(tile.get("id","")) and not str(mark.get("kind","")) in policy.softMarks: return stone
	var index := str(level.get("id","0-0")).get_slice("-",1).to_int()
	var patch := posmod(int(floor((float(tile.x)+float(policy.offset))/float(policy.cellSize)))*int(policy.xWeight)+int(floor((float(tile.z)+float(policy.offset))/float(policy.cellSize)))*int(policy.zWeight)+index,int(policy.modulus))
	if patch<int(policy.grassThreshold.get(chapter,policy.grassThreshold.default)): return str(style.grass)
	return str(style.moss) if patch<int(policy.mossThreshold) else stone

static func root_style(kind: String, mode: int = 0, memory: bool = false) -> Dictionary:
	var style: Dictionary = _data().roots["shadow" if kind=="shadow" else "root"]
	var color := Color(str(style.sunColor if mode==0 else style.moonColor)) if kind=="shadow" else Color(str(style.color))
	if kind=="shadow" and memory: color = color.lightened(float(style.memoryLighten))
	return {"texture":str(style.texture),"color":color,"emission_enabled":kind=="shadow" and memory,"emission":color*float(style.get("emissionStrength",0.0))}
