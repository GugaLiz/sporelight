extends RefCounted
## Transparent paper ornaments and shared tool art; input stays on real Buttons.
const Assets := preload("res://elements/element_assets.gd")
const PaperStar := preload("res://ui/art/paper-star.svg")
const PaperLeaves := preload("res://ui/art/paper-leaves.svg")
var _primary_styles: Dictionary = {}
var _style_revision := -1

func decorate_tool(button: Button, action: String) -> void:
	button.set_meta("tool_icon", true)
	style_tool(button, action == "primary")
	button.draw.connect(_draw_tool.bind(button, action))

func style_tool(button: Button, primary: bool, available := true) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fff5e4b8") if primary else Color.TRANSPARENT
		if state == "hover": style.bg_color = Color("fffaf0de")
		elif state == "pressed": style.bg_color = Color("edd9b87d")
		elif state == "disabled": style.bg_color = Color("fff8ed55") if primary else Color.TRANSPARENT
		style.border_color = Color("dec29699") if available else Color("dfcfb85c")
		style.set_border_width_all(1 if primary else 0)
		style.set_corner_radius_all(13)
		style.content_margin_left = 5
		style.content_margin_right = 5
		style.content_margin_top = 28
		style.content_margin_bottom = 2
		button.add_theme_stylebox_override(state, style)
	fit_tool(button)

func fit_tool(button: Button, height := -1.0) -> void:
	var tall := (button.size.y if height < 0 else height) > 50
	var top := 40.0 if tall else 28.0
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := button.get_theme_stylebox(state)
		style.content_margin_top = top
		style.content_margin_bottom = 4 if tall else 2

func _draw_tool(button: Button, action: String) -> void:
	var large := button.size.y > 50
	var centre := Vector2(button.size.x * .5, 24 if large else 13)
	var ink := Color("b89a6d") if button.disabled else Color("92734c")
	if action != "primary":
		var badge := StyleBoxFlat.new()
		badge.bg_color = Color("f6e6cc88") if not button.disabled else Color("eadfce44")
		badge.border_color = Color("d9bc8c77") if not button.disabled else Color("dccdbb33")
		badge.set_border_width_all(1)
		badge.set_corner_radius_all(9)
		var span := 36.0 if large else 24.0
		button.draw_style_box(badge,Rect2(centre-Vector2.ONE*span*.5,Vector2.ONE*span))
	if action in ["primary", "hint", "mode", "jump"]:
		var alias := {"primary":"flower", "hint":"spore", "mode":"red-mushroom", "jump":"idle-quarter"}
		var resource := str(alias[action])
		var image: Texture2D = Assets.texture(resource)
		if image != null:
			var span := 30.0 if large else 24.0
			button.draw_texture_rect(image, Rect2(centre - Vector2.ONE*span*.5, Vector2.ONE*span), false, Color(1,1,1,.4 if button.disabled else 1))
			return
	if action == "undo":
		# One step back: a left-facing hooked arrow, without a circular loop.
		var curve := Curve2D.new()
		curve.add_point(Vector2(-8,-4),Vector2.ZERO,Vector2(8,0))
		curve.add_point(Vector2(7,3),Vector2(0,-7),Vector2(0,5))
		curve.add_point(Vector2(0,8),Vector2(5,0))
		var points := curve.tessellate(4,2)
		for index in points.size(): points[index] += centre
		button.draw_polyline(points,ink,1.7,true)
		button.draw_polyline(PackedVector2Array([centre+Vector2(-3,-9),centre+Vector2(-8,-4),centre+Vector2(-3,1)]),ink,1.7,true)
	elif action == "restart":
		# Start the whole level again: a clockwise circular arrow.
		button.draw_arc(centre,8,-PI*.3,PI*1.5,36,ink,1.7,true)
		button.draw_polyline(PackedVector2Array([centre+Vector2(-4,-12),centre+Vector2(0,-8),centre+Vector2(-4,-4)]),ink,1.7,true)
	elif action == "menu":
		button.draw_line(centre+Vector2(8,0),centre-Vector2(8,0),ink,1.7,true)
		button.draw_polyline(PackedVector2Array([centre+Vector2(-2,-6),centre+Vector2(-8,0),centre+Vector2(-2,6)]),ink,1.7,true)
	else:
		for dx in [-5,5]:
			button.draw_circle(centre+Vector2(dx,-3),3,ink,false,1.5,true)
			button.draw_arc(centre+Vector2(dx,8),6,PI,TAU,12,ink,1.5,true)

