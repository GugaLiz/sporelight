extends "res://core/garden_world.gd"
## Cloud gardens use the same spatial, interaction and rendering contract as the
## mainline. The original cloud rules and discovery text are retained.
const CLOUD_IDS := ["cloud-1", "cloud-2", "cloud-3"]
static var _cloud_definitions: Array = []

func _init(level_id: String = "cloud-1", saved: Dictionary = {}) -> void:
	if _cloud_definitions.is_empty():
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json"))
		_cloud_definitions = parsed.get("levels", [])
	level = _cloud_definitions[0].duplicate(true)
	for definition: Dictionary in _cloud_definitions:
		if definition.id == level_id:
			level = definition.duplicate(true)
			break
	state = {"designVersion": 2, "levelId": level.id, "active": "luvie",
		"actors": {"luvie": level.start, "buddy": level.start}, "follow": level.id != "cloud-1",
		"growth": {}, "turns": {"bridge": 1 if level.id == "cloud-3" else 0, "lift": 0},
		"flags": [], "items": {}, "collected": [], "observations": [], "discovered": [],
		"water": 0, "mode": 0, "frozen": null, "song": ["turn", "rise", "rest"],
		"beat": 0, "playing": false, "completed": false,
		"cloudSeed": false, "cloudLatch": false, "cloudBuddy": "sleep" if level.id == "cloud-1" else "follow"}
	_history.clear()
	if level.id == "cloud-1":
		state.actors.buddy = "floor:10:3"
	if not saved.is_empty():
		var normalized := _cloud_normalize(saved)
		if normalized.get("ok", false):
			state = normalized.snapshot

func fork(saved: Dictionary) -> RefCounted:
	return get_script().new(str(level.id), saved)

func normalize_saved(saved: Dictionary) -> Dictionary:
	return _cloud_normalize(saved)

func _cloud_normalize(saved: Dictionary) -> Dictionary:
	if saved.get("levelId") != level.id:
		return {"ok": false}
	var result: Dictionary = snapshot()
	if saved.get("version") == 1:
		if not saved.get("tile") is String:
			return {"ok": false}
		result.actors.luvie = saved.tile
		result.actors.buddy = saved.tile
		if level.id == "cloud-1" and saved.get("buddy", "sleep") == "sleep":
			result.actors.buddy = "floor:10:3"
		result.turns.bridge = 1 if saved.get("bridge") == "east" else 0
		result.turns.lift = 1 if saved.get("lift") == "high" else 0
		result.cloudSeed = saved.get("seed") == true
		result.cloudLatch = saved.get("latch") == true
		result.cloudBuddy = str(saved.get("buddy", result.cloudBuddy))
		result.observations = saved.get("found", []).duplicate() if saved.get("found") is Array else []
		result.completed = saved.get("repaired") == true
	elif saved.get("designVersion") == 2:
		if not saved.get("actors") is Dictionary or not saved.get("turns") is Dictionary:
			return {"ok": false}
		for field: String in ["cloudSeed", "cloudLatch", "completed"]:
			if not saved.get(field) is bool:
				return {"ok": false}
			result[field] = saved[field]
		result.actors = saved.actors.duplicate(true)
		for who: String in ACTORS:
			if not result.actors.get(who) is String:
				return {"ok": false}
		for field: String in ["bridge", "lift"]:
			var value: Variant = saved.turns.get(field)
			if not _integer(value) or not int(value) in [0, 1]:
				return {"ok": false}
			result.turns[field] = int(value)
		result.cloudBuddy = str(saved.get("cloudBuddy", result.cloudBuddy))
		result.observations = saved.get("observations", []).duplicate() if saved.get("observations") is Array else []
		if saved.get("runtime") is Dictionary:
			var runtime: Dictionary = saved.runtime
			if runtime.get("version") == 1 and runtime.get("poses") is Dictionary:
				for who: String in runtime.poses:
					var pose: Variant = runtime.poses[who]
					if not who in ACTORS or not pose is Dictionary or not pose.get("offset") is Array or pose.offset.size() != 3 or pose.get("support") != result.actors.get(who):
						return {"ok": false}
					for coordinate: Variant in pose.offset:
						if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 2.0:
							return {"ok": false}
				result.runtime = runtime.duplicate(true)
	else:
		return {"ok": false}
	if not result.cloudBuddy in ["sleep", "follow", "wait", "sit"]:
		return {"ok": false}
	if level.id != "cloud-3" and result.cloudBuddy == "wait":
		return {"ok": false}
	if level.id != "cloud-1" and result.cloudBuddy == "sleep":
		return {"ok": false}
	if not result.completed and result.cloudBuddy == "sit":
		result.cloudBuddy = "sleep" if level.id == "cloud-1" else "follow"
	var valid_found: Array = []
	for mark: Dictionary in level.marks:
		if mark.get("text", "") != "" and mark.id in result.observations:
			valid_found.append(mark.id)
	result.observations = valid_found
	result.collected = valid_found.duplicate()
	result.active = "luvie"
	result.follow = result.cloudBuddy == "follow"
	if result.completed:
		result.cloudBuddy = "sit"
		result.follow = false
		if level.id == "cloud-1":
			result.cloudSeed = true
		if level.id == "cloud-3":
			result.cloudLatch = true
	if result.cloudBuddy == "wait":
		result.actors.buddy = "floor:3:6"
	if result.get("runtime") is Dictionary:
		for who: String in result.runtime.get("poses", {}).keys():
			if result.runtime.poses[who].get("support") != result.actors.get(who):
				result.runtime.poses.erase(who)
	var prior: Dictionary = state
	state = result
	var valid := true
	for who: String in ACTORS:
		if point_for(str(result.actors.get(who, ""))).is_empty():
			valid = false
	if level.id == "cloud-3" and not result.cloudLatch and result.cloudBuddy != "wait":
		var at := point_for(str(result.actors.luvie))
		if not at.is_empty() and float(at.x) > 3:
			valid = false
	if valid and not result.completed:
		if level.id != "cloud-2" and not has_path_to(str(level.start), "luvie"):
			valid = false
		elif level.id == "cloud-2":
			var at := point_for(str(result.actors.luvie))
			if float(at.get("h", 0)) == 3 and int(result.turns.lift) == 0:
				valid = false
	state = prior
	return {"ok": true, "snapshot": result} if valid else {"ok": false}

