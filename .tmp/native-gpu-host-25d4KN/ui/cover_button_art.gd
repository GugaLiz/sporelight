extends Control
## Five horizontal slices: caps, leaves and centre diamonds keep their aspect.
## Only the two unornamented paper spans grow with the real button width.
const Assets := preload("res://elements/element_assets.gd")
var paper: Texture2D
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper = Assets.texture_for_source("res://assets/images/material-ready/menu-paper.png")
	var button := get_parent() as Button
	for event: String in ["mouse_entered","mouse_exited","button_down","button_up","focus_entered","focus_exited"]:
		button.connect(event,queue_redraw)
	resized.connect(queue_redraw)
func _draw() -> void:
	if paper == null: return
	var button := get_parent() as Button
	var tint := Color(.93,.91,.85,.55) if button.disabled else Color(.97,.95,.90) if button.is_pressed() else Color(1.05,1.05,1.02) if button.is_hovered() or button.has_focus() else Color.WHITE
	var source_size := paper.get_size()
	var unit := size.y/source_size.y
	var cap := source_size.x*.31*unit
	var ornament := source_size.x*.18*unit
	var span := maxf(0,(size.x-cap*2-ornament)*.5)
	var widths := [cap,span,ornament,span,cap]
	var cuts := [0.0,.31,.41,.59,.69,1.0]
	var x := 0.0
	for index in 5:
		draw_texture_rect_region(paper,Rect2(x,0,widths[index],size.y),Rect2(source_size.x*cuts[index],0,source_size.x*(cuts[index+1]-cuts[index]),source_size.y),tint)
		x += widths[index]
