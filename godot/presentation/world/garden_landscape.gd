class_name GardenLandscape
extends RefCounted

const SCENERY := ["dew-plant", "dew-parcel", "berry-bush", "river-rock", "pebble-cluster", "small-pebbles", "stone-lantern", "gold-lotus", "trailing-vine", "pink-flowers", "ivory-lotus", "glow-flower", "fern", "blue-flowers", "yellow-flowers", "red-mushroom", "blue-mushroom", "wood-lantern", "violet-crystal", "light-tower", "lotus-pool"]
static var _pond_outlines: Dictionary = {}

static func surface(level: Dictionary, tile: Dictionary) -> String:
	var chapter: String = level.get("chapter", "valley")
	var stone := "paving-pond" if chapter == "pond" else "paving-valley"
	if tile.get("kind", "") in ["water", "module", "shadow"]:
		return stone
	if tile.get("small", false) or tile.get("kind", "") == "root":
		return "paving-grass"
	for mark in level.get("marks", []):
		if mark.tile == tile.id and mark.kind not in ["rest", "observe"]:
			return stone
	var patch := posmod(int(floor((float(tile.x) + 30) / 2)) * 3 + int(floor((float(tile.z) + 30) / 2)) * 5 + int(str(level.id).right(1)), 8)
	return "paving-grass" if patch < (3 if chapter == "valley" else 1) else "paving-moss" if patch < 5 else stone

static func tile_at(tiles: Array, x: float, z: float, skip := "") -> Dictionary:
	for tile in tiles:
		if is_equal_approx(float(tile.x), x) and is_equal_approx(float(tile.z), z) and str(tile.id) != skip:
			return tile
	return {}

static func face_depth(tile: Dictionary, neighbor: Dictionary, base: float) -> float:
	return maxf(0, (float(tile.h) - float(neighbor.h)) * 48.0) if not neighbor.is_empty() else maxf(12, base + float(tile.h) * 48.0)

static func steps(tiles: Array) -> Array:
	var result: Array = []
	for a in tiles:
		for direction in [Vector2(1, 0), Vector2(0, 1)]:
			var b := tile_at(tiles, float(a.x) + direction.x, float(a.z) + direction.y)
			if not b.is_empty() and not a.get("solid", false) and not b.get("solid", false):
				var difference := absf(float(a.h) - float(b.h))
				if difference > 0.01 and difference <= 1:
					result.append([a, b] if float(a.h) < float(b.h) else [b, a])
	return result

static func floor_tile(p: GardenPaint, view: Variant, tile: Dictionary, tiles: Array, level: Dictionary, state: Dictionary, time: float, opacity := 1.0) -> void:
	var chapter: String = level.get("chapter", "valley")
	var kind: String = tile.get("kind", "")
	var base := 11.0 if kind == "shadow" else 30.0 if kind == "root" else 112.0 if chapter == "valley" else 42.0 if chapter == "pond" else 60.0
	p.push(view.project(tile), Vector2.ONE * view.scale_factor, 0, opacity)
	for side in ["left", "right"]:
		var neighbor := tile_at(tiles, float(tile.x) + (1 if side == "right" else 0), float(tile.z) + (1 if side == "left" else 0), tile.id)
		var depth := face_depth(tile, neighbor, base)
		if depth < 0.1:
			continue
		var corners := PackedVector2Array([Vector2(-35, 0), Vector2(0, 17.5), Vector2(0, 17.5 + depth), Vector2(-35, depth)]) if side == "left" else PackedVector2Array([Vector2(0, 17.5), Vector2(35, 0), Vector2(35, depth), Vector2(0, 17.5 + depth)])
		p.poly(corners, "#9b9b79" if side == "left" else "#7c886f")
		var id: String = "wall-" + str(side) if chapter == "cave" else "masonry-" + chapter
		var texture: Texture2D = p.images.get(id)
		if texture != null:
			var u := (float(tile.x) if side == "left" else -float(tile.z)) * 70.0
			var v := -float(tile.h) * 48.0
			var tw := float(texture.get_width())
			var th := float(texture.get_height())
			var uvs := PackedVector2Array([Vector2(u, v), Vector2(u + 70, v), Vector2(u + 70, v + depth), Vector2(u, v + depth)]) if side == "left" else PackedVector2Array([Vector2(u, v), Vector2(u + 70, v), Vector2(u + 70, v + depth), Vector2(u, v + depth)])
			for index in range(uvs.size()):
				uvs[index] /= Vector2(tw, th)
			p.textured_poly(corners, id, uvs)
		p.poly(corners, p.linear(Rect2(-35, 0, 70, depth), ["#76a9a82a" if chapter == "pond" else "#b4b89415", "#334d413a"]))
		var seed := absi(int(float(tile.x) * 19 + float(tile.z) * 31 + (3 if side == "left" else 0)))
		if chapter == "valley" and seed % 3 == 0 and depth > 25:
			var vx := -19.6 if side == "left" else 16.1
			var length := minf(depth * 0.75, 85)
			p.quadratic(Vector2(vx, 8.05), Vector2(vx - 5, 8.05 + length * 0.5), Vector2(vx + 2, 8.05 + length), "#7b8962", 1.1)
			var vine: Texture2D = p.images.get("trailing-vine")
			if vine != null:
				var width := minf(24, length * vine.get_width() / float(vine.get_height()))
				p.image("trailing-vine", vx, 8.05, width, 0)
	var diamond := PackedVector2Array([Vector2(0, -17.5), Vector2(35, 0), Vector2(0, 17.5), Vector2(-35, 0)])
	p.poly(diamond, "#aec0af" if chapter == "pond" else "#cec8a4")
	p.textured_poly(diamond, surface(level, tile), PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
	p.poly(diamond, "#ffffff00", "#efe4c06b")
	if chapter == "pond":
		if kind == "water":
			p.poly(diamond, "#8dc2c6d9")
			for index in range(3):
				var shift := fmod(time * 0.004 + index * 9, 28)
				p.quadratic(Vector2(-31, shift - 14), Vector2(0, shift - 19), Vector2(30, shift - 14), "#e0f4e399", 0.8)
			p.oval(1, 4, 22, 9, "#528b9266")
			p.oval(0, 1, 20, 9, p.soft(-5, -2, 25, "#e0dfbf", "#b9c2a7", "#879f91"))
			p.textured_oval(0, 0, 19, 8, "paving-pond", 0.7, 0, Rect2(-22, -9, 44, 18))
			p.arc(0, 0, 19, 8, PI * 0.95, PI * 1.9, "#e1e5c8b0", 0.8)
		elif absi(int(float(tile.x) * 17 + float(tile.z) * 29)) % 4 == 0:
			p.push(Vector2.ZERO, Vector2.ONE, 0, 0.36)
			p.oval(-4, 2, 14, 5, p.soft(0, 0, 20, "#dbf6ec", "#7aafb5", "#5a979f"), -0.1)
			p.arc(-5, 2, 10, 3, PI, PI * 1.8, "#d8eee3", 0.8, -0.1)
			p.leaf(9, 3, 0.22, 0.4)
			p.pop()
	if kind == "root":
		p.image("flowers", 0, 5, 24.5, 0.8, 0.6)
	if kind == "shadow":
		p.poly(diamond, "#b8d6ed45" if int(state.get("mode", 0)) else "#ffe1a045", "#eee7ae")
	if kind == "module":
		p.poly(diamond, "#d8d7b515", "#e9e0b18a")
	p.pop()

static func terrain_steps(p: GardenPaint, view: Variant, pair: Array) -> void:
	var low: Dictionary = pair[0]
	var high: Dictionary = pair[1]
	var direction := Vector2(float(high.x) - float(low.x), float(high.z) - float(low.z))
	for index in range(4):
		var corners := PackedVector2Array()
		var height := lerpf(float(low.h), float(high.h), (index + 1) / 4.0)
		for side in [Vector2(-0.29, index / 4.0 * 0.8), Vector2(0.29, index / 4.0 * 0.8), Vector2(0.29, (index + 1) / 4.0 * 0.8), Vector2(-0.29, (index + 1) / 4.0 * 0.8)]:
			corners.append(view.project({"x": float(low.x) + direction.x * (0.1 + side.y) - direction.y * side.x, "z": float(low.z) + direction.y * (0.1 + side.y) + direction.x * side.x, "h": height}))
		var drop: float = (float(high.h) - float(low.h)) / 4.0 * 48.0 * view.scale_factor
		p.poly([corners[0], corners[1], corners[1] + Vector2(0, drop), corners[0] + Vector2(0, drop)], "#9b9f82")
		p.poly(corners, "#ddd6b9" if index % 2 else "#cbcbb0", "#f8ebc594", 0.7 * view.scale_factor)

static func scenery(level: Dictionary) -> Array:
	var chapter: String = level.get("chapter", "valley")
	var palette: Array = ["berry-bush", "fern", "small-pebbles", "pink-flowers", "stone-lantern", "yellow-flowers", "red-mushroom", "blue-flowers", "gold-lotus", "bush"] if chapter == "valley" else ["fern", "river-rock", "blue-flowers", "ivory-lotus", "berry-bush", "yellow-flowers", "lotus-pool", "pink-flowers", "stone-lantern"] if chapter == "pond" else ["blue-mushroom", "small-pebbles", "fern", "violet-crystal", "stone-lantern", "blue-flowers", "glow-flower"]
	var fixed: Array = level.get("tiles", [])
	var landmarks: Array = []
	for mark in level.get("marks", []):
		if mark.kind in ["rest", "observe"]:
			continue
		for tile in fixed:
			if tile.id == mark.tile:
				landmarks.append(tile)
	var approaches: Array = []
	for module in level.get("modules", []):
		for local in module.get("shape", []):
			for turn in range(4 if module.kind == "rotate" else 2 if module.kind == "slide" else 1):
				var position := Vector2(float(local[0]), float(local[1]))
				if module.kind == "rotate":
					for unused in range(turn):
						position = Vector2(-position.y, position.x)
				var shift := turn * float(module.get("distance", 0))
				approaches.append({"x": float(module.x) + position.x + (shift if module.get("axis", "") == "x" else 0), "z": float(module.z) + position.y + (shift if module.get("axis", "") == "z" else 0)})
	var candidates: Array = []
	var directions := [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)]
	for tile in fixed:
		if tile.get("small", false) or tile.get("solid", false) or tile.get("kind", "") == "water" or tile.id == level.get("start", "") or tile.id == level.get("buddy", ""):
			continue
		var blocked := false
		for collectible in level.get("collectibles", []):
			if collectible.tile == tile.id:
				blocked = true
		for place in landmarks:
			if distance(tile, place) < 2:
				blocked = true
		for place in approaches:
			if distance(tile, place) <= 1:
				blocked = true
		for root in level.get("roots", []):
			for socket in root.get("sockets", []):
				if distance(tile, {"x": socket[0], "z": socket[1]}) <= 1:
					blocked = true
		if not blocked:
			for direction in directions:
				if tile_at(fixed, float(tile.x) + direction.x, float(tile.z) + direction.y).is_empty():
					var candidate: Dictionary = tile.duplicate()
					candidate["_authored_order"] = candidates.size()
					candidates.append(candidate)
					break
	# JavaScript's Array.sort is stable; retain authored order for equal depths.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first: float = GardenIsoProjection.ground_depth(a)
		var second: float = GardenIsoProjection.ground_depth(b)
		return first < second if not is_equal_approx(first, second) else int(a._authored_order) < int(b._authored_order))
	var result: Array = []
	var widths := {"berry-bush": 39, "bush": 39, "small-pebbles": 25, "river-rock": 30, "pebble-cluster": 29, "stone-lantern": 30, "lotus-pool": 47, "gold-lotus": 32}
	for tile in candidates:
		var blocked := result.size() >= 13
		for decoration in result:
			if distance(decoration, tile) < 1.3:
				blocked = true
		if blocked:
			continue
		var edge := Vector2.ZERO
		for direction in directions:
			if tile_at(fixed, float(tile.x) + direction.x, float(tile.z) + direction.y).is_empty():
				edge = direction
				break
		var index := result.size()
		var asset: String = palette[(index + int(str(level.id).right(1)) * 2) % palette.size()]
		result.append({"x": float(tile.x) + edge.x * 0.24, "z": float(tile.z) + edge.y * 0.24, "h": tile.h, "depth": GardenIsoProjection.ground_depth(tile) + 0.12, "asset": asset, "width": widths.get(asset, 35 if index % 3 == 0 else 30)})
	if level.has("sanctuary"):
		var flowers := ["pink-flowers", "blue-flowers", "yellow-flowers", "ivory-lotus", "gold-lotus"]
		var index := 0
		var sanctuary: Dictionary = level.sanctuary
		for x in [-11, -9, -7]:
			for z in [-2, 2]:
				if x == -9 and z == -2:
					continue
				var tile := tile_at(sanctuary.tiles, x, z)
				result.append({"x": x, "z": z, "h": tile.get("h", 0), "asset": flowers[index % flowers.size()], "width": 42})
				index += 1
		result.append({"x": -11, "z": 0, "h": tile_at(sanctuary.tiles, -11, 0).get("h", 0), "asset": "berry-bush", "width": 46})
		result.append({"x": -7, "z": -1.7, "h": 1, "asset": "stone-lantern", "width": 29})
	if level.id in ["1-3", "2-4", "3-4"]:
		for tile in fixed:
			var blocked: bool = tile.get("small", false)
			for landmark in landmarks:
				blocked = blocked or distance(landmark, tile) < 2
			for decoration in result:
				blocked = blocked or distance(decoration, tile) < 1
			if not blocked:
				var prop: Dictionary = tile.duplicate()
				prop.merge({"asset": "arch" if chapter == "valley" else "wood-lantern" if chapter == "pond" else "light-tower", "width": 90 if chapter == "valley" else 40 if chapter == "pond" else 65}, true)
				result.append(prop)
				break
	return result

static func distance(a: Dictionary, b: Dictionary) -> float:
	return absf(float(a.x) - float(b.x)) + absf(float(a.z) - float(b.z))

static func pond_footprint(level: Dictionary) -> Array:
	var key := str(level.get("id", "")) + ":" + str(hash(level))
	if _pond_outlines.has(key):
		return _pond_outlines[key]
	var vertices := PackedVector2Array()
	var positions: Array = level.get("tiles", []).duplicate()
	for module in level.get("modules", []):
		for local in module.get("shape", []):
			for shift in [0, module.get("distance", 0)]:
				positions.append({"x": float(module.x) + float(local[0]) + (float(shift) if module.get("axis", "") == "x" else 0), "z": float(module.z) + float(local[1]) + (float(shift) if module.get("axis", "") == "z" else 0)})
	for position in positions:
		for index in range(8):
			vertices.append(Vector2(float(position.x), float(position.z)) + Vector2(cos(index * PI / 4), sin(index * PI / 4)) * 3.2)
	var hull := Geometry2D.convex_hull(vertices)
	if hull.size() > 1 and hull[0] == hull[-1]:
		hull.remove_at(hull.size() - 1)
	# Match the monotonic-chain source order: lexicographic start, then lower hull.
	# Per-vertex seeded bank details depend on this ordering, not only the same shape.
	var start := 0
	for index in range(hull.size()):
		if hull[index].x < hull[start].x or is_equal_approx(hull[index].x, hull[start].x) and hull[index].y < hull[start].y:
			start = index
	var ordered := PackedVector2Array()
	for index in range(hull.size()):
		ordered.append(hull[(start + index) % hull.size()])
	if ordered.size() >= 3:
		var first := ordered[1] - ordered[0]
		var second := ordered[2] - ordered[1]
		if first.cross(second) < 0:
			var reverse := PackedVector2Array([ordered[0]])
			for index in range(ordered.size() - 1, 0, -1):
				reverse.append(ordered[index])
			ordered = reverse
	var result: Array = []
	for point in ordered:
		result.append({"x": point.x, "z": point.y, "h": 0.0})
	_pond_outlines[key] = result
	return result