func tiles() -> Array:
	var result: Array = []
	match str(level.id):
		"cloud-1":
			_rect(result, 0, 6, 3, 8, 0)
			_add_cloud(result, 3, 5, 0, "stair")
			_add_cloud(result, 3, 4, 1, "stair")
			_rect(result, 3, 2, 5, 3, 1)
			_add_cloud(result, 4, 4, 1)
			_add_cloud(result, 5, 4, 1)
			_rect(result, 3, -4, 5, -2, 1)
			_rect(result, 9, 2, 11, 4, 1)
			if int(state.turns.bridge) == 0:
				_rect(result, 4, -1, 4, 1, 1, "bridge")
			else:
				_rect(result, 6, 3, 8, 3, 1, "bridge")
		"cloud-2":
			_rect(result, 0, 6, 3, 8, 0)
			_rect(result, 3, 3, 5, 5, 0)
			_rect(result, 8, 3, 11, 5, 3)
			_rect(result, 6, 3, 7, 4, 0 if int(state.turns.lift) == 0 else 3, "lift")
		"cloud-3":
			_rect(result, 0, 6, 3, 8, 1)
			_rect(result, 7, 5, 9, 7, 1)
			_rect(result, 7, -1, 9, 1, 1)
			_rect(result, 13, 4, 14, 6, 1)
			if state.cloudLatch or state.cloudBuddy == "wait":
				_rect(result, 4, 6, 6, 6, 1, "gate")
			if int(state.turns.bridge) == 0:
				_rect(result, 8, 2, 8, 4, 1, "bridge")
			else:
				_rect(result, 10, 5, 12, 5, 1, "bridge")
	return result

func _rect(result: Array, x1: int, z1: int, x2: int, z2: int, height: int, kind: String = "floor") -> void:
	for x: int in range(x1, x2 + 1):
		for z: int in range(z1, z2 + 1):
			_add_cloud(result, x, z, height, kind)

func _add_cloud(result: Array, x: int, z: int, height: int, kind: String = "floor") -> void:
	result.append({"id": "%s:%d:%d" % [kind, x, z], "x": x, "z": z, "h": height, "kind": kind, "small": false})

func neighbors(id: String, who: String = "", world_tiles: Array = []) -> Array:
	if world_tiles.is_empty():
		world_tiles = tiles()
	var at: Dictionary = point_for(id, world_tiles)
	var result: Array = []
	if at.is_empty():
		return result
	for tile: Dictionary in world_tiles:
		if _distance(at, tile) == 1 and (float(at.h) == float(tile.h) or (absf(float(at.h) - float(tile.h)) == 1 and (at.kind == "stair" or tile.kind == "stair"))):
			result.append(tile)
	return result

func budget() -> int:
	return 0

func connected(_root: Dictionary = {}) -> bool:
	return ready()

func ready(_world_tiles: Array = []) -> bool:
	return bool(state.cloudSeed) if level.id == "cloud-1" else state.cloudBuddy == "follow" if level.id == "cloud-3" else true

func together(world_tiles: Array = []) -> bool:
	if level.id != "cloud-3" or state.completed:
		return true
	if state.cloudBuddy != "follow" or not super.together(world_tiles):
		return false
	var poses: Dictionary = state.get("runtime", {}).get("poses", {})
	if poses.has("luvie") and poses.has("buddy"):
		var a := point_for(str(state.actors.luvie))
		var b := point_for(str(state.actors.buddy))
		var left := Vector2(float(a.x) + float(poses.luvie.offset[0]), float(a.z) + float(poses.luvie.offset[2]))
		var right := Vector2(float(b.x) + float(poses.buddy.offset[0]), float(b.z) + float(poses.buddy.offset[2]))
		return left.distance_to(right) <= 1.1
	return true

