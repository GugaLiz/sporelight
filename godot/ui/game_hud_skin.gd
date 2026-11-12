extends RefCounted
## Reuse the original art without changing HUD geometry or input ownership.
const ORNAMENT := preload("res://assets/images/material-ready/panel-paper.png")
const SPORE := preload("res://assets/images/material-ready/icon-spore.png")
const PRIMARY := preload("res://assets/images/material-ready/button-green.png")
var _primary_styles: Dictionary = {}


func attach(panel: PanelContainer, role: String) -> void:
	panel.set_meta("game_paper_role", role)
	panel.draw.connect(_draw_edge.bind(panel))


func _draw_edge(panel: PanelContainer) -> void:
	# Existing paper texture and inner border remain in GardenHUD. The leaves
	# stay wholly in its existing bottom padding, below the text content rect.
	var inset := panel.get_theme_stylebox("panel").content_margin_bottom
	var height := minf(7, maxf(2, inset - 1))
	var width := height * 3
	var y := panel.size.y - height - 1
	var tint := Color(1, 1, 1, 0.42 if height > 3 else 0.24)
	panel.draw_texture_rect_region(ORNAMENT, Rect2(8, y, width, height), Rect2(8.8889, 262.2222, 84.4444, 88.8889), tint)
	panel.draw_texture_rect_region(ORNAMENT, Rect2(panel.size.x - width - 8, y, width, height), Rect2(500, 262.2222, 84.4444, 88.8889), tint)
	if str(panel.get_meta("game_paper_role", "")) == "message":
		panel.draw_texture_rect_region(ORNAMENT, Rect2(panel.size.x * 0.5 - 14, panel.size.y - height, 28, height - 1), Rect2(180, 16.6667, 226.6667, 40), Color(1, 1, 1, 0.4))


func apply_primary(button: Button) -> void:
	if _primary_styles.is_empty():
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxTexture.new()
			style.texture = PRIMARY
			style.content_margin_left = 18
			style.content_margin_right = 18
			style.content_margin_top = 7
			style.content_margin_bottom = 7
			style.modulate_color = Color(1.08, 1.08, 1.03) if state == "hover" else Color(0.88, 0.92, 0.82) if state == "pressed" else Color(0.9, 0.9, 0.85, 0.45) if state == "disabled" else Color.WHITE
			_primary_styles[state] = style
	for state: String in _primary_styles:
		button.add_theme_stylebox_override(state, _primary_styles[state])
	for name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(name, Color("fff9e7"))
	button.add_theme_color_override("font_disabled_color", Color("8c8774"))
	button.set_meta("game_action_skin", "primary")
