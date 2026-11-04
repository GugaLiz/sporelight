class_name GardenWorld
extends RefCounted
## Deterministic port of the frozen garden2 rule model. Rendering never mutates this class.

const DIRECTIONS: Dictionary = {"up": [0, -1], "right": [1, 0], "down": [0, 1], "left": [-1, 0]}
const ACTORS: Array = ["luvie", "buddy"]
static var _definitions: Array = []
var level: Dictionary
var state: Dictionary
var _history: Array = []
var _error: String = ""

func _init(level_id: String = "1-1", saved: Dictionary = {}) -> void:
	if _definitions.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
		if parsed is Dictionary:
			_definitions = parsed.get("levels", [])
	assert(not _definitions.is_empty(), "Missing migration content/levels.json")
	level = _definitions[0].duplicate(true)
	for definition: Dictionary in _definitions:
		if definition.id == level_id:
			level = definition.duplicate(true)
			break
	state = {"designVersion": 2, "levelId": level.id, "active": "luvie", "actors": {"luvie": level.start, "buddy": level.get("buddy", level.start)}, "follow": not level.id in ["1-4", "2-3", "3-1", "3-4"], "growth": {}, "turns": {}, "flags": [], "items": {}, "collected": [], "observations": [], "discovered": [], "water": 0, "mode": 0, "frozen": null, "song": ["turn", "rise", "rest"], "beat": 0, "playing": false, "completed": false}
	for root: Dictionary in level.roots:
		state.growth[root.id] = []
	for module: Dictionary in level.modules:
		state.turns[module.id] = 0
	match str(level.id):
		"1-4": state.items.bell = {"tile": cell(-2, 5), "angle": 0}
		"2-2":
			state.items.mirrorA = {"tile": cell(1, 1), "angle": 0}
			state.items.mirrorB = {"tile": cell(4, 3), "angle": 0}
		"2-1": state.items.dew = {"tile": cell(0, 4), "angle": 0}
		"2-4": state.items.bug = {"tile": cell(-4, 0), "angle": 0}
		"3-1": state.items.lamp = {"tile": cell(-3, 0), "angle": 0}
		"3-2":
			state.items.sunPost = {"tile": cell(-2, 0), "angle": 0}
			state.items.moonPost = {"tile": cell(-2, 1), "angle": 0}
		"3-3": state.items.dew = {"tile": cell(8, 0), "angle": 0}
		"3-4": state.items.mirror = {"tile": cell(1, -4), "angle": 0}
	if saved.get("designVersion") == 2 and saved.get("levelId") == level_id:
		var initial: Dictionary = snapshot()
		if not _restore(saved, initial):
			state = initial

static func cell(x: float, z: float) -> String:
	return "f:%d:%d" % [int(x), int(z)]

