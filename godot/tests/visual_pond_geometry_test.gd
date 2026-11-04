extends SceneTree

const World = preload("res://core/garden_world.gd")
const View = preload("res://presentation/world/garden_view.gd")
const EnvironmentArt = preload("res://presentation/world/garden_environment.gd")
const Landscape = preload("res://presentation/world/garden_landscape.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var _logger := ErrorLogger.new()
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	OS.add_logger(_logger)
	call_deferred("_run")

func _run() -> void:
	var view := View.new()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/qa-godot-migration/reference/manifest.json"))
	var states := 0
	for capture in manifest.captures:
		if not str(capture.levelId).begins_with("2-"):
			continue
		var world := World.new(str(capture.levelId), capture.snapshot)
		var board: Array = world.tiles()
		var original: Array = board.duplicate(true)
		var geography := view.pond_geometry(world.level, board)
		_check(is_same(geography, view.pond_geometry(world.level.duplicate(true), board.duplicate(true))), "equivalent fresh boards reuse the one current layout")
		for transform in [
			[Vector2(600, 360), 1.28, -0.5], [Vector2(148.2, 422), 0.92, -0.55],
			[Vector2(-43.8, 197.4), 0.38, -0.37], [Vector2(1200.5, 675.5), 1.5, 0.82]
		]:
			view.origin = transform[0]
			view.scale_factor = transform[1]
			var water: float = transform[2]
			_check(is_same(geography, view.pond_geometry(world.level, board)), "camera and uniform water translation preserve world geography")
			_check(geography.cells == _original_cells(view, geography.bank, board, water), "%s/%s cached cell order, polygon membership and proximity match original screen-space code" % [capture.levelId, capture.stage])
		_check(geography.particles == _original_particles(geography.bank, board), "particle positions and proximity retain original order")
		var edges: Array = []
		for tile in board:
			if tile.has("module") or float(tile.h) > 0.1:
				continue
			if Landscape.tile_at(board, float(tile.x), float(tile.z) + 1).is_empty():
				edges.append({"x": tile.x, "z": tile.z})
		_check(geography.edges == edges, "edge ripples retain original tile order and exclusions")
		_check(board == original and world.tiles() == original, "building geography never changes independent rule boards")
		var separate := EnvironmentArt.build_pond_geometry(world.level, board)
		separate.cells.clear()
		separate.bank.clear()
		_check(not geography.cells.is_empty() and not geography.bank.is_empty(), "independent geometry builds cannot alter the retained layout")
		var changed: Array = board.duplicate(true)
		changed[0].solid = not bool(changed[0].get("solid", false))
		_check(not is_same(geography, view.pond_geometry(world.level, changed)), "solid/geography changes invalidate the layout")
		var changed_level: Dictionary = world.level.duplicate(true)
		changed_level["geometryTest"] = true
		var current := view.pond_geometry(world.level, board)
		_check(not is_same(current, view.pond_geometry(changed_level, board)), "changed authored level definition invalidates the layout")
		states += 1
	view.free()
	failures.append_array(_logger.captured_errors())
	if failures.is_empty():
		print("PASS pond geography cache: %d states / %d checks" % [states, checks])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _original_cells(view: Node2D, bank: Array, board: Array, water: float) -> Array:
	var outline := PackedVector2Array()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for index in range(bank.size()):
		var point: Dictionary = bank[index]
		outline.append(view.project({"x": float(point.x) + sin(index * 0.7) * 0.42, "z": float(point.z) + cos(index * 0.9) * 0.36, "h": water}))
		minimum = minimum.min(Vector2(point.x, point.z))
		maximum = maximum.max(Vector2(point.x, point.z))
	var shape := EnvironmentArt._shoreline(outline)
	var result: Array = []
	for x in range(int(floor(minimum.x)), int(ceil(maximum.x)) + 1):
		for z in range(int(floor(minimum.y)), int(ceil(maximum.y)) + 1):
			var at: Vector2 = view.project({"x": x + 0.23, "z": z + 0.15, "h": water})
			if not Geometry2D.is_point_in_polygon(at, shape):
				continue
			var near := false
			for tile in board:
				if Landscape.distance(tile, {"x": x, "z": z}) < 1.6:
					near = true
			result.append({"x": x, "z": z, "seed": absi(x * 37 + z * 61), "near": near})
	return result

func _original_particles(bank: Array, board: Array) -> Array:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point in bank:
		minimum = minimum.min(Vector2(point.x, point.z))
		maximum = maximum.max(Vector2(point.x, point.z))
	var result: Array = []
	for index in range(23):
		var x := minimum.x + fposmod(index * 0.75487766 + 0.21, 1) * (maximum.x - minimum.x)
		var z := minimum.y + fposmod(index * 0.56984029 + 0.37, 1) * (maximum.y - minimum.y)
		var near := false
		for tile in board:
			near = near or Landscape.distance(tile, {"x": x, "z": z}) < 1.3
		result.append({"x": x, "z": z, "near": near})
	return result

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
