class_name GardenEnvironment
extends RefCounted
static var _banks: Dictionary = {}

static func background(p: GardenPaint, size: Vector2, chapter: String) -> void:
	p.target.draw_rect(Rect2(Vector2.ZERO, size), Color("d9dfcc"))
	var texture: Texture2D = p.images.get("background-" + chapter)
	if texture != null:
		var factor := maxf(size.x / texture.get_width(), size.y / texture.get_height())
		var dimensions := texture.get_size() * factor
		p.target.draw_texture_rect(texture, Rect2((size - dimensions) / 2, dimensions), false)
	p.target.draw_rect(Rect2(Vector2.ZERO, size), Color("14223944" if chapter == "cave" else "f2ecd822"))

static func _shoreline(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size()):
		var previous := points[posmod(index - 1, points.size())]
		var point := points[index]
		var next := points[(index + 1) % points.size()]
		result.append_array(GardenPaint.quadratic_points((previous + point) / 2, point, (point + next) / 2, 6))
	return result

static func _bank(level: Dictionary) -> Array:
	var key := str(level.get("id", "")) + ":" + str(hash(level))
	if _banks.has(key):
		return _banks[key]
	var outline := GardenLandscape.pond_footprint(level)
	var result: Array = []
	for index in range(outline.size()):
		var a: Dictionary = outline[posmod(index - 1, outline.size())]
		var point: Dictionary = outline[index]
		var b: Dictionary = outline[(index + 1) % outline.size()]
		for sample in range(3):
			var t := sample / 3.0
			var u := 1 - t
			result.append({"x": u * u * (float(a.x) + float(point.x)) / 2 + 2 * u * t * float(point.x) + t * t * (float(point.x) + float(b.x)) / 2, "z": u * u * (float(a.z) + float(point.z)) / 2 + 2 * u * t * float(point.z) + t * t * (float(point.z) + float(b.z)) / 2, "h": 0})
	_banks[key] = result
	return result

## Classify geography in local projection space. The positive camera scale and
## common water-height translation preserve polygon membership and distances.
## The input board stays independent and no rule state is stored or changed.
static func build_pond_geometry(level: Dictionary, tiles: Array) -> Dictionary:
	var bank := _bank(level)
	var outline := PackedVector2Array()
	var world_min := Vector2(INF, INF)
	var world_max := Vector2(-INF, -INF)
	for index in range(bank.size()):
		var point: Dictionary = bank[index]
		outline.append(GardenIsoProjection.raw({"x": float(point.x) + sin(index * 0.7) * 0.42, "z": float(point.z) + cos(index * 0.9) * 0.36, "h": 0}))
		world_min = world_min.min(Vector2(point.x, point.z))
		world_max = world_max.max(Vector2(point.x, point.z))
	var shape := _shoreline(outline)
	var cells: Array = []
	for x in range(int(floor(world_min.x)), int(ceil(world_max.x)) + 1):
		for z in range(int(floor(world_min.y)), int(ceil(world_max.y)) + 1):
			var at := GardenIsoProjection.raw({"x": x + 0.23, "z": z + 0.15, "h": 0})
			if not Geometry2D.is_point_in_polygon(at, shape):
				continue
			var near := false
			for tile in tiles:
				if GardenLandscape.distance(tile, {"x": x, "z": z}) < 1.6:
					near = true
					break
			cells.append({"x": x, "z": z, "seed": absi(x * 37 + z * 61), "near": near})
	var particles: Array = []
	for index in range(23):
		var x := world_min.x + fposmod(index * 0.75487766 + 0.21, 1) * (world_max.x - world_min.x)
		var z := world_min.y + fposmod(index * 0.56984029 + 0.37, 1) * (world_max.y - world_min.y)
		var near := false
		for tile in tiles:
			if GardenLandscape.distance(tile, {"x": x, "z": z}) < 1.3:
				near = true
				break
		particles.append({"x": x, "z": z, "near": near})
	var edges: Array = []
	for tile in tiles:
		if not tile.has("module") and float(tile.h) <= 0.1 and GardenLandscape.tile_at(tiles, float(tile.x), float(tile.z) + 1).is_empty():
			edges.append({"x": tile.x, "z": tile.z})
	return {"bank": bank.duplicate(true), "cells": cells, "particles": particles, "edges": edges}