static func module_cell(id: String, x: float = 0, z: float = 0) -> String:
	return "m:%s:%d:%d" % [id, int(x), int(z)]

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _unique(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		if not value in result:
			result.append(value)
	return result

func _restore(saved: Dictionary, initial: Dictionary) -> bool:
	var s: Dictionary = saved.duplicate(true)
	for key: String in ["actors", "items", "turns", "growth"]:
		if not s.get(key) is Dictionary:
			return false
	if not s.get("active") in ACTORS:
		return false
	for key: String in ["flags", "collected", "observations"]:
		if not s.get(key) is Array:
			return false
		for value: Variant in s[key]:
			if not value is String:
				return false
	s.follow = s.get("follow") is bool and s.follow
	s.playing = s.get("playing") is bool and s.playing
	s.completed = s.get("completed") is bool and s.completed
	s.discovered = []
	if saved.get("discovered") is Array:
		for value: Variant in saved.discovered:
			if value is String:
				s.discovered.append(value)
	if s.get("shadowMemory") != null:
		if not s.shadowMemory is Array or s.shadowMemory.size() != 2:
			return false
		for p: Variant in s.shadowMemory:
			if not p is Dictionary or not _integer(p.get("x")) or not _integer(p.get("z")) or not _integer(p.get("h")) or int(p.h) != 0:
				return false
	var collections: Array = []
	if level.id == "3-4":
		for f: String in ["root", "rain", "star", "moon"]:
			for i: int in range(2):
				collections.append("gift-%s-%d" % [f, i])
	else:
		for c: Dictionary in level.collectibles:
			collections.append(c.id)
	s.collected = _unique(s.collected.filter(func(value: Variant) -> bool: return value in collections))
	s.water = int(s.water) if _integer(s.get("water")) and int(s.water) in [0, 1, 2] else 0
	s.mode = 1 if _integer(s.get("mode")) and int(s.mode) == 1 else 0
	s.frozen = int(s.frozen) if _integer(s.get("frozen")) and int(s.frozen) in [0, 1] else null
	s.beat = clampi(int(s.get("beat", 0)), 0, 3) if _integer(s.get("beat")) else 0
	var valid_song: bool = s.get("song") is Array and s.song.size() == 3 and _unique(s.song).size() == 3
	if valid_song:
		for note: Variant in s.song:
			if not note in ["turn", "rise", "rest"]:
				valid_song = false
	s.song = s.song if valid_song else ["turn", "rise", "rest"]
	for module: Dictionary in level.modules:
		var turn: Variant = s.turns.get(module.id)
		s.turns[module.id] = posmod(int(turn), 4) if _integer(turn) else 0
	for root: Dictionary in level.roots:
		var path: Variant = s.growth.get(root.id)
		if not path is Array or path.size() > root.budget or _unique(path).size() != path.size():
			return false
		for value: Variant in path:
			if not value is String:
				return false
	if s.get("trial", "") != "":
		if not s.trial is String:
			return false
		var trial: Variant = JSON.parse_string(s.trial)
		if not trial is Dictionary or trial.get("designVersion") != 2 or trial.get("trial", "") != "" or trial.get("levelId") != level.id:
			return false
	for name: String in s.items:
		var item: Variant = s.items[name]
		if not initial.items.has(name) or not item is Dictionary or not item.get("tile") is String or not _integer(item.get("angle")):
			return false
		if item.get("holder", "") != "" and (not item.holder in ACTORS or item.tile != ""):
			return false
		if name.begins_with("mirror") and item.get("holder") == "buddy":
			return false
	for name: String in initial.items:
		if not s.items.has(name):
			return false
	var held: Dictionary = {"luvie": 0, "buddy": 0}
	for name: String in s.items:
		var item: Dictionary = s.items[name]
		if name == "dew" and ((item.get("picked") is bool and item.picked) or item.get("holder", "") != "" or item.tile != initial.items[name].tile):
			item.picked = true
		else:
			item.erase("picked")
		if item.get("holder", "") in ACTORS:
			held[item.holder] += 1
	if held.luvie > 1 or held.buddy > 1:
		return false
	state = s
	var world_tiles: Array = tiles()
	for who: String in ACTORS:
		var tile: Dictionary = _find_tile(str(s.actors.get(who, "")), world_tiles)
		if tile.is_empty() or tile.get("solid", false) or (who == "luvie" and tile.get("small", false)):
			return false
	for item: Dictionary in s.items.values():
		if item.tile != "" and _find_tile(item.tile, world_tiles).is_empty():
			return false
	for root: Dictionary in level.roots:
		var previous: Dictionary = point_for(root.at)
		for id: Variant in s.growth[root.id]:
			if not id is String:
				return false
			var tile: Dictionary = _growth_point(id, root.h)
			if tile.is_empty() or _distance(previous, tile) != 1 or not _socket(root, tile.x, tile.z):
				return false
			previous = tile
	return true

func snapshot() -> Dictionary:
	return state.duplicate(true)

func fork(saved: Dictionary) -> RefCounted:
	return get_script().new(str(level.id), saved)

func normalize_saved(saved: Dictionary) -> Dictionary:
	# Constructor fallback is useful for play, but import must distinguish rejection from repair.
	if saved.get("designVersion") != 2 or saved.get("levelId") != level.id:
		return {"ok": false, "snapshot": {}, "error": "unsupported_snapshot_version_or_level"}
	var fresh: RefCounted = get_script().new(str(level.id))
	var initial: Dictionary = fresh.snapshot()
	if not fresh._restore(saved, initial):
		return {"ok": false, "snapshot": {}, "error": "invalid_saved_state"}
	return {"ok": true, "snapshot": fresh.snapshot()}

func tiles_for_state(saved: Dictionary) -> Array:
	return fork(saved).tiles()

func can_undo() -> bool:
	return not _history.is_empty()

func undo() -> bool:
	if _history.is_empty():
		return false
	state = _history.pop_back()
	return true

func flag(id: String) -> bool:
	return id in state.flags

func _set_flag(id: String) -> void:
	if not flag(id):
		state.flags.append(id)

func actor() -> String:
	return str(state.active)

func point() -> Dictionary:
	return point_for(str(state.actors[state.active]))

func budget() -> int:
	return int(level.roots[0].budget - state.growth[level.roots[0].id].size()) if not level.roots.is_empty() else 0

func connected(root: Dictionary = {}) -> bool:
	if root.is_empty():
		if level.roots.is_empty():
			return false
		root = level.roots[0]
	var path: Array = state.growth[root.id]
	if path.is_empty():
		return false
	var end: Dictionary = _growth_point(str(path.back()), root.h)
	return not end.is_empty() and end.x == root.goal[0] and end.z == root.goal[1]

static func _distance(a: Dictionary, b: Dictionary) -> float:
	return absf(float(a.x - b.x)) + absf(float(a.z - b.z))

static func _find_tile(id: String, values: Array) -> Dictionary:
	for tile: Dictionary in values:
		if tile.id == id:
			return tile
	return {}

func point_for(id: String, world_tiles: Array = []) -> Dictionary:
	return _find_tile(id, tiles() if world_tiles.is_empty() else world_tiles)

static func _socket(root: Dictionary, x: float, z: float) -> bool:
	for socket: Array in root.sockets:
		if socket[0] == x and socket[1] == z:
			return true
	return false

static func _growth_point(id: String, height: float) -> Dictionary:
	var parts: PackedStringArray = id.split(":")
	if parts.size() != 4 or parts[0] != "g" or not parts[2].is_valid_int() or not parts[3].is_valid_int():
		return {}
	return {"id": id, "x": int(parts[2]), "z": int(parts[3]), "h": height, "kind": "root"}

func growth_guidance() -> Dictionary:
	if level.roots.is_empty() or connected():
		return {}
	var root: Dictionary = level.roots[0]
	var grown: Array = state.growth[root.id]
	var origin: Dictionary = point_for(root.at)
	var end: Dictionary = _growth_point(str(grown.back()), root.h) if not grown.is_empty() else origin
	var queue: Array = [{"point": end, "route": []}]
	var index: int = 0
	while index < queue.size():
		var current: Dictionary = queue[index]
		index += 1
		if current.point.x == root.goal[0] and current.point.z == root.goal[1]:
			return {"root": root, "origin": origin, "end": end, "route": current.route, "retract": false}
		if grown.size() + current.route.size() >= root.budget:
			continue
		for direction: Array in DIRECTIONS.values():
			var x: float = current.point.x + direction[0]
			var z: float = current.point.z + direction[1]
			var id: String = "g:%s:%d:%d" % [root.id, int(x), int(z)]
			var used: bool = false
			for p: Dictionary in current.route:
				if p.x == x and p.z == z:
					used = true
			if not _socket(root, x, z) or id in grown or used:
				continue
			var p: Dictionary = {"x": x, "z": z, "h": root.h}
			queue.append({"point": p, "route": current.route + [p]})
	return {"root": root, "origin": origin, "end": end, "route": [], "retract": true}

func module_point(id: String, local: Array) -> Dictionary:
	var module: Dictionary = {}
	for candidate: Dictionary in level.modules:
		if candidate.id == id:
			module = candidate
	if module.is_empty():
		return {}
	var x: float = local[0]
	var z: float = local[1]
	var turn: int = int(state.turns.get(id, 0))
	if module.kind == "rotate":
		for unused: int in range(turn):
			var old_x: float = x
			x = -z
			z = old_x
	var shift: float = (turn % 2) * module.get("distance", 0) if module.kind == "slide" else 0.0
	var height: float = module.h
	if module.kind == "lift":
		height = state.water if id == "float" else module.get("high", 2) if turn % 2 else module.get("low", 0)
	if level.id == "2-3" and id == "stage":
		height = 2 if flag("raised") else 0
	return {"x": module.x + x + (shift if module.get("axis") == "x" else 0), "z": module.z + z + (shift if module.get("axis") == "z" else 0), "h": height}

static func _add(values: Array, x: float, z: float, height: float = 0, kind: String = "root", small: bool = false, id: String = "") -> void:
	values.append({"id": cell(x, z) if id == "" else id, "x": x, "z": z, "h": height, "kind": kind, "small": small})

static func _line(values: Array, a: Array, b: Array, height: float = 0, small: bool = false) -> void:
	var x: int = int(a[0])
	var z: int = int(a[1])
	while x != b[0] or z != b[1]:
		if x != b[0]:
			x += signi(int(b[0]) - x)
		else:
			z += signi(int(b[1]) - z)
		_add(values, x, z, height, "root", small)

func tiles() -> Array:
	var base: Array = level.tiles.duplicate(true)
	if level.has("sanctuary"):
		for tile: Dictionary in level.sanctuary.tiles:
			var added: Dictionary = tile.duplicate(true)
			added.solid = tile.x == level.sanctuary.fountain.x and tile.z == level.sanctuary.fountain.z
			base.append(added)
		var gate: Dictionary = level.sanctuary.gate.duplicate(true)
		gate.solid = not flag("home")
		base.append(gate)
	match str(level.id):
		"1-1": base = base.filter(func(t: Dictionary) -> bool: return t.z != 1)
		"1-4":
			var handle: Dictionary = _find_tile(cell(-3, 0), level.tiles)
			var holder: Dictionary = _find_tile(str(state.actors.luvie), base)
			var holding: bool = flag("hold") and not handle.is_empty() and not holder.is_empty() and holder.h == handle.h and _distance(holder, handle) <= 1
			if flag("latch") or holding:
				_line(base, [-2, 0], [2, 0])
			if flag("latch") or state.actors.buddy == cell(3, 5):
				_line(base, [-3, 1], [-3, 4])
		"2-1":
			if state.water != 0: base = base.filter(func(t: Dictionary) -> bool: return t.z < 2)
			if state.water == 0: _add(base, -2, 0)
			if state.water == 1 and flag("care"): _add(base, 2, 0, 1)
			if state.water == 2: _add(base, 0, -2, 2)
		"2-2":
			if not beam_hits(4, 0): base = base.filter(func(t: Dictionary) -> bool: return not (t.z == 0 and t.x >= 3))
		"2-3":
			if flag("latch"):
				for z: int in range(-1, -5, -1): _add(base, -4, z, round(float(-z - 1) * 2.0 / 3.0))
				_line(base, [-4, -4], [0, -4], 2)
		"2-4":
			_add(base, -2 if int(state.turns.get("boat", 0)) % 2 == 0 else 8, 0)
			if not flag("pollinated"): base = base.filter(func(t: Dictionary) -> bool: return t.x < 9)
		"3-1":
			if flag("window") or lamp_at_receiver(): _line(base, [-2, 0], [2, 0])
		"3-2":
			for mode: int in [0, 1]:
				if state.mode == mode or state.frozen == mode:
					var points: Array = state.shadowMemory if state.frozen == mode and state.has("shadowMemory") else projection(mode)
					for i: int in range(points.size()):
						var id: String = ("shadow:sun" if i == 0 else "shadow:sun:2") if mode == 0 else "shadow:moon:%d" % (i + 1)
						_add(base, points[i].x, points[i].z, points[i].h, "shadow", false, id)
	if level.id in ["3-3", "3-4"]:
		if connected() or flag("root"):
			if level.id == "3-3": _add(base, 4, -2)
			else:
				_add(base, 4, -3)
				_add(base, 4, -2)
		if int(state.turns.get("lift", 0)) % 2: _add(base, 6, 0, 2)
		if level.id == "3-3" and flag("root") and state.turns.get("water", 0) == 1 and int(state.turns.get("lift", 0)) % 2:
			_line(base, [4, 1], [4, 2], 2)
			_line(base, [4, 2], [0, 2], 2)
			_add(base, 0, 3, 2, "shadow")
		if level.id == "3-4":
			if flag("root"):
				_line(base, [0, -4], [-4, -4])
				for z: int in range(-3, 1): _add(base, -4, z)
			_add(base, 8, 2, 2)
			if flag("star"): _line(base, [8, 2], [8, 3], 2)
	for module: Dictionary in level.modules:
		for local: Array in module.shape:
			if level.id == "3-3" and module.id == "lift" and local[0] == -1 and local[1] == 0 and not flag("root"):
				continue
			var tile: Dictionary = module_point(module.id, local)
			tile.merge({"id": module_cell(module.id, local[0], local[1]), "kind": "module", "module": module.id, "local": local})
			if module.has("small"): tile.small = module.small
			base.append(tile)
	for root: Dictionary in level.roots:
		for id: String in state.growth.get(root.id, []):
			var tile: Dictionary = _growth_point(id, root.h)
			if not tile.is_empty(): base.append(tile)
	var coords: Dictionary = {}
	for tile: Dictionary in base:
		var key: String = "%s,%s,%s" % [_number_key(tile.x), _number_key(tile.z), _number_key(tile.h)]
		var occupied: bool = tile.id in state.actors.values()
		for item: Dictionary in state.items.values():
			if item.tile == tile.id: occupied = true
		if not coords.has(key) or occupied: coords[key] = tile
	return coords.values()

static func _number_key(value: float) -> String:
	return str(int(value)) if value == floor(value) else str(value)

func rays() -> Array:
	if not level.id in ["2-2", "3-4"]: return []
	var x: int = 0 if level.id == "2-2" else 8
	var z: int = 1 if level.id == "2-2" else 4
	var dx: int = 1 if level.id == "2-2" else 0
	var dz: int = 0 if level.id == "2-2" else -1
	var height: int = 0 if level.id == "2-2" else 2
	var result: Array = [{"x": x, "z": z, "h": height}]
	if level.id == "3-4" and state.turns.get("light", 0) != 1: return result
	var seen: Dictionary = {}
	for unused: int in range(48):
		x += dx
		z += dz
		var key: String = "%d,%d,%d,%d" % [x, z, dx, dz]
		if seen.has(key): break
		seen[key] = true
		result.append({"x": x, "z": z, "h": height})
		if (level.id == "2-2" and x == 4 and z == 0) or (level.id == "3-4" and x == -4 and z == 0): break
		if [x, z] in level.get("walls", []): break
		for name: String in state.items:
			var item: Dictionary = state.items[name]
			if name.begins_with("mirror") and item.get("holder", "") == "" and item.tile != "":
				var p: Dictionary = _raw_item_point(item.tile)
				if not p.is_empty() and p.x == x and p.z == z and p.h == height:
					var old_dx: int = dx
					dx = -dz if int(item.angle) % 2 else dz
					dz = -old_dx if int(item.angle) % 2 else old_dx
					break
		if x < -6 or x > 15 or z < -7 or z > 12: break
	return result

func _raw_item_point(id: String) -> Dictionary:
	var parts: PackedStringArray = id.split(":")
	if parts.size() == 4 and parts[0] == "m": return module_point(parts[1], [int(parts[2]), int(parts[3])])
	if parts.size() == 3 and parts[0] == "f":
		var existing: Dictionary = _find_tile(id, level.tiles)
		return existing if not existing.is_empty() else {"x": int(parts[1]), "z": int(parts[2]), "h": 0}
	return {}

func beam_hits(x: float, z: float) -> bool:
	for p: Dictionary in rays():
		if p.x == x and p.z == z: return true
	return false

func projection(mode: int) -> Array:
	var item: Dictionary = state.items.get("sunPost" if mode == 0 else "moonPost", {})
	if item.is_empty() or item.get("holder", "") != "" or item.tile == "": return []
	var p: Dictionary = _raw_item_point(item.tile)
	if p.is_empty(): return []
	return [{"x": p.x + 1, "z": p.z, "h": 0}, {"x": p.x + 2, "z": p.z, "h": 0}] if mode == 0 else [{"x": p.x - 1, "z": p.z + 2, "h": 0}, {"x": p.x - 1, "z": p.z + 3, "h": 0}]

func lamp_ray() -> Array:
	var lamp: Dictionary = state.items.get("lamp", {})
	if lamp.is_empty(): return []
	var p: Dictionary = _raw_item_point(str(state.actors[lamp.holder]) if lamp.get("holder", "") != "" else lamp.tile)
	if p.is_empty(): return []
	var direction: Array = DIRECTIONS.values()[int(lamp.angle) % 4]
	var result: Array = [p]
	for i: int in range(1, 9):
		var target: Dictionary = {"x": p.x + direction[0] * i, "z": p.z + direction[1] * i, "h": p.h}
		result.append(target)
		if not flag("window") and target.x == 3 and target.z == 2: break
	return result

func lamp_at_receiver() -> bool:
	for p: Dictionary in lamp_ray():
		if p.x == 3 and p.z == 3: return true
	return false

func visible(tile: Dictionary) -> bool:
	if level.id != "3-1" or flag("window") or tile.id in state.get("discovered", []): return true
	var world_tiles: Array = tiles()
	for id: String in state.actors.values():
		var position: Dictionary = _find_tile(id, world_tiles)
		if not position.is_empty() and _distance(position, tile) <= 2: return true
	for p: Dictionary in lamp_ray():
		if _distance(p, tile) <= 1: return true
	return false

func neighbors(id: String, who: String = "", world_tiles: Array = []) -> Array:
	if who == "": who = actor()
	if world_tiles.is_empty(): world_tiles = tiles()
	var p: Dictionary = _find_tile(id, world_tiles)
	if p.is_empty(): return []
	var result: Array = []
	for tile: Dictionary in world_tiles:
		if not tile.get("solid", false) and not (who == "luvie" and tile.get("small", false)) and _distance(p, tile) == 1 and absf(float(p.h - tile.h)) <= 1:
			result.append(tile)
	return result

func _route_to(id: String, who: String = "") -> Variant:
	if who == "": who = actor()
	var world_tiles: Array = tiles()
	var queue: Array = [[state.actors[who], []]]
	var seen: Dictionary = {state.actors[who]: true}
	var index: int = 0
	while index < queue.size():
		var current: Array = queue[index]
		index += 1
		if current[0] == id: return current[1]
		for tile: Dictionary in neighbors(current[0], who, world_tiles):
			if not seen.has(tile.id):
				seen[tile.id] = true
				queue.append([tile.id, current[1] + [tile.id]])
	return null

func path_to(id: String, who: String = "") -> Array:
	var route: Variant = _route_to(id, who)
	return route if route is Array else []

func has_path_to(id: String, who: String = "") -> bool:
	return _route_to(id, who) != null

func near(id: String, who: String = "", world_tiles: Array = []) -> bool:
	if who == "": who = actor()
	if world_tiles.is_empty(): world_tiles = tiles()
	var p: Dictionary = _find_tile(str(state.actors[who]), world_tiles)
	var q: Dictionary = _find_tile(id, world_tiles)
	return not p.is_empty() and not q.is_empty() and absf(float(p.h - q.h)) <= 0.1 and _distance(p, q) <= 1

func together(world_tiles: Array = []) -> bool:
	var a: Dictionary = point_for(str(state.actors.luvie), world_tiles)
	var b: Dictionary = point_for(str(state.actors.buddy), world_tiles)
	return not a.is_empty() and not b.is_empty() and _distance(a, b) <= 1 and a.h == b.h

func move(id: String) -> Dictionary:
	if state.playing or _find_tile(id, neighbors(str(state.actors[actor()]))).is_empty():
		return {"ok": false, "message": "这里尚未接通，看看地面、高度与庭院的朝向。"}
	return _transaction(func() -> String:
		state.actors[actor()] = id
		if actor() == "luvie": state.flags = state.flags.filter(func(value: Variant) -> bool: return value != "hold")
		if state.follow:
			var other: String = "buddy" if actor() == "luvie" else "luvie"
			var path: Array = path_to(id, other)
			if not path.is_empty(): state.actors[other] = path[0]
		return "石板记住了两双小脚印。"
	)

func _fail(message: String) -> String:
	_error = message
	return ""

func _transaction(change: Callable) -> Dictionary:
	var before: Dictionary = snapshot()
	_error = ""
	var message: String = change.call()
	if _error == "":
		var world_tiles: Array = tiles()
		for who: String in ACTORS:
			var tile: Dictionary = _find_tile(str(state.actors[who]), world_tiles)
			if tile.is_empty() or tile.get("solid", false) or (who == "luvie" and tile.get("small", false)):
				_error = "这次变化会收走脚下的路，先把两位旅人带到安全台。"
				break
		if _error == "":
			for item: Dictionary in state.items.values():
				if item.tile != "" and item.get("holder", "") == "" and _find_tile(item.tile, world_tiles).is_empty():
					_error = "先把关键物件放到安全台，再改变这段路。"
					break
	if _error != "":
		state = before
		return {"ok": false, "message": _error}
	_update_outcomes()
	_collect()
	state = snapshot()
	_history.append(before)
	if _history.size() > 400: _history.pop_front()
	return {"ok": true, "message": message}

func _collect() -> void:
	for collection: Dictionary in level.collectibles:
		if not collection.id in state.collected and collection.tile in state.actors.values(): state.collected.append(collection.id)
	if level.id == "3-1":
		var seen: Array = state.get("discovered", []).duplicate()
		for tile: Dictionary in tiles():
			if visible(tile) and not tile.id in seen: seen.append(tile.id)
		state.discovered = seen

func _update_outcomes() -> void:
	if level.id != "3-4": return
	if connected(): _set_flag("root")
	if flag("root") and state.turns.water == 1: _set_flag("rain")
	if flag("rain") and state.items.mirror.tile == cell(8, 0) and beam_hits(-4, 0): _set_flag("star")
	if flag("star") and together() and near(cell(-4, 0), "luvie"): _set_flag("moon")
	for f: String in ["root", "rain", "star", "moon"]:
		if flag(f):
			for i: int in range(2):
				var id: String = "gift-%s-%d" % [f, i]
				if not id in state.collected: state.collected.append(id)

func ready() -> bool:
	match str(level.id):
		"1-1", "1-2": return connected()
		"1-3": return true
		"1-4": return flag("latch") and flag("home") and together()
		"2-1": return flag("care") and state.water == 1
		"2-2": return beam_hits(4, 0)
		"2-3": return flag("latch") and together()
		"2-4": return flag("pollinated")
		"3-1": return flag("window") and together() and state.items.lamp.get("holder", "") != ""
		"3-2": return (state.mode == 0 or state.frozen == 0) and (state.mode == 1 or state.frozen == 1)
		"3-3": return flag("root") and state.turns.water == 1 and int(state.turns.lift) % 2 == 1
		"3-4": return flag("root") and flag("rain") and flag("star") and flag("moon") and state.turns.inner == 1 and state.turns.water == 1 and beam_hits(-4, 0) and together()
	return false

func commands() -> Array:
	var result: Array = []
	# This method is a pure query. Reuse one private board for its spatial lookups only.
	# No board survives this call, crosses an action, or changes tiles()' independent results.
	var world_tiles: Array = tiles()
	if state.completed:
		if level.get("dual", false): result.append_array([{"id": "switch", "label": "换手看看花园"}, {"id": "follow", "label": "关闭自动同行" if state.follow else "沿小路一起走", "selected": state.follow}])
		for mark: Dictionary in level.marks:
			if mark.kind in ["rest", "observe"] and near(mark.tile, "", world_tiles): result.append({"id": "observe:" + mark.id, "label": mark.label})
		return result
	var near_core: bool = false
	for mark: Dictionary in level.marks:
		if mark.kind == "core" and near(mark.tile, "", world_tiles): near_core = true
	if actor() == "luvie" and state.follow and not together(world_tiles) and near_core and not path_to(str(state.actors.luvie), "buddy").is_empty(): result.append({"id": "rejoin", "label": "等伙伴沿路跟上"})
	if level.get("dual", false):
		result.append({"id": "switch", "label": "换手：操控小苔灵" if actor() == "luvie" else "换手：操控露薇"})
		result.append({"id": "follow", "label": "各自等候" if state.follow else "一起走（需要连通）", "selected": state.follow})
	for root: Dictionary in level.roots:
		if near(root.at, "", world_tiles) and actor() == "luvie":
			var path: Array = state.growth[root.id]
			var end: Dictionary = _growth_point(str(path.back()), root.h) if not path.is_empty() else point_for(root.at, world_tiles)
			for direction: String in DIRECTIONS:
				var x: float = end.x + DIRECTIONS[direction][0]
				var z: float = end.z + DIRECTIONS[direction][1]
				var target: String = "g:%s:%d:%d" % [root.id, int(x), int(z)]
				if path.size() < root.budget and _socket(root, x, z) and not target in path: result.append({"id": "grow:%s:%s" % [root.id, direction], "label": "引芽 %s · 余%d" % [{"up": "↑", "right": "→", "down": "↓", "left": "←"}[direction], budget()], "target": target})
			if not path.is_empty() and not flag("root"): result.append({"id": "retract:" + root.id, "label": "收回最后一节芽"})
	for mark: Dictionary in level.marks:
		if not near(mark.tile, "", world_tiles): continue
		var own: Dictionary = {}
		for module: Dictionary in level.modules:
			if module_cell(module.id) == mark.tile: own = module
		if mark.kind == "turn" and not own.is_empty(): result.append({"id": "turn:" + own.id, "label": "移动整座花园 ⇄" if own.kind == "slide" else "连人带庭院转90° ↻"})
		if mark.kind == "valve":
			var label: String = "花阀：安全下降 ↓" if int(state.turns.get("lift", 0)) % 2 else "花阀：上升 ↑"
			if mark.id == "mode": label = "切换日／月"
			elif level.id == "2-1": label = "水位：%s → %s" % [["低", "中", "高"][int(state.water)], ["低", "中", "高"][(int(state.water) + 1) % 3]]
			elif own.get("kind") == "rotate": label = "转动沟槽与庭院 ↻"
			result.append({"id": "valve:" + mark.id, "label": label})
		if mark.kind == "lever" and actor() == "luvie": result.append({"id": "use:" + mark.id, "label": "保持拉杆 · 换小苔灵过桥" if mark.id == "hold" and flag("hold") else "已经安定了" if flag(mark.id) else mark.label})
		if mark.kind == "latch" and actor() == "luvie" and not flag("latch"): result.append({"id": "use:latch", "label": mark.label})
		if mark.kind == "flower" and mark.id in ["care", "home", "plant", "invite"] and not (mark.id == "home" and flag("home")): result.append({"id": "use:" + mark.id, "label": mark.label})
		if mark.id == "freeze": result.append({"id": "freeze", "label": "留影苔：固定当前投影"})
		if mark.kind == "core" and actor() == "luvie": result.append({"id": "repair", "label": "一起种下微光 ✧"})
		if mark.kind in ["rest", "observe"]: result.append({"id": "observe:" + mark.id, "label": mark.label})
		if mark.kind == "song":
			for i: int in range(2): result.append({"id": "swap:%d" % i, "label": "交换第%d、%d片动作叶" % [i + 1, i + 2]})
			result.append_array([{"id": "play", "label": "暂停试奏" if state.playing else "开始／继续试奏"}, {"id": "beat", "label": "单步试奏下一拍"}, {"id": "resetSong", "label": "重新排练（恢复试奏前）"}])
	for id: String in state.items:
		var item: Dictionary = state.items[id]
		if item.get("holder") == actor():
			var slot: Dictionary = {}
			for mark: Dictionary in level.marks:
				if mark.kind == "slot" and near(mark.tile, "", world_tiles):
					slot = mark
					break
			var label: String = "放在脚边的固定地面" if slot.is_empty() else "放入②号镜叶光槽" if level.id == "2-2" else "放到" + str(slot.label)
			result.append({"id": "drop:%s:%s" % [id, slot.get("tile", state.actors[actor()])], "label": label})
			if id.begins_with("mirror") or id == "lamp": result.append({"id": "angle:" + id, "label": "把灯转90°" if id == "lamp" else "转动手中的反光叶"})
		elif item.get("holder", "") == "" and item.tile != "" and near(item.tile, "", world_tiles) and id != "bug":
			if id != "mirrorA" and (actor() == "luvie" or id == "lamp"):
				var label: String = "提起暖灯" if id == "lamp" else "搬起日月影柱" if id.ends_with("Post") else "搬起反光叶" if id.begins_with("mirror") else "接住露珠" if id == "dew" else "收好门铃"
				result.append({"id": "take:" + id, "label": label})
			if id.begins_with("mirror"): result.append({"id": "angle:" + id, "label": "转动%s号镜叶" % ("①" if id == "mirrorA" else "②") if level.id == "2-2" else "转动反光叶朝向"})
	if level.id == "2-3" and state.get("trial", "") != "" and not flag("latch"): result.append_array([{"id": "play", "label": "暂停试奏" if state.playing else "继续试奏"}, {"id": "resetSong", "label": "重新排练（恢复试奏前）"}])
	var unique: Dictionary = {}
	for command: Dictionary in result: unique[command.id] = command
	return unique.values()

func act(id: String, quiet: bool = false) -> Dictionary:
	if state.completed and not id in ["switch", "follow"] and not id.begins_with("observe:"): return {"ok": false, "message": "花园已经安定了，留下看看吧。"}
	var offered: bool = false
	for command: Dictionary in commands():
		if command.id == id: offered = true
	if not quiet and not offered: return {"ok": false, "message": "走近操作点，或换一位旅人试试。"}
	return _transaction(func() -> String: return _apply(id))

func _apply(id: String) -> String:
	var parts: PackedStringArray = id.split(":")
	if id == "switch":
		state.active = "buddy" if actor() == "luvie" else "luvie"
		state.follow = false
		return "换你来帮我啦。另一位会留在原地安心等候。"
	if id == "rejoin":
		var path: Array = path_to(str(state.actors.luvie), "buddy")
		if path.is_empty(): return _fail("伙伴身旁的路还没有接通，先换手看看。")
		state.actors.buddy = path[0]
		return "小苔灵沿石板靠近你，一起把微光种下。"
	if id == "follow":
		if not state.follow and not has_path_to(str(state.actors[actor()]), "buddy" if actor() == "luvie" else "luvie"): return _fail("两位之间还没有路，先接上归途。")
		state.follow = not state.follow
		return "一起慢慢走。" if state.follow else "各自站好，再安排一次配合。"
	if id.begins_with("grow:"):
		var root: Dictionary = {}
		for candidate: Dictionary in level.roots:
			if candidate.id == parts[1]: root = candidate
		if root.is_empty(): return _fail("先走近一点，再看看能帮什么忙。")
		var path: Array = state.growth[parts[1]]
		var p: Dictionary = _growth_point(str(path.back()), root.h) if not path.is_empty() else point_for(root.at)
		if level.id == "3-3" and not state.turns.water in [0, 3] and not flag("root"): return _fail("藤根还没接到水，先把沟槽转向北侧。")
		var direction: Array = DIRECTIONS[parts[2]]
		path.append("g:%s:%d:%d" % [root.id, int(p.x + direction[0]), int(p.z + direction[1])])
		return "根须托起一节石板，你安排的小路正在生长。"
	if id.begins_with("retract:"):
		state.growth[parts[1]].pop_back()
		return "叶片合拢休息，可以重新安排方向。"
	if id.begins_with("turn:"):
		var period: int = 4
		for module: Dictionary in level.modules:
			if module.id == parts[1] and module.kind == "slide": period = 2
		state.turns[parts[1]] = (int(state.turns[parts[1]]) + 1) % period
		return "整座庭院托着旅人转向远方。看看出口、水与光的位置。"
	if id.begins_with("valve:"):
		var key: String = parts[1]
		if key == "mode": state.mode = 1 if state.mode == 0 else 0
		elif level.id == "2-1": state.water = (int(state.water) + 1) % 3
		elif key == "water": state.turns.water = (int(state.turns.water) + 1) % 4
		else:
			if int(state.turns.lift) % 2 == 0 and level.id == "3-3" and not state.turns.water in [0, 1]: return _fail("花台没有上升动力，但随时可以安全下降。")
			if level.id == "3-4" and int(state.turns.lift) % 2 == 0 and not flag("rain"): return _fail("请小苔灵去送水庭，把水接向花台。")
			state.turns.lift = (int(state.turns.lift) + 1) % 2
		return "水位与落岸变化了，脚下的旅人和物件也一起移动。"
	if id == "freeze":
		var points: Array = projection(int(state.mode))
		if points.is_empty(): return _fail("先把当前光照对应的影柱放到槽中，再留影。")
		state.frozen = state.mode
		state.shadowMemory = points
		return "留影苔记住了这段实际投影，再换一个时刻看看。"
	if id.begins_with("take:"):
		for item: Dictionary in state.items.values():
			if item.get("holder") == actor(): return _fail("一次带一件，先把随身的物品放好。")
		state.items[parts[1]].holder = actor()
		state.items[parts[1]].tile = ""
		if id == "take:dew":
			state.items.dew.picked = true
			return "用柔软的叶片包好清露，收进贴身的小挎袋。"
		return "把门铃收进小挎袋，带回鼹鼠的家。" if id == "take:bell" else "稳稳带好了，沿接通的路继续走吧。"
	if id.begins_with("drop:"):
		var target: String = ":".join(parts.slice(2))
		if point_for(target).get("kind") == "root": return _fail("先把关键物件放到固定台或庭院上的放置槽。")
		state.items[parts[1]].tile = target
		state.items[parts[1]].erase("holder")
		return "稳稳放好了，看看光与道路有没有一起改变。"
	if id.begins_with("angle:"):
		state.items[parts[1]].angle = (int(state.items[parts[1]].angle) + 1) % (4 if parts[1] == "lamp" else 2)
		return "叶片转向了，光沿实际方向前进。"
	if id == "use:hold":
		_set_flag("hold")
		return "露薇扳住重杆。换小苔灵走过短桥与低拱吧。"
	if id == "use:latch":
		_set_flag("latch")
		return "归途固定了，两位可以沿真实的路重新会合。"
	if id == "use:window":
		if not lamp_at_receiver(): return _fail("先让小苔灵把灯带到照孔，朝上照亮接收叶。")
		_set_flag("window")
		return "石窗打开，灯井学会自己发光了。现在把伙伴与暖灯接回来。"
	if id == "use:home":
		if state.items.bell.get("holder") != "luvie": return _fail("门铃还在内庭，带回来给鼹鼠吧。")
		state.items.bell.erase("holder")
		state.items.bell.tile = ""
		_set_flag("home")
		return "门铃响了，花门打开了！接上小苔灵，沿花径去小花园中央种下微光吧。"
	if id == "use:care":
		if state.items.dew.get("holder") != actor(): return _fail("先带回一滴清露，再把它留给花心。")
		state.items.dew.erase("holder")
		state.items.dew.tile = ""
		_set_flag("root" if level.id == "3-3" else "care")
		return "被照顾的根系学会蓄水，留下了一条安定的路。"
	if id == "use:plant":
		_set_flag("plant")
		return "蜜花展开了，光虫有了安心停脚的地方。"
	if id == "use:invite":
		if not flag("plant"): return _fail("先种一朵蜜花，再邀请光虫。")
		if not state.turns.boat:
			if state.items.bug.tile == cell(-4, 0): state.items.bug.tile = module_cell("boat")
			else: return _fail("光虫已经在花园里，载它去另一岸吧。")
		else:
			if state.items.bug.tile != module_cell("boat"): return _fail("还没有接上光虫，先把花园移回花粉岸。")
			state.items.bug.tile = cell(10, 0)
			_set_flag("pollinated")
		return "小花园载着光虫，把花粉送到了新的家。"
	if id.begins_with("observe:"):
		if not parts[1] in state.observations: state.observations.append(parts[1])
		for mark: Dictionary in level.marks:
			if mark.id == parts[1]: return str(mark.get("text", level.story))
		return str(level.story)
	if id.begins_with("swap:"):
		if state.beat or state.playing: return _fail("先重新排练，再换动作叶的位置。")
		var n: int = int(parts[1])
		var first: String = state.song[n]
		state.song[n] = state.song[n + 1]
		state.song[n + 1] = first
		return "叶片换好位置了，试试顺序会带来什么不同。"
	if id == "resetSong":
		if state.get("trial", "") != "":
			var trial: Dictionary = JSON.parse_string(state.trial)
			var collections: Array = state.collected.duplicate()
			var observations: Array = state.observations.duplicate()
			state = trial
			state.collected = _unique(trial.collected + collections)
			state.observations = observations
			state.playing = false
			state.beat = 0
			state.erase("trial")
		return "回到试奏前，两位和庭院都稳稳站好了。"
	if id in ["play", "beat"]:
		if state.get("trial", "") == "":
			var trial: Dictionary = snapshot()
			trial.erase("trial")
			state.trial = JSON.stringify(trial)
		if id == "play":
			state.playing = not state.playing
			return "雨歌开始，一拍一拍看花园怎样变化。" if state.playing else "暂停试奏，慢慢看看下一片叶。"
		if state.beat >= 3:
			state.playing = false
			return "短句已经演奏完了，可以到岸边固定便道，或重新排练。"
		var note: String = state.song[int(state.beat)]
		state.beat += 1
		if note == "turn" and not flag("raised"): state.turns.stage = (int(state.turns.stage) + 1) % 4
		if note == "rise": _set_flag("raised")
		if state.beat >= 3: state.playing = false
		return "高处限位挡住了转轴。可以重新排练，试试先转后升。" if note == "turn" and flag("raised") else "第%d拍：%s。" % [int(state.beat), {"turn": "转庭", "rise": "升台", "rest": "停拍"}[note]]
	if id == "repair":
		if not ready(): return _fail(str(hint().message))
		if not together(): return _fail("沿真正接通的路，把另一位旅人带到花床旁，一起种下微光。")
		state.completed = true
		state.playing = false
		return str(level.story)
	return _fail("先走近一点，再看看能帮什么忙。")

func hint() -> Dictionary:
	if state.completed: return {"message": level.story}
	var message: String = str(level.intro)
	match str(level.id):
		"1-1": message = "走近根台，向右引一节芽，沿石板到花床，再种下微光。"
		"1-2": message = "从根台向上绕：上、右、右、下；或从下方对称绕行。四节芽都要连续。"
		"1-3": message = "进入庭院中心，连人带花园转90°。原来的西口会接向北岸。"
		"1-4": message = "露薇在外庭扳住重杆；换小苔灵过桥穿低拱，到轻踏板；再换露薇过南门固定门闩。" if not flag("latch") else "露薇取回内庭的门铃，带到鼹鼠家门。交还铃铛后，花门就会打开。" if not flag("home") else "接上小苔灵，穿过鼹鼠旁已打开的花门，到小花园中央一起播种。"
		"2-1": message = "保持低水位，走南侧石阶取清露，回浮台把露珠留给花心。" if not flag("care") else "水位调到中位，浮台会接上右侧花岸；高位通往可选芦苇湾。"
		"2-2": message = str(mirror_guidance().get("message", level.intro))
		"2-3": message = "露薇走上花台，小苔灵留在琴台。转庭必须先于升台；可以单步试奏。" if not flag("raised") else "正确朝向应向北。若先升后转，重新排练；到北岸后固定便道。" if not flag("latch") else "固定便道已经打开，操控小苔灵走回露薇身边，再播种。"
		"2-4": message = "走上移动花园种蜜花，再在靠近左岸时邀请光虫。" if not flag("plant") else "把花园停近左岸，邀请光虫落在蜜花上。" if state.items.bug.tile != module_cell("boat") and not flag("pollinated") else "载光虫一起移到右岸，再邀请它飞向核心花岸授粉。" if not flag("pollinated") else "远岸成熟了，沿接上的石板过去，一起播种。"
		"3-1": message = "让小苔灵提灯穿南侧低通道，到右下照孔，灯朝上；露薇穿门后移开石窗。" if not flag("window") else "灯井已经自亮，提灯沿低通道回来。两人带灯在核心旁会合。"
		"3-2": message = "露薇搬起左岸日影柱，放到起点日影槽(0,0)，先接上去中台的路。" if state.items.sunPost.tile != cell(0, 0) else "把左岸月影柱带过日影路，放在右上月影槽(3,-1)，再回起点。" if state.items.moonPost.tile != cell(3, -1) else "固定日影再切月光；或先固定月影再切日光。留影保存的是当时的实际形状。"
		"3-3": message = "保持分水庭0°，沿北口去藤根，引芽：右、右、右、下，接往花台。" if not connected() else "乘东侧花台上升取露珠，降回藤根，把露珠留给它。" if not flag("root") else "藤根已经自给，转分水庭到90°，水同时去花台与苔藓。沿固定根阶再升高，走南侧影路。"
		"3-4": message = "从内庭北口到根台，引芽向右三节，固定叶阶。" if not flag("root") else "小苔灵沿南侧低拱去送水庭，转90°接水；露薇搬起北台重镜叶，走上花台。" if not flag("rain") else "露薇带镜叶升高，放在右岸高槽。沿右侧石阶到外庭，将光源转90°朝北。" if not flag("star") else "把内庭转到90°，接上花台到藤根的回流通路。" if state.turns.inner != 1 else "把送水庭恢复到90°，继续给花台供水。" if state.turns.water != 1 else "保持高槽镜叶与外庭朝向，让光实际到达西侧核心。" if not beam_hits(-4, 0) else "切换角色，沿已经固定的归途，让两位在西岸会合。" if not together() else "路、水与光都已相连，一起种下微光吧。"
	return {"message": message}

func mirror_guidance() -> Dictionary:
	if level.id != "2-2" or state.completed: return {}
	var a: Dictionary = state.items.mirrorA
	var b: Dictionary = state.items.mirrorB
	var slot: Dictionary = {}
	var core: Dictionary = {}
	var source: Dictionary = {}
	for mark: Dictionary in level.marks:
		if mark.id == "slot": slot = mark
		if mark.kind == "core": core = mark
		if mark.id == "source": source = mark
	var result: Dictionary = {"route": [_find_tile(source.tile, level.tiles), _find_tile(a.tile, level.tiles), _find_tile(slot.tile, level.tiles), _find_tile(core.tile, level.tiles)]}
	if b.get("holder", "") != "": result.merge({"stage": "place", "tile": slot.tile, "action": "drop:mirrorB:" + slot.tile, "label": "把镜叶放到这里", "message": "跟着箭头到发光的叶形槽，走近后点「放入镜叶」。"})
	elif b.tile != slot.tile: result.merge({"stage": "take", "tile": b.tile, "action": "take:mirrorB", "label": "先搬这片镜叶", "message": "先走近发光的反光叶，点「搬起镜叶」，再带到叶形光槽。"})
	elif int(a.angle) % 2 != 1: result.merge({"stage": "turn-a", "tile": a.tile, "action": "angle:mirrorA", "label": "转动①，让光向上", "message": "走近①号镜叶，点「转动镜叶」；让光从这里向上折向②。"})
	elif int(b.angle) % 2 != 1: result.merge({"stage": "turn-b", "tile": b.tile, "action": "angle:mirrorB", "label": "转动②，让光向右", "message": "走近②号镜叶，点「转动镜叶」；让光向右照到花床。"})
	else: result.merge({"stage": "plant", "tile": core.tile, "action": "repair", "label": "光已接通，去花床", "message": "两片镜叶已经接通光路。和小苔灵到发光花床旁，一起种下微光。"})
	return result