func visible(_tile: Dictionary, _world_tiles: Array = []) -> bool:
	return true

func growth_guidance() -> Dictionary:
	return {}

func mirror_guidance() -> Dictionary:
	return {}

func rays() -> Array:
	return []

func projection(_mode: int) -> Array:
	return []

func lamp_ray() -> Array:
	return []

func _mark_near(mark: Dictionary) -> bool:
	var at := point()
	var h := 3 if mark.id == "valve" and int(state.turns.lift) == 1 else int(mark.h)
	return not at.is_empty() and float(at.h) == h and absf(float(at.x) - float(mark.x)) + absf(float(at.z) - float(mark.z)) <= 1

func commands() -> Array:
	var result: Array = []
	if state.completed:
		return result
	for mark: Dictionary in level.marks:
		if not _mark_near(mark):
			continue
		var id := str(mark.id)
		if mark.get("text", "") != "":
			if not id in state.observations:
				result.append({"id": "discover:" + id, "label": mark.label, "target": id})
			continue
		match id:
			"turn":
				if point().kind != "bridge":
					result.append({"id": "rotate", "label": "转向侧庭" if int(state.turns.bridge) == 0 else "转向远庭", "target": id})
			"seed":
				if not state.cloudSeed:
					result.append({"id": "seed", "label": mark.label, "target": id})
			"valve":
				if point().kind == "lift":
					result.append({"id": "lift", "label": "升起花台" if int(state.turns.lift) == 0 else "降下花台", "target": id})
			"dock":
				if point().kind != "lift" and int(state.turns.lift) == 1:
					result.append({"id": "lift", "label": "唤回花台", "target": id})
			"pad":
				if state.cloudBuddy == "follow":
					result.append({"id": "wait", "label": "请伙伴守住踏板", "target": id})
				elif state.cloudBuddy == "wait":
					result.append({"id": "call", "label": "接回小苔灵", "target": id})
			"latch":
				if not state.cloudLatch:
					result.append({"id": "latch", "label": mark.label, "target": id})
			"finish":
				result.append({"id": "repair", "label": mark.label, "target": id})
	if level.id == "cloud-2" and point().kind == "lift" and not result.any(func(command: Dictionary) -> bool: return command.id == "lift"):
		result.append({"id": "lift", "label": "升起花台" if int(state.turns.lift) == 0 else "降下花台", "target": "valve"})
	if state.cloudBuddy == "follow":
		result.append({"id": "pet", "label": "摸摸小苔灵", "target": "buddy"})
	return result

func act(id: String, _quiet: bool = false) -> Dictionary:
	if not commands().any(func(command: Dictionary) -> bool: return command.id == id):
		return {"ok": false, "message": "走近目标，再和它打个招呼。"}
	if id == "pet":
		return {"ok": true, "message": "小苔灵蹭了蹭你的手。"}
	return _transaction(func() -> String: return _cloud_apply(id))

func _cloud_apply(id: String) -> String:
	match id:
		"rotate":
			if point().kind == "bridge":
				return _fail("先走回固定庭院。")
			state.turns.bridge = 1 - int(state.turns.bridge)
			return "拱桥转向了另一座庭院。"
		"lift":
			state.turns.lift = 1 - int(state.turns.lift)
			return "花台升起。" if int(state.turns.lift) == 1 else "花台回到岸边。"
		"seed":
			state.cloudSeed = true
			return "花种收进了掌心。"
		"wait":
			state.cloudBuddy = "wait"
			state.follow = false
			state.actors.buddy = "floor:3:6"
			return "小苔灵守住踏板，拱廊打开了。"
		"latch":
			state.cloudLatch = true
			return "门闩固定，归途留住了。"
		"call":
			if not state.cloudLatch:
				return _fail("门闩还没固定，伙伴需要守住踏板。")
			state.cloudBuddy = "follow"
			state.follow = true
			return "小苔灵重新跟上你的脚步。"
		"repair":
			if level.id == "cloud-1" and not state.cloudSeed:
				return _fail("花床还在等待一粒花种。")
			if level.id == "cloud-3" and not together():
				return _fail("伙伴还在等你，一起点亮星灯吧。")
			state.completed = true
			state.cloudBuddy = "sit"
			state.follow = false
			return str(level.restored)
	if id.begins_with("discover:"):
		var name := id.trim_prefix("discover:")
		for mark: Dictionary in level.marks:
			if mark.id == name:
				state.observations.append(name)
				return str(mark.text)
	return _fail("这里暂时没有这个动作。")

func _collect() -> void:
	state.collected = state.observations.duplicate()

func hint() -> Dictionary:
	if state.completed:
		return {"message": level.restored}
	return {"message": "观察桥的朝向和庭院之间的连接。" if level.id == "cloud-1" else "花台的高度决定可以停靠的庭院。" if level.id == "cloud-2" else "门闩能为等待的伙伴留住归途。"}