static func spore_texture() -> Texture2D:
	return Assets.texture_for_source("res://assets/images/material-ready/icon-spore.png")


func attach(panel: PanelContainer, role: String) -> void:
	panel.set_meta("game_paper_role", role)
	panel.draw.connect(_draw_edge.bind(panel))


func _draw_edge(panel: PanelContainer) -> void:
	if str(panel.get_meta("game_paper_role", "")) == "message":
		draw_flourish(panel, Vector2(panel.size.x*.5,panel.size.y-3),28,.4)

func draw_flourish(canvas: Control, centre: Vector2, width := 136.0, opacity := .9) -> void:
	var size := Vector2(width,width*28/180)
	canvas.draw_texture_rect(PaperStar,Rect2(centre-size*.5,size),false,Color(1,1,1,opacity))

func draw_corner_leaves(canvas: Control, root_at: Vector2, mirror := false) -> void:
	var size := Vector2(36,36)
	canvas.draw_set_transform(root_at,0,Vector2(-1 if mirror else 1,1))
	canvas.draw_texture_rect(PaperLeaves,Rect2(Vector2(-33.75,-33.75),size),false)
	canvas.draw_set_transform(Vector2.ZERO)


func decorate_completion(button: Button, primary: bool) -> void:
	button.custom_minimum_size = Vector2(44,46 if primary else 44)
	button.add_theme_font_size_override("font_size",14 if primary else 13)
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e8eddb") if primary else Color("fff9ef")
		if state == "hover": style.bg_color = Color("f0f4e6") if primary else Color("fffdf6")
		elif state == "pressed": style.bg_color = Color("dce4ce") if primary else Color("efe6d5")
		style.border_color = Color("b5a274") if primary else Color("e0caa5")
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("ad945d")
		style.set_border_width_all(2 if state == "focus" else 1)
		style.set_corner_radius_all(12)
		style.content_margin_left = 38 if primary else 28
		style.content_margin_right = style.content_margin_left
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		if primary and state == "normal":
			style.shadow_color = Color("9e8f6b16")
			style.shadow_size = 2
			style.shadow_offset = Vector2(0,2)
		button.add_theme_stylebox_override(state,style)
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(state,Color("5b684b") if primary else Color("7d694d"))
	button.draw.connect(_draw_completion_button.bind(button,primary))


func _draw_completion_button(button: Button, primary: bool) -> void:
	var span := 24.0 if primary else 18.0
	var inset := 11.0 if primary else 7.0
	var at := Vector2(inset,(button.size.y-span)*.5)
	button.draw_texture_rect(PaperLeaves,Rect2(at,Vector2.ONE*span),false,Color(1,1,1,.8 if primary else .6))
	button.draw_set_transform(Vector2(button.size.x-inset,at.y),0,Vector2(-1,1))
	button.draw_texture_rect(PaperLeaves,Rect2(Vector2.ZERO,Vector2.ONE*span),false,Color(1,1,1,.8 if primary else .6))
	button.draw_set_transform(Vector2.ZERO)


func apply_primary(button: Button) -> void:
	if _style_revision != Assets.revision():
		_primary_styles.clear()
		_style_revision = Assets.revision()
	if _primary_styles.is_empty():
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxTexture.new()
			style.texture = Assets.texture_for_source("res://assets/images/material-ready/button-green.png")
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
