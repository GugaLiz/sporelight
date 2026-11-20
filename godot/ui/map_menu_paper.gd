extends Control
## Small paper grain and botanical details; no controls or baked lettering.
const Assets := preload("res://elements/element_assets.gd")
const MenuSkin := preload("res://ui/map_menu_skin.gd")
var paper: Texture2D
var flowers: Texture2D
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper = Assets.texture_for_source("res://assets/images/gallery-journal/paper-texture.jpg")
	flowers = Assets.texture_for_source("res://assets/images/full-asset-redraw-20261116/pink-flowers.png")
	resized.connect(queue_redraw)
	queue_redraw()
func _draw() -> void:
	if paper == null: return
	draw_texture_rect(paper,Rect2(14,14,size.x-28,size.y-28),false,Color(1,1,1,.12))
	var border := MenuSkin.surface(Color.TRANSPARENT,Color("d4bb8b80"),15)
	draw_style_box(border,Rect2(8,8,size.x-16,size.y-16))
	draw_line(Vector2(24,78),Vector2(size.x-24,78),Color("d4bb8b99"),1,true)
	var center := Vector2(size.x*.5,78)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-3),center+Vector2(3,0),center+Vector2(0,3),center-Vector2(3,0)]),Color("b6a079"))
	if size.x >= 330:
		var box := Vector2(58,62)
		var fit := flowers.get_size()*minf(box.x/flowers.get_width(),box.y/flowers.get_height())
		draw_texture_rect(flowers,Rect2(Vector2(size.x-144,10)+(box-fit)*.5,fit),false,Color(1,1,1,.85))
