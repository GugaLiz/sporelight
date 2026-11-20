extends RefCounted
## Cached vector equivalents of pondWeather.ts / landscape.ts small drawings.
## SVGs are rasterized only once per variant, never in the animation loop.
static var _textures: Dictionary = {}

const Assets = preload("res://elements/element_assets.gd")
const Props = preload("res://elements/prop_definitions.gd")
static var _frog_revision := ""

static func frog_spec() -> Dictionary:
	return Props.natural_spec("pond", "frog")

static func frog(blink: bool) -> Texture2D:
	var revision := str(Assets.revision()) + ":" + str(Props.revision())
	if _frog_revision != revision:
		_textures.erase("frog_closed"); _textures.erase("frog_open")
		_frog_revision = revision
	var key := "frog_closed" if blink else "frog_open"
	if _textures.has(key): return _textures[key]
	var spec := frog_spec()
	var crop: Array = spec.atlasAlpha8
	var atlas := AtlasTexture.new()
	atlas.atlas = Assets.texture(str(spec.states.closed if blink else spec.states.open))
	atlas.region = Rect2(crop[0],crop[1],crop[2],crop[3])
	atlas.filter_clip = true
	_textures[key] = atlas
	return atlas

static func reeds() -> Texture2D:
	if _textures.has("reeds"): return _textures.reeds
	var paths := ""
	for index in range(4):
		var x := (float(index) - 1.5) * 4.0
		var top := -21.0 - float(index % 2) * 12.0
		paths += '<path d="M0 0 Q%s %s %s %s" stroke="#668d70" stroke-width="1.3" fill="none"/><path d="M%s %s L%s %s" stroke="#9f8b5e" stroke-width="3" stroke-linecap="round"/>' % [x, top + 11, x, top, x, top, x, top - 5]
	return _cache("reeds", '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="42" viewBox="-12 -40 24 42">' + paths + '</svg>')

static func flower() -> Texture2D:
	if _textures.has("flower"): return _textures.flower
	return _cache("flower", '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="12" viewBox="-5 -9 10 12"><ellipse cx="0" cy="-4" rx="3" ry="2" fill="#f4d9c0"/><ellipse cx="0" cy="-5" rx="1.2" ry="1.3" fill="#ffe7ae"/></svg>')

static func leaves() -> Texture2D:
	if _textures.has("leaves"): return _textures.leaves
	return _cache("leaves", '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="22" viewBox="-12 -18 24 22"><path d="M0 0 Q-10 -3 -8 -12 Q1 -12 0 0 M0 0 Q1 -11 10 -13 Q12 -3 0 0" fill="#96b782" stroke="#6b966c" stroke-width=".7"/><path d="M0 0 L-6 -10 M0 0 L8 -11" fill="none" stroke="#c4d6a5" stroke-width=".5"/></svg>')

static func _cache(key: String, svg: String) -> Texture2D:
	var image := Image.new()
	var error := image.load_svg_from_string(svg, 2.0)
	if error != OK:
		push_error("Original pond SVG failed: " + key)
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture
