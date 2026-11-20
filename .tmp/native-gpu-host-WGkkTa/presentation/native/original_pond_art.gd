extends RefCounted
## Cached vector equivalents of pondWeather.ts / landscape.ts small drawings.
## SVGs are rasterized only once per variant, never in the animation loop.
static var _textures: Dictionary = {}

static func frog(blink: bool) -> Texture2D:
	var key := "frog_closed" if blink else "frog_open"
	if _textures.has(key): return _textures[key]
	var eyes := '<path d="M-7 -16 Q-5 -14 -3 -16 M1 -16 Q3 -14 5 -16" fill="none" stroke="#465744" stroke-width="1.1"/>' if blink else '<ellipse cx="-5" cy="-16" rx="1.7" ry="2" fill="#394d3c"/><ellipse cx="3" cy="-16" rx="1.7" ry="2" fill="#394d3c"/><circle cx="-5.5" cy="-16.6" r=".6" fill="#ffffe6"/><circle cx="2.5" cy="-16.6" r=".6" fill="#ffffe6"/>'
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48" viewBox="-32 -32 64 48"><defs><radialGradient id="body" cx="30%" cy="20%"><stop stop-color="#d9e6a0"/><stop offset=".55" stop-color="#9abb70"/><stop offset="1" stop-color="#5f8758"/></radialGradient><radialGradient id="head" cx="35%" cy="20%"><stop stop-color="#e4ecb5"/><stop offset=".6" stop-color="#a7c77a"/><stop offset="1" stop-color="#73965b"/></radialGradient></defs><ellipse cx="1" cy="-9" rx="10" ry="7" fill="url(#body)"/><ellipse cx="-6" cy="-5" rx="6" ry="3" fill="#83a761"/><ellipse cx="7" cy="-5" rx="5" ry="3" fill="#7e9e59"/><ellipse cx="-4" cy="-15" rx="6" ry="5" fill="url(#head)"/><ellipse cx="3" cy="-15" rx="5" ry="5" fill="#adc97d"/>' + eyes + '<path d="M-3 -10 Q0 -8 4 -10" fill="none" stroke="#6e8856" stroke-width=".7"/><path d="M16 0 Q15 -7 23 -4 Q23 1 16 0" fill="#94b676" stroke="#6a9568" stroke-width=".6"/></svg>'
	return _cache(key, svg)

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