static func pond(p: GardenPaint, view: Variant, level: Dictionary, tiles: Array, water_height: float, time: float, settings: Dictionary) -> void:
	var geography: Dictionary = view.pond_geometry(level, tiles)
	var bank: Array = geography.bank
	var outline := PackedVector2Array()
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for index in range(bank.size()):
		var point: Dictionary = bank[index]
		var projected: Vector2 = view.project({"x": float(point.x) + sin(index * 0.7) * 0.42, "z": float(point.z) + cos(index * 0.9) * 0.36, "h": water_height})
		outline.append(projected)
		min_x = minf(min_x, projected.x)
		max_x = maxf(max_x, projected.x)
		min_y = minf(min_y, projected.y)
		max_y = maxf(max_y, projected.y)
	if outline.size() < 3:
		return
	var shape := _shoreline(outline)
	var scale: float = view.scale_factor
	p.push(Vector2(0, 9 * scale))
	p.poly(shape, "#668b8738")
	p.pop()
	p.line(shape, "#8da68b55", 17 * scale, true)
	for index in range(outline.size()):
		var at := outline[index]
		var seed := index * 29 % 67
		if index % 3 != 0:
			var rx := (10 + seed % 18) * scale
			var ry := (5 + seed % 7) * scale
			p.oval(at.x, at.y - 2 * scale, rx, ry, p.soft(at.x, at.y, 29 * scale, "#c6d3a2", "#9fb68a", "#759784"), sin(float(index)) * 0.12)
			p.textured_oval(at.x, at.y - 2 * scale, rx, ry, "paving-grass", 0.35, sin(float(index)) * 0.12)
		if index % 5 == 0:
			p.image("river-rock" if index % 2 else "small-pebbles", at.x, at.y - 2 * scale, (22 + seed % 16) * scale, 1)
		if index % 7 == 2:
			p.leaf(at.x, at.y - 6 * scale, 0.7 * scale, index * 0.43)
			p.leaf(at.x + 6 * scale, at.y - 4 * scale, 0.55 * scale, index * 0.43 + 1)
		if index % 4 == 1:
			p.image("fern", at.x, at.y, (20 + seed % 10) * scale, 1, 0.75)
		if index % 13 == 4 and at.y < min_y + (max_y - min_y) * 0.65:
			p.image("berry-bush" if index % 2 else "fern", at.x, at.y - 5 * scale, (33 + seed % 13) * scale, 1)
	var rear := PackedVector2Array()
	for at in outline:
		if at.y < min_y + (max_y - min_y) * 0.24:
			rear.append(at)
	for index in range(2):
		if rear.is_empty():
			break
		var at := rear[int(floor((rear.size() - 1) * (0.18 if index == 0 else 0.76)))]
		var rx := (62 if index == 0 else 48) * scale
		var ry := (23 if index == 0 else 18) * scale
		p.oval(at.x, at.y - 2 * scale, rx, ry, "#849780")
		p.oval(at.x, at.y - 8 * scale, rx, ry, p.soft(at.x - 15 * scale, at.y - 16 * scale, rx, "#c4d4a0", "#9cb585", "#73957c"))
		p.textured_oval(at.x, at.y - 8 * scale, rx, ry, "paving-grass", 0.4)
		var width := (53 if index == 0 else 44) * scale
		p.image("bush" if index == 0 else "berry-bush", at.x - width * 0.2, at.y - 15 * scale, width, 1)
		p.leaf(at.x + rx * 0.55, at.y - 16 * scale, 0.8 * scale, 0.3)
	var bounds := Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	p.poly(shape, p.linear(bounds, ["#94bcb6", "#a8ced0", "#83b8c4", "#84b0b9"], [0.0, 0.32, 0.65, 1.0]), "#537e7670", 3 * scale)
	var texture: Texture2D = p.images.get("water-pigment")
	if texture != null:
		var uv := PackedVector2Array()
		for point in shape:
			uv.append(point / texture.get_size())
		p.textured_poly(shape, "water-pigment", uv, 0.4)
	var reflection := PackedVector2Array()
	for point in shape:
		var uv := (point - bounds.position) / bounds.size
		reflection.append(Vector2(uv.x, 1 - uv.y))
	p.textured_poly(shape, "background-pond", reflection, 0.055)
	p.poly(shape, p.linear(bounds, ["#658c7f91", "#8bb5aa00", "#9db6a700", "#8ca8954a"], [0, 0.22, 0.82, 1]))
	for cell in geography.cells:
		var seed: int = cell.seed
		var at: Vector2 = view.project({"x": int(cell.x) + 0.23, "z": int(cell.z) + 0.15, "h": water_height})
		if seed % 3 == 0:
			p.arc(at.x + sin(time * 0.0005 + seed) * 3 * scale, at.y, (11 + seed % 13) * scale, (3 + seed % 4) * scale, PI * 0.15, PI * 1.1, "#e4f7e84d", 0.8 * scale, -0.08)
		if cell.near:
			continue
		if seed % 7 == 0:
			var width := (19 + seed % 11) * scale
			var pad: Texture2D = p.images.get("lilypad")
			if pad != null:
				p.target.draw_texture_rect(pad, Rect2(at.x - width / 2, at.y - width * 0.25, width, width * 0.54), false)
			if seed % 2 == 0:
				p.oval(at.x, at.y - 4 * scale, 3 * scale, 2 * scale, "#f4d9c0")
				p.oval(at.x, at.y - 5 * scale, 1.2 * scale, 1.3 * scale, "#ffe7ae")
		if seed % 13 == 0:
			for index in range(4):
				var dx := (index - 1.5) * 4 * scale
				var top := at.y - (21 + index % 2 * 12) * scale
				p.quadratic(at, Vector2(at.x + dx, top + 11 * scale), Vector2(at.x + dx, top), "#668d70", 1.3 * scale)
				p.line([Vector2(at.x + dx, top), Vector2(at.x + dx, top - 5 * scale)], "#9f8b5e", 3 * scale)
	for tile in geography.edges:
		var at: Vector2 = view.project({"x": tile.x, "z": tile.z, "h": water_height})
		p.quadratic(at + Vector2(-30, 4) * scale, at + Vector2(-12, 20) * scale, at + Vector2(6, 20) * scale, "#d8eee180", 0.85 * scale)
	if settings.get("particles", true) and not settings.get("lowMotion", false):
		for index in range(23):
			var particle: Dictionary = geography.particles[index]
			if particle.near:
				continue
			var at: Vector2 = view.project({"x": particle.x, "z": particle.z, "h": water_height})
			var phase := fposmod(time / (3300 + index % 5 * 430) + index * 0.381966, 1)
			var height := (1 - phase / 0.64) * 105 if phase < 0.64 else 0.0
			p.push(Vector2.ZERO, Vector2.ONE, 0, 0.7 if phase < 0.64 else (1 - phase) / 0.36)
			if phase < 0.64:
				p.line([at + Vector2(2, -height - 8) * scale, at + Vector2(0, -height) * scale], "#edfdf2", 1.1 * scale)
			else:
				var radius := (2 + (phase - 0.64) / 0.36 * 19) * scale
				p.arc(at.x, at.y, radius, radius * 0.32, 0, TAU, "#e4f9ed", scale)
				p.arc(at.x, at.y, radius * 0.62, radius * 0.2, 0, TAU, "#e4f9ed80", scale)
				if phase < 0.79:
					var height_splash := sin((phase - 0.64) / 0.15 * PI) * 9 * scale
					p.quadratic(at - Vector2(4 * scale, 0), at - Vector2(0, height_splash * 1.6), at + Vector2(3 * scale, 0), "#e4f9ed", scale)
					p.oval(at.x, at.y - height_splash, scale, 1.5 * scale, "#f2fff2")
			p.pop()

static func rain(p: GardenPaint, size: Vector2, time: float, foreground: bool, settings: Dictionary) -> void:
	if settings.get("lowMotion", false) or not settings.get("particles", true):
		return
	for index in range(38 if size.x < 650 else 76):
		if (index % 5 == 0) != foreground:
			continue
		var duration := 2800 + index * 137 % 1700
		var phase := fposmod(time / duration + index * 0.61803398875, 1)
		var x := fposmod(index * 0.754877666 + 0.13, 1) * size.x - phase * 12
		var y := phase * (size.y + 90) - 45
		p.line([Vector2(x, y), Vector2(x - 1.5, y + (5 + index % 9) * (1.6 if foreground else 1.0))], "#eefbf2a3" if foreground else "#d7ecee52", 1 if foreground else 0.65)
		if foreground and index % 10 == 0:
			var length := 5 + index % 9
			var shape := GardenPaint.cubic_points(Vector2(x, y + length + 1), Vector2(x - 4, y + length + 7), Vector2(x + 3, y + length + 9), Vector2(x, y + length + 1))
			p.poly(shape, "#d8f4ee5c")
	if not foreground:
		return
	for side in [-1, 1]:
		for index in range(3):
			var phase := fposmod(time / (5800 + index * 800) + index * 0.31, 1)
			if phase > 0.7:
				continue
			var x := size.x * (0.035 + index * 0.04) if side < 0 else size.x * (0.965 - index * 0.035)
			var y := size.y * 0.1 + phase * size.y * 0.8
			var extent := 1.1 + index * 0.3
			var shape := GardenPaint.cubic_points(Vector2(x, y - 5 * extent), Vector2(x - 2 * extent, y), Vector2(x - 2 * extent, y + extent), Vector2(x, y + extent))
			shape.append_array(GardenPaint.cubic_points(Vector2(x, y + extent), Vector2(x + 2 * extent, y + extent), Vector2(x + 2 * extent, y), Vector2(x, y - 5 * extent)))
			p.poly(shape, "#d3f0ea96", "#effff1a0", 0.6)

