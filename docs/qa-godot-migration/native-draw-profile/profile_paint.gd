extends "res://presentation/world/garden_paint.gd"

func _init(canvas: CanvasItem, textures: Dictionary = {}) -> void:
	super(canvas, textures)

func poly(points: Variant, fill: Variant, stroke: Variant = null, width := 0.7) -> void:
	var __started: int = Time.get_ticks_usec()
	super.poly(points, fill, stroke, width)
	_profile_record("paint.poly", Time.get_ticks_usec() - __started)

func line(points: Variant, color: Variant, width := 1.0, closed := false) -> void:
	var __started: int = Time.get_ticks_usec()
	super.line(points, color, width, closed)
	_profile_record("paint.line", Time.get_ticks_usec() - __started)

func oval(x: float, y: float, rx: float, ry: float, fill: Variant, angle := 0.0, stroke: Variant = null, width := 0.7) -> void:
	var __started: int = Time.get_ticks_usec()
	super.oval(x, y, rx, ry, fill, angle, stroke, width)
	_profile_record("paint.oval", Time.get_ticks_usec() - __started)

func textured_poly(points: Variant, id: String, uvs: PackedVector2Array, opacity := 1.0) -> void:
	var __started: int = Time.get_ticks_usec()
	super.textured_poly(points, id, uvs, opacity)
	_profile_record("paint.textured_poly", Time.get_ticks_usec() - __started)

func textured_oval(x: float, y: float, rx: float, ry: float, id: String, opacity := 1.0, angle := 0.0, texture_bounds := Rect2()) -> void:
	var __started: int = Time.get_ticks_usec()
	super.textured_oval(x, y, rx, ry, id, opacity, angle, texture_bounds)
	_profile_record("paint.textured_oval", Time.get_ticks_usec() - __started)

func halo(at: Vector2, rx: float, ry: float, color: String, blur: float, line_width := 1.7, opacity := 1.0) -> void:
	var __started: int = Time.get_ticks_usec()
	super.halo(at, rx, ry, color, blur, line_width, opacity)
	_profile_record("paint.halo", Time.get_ticks_usec() - __started)

func soft(x: float, y: float, radius: float, light: String, base: String, shade: String) -> Dictionary:
	var __started: int = Time.get_ticks_usec()
	var __result: Dictionary = super.soft(x, y, radius, light, base, shade)
	_profile_record("paint.soft", Time.get_ticks_usec() - __started)
	return __result

func linear(bounds: Rect2, colors: Array, offsets: Array = []) -> Dictionary:
	var __started: int = Time.get_ticks_usec()
	var __result: Dictionary = super.linear(bounds, colors, offsets)
	_profile_record("paint.linear", Time.get_ticks_usec() - __started)
	return __result

func glow(at: Vector2, radius: float, color: String, opacity := 1.0, flatten := 1.0) -> void:
	var __started: int = Time.get_ticks_usec()
	super.glow(at, radius, color, opacity, flatten)
	_profile_record("paint.glow", Time.get_ticks_usec() - __started)

func image(id: String, x: float, y: float, width: float, anchor := 0.9, opacity := 1.0) -> void:
	var __started: int = Time.get_ticks_usec()
	super.image(id, x, y, width, anchor, opacity)
	_profile_record("paint.image", Time.get_ticks_usec() - __started)

func arc(x: float, y: float, rx: float, ry: float, start: float, end: float, color: Variant, width := 1.0, angle := 0.0) -> void:
	var __started: int = Time.get_ticks_usec()
	super.arc(x, y, rx, ry, start, end, color, width, angle)
	_profile_record("paint.arc", Time.get_ticks_usec() - __started)

var profile_data: Dictionary = {}
func _profile_record(label: String, elapsed: int) -> void:
	var values: Dictionary = profile_data.get(label, {"calls": 0, "usec": 0})
	values.calls += 1
	values.usec += elapsed
	profile_data[label] = values
