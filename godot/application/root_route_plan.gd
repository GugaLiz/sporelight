extends RefCounted
## A disposable route draft. No edits or traversal are committed while drawing.
var source: RefCounted
var preview: RefCounted
var commands: Array[String] = []
var targets: Array[String] = []
var baseline: Dictionary

func _init(world: RefCounted) -> void:
	source = world
	baseline = world.snapshot()
	_rebuild()

func choices() -> Array:
	return preview.commands().filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("grow:root:"))

func append(id: String) -> bool:
	for choice: Dictionary in choices():
		if choice.id != id: continue
		var before: Dictionary = preview.snapshot()
		if not preview.act(id).ok: return false
		if not _walk_preview_to_frontier():
			preview = source.fork(before)
			return false
		commands.append(id)
		targets.append(str(choice.target))
		return true
	return false

func trim(count: int) -> void:
	commands.resize(clampi(count, 0, commands.size()))
	_rebuild()

func _rebuild() -> void:
	preview = source.fork(baseline)
	targets.clear()
	var draft: Array[String] = commands.duplicate()
	commands.clear()
	if not _walk_preview_to_frontier(): return
	for id: String in draft:
		if not append(id): break

func _walk_preview_to_frontier() -> bool:
	# Planning is still disposable. Simulate legal movement in the fork so
	# it obeys the same per-board rule as actual execution, never quiet-grow.
	var root: Dictionary = preview.level.roots[0]
	if preview.can_grow_root(root): return true
	var station: Dictionary = preview.root_growth_station(root)
	if station.is_empty(): return false
	var route: Array = preview.path_to(str(station.id))
	if route.is_empty(): return false
	for id: String in route:
		if not preview.move(id).ok: return false
	return preview.can_grow_root(root)

func ready() -> bool:
	return not commands.is_empty() and preview.state.growth.root.size() == 4 and preview.budget() == 0 and preview.connected()
