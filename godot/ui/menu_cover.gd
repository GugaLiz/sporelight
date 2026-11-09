extends Control
## Authored cover composition. Buttons remain real Godot controls owned by HUD;
## scenery and actors share a transform so resize cannot detach their feet.
const Vignette := preload("res://ui/menu_vignette.gd")
const MenuButtons := preload("res://ui/menu_button_styles.gd")
const INK := Color("6d5439")
const MUTED := Color("6a7655")
var scenery := Vignette.new()
var logo := TextureRect.new()
var tagline := Label.new()
var invitation := ScrollContainer.new()
var content := VBoxContainer.new()
var footer := Label.new()
var _shade := TextureRect.new()
var _built := false


func _ready() -> void:
	setup()


func setup() -> void:
	if _built:
		return
	name = "OriginalMenuCover"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	add_child(scenery)
	_shade.name = "CoverReadabilityShade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	logo.name = "HomeLogo"
	logo.texture = load("res://assets/images/material-ready/menu-logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	tagline.name = "CoverTagline"
	tagline.text = "把一粒微光，种成回家的路。"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_color_override("font_color", MUTED)
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tagline)
	invitation.name = "CoverInvitationScroll"
	invitation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	invitation.follow_focus = true
	add_child(invitation)
	content.name = "CoverInvitations"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	invitation.add_child(content)
	footer.name = "CoverFooter"
	footer.text = "探索 · 播种 · 共生                     没有失败，只有慢慢生长。"
	footer.add_theme_color_override("font_color", MUTED)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.clip_text = true
	add_child(footer)
	_built = true
	resized.connect(relayout)
	relayout()


func configure(settings: Dictionary) -> void:
	scenery.configure(settings)


func _gradient(portrait: bool) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.38, 0.58, 0.75, 1])
	gradient.colors = PackedColorArray([Color("fff6df35"), Color("fff6df00"), Color("fff6e4c9"), Color("f8f3e4ef"), Color("f8f3e4f5")]) if portrait else PackedColorArray([Color("f8efdb45"), Color("eef0dc15"), Color("f8f3e4bd"), Color("f8f3e4ef"), Color("f8f3e4f5")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8 if portrait else 256
	texture.height = 256 if portrait else 8
	texture.fill_to = Vector2.DOWN if portrait else Vector2.RIGHT
	return texture


func relayout() -> void:
	if not _built:
		return
	var viewport := size
	var portrait := viewport.y > viewport.x
	var short := viewport.y <= 420
	_shade.texture = _gradient(portrait)
	if portrait:
		var scene_scale := minf(0.7, viewport.x / 550.0)
		scenery.scale = Vector2.ONE * scene_scale
		scenery.position = Vector2(viewport.x * 0.5 - 407 * scene_scale, -82 * scene_scale / 0.7 + maxf(0, 0.7 - scene_scale) * 180)
		logo.position = Vector2((viewport.x - minf(280, viewport.x - 36)) * 0.5, 8)
		logo.size = Vector2(minf(280, viewport.x - 36), 138)
		tagline.position = Vector2(12, 143)
		tagline.size = Vector2(viewport.x - 24, 24)
		tagline.add_theme_font_size_override("font_size", 11)
		var top := maxf(355, 405 * scene_scale / 0.7)
		invitation.position = Vector2(24, top)
		invitation.size = Vector2(viewport.x - 48, maxf(80, viewport.y - top - 14))
		footer.hide()
	else:
		var scene_scale := maxf(viewport.x / 1280, viewport.y / 720)
		scenery.scale = Vector2.ONE * scene_scale
		scenery.position = Vector2((viewport.x - 1280 * scene_scale) * 0.5, viewport.y - 720 * scene_scale)
		var ui_scale := clampf(minf(viewport.x / 1280, viewport.y / 720), 0.5, 1.3)
		logo.position = Vector2(47, 35) * ui_scale
		logo.size = Vector2(450, 220) * ui_scale
		tagline.position = Vector2(47, 253) * ui_scale
		tagline.size = Vector2(450 * ui_scale, 28)
		tagline.add_theme_font_size_override("font_size", 11 if short else 14)
		var margin := 12.0 if short else 32.0
		var width := minf(460, viewport.x * (0.43 if viewport.x < 800 else 0.285))
		var right := minf(94 * ui_scale, viewport.x * 0.055)
		invitation.position = Vector2(viewport.x - right - width, margin if short else 76 * ui_scale)
		invitation.size = Vector2(width, viewport.y - invitation.position.y - (margin if short else 54))
		footer.position = Vector2(72 * ui_scale, viewport.y - 35)
		footer.size = Vector2(viewport.x - 144 * ui_scale, 25)
		footer.add_theme_font_size_override("font_size", 12)
		footer.visible = not short
	content.add_theme_constant_override("separation", 7 if portrait or short else 10)
	for button in _buttons(content):
		if button.get_meta("cover_primary", false):
			button.custom_minimum_size.y = 58 if portrait or short else 83
			button.add_theme_font_size_override("font_size", 18 if portrait or short else 23)
		elif button.get_meta("cover_secondary", false):
			button.add_theme_font_size_override("font_size", 12 if invitation.size.x < 290 else 14)
	for node in content.get_children():
		if node is Label and node.get_meta("cover_heading", false):
			node.add_theme_font_size_override("font_size", 22 if portrait or short else 29)


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


func style_primary(button: Button) -> void:
	button.set_meta("cover_primary", true)
	var paper := StyleBoxTexture.new()
	paper.texture = load("res://assets/images/material-ready/menu-paper.png")
	paper.content_margin_left = 20
	paper.content_margin_right = 20
	paper.content_margin_top = 8
	paper.content_margin_bottom = 8
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := paper.duplicate() as StyleBoxTexture
		style.modulate_color = Color(1.05, 1.05, 1.02) if state == "hover" else Color(0.93, 0.91, 0.85, 0.55) if state == "disabled" else Color.WHITE
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("9a8e78"))
	_use_hover_for_focus(button)


func style_secondary(button: Button, quiet: bool = false) -> void:
	button.set_meta("cover_secondary", true)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fff8e766") if state == "normal" and not quiet else Color.TRANSPARENT
		if state == "hover":
			style.bg_color = Color("fffaf0b3")
		elif state == "pressed":
			style.bg_color = Color("e7d1ab80")
		style.set_corner_radius_all(10)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", MUTED if quiet else INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	_use_hover_for_focus(button)


func _use_hover_for_focus(button: Button) -> void:
	MenuButtons.focus_like_hover(button)
