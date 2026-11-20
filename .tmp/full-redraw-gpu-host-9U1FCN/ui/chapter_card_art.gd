extends Control
## Resolution-independent paper edging, botanical flourishes and live progress.
var kind := "frame"
var stages: Array[Dictionary] = []
var selected := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _leaf(at: Vector2, angle: float, tint: Color, length: float = 8.0) -> void:
	var points := PackedVector2Array()
	for i in 25:
		var t := float(i)/24.0*TAU
		points.append(at+Vector2(cos(t)*length,sin(t)*length*.42).rotated(angle))
	draw_colored_polygon(points,tint)

func _sprig(at: Vector2, mirrored: bool = false) -> void:
	var sign_x := -1.0 if mirrored else 1.0
	draw_line(at,at+Vector2(15*sign_x,-17),Color("8d9b6d"),1.2,true)
	_leaf(at+Vector2(4*sign_x,-4),.25*sign_x,Color("9aa97a"),5)
	_leaf(at+Vector2(9*sign_x,-10),1.2*sign_x,Color("b5bd8c"),5)
	_leaf(at+Vector2(15*sign_x,-17),-.9*sign_x,Color("87966b"),5)

func _draw() -> void:
	if kind == "frame":
		var border := StyleBoxFlat.new()
		border.bg_color = Color.TRANSPARENT
		border.border_color = Color("e5d2ad")
		border.set_border_width_all(2)
		border.set_corner_radius_all(24)
		draw_style_box(border,Rect2(Vector2(5,5),size-Vector2(10,10)))
	elif kind == "detail":
		draw_set_transform(Vector2.ZERO,0,size/Vector2(318,350))
		draw_line(Vector2(61,98),Vector2(257,98),Color("ddcba9"),1,true)
		_sprig(Vector2(41,104)); _sprig(Vector2(277,104),true)
		var count := stages.size()
		if count > 0:
			draw_line(Vector2(63,224),Vector2(255,224),Color("ad9d7d"),1,true)
			for i in count:
				var at := Vector2(63+192.0*i/maxi(1,count-1),224)
				var current := str(stages[i].id) == selected
				var color := Color("8ca489") if stages[i].completed else Color("ded5b9")
				var diamond := PackedVector2Array([at+Vector2(0,-5),at+Vector2(5,0),at+Vector2(0,5),at+Vector2(-5,0)])
				if current: draw_circle(at,10,Color("f3e2c6"))
				draw_colored_polygon(diamond,Color("fff5de") if current else color)
				diamond.append(diamond[0])
				draw_polyline(diamond,Color("bd8056") if current else Color("8c9a7b") if stages[i].completed else Color("b3a68a"),1.8 if current else 1,true)
	elif kind == "button":
		_sprig(Vector2(15,size.y-10))
		_sprig(Vector2(size.x-15,16),true)
		var center := Vector2(size.x-20,size.y-10)
		for i in 5:
			var angle := TAU*i/5.0-PI*.5
			_leaf(center+Vector2.from_angle(angle)*6,angle,Color("fff2b7"),6)
		draw_circle(center,2.7,Color("e7c977"))
