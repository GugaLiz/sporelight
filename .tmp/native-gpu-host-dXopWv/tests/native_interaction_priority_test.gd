extends SceneTree
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Interaction = preload("res://application/native_interaction.gd")
const Profiles = preload("res://presentation/native/level_presentation_profiles.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var saved := {}
	for entry: Dictionary in fixture.cases:
		if str(entry.name) == "authored/3-1":
			saved = entry.steps[-2].snapshot
	var world: RefCounted = World.new("3-1", saved)
	var before: Dictionary = world.snapshot()
	_check(world.state.actors.luvie == "f:3:0" and world.flag("window"), "reproduce standing at the opened window")
	var context := _context(world)
	_check(context.choices[0].id == "repair" and not context.choices[0].disabled, "available nearby flowerbed outranks disabled window underfoot")
	_check(world.snapshot() == before, "selecting an available target never commits the action")
	_check(world.fork(before).act("repair").ok, "offered repair satisfies real held-lamp and reunion conditions")
	world.state.items.lamp.holder = ""
	world.state.items.lamp.tile = "f:4:0"
	context = _context(world)
	_check(not context.choices.any(func(choice: Dictionary) -> bool: return choice.id == "repair" and not choice.disabled) and not world.fork(world.snapshot()).act("repair").ok, "missing held lamp cannot be bypassed by interaction ranking")
	_check(context.choices.any(func(choice: Dictionary) -> bool: return choice.id == "take:lamp" and not choice.disabled), "a dropped lamp can still be picked up to restore readiness")
	for level: String in ["1-1", "1-2"]:
		world = World.new(level)
		context = _context(world)
		_check(context.id == "context", level + " still asks for an explicit growth direction")
		_check(context.choices.size() >= 2, level + " retains alternative growth choices")
		_check(world.state.growth.root.is_empty(), level + " focus cannot plant a road")
	# Available groups retain the existing distance/observation ranking.
	world = World.new("1-1")
	var commands := [{"id":"grow:root:right", "label":"grow"}, {"id":"observe:test", "label":"observe", "target":"f:-1:0"}]
	var states := {"grow:root:right":{"available":true}, "observe:test":{"available":true}}
	context = Interaction.context(world, commands, states, Vector3(-0.5,0,0), _position)
	_check(context.tile.id == "f:0:0", "observation keeps original proximity penalty among available actions")
	_check(Interaction.context(world, commands, states, Vector3(30,0,30), _position).is_empty(), "availability cannot extend interaction range")
	var original := commands.duplicate(true)
	states["grow:root:right"] = {"available":false, "reason":"occupied"}
	context = Interaction.context(world, commands, states, Vector3.ZERO, _position)
	_check(context.tile.id == "f:0:0" and context.choices[0].reason == "occupied", "optional observation does not hide the closest blocked mechanism reason")
	_check(context.id == "context" and context.choices.any(func(choice: Dictionary) -> bool: return choice.id == "observe:test" and not choice.disabled), "nearby optional observation stays accessible through menu")
	_check(commands == original, "ranking never edits command data")
	states["observe:test"] = {"available":false, "reason":"hidden"}
	context = Interaction.context(world, commands, states, Vector3.ZERO, _position)
	_check(context.choices.all(func(choice: Dictionary) -> bool: return bool(choice.disabled)), "when all local actions are unavailable preserve unavailable choices")
	_check(context.choices[0].reason == "occupied", "closest blocked action keeps its domain denial reason")
	# Cloud companionship and optional discoveries share the same local menu.
	for level: String in ["cloud-2", "cloud-3"]:
		world = Cloud.new(level)
		context = _context(world)
		var discovery := "discover:rain" if level == "cloud-2" else "discover:home"
		_check(context.id == "context", level + " single pet cannot bypass nearby choices")
		_check(context.choices.any(func(choice: Dictionary) -> bool: return choice.id == discovery and not choice.disabled), level + " optional discovery remains touch accessible")
		_check(context.choices.any(func(choice: Dictionary) -> bool: return choice.id == "pet" and not choice.disabled), level + " companion interaction is retained")
	world = World.new("1-1")
	commands = [{"id":"grow:root:right", "label":"blocked"}, {"id":"grow:root:down", "label":"available"}, {"id":"observe:test", "label":"observe", "target":"f:-1:0"}]
	states = {"grow:root:right":{"available":false,"reason":"occupied"}, "grow:root:down":{"available":true}, "observe:test":{"available":true}}
	context = Interaction.context(world, commands, states, Vector3.ZERO, _position)
	_check(context.tile.id == "f:0:0", "mixed available and disabled choices count as an actionable group")
	_check(context.choices[0].id == "grow:root:right" and context.choices[0].reason == "occupied" and context.choices[1].id == "grow:root:down", "same-group order and denial reason are preserved")
	print(JSON.stringify({"suite":"native-interaction-priority", "checks":checks, "passed":failures.is_empty(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _context(world: RefCounted) -> Dictionary:
	var commands: Array = world.commands().filter(func(command: Dictionary) -> bool: return not str(command.id) in ["switch", "follow"])
	var states := {}
	var snapshot: Dictionary = world.snapshot()
	for command: Dictionary in commands:
		var result: Dictionary = world.fork(snapshot).act(str(command.id))
		states[str(command.id)] = {"available":bool(result.get("ok",false)), "reason":str(result.get("message",""))}
	return Interaction.context(world, commands, states, _position(world.point()), _position, Profiles.for_level(str(world.level.id)))

func _position(tile: Dictionary) -> Vector3:
	return Vector3(float(tile.x), float(tile.get("h", 0)) * 0.65, float(tile.z))

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