static func runoff_source(level: Dictionary, tiles: Array) -> Dictionary:
	var result: Array = []
	for tile in tiles:
		if tile.has("module") or tile.get("small", false) or tile.get("solid", false) or float(tile.h) < (0 if level.get("chapter", "") == "pond" else 1):
			continue
		if not GardenLandscape.tile_at(tiles, float(tile.x), float(tile.z) + 1).is_empty():
			continue
		var marked := false
		for mark in level.get("marks", []):
			marked = marked or mark.tile == tile.id
		if not marked:
			result.append(tile)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.h) > float(b.h) if not is_equal_approx(float(a.h), float(b.h)) else float(a.x) > float(b.x))
	return {} if result.is_empty() else result[0]

static func runoff(p: GardenPaint, view: Variant, source: Dictionary, level: Dictionary, water_height: float, time: float) -> void:
	var lip := {"x": source.x, "z": float(source.z) + 0.5, "h": source.h}
	var at: Vector2 = view.project(lip)
	var bottom: Vector2 = view.project({"x": lip.x, "z": lip.z, "h": water_height if level.get("chapter", "") == "pond" else float(source.h) - 2.8})
	var scale: float = view.scale_factor
	if bottom.y - at.y < 5 * scale:
		return
	var head: Vector2 = view.project({"x": lip.x, "z": float(lip.z) - 0.9, "h": lip.h})
	p.quadratic(head, at + Vector2(6, -8) * scale, at, "#6b9f9b99", 11 * scale)
	p.quadratic(head, at + Vector2(6, -8) * scale, at, "#c6efdf", 4.5 * scale)
	var width := 10 * scale
	var shape := GardenPaint.cubic_points(at - Vector2(width * 0.45, 0), at + Vector2(-width * 0.6, 20 * scale), bottom + Vector2(-width * 0.8, -12 * scale), bottom + Vector2(-width * 0.9, 0))
	shape.append(bottom + Vector2(width * 0.9, 0))
	shape.append_array(GardenPaint.cubic_points(bottom + Vector2(width * 0.9, 0), bottom + Vector2(width * 0.4, -20 * scale), at + Vector2(width * 0.3, 20 * scale), at + Vector2(width * 0.45, 0)))
	p.poly(shape, p.linear(Rect2(at.x - width, at.y, width * 2, bottom.y - at.y), ["#d1f0e5e6", "#91cad6c7", "#d0ede066"]))
	for index in range(3):
		var y := at.y + fposmod(time * 0.025 + index * 23, maxf(10, bottom.y - at.y))
		p.line([Vector2(at.x + (index - 1) * 3 * scale, y), Vector2(at.x + (index - 1) * 3 * scale, y + 10 * scale)], "#effdecaa", 1.1 * scale)
	p.oval(bottom.x, bottom.y + 2 * scale, 21 * scale, 6 * scale, p.soft(bottom.x, bottom.y, 24 * scale, "#d1e9d6", "#82b8bc", "#688f9e"))
	for index in range(3):
		p.arc(bottom.x, bottom.y, (9 + index * 6 + sin(time * 0.001 + index)) * scale, (2 + index * 1.7) * scale, 0, PI * 1.8, "#effdecaa", 1.1 * scale)

