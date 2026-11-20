extends RefCounted
## Native paper surfaces and vector icons render at the actual screen size.
const INK := Color("65563f")
const GREEN := Color("78866a")
static var _icons: Dictionary = {}

static func surface(fill: Color, edge: Color, radius: int = 14) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func button(caption: String, kind: String, primary: bool = false) -> Button:
	var result := Button.new()
	result.text = caption
	result.icon = icon(kind,primary)
	result.add_theme_constant_override("h_separation",10)
	result.add_theme_constant_override("icon_max_width",22)
	result.expand_icon = true
	result.custom_minimum_size = Vector2(44,48)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_size_override("font_size",14)
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		var fill := Color("7c8c6a") if primary else Color("fff4df")
		if state == "hover": fill = Color("8e9e7c") if primary else Color("fffaf0")
		if state == "pressed": fill = Color("6b7d5b") if primary else Color("eddec2")
		var box := surface(fill,Color("bba47a"))
		box.shadow_color = Color("3e342b20")
		box.shadow_size = 3
		box.shadow_offset = Vector2(0,2)
		result.add_theme_stylebox_override(state,box)
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:
		result.add_theme_color_override(state,Color("fff8e9") if primary else INK)
	var focus := surface(Color.TRANSPARENT,Color("b98a40"))
	focus.set_border_width_all(2)
	result.add_theme_stylebox_override("focus",focus)
	return result

static func icon(kind: String, light: bool = false) -> Texture2D:
	var key := kind+str(light)
	if _icons.has(key): return _icons[key]
	var paths := {
		"lock":"<path d='M16 21v-7a8 8 0 0 1 16 0v7'/><rect x='11' y='20' width='26' height='23' rx='6' fill='COLOR' stroke='none'/><circle cx='24' cy='29' r='2.5' stroke='#a19475'/><path d='M24 31v4' stroke='#a19475'/>",
		"home":"<path d='M24 7 10 16l14 9M10 16h30'/>",
		"world_overview":"<path d='m5 11 12-5 13 5 13-5v28l-13 5-13-5-12 5zM17 6v28m13-23v28'/><circle cx='30' cy='21' r='3'/>",
		"map_tools":"<path d='M9 8h27a4 4 0 0 1 4 4v28H12a5 5 0 0 1-5-5V12a4 4 0 0 1 2-4zm5 0v32m7-22h11m-11 7h8'/><path d='m31 8 1-4m6 6 4-3'/>",
		"settings":"<path d='M7 12h34M7 24h34M7 36h34'/><circle cx='17' cy='12' r='4' fill='FILL'/><circle cx='32' cy='24' r='4' fill='FILL'/><circle cx='20' cy='36' r='4' fill='FILL'/>",
		"gallery":"<path d='M10 35c-9-19 9-29 29-28 1 20-8 35-27 29M9 40 31 18m-10 9-1-10m1 10 10 1'/>",
		"journal":"<path d='M24 12C18 7 10 7 5 9v29c6-3 13-3 19 1 6-4 13-4 19-1V9c-7-2-13-2-19 3zm0 0v27M11 17h7m-7 7h7m13-7h6m-6 7h6'/>",
		"cloud":"<path d='M11 34a8 8 0 0 1-1-16 12 12 0 0 1 23-3 10 10 0 1 1 4 19zM24 4v5m15-1-3 4'/>",
		"resume":"<path d='m19 8 18 16-18 16zM8 11v26'/>",
		"save":"<path d='M8 31v10h32V31M17 28V6m-7 7 7-7 7 7m7 4v18m-6-6 6 6 6-6'/>",
		"close_map_tools":"<path d='m12 12 24 24m0-24L12 36'/>",
		"cloud_story":"<path d='M10 9h28v30H10zM17 18h14m-14 7h14m-14 7h8'/>",
		"sprig":"<path d='M8 42c15-5 25-17 30-36'/><path d='M15 36C4 33 6 26 6 26c10 0 12 4 9 10Zm8-8c-11-4-8-12-8-12 10 2 12 7 8 12Zm7-9C24 8 30 4 30 4c6 5 5 11 0 15ZM20 32c10-1 16-9 16-9-11-2-15 2-16 9Z' fill='COLOR' stroke='none'/>"
	}
	var color := "#fff5df" if light else "#78866a"
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96' viewBox='0 0 48 48'><g fill='none' stroke='%s' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % [color,str(paths.get(kind,paths.map_tools)).replace("FILL","#fff4df").replace("COLOR",color)]
	var image := Image.new()
	image.load_svg_from_string(svg)
	var texture := ImageTexture.create_from_image(image)
	_icons[key] = texture
	return texture
