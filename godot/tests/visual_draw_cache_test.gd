extends SceneTree

const View = preload("res://presentation/world/garden_view.gd")
const World = preload("res://core/garden_world.gd")
const Paint = preload("res://presentation/world/garden_paint.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var _logger := ErrorLogger.new()
var failures: Array[String] = []
var checks := 0
var _done := false

class CountingWorld:
	extends RefCounted
	var level: Dictionary
	var state: Dictionary
	var board: Array
	var requests := 0
	func tiles() -> Array:
		requests += 1
		return board
	func visible(_tile: Dictionary) -> bool:
		return true
	func commands() -> Array:
		return []
	func ready() -> bool:
		return false

func _initialize() -> void:
	OS.add_logger(_logger)
	create_timer(30).timeout.connect(func() -> void:
		if not _done:
			push_error("Draw-cache verification did not complete")
			quit(1))
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	var original := World.new("1-1")
	var counter := CountingWorld.new()
	counter.level = original.level
	counter.state = original.snapshot()
	counter.board = original.tiles()
	view.set_world(counter)
	view.set_visual_time(1200)
	await process_frame
	await process_frame
	var before := counter.requests
	view._draw_tiles = counter.board
	view._draw_tile_by_id = {}
	for tile in counter.board:
		view._draw_tile_by_id[tile.id] = tile
	view._in_draw = true
	for index in range(100):
		_check(view._near("f:0:0"), "nearby rule result remains true from the current draw snapshot")
		view._tiles()
	_check(counter.requests == before, "draw-local nearby reads never rebuild the rule world's tile array")
	view._in_draw = false
	view._draw_tiles = []
	view._draw_tile_by_id = {}
	view._near("f:0:0")
	_check(counter.requests == before + 1, "outside drawing, a nearby read takes one fresh board, never a stale cache")
	for segments in Paint._oval_fans:
		var fan: Dictionary = Paint._oval_fans[segments]
		_check(fan.unit.size() == segments * 2 and fan.indices.size() == (segments - 2) * 3, "indexed ellipse fan retains its exact vertex and triangle counts")
		for index in range(segments):
			var theta: float = float(index) / int(segments) * TAU
			_check(fan.unit[index * 2] == cos(theta) and fan.unit[index * 2 + 1] == sin(theta), "cached unit circle retains original double-precision coefficients")
		for index in range(segments - 2):
			_check(fan.indices[index * 3] == 0 and fan.indices[index * 3 + 1] == index + 1 and fan.indices[index * 3 + 2] == index + 2, "indexed ellipse uses the same explicit fan instead of ear clipping")
	var actor := Rect2(85, 198, 72, 100)
	viewport.size = Vector2i(320, 568)
	view.set_ui_regions([
		{"rect": [12, 12, 196, 70]}, {"rect": [170, 100, 138, 210]},
		{"rect": [12, 76, 130, 130]}, {"rect": [12, 404, 296, 144]},
		{"rect": [12, 342, 296, 46]}
	])
	_check(not view._choose_dialogue_rect(Vector2(80, 280), Vector2(250, 62), actor).has_area(), "tiny full UI hides decorative greeting when no safe candidate exists")
	viewport.size = Vector2i(390, 844)
	actor = Rect2(113, 330, 72, 100)
	view.set_ui_regions([
		{"rect": [12, 12, 264, 150]}, {"rect": [218, 190, 160, 144]},
		{"rect": [12, 176, 130, 130]}, {"rect": [12, 685, 366, 139]},
		{"rect": [12, 620, 366, 46]}
	])
	var bubble: Rect2 = view._choose_dialogue_rect(Vector2(110, 410), Vector2(250, 62), actor)
	_check(bubble.has_area() and not bubble.grow(8).intersects(actor), "tall portrait chooses a bubble clear of the current character")
	for region in view._ui_regions:
		_check(not bubble.grow(8).intersects(region), "portrait greeting avoids every actual HUD card/button region")
	view.set_ui_regions([{"rect": [0, 0, 390, 844]}])
	_check(not view._choose_dialogue_rect(Vector2(110, 410), Vector2(250, 62), actor).has_area(), "modal/full UI cannot be covered by NPC greetings")
	viewport.queue_free()
	await process_frame
	failures.append_array(_logger.captured_errors())
	_done = true
	if failures.is_empty():
		print("PASS draw-local cache, indexed ellipses and NPC layout: %d checks" % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