static func residents(level: Dictionary, tiles: Array) -> Array:
	var minimum := INF
	var maximum := -INF
	var max_z := -INF
	for tile in level.get("tiles", []):
		minimum = minf(minimum, float(tile.x))
		maximum = maxf(maximum, float(tile.x))
		max_z = maxf(max_z, float(tile.z))
	var result: Array = []
	for point in [{"x": minimum - 1.7, "z": max_z + 0.9, "h": 0}, {"x": maximum + 1.6, "z": max_z + 0.8, "h": 0}, {"x": maximum - 0.7, "z": max_z + 1.7, "h": 0}]:
		var blocked := false
		for tile in tiles:
			blocked = blocked or GardenLandscape.distance(tile, point) < 1.45
		for module in level.get("modules", []):
			blocked = blocked or (absf(float(point.z) - float(module.z)) < 3 and float(point.x) >= float(module.x) - 3 and float(point.x) <= float(module.x) + absf(float(module.get("distance", 0))) + 3)
		if not blocked and result.size() < 2:
			result.append(point)
	return result

static func resident(p: GardenPaint, at: Vector2, scale: float, time: float) -> void:
	p.push(at, Vector2.ONE * scale)
	p.oval(0, 2, 22, 8, "#467f7740")
	var pad: Texture2D = p.images.get("lilypad")
	if pad != null:
		var points := PackedVector2Array([Vector2(-22, -9), Vector2(22, -9), Vector2(22, 12), Vector2(-22, 12)])
		p.textured_poly(points, "lilypad", PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
	p.push(Vector2(0, sin(time / 1600.0) * 0.35))
	p.oval(1, -9, 10, 7, p.soft(-3, -13, 14, "#d9e6a0", "#9abb70", "#5f8758"))
	p.oval(-6, -5, 6, 3, "#83a761")
	p.oval(7, -5, 5, 3, "#7e9e59")
	p.oval(-4, -15, 6, 5, p.soft(-5, -18, 9, "#e4ecb5", "#a7c77a", "#73965b"))
	p.oval(3, -15, 5, 5, "#adc97d")
	var blink := fmod(time, 6200) > 6010
	p.eye(-5, -16, blink, 0.62)
	p.eye(3, -16, blink, 0.62)
	p.quadratic(Vector2(-3, -10), Vector2(0, -8), Vector2(4, -10), "#6e8856", 0.7)
	p.leaf(18, -1, 0.45, -0.3)
	p.pop()
	p.pop()
