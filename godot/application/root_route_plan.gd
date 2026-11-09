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
		if not preview.act(id).ok: return false
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
	for id: String in commands:
		for choice: Dictionary in preview.commands():
			if choice.id == id: targets.append(str(choice.target))
		preview.act(id)

func ready() -> bool:
	return not commands.is_empty() and preview.state.growth.root.size() == 4 and preview.budget() == 0 and preview.connected()
