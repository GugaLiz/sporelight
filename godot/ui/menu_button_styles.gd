extends RefCounted
## Shared menu feedback. Keep real buttons and keyboard focus; change surfaces.
const INK := Color("6d5439")


static func focus_like_hover(button: Button) -> void:
	if button.has_meta("menu_focus_styled"):
		return
	button.set_meta("menu_focus_styled", true)
	var normal := button.get_theme_stylebox("normal")
	var hover := button.get_theme_stylebox("hover")
	var normal_color := button.get_theme_color("font_color")
	var hover_color := button.get_theme_color("font_hover_color")
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_focus_color", hover_color)
	button.focus_entered.connect(func() -> void:
		button.add_theme_stylebox_override("normal", hover)
		button.add_theme_color_override("font_color", hover_color))
	button.focus_exited.connect(func() -> void:
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_color_override("font_color", normal_color))


static func _surface(background: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func level_row(button: Button, completed: bool) -> void:
	button.set_meta("menu_style", "level")
	button.custom_minimum_size.y = 50
	button.add_theme_font_size_override("font_size", 14)
	var normal := Color("eef0e1c9") if completed else Color("fffaf0bf")
	button.add_theme_stylebox_override("normal", _surface(normal, Color("cfbf9a70")))
	button.add_theme_stylebox_override("hover", _surface(Color("fffdf5"), Color("b89c62")))
	button.add_theme_stylebox_override("pressed", _surface(Color("ebdfc3"), Color("b89c62")))
	button.add_theme_stylebox_override("disabled", _surface(Color("eee9dd80")))
	button.add_theme_color_override("font_color", Color("62734e") if completed else INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("8d826d"))
	button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
	focus_like_hover(button)


static func utility(button: Button, quiet: bool = true) -> void:
	button.set_meta("menu_style", "utility")
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal", _surface(Color.TRANSPARENT if quiet else Color("fff8e780")))
	button.add_theme_stylebox_override("hover", _surface(Color("fffaf0e6")))
	button.add_theme_stylebox_override("pressed", _surface(Color("e7d1ab80")))
	button.add_theme_stylebox_override("disabled", _surface(Color("eee9dd80")))
	button.add_theme_color_override("font_color", Color("756d56"))
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
	focus_like_hover(button)


static func category_tab(button: Button) -> void:
	utility(button, false)
	button.set_meta("menu_style", "category_tab")
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 8
		style.content_margin_bottom = 8
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
