extends "res://presentation/native/native_garden_stage.gd"

signal world_clicked(at: Vector2)
var planning := false
var draft: Array[String] = []
var options: Array = []
var _last_pointer_at := Vector2(INF, INF)
var _last_pointer_kind := ""
var _last_pointer_time := -1000

class Dressing:
	extends RefCounted
	static func planter(stage: Node, parent: Node3D) -> void:
		preload("res://presentation/native/second_garden_dressing.gd").planter(stage, parent)
	static func scenery(stage: Node) -> void:
		preload("res://presentation/native/second_garden_dressing.gd").scenery(stage)
		preload("res://prototypes/root_weaving_courtyard.gd").build(stage)
	static func obstacle(stage: Node, wall: Array) -> void:
		preload("res://presentation/native/isolated_rock_spire.gd").build(stage, wall)

func _select_presentation() -> void:
	super._select_presentation()
	if str(world.level.id) == "1-2":
		_dressing = Dressing
		_terrain_profile = preload("res://prototypes/root_weaving_courtyard_profile.gd")

func growth_choice_layout() -> Array:
	return [] if str(world.level.id) == "1-2" else super.growth_choice_layout()

func target_position(id: String) -> Vector2:
	return project(_growth_target(id))

func draft_origin() -> Vector2:
	var root: Dictionary = world.level.roots[0]
	var grown: Array = world.state.growth[root.id]
	return target_position(str(grown.back())) if not grown.is_empty() else project(world.point_for(str(root.at)))

func draft_number(index: int) -> int:
	return world.state.growth[world.level.roots[0].id].size() + index + 1

func _unhandled_input(event: InputEvent) -> void:
	if not planning:
		super._unhandled_input(event)
		return
	if _paused: return
	var at: Vector2
	var kind := ""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		at = event.position
		kind = "mouse"
	elif event is InputEventScreenTouch and event.pressed:
		at = event.position
		kind = "touch"
	else: return
	for region: Rect2 in _regions:
		if region.has_point(at): return
	get_viewport().set_input_as_handled()
	# Browsers/platforms can emit the synthesized mouse event before or after
	# touch. One physical tap must not select a node and immediately undo it.
	var now := Time.get_ticks_msec()
	if kind != _last_pointer_kind and at.distance_to(_last_pointer_at) < 8 and now - _last_pointer_time < 450: return
	_last_pointer_at = at
	_last_pointer_kind = kind
	_last_pointer_time = now
	world_clicked.emit(at)

func _polygon(id: String) -> PackedVector2Array:
	var at := tile_position(_growth_target(id)) + Vector3(0, 0.035, 0)
	var result := PackedVector2Array()
	for corner: Vector2 in CORNERS:
		result.append(world_to_screen(at + Vector3(corner.x, 0, corner.y) * 0.84))
	return result

func draw_context(canvas: CanvasItem) -> void:
	if not planning:
		super.draw_context(canvas)
		return
	if world == null or _paused: return
	var font: Font = label_font
	if font == null: return
	for socket: Array in world.level.roots[0].sockets:
		var id := "g:root:%d:%d" % [socket[0], socket[1]]
		if id in world.state.growth.root: continue
		var polygon := _polygon(id)
		canvas.draw_colored_polygon(polygon, Color(1, 0.96, 0.78, 0.09))
		polygon.append(polygon[0])
		canvas.draw_polyline(polygon, Color(1, 0.96, 0.78, 0.35), 1.0, true)
	var previous := draft_origin()
	for i in range(draft.size()):
		var at := target_position(draft[i])
		canvas.draw_colored_polygon(_polygon(draft[i]), Color(0.68, 0.80, 0.47, 0.65))
		var direction := previous.direction_to(at)
		canvas.draw_line(previous + direction * 13, at - direction * 13, Color("f8e2a2"), 3, true)
		canvas.draw_circle(at, 12, Color("537151"))
		var number := str(draft_number(i))
		canvas.draw_string(font, at + Vector2(-font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2, 5), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff6dd"))
		previous = at
	for choice: Dictionary in options:
		var at := target_position(str(choice.target))
		canvas.draw_circle(at, 17, Color("fff1d9"))
		canvas.draw_arc(at, 17, 0, TAU, 32, Color("859168"), 1.5, true)
		canvas.draw_line(at - Vector2(5, 0), at + Vector2(5, 0), Color("506e49"), 2, true)
		canvas.draw_line(at - Vector2(0, 5), at + Vector2(0, 5), Color("506e49"), 2, true)
