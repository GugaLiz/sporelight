extends SceneTree
## Prepared domain boundary checks; actual body movement is captured separately.
const World = preload("res://core/garden_world.gd")
const Interaction = preload("res://application/native_interaction.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _offered(world: RefCounted, id: String) -> bool:
	return world.commands().any(func(c: Dictionary) -> bool: return str(c.id) == id)

func _grow(world: RefCounted) -> Array:
	return world.commands().filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("grow:"))

func _fixture(id: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if str(entry.name) == "authored/" + id: return entry
	return {}

func _before(id: String, action: String) -> Dictionary:
	var fixture := _fixture(id)
	var last: Dictionary = fixture.initial.snapshot
	for step: Dictionary in fixture.steps:
		if str(step.command.value) == action: return last.duplicate(true)
		last = step.snapshot
	return {}

func _boundaries(id: String, first: String, second: String) -> void:
	var world := World.new(id)
	var origin := str(world.level.roots[0].at)
	world.state.actors.luvie = origin
	world.state.actors.buddy = origin
	world.state.active = "luvie"
	var root_before: Dictionary = world.snapshot().duplicate(true)
	_check(_offered(world, first) and world.act(first).ok, id + " first section remains available at root")
	var first_tip := str(world.state.growth.root.back())
	var at_origin: Dictionary = world.snapshot().duplicate(true)
	_check(_grow(world).is_empty(), id + " cannot keep building from origin")
	_check(not world.act(second).ok and world.snapshot() == at_origin, id + " ordinary remote request rejected without spending bud")
	_check(not world.act(second, true).ok and world.snapshot() == at_origin, id + " quiet remote request cannot bypass frontier")
	var restored := World.new(id, at_origin)
	_check(restored.state.growth.root == world.state.growth.root and _grow(restored).is_empty(), id + " old partial save retains progress but requires travel")
	_check(world.move(first_tip).ok, id + " legal first segment can be entered")
	_check(_offered(world, second), id + " standing on newest section enables next")
	var command: Dictionary = _grow(world).filter(func(c: Dictionary) -> bool: return str(c.id) == second)[0]
	var anchor := Interaction.command_tile(world, command)
	_check(str(anchor.id) == first_tip, id + " context anchor is existing frontier rather than unborn socket")
	var before_second: Dictionary = world.snapshot().duplicate(true)
	_check(world.act(second).ok and world.state.growth.root.size() == 2, id + " exactly one new segment committed")
	_check(_grow(world).is_empty(), id + " previous frontier cannot build again while next exists")
	_check(world.undo() and world.snapshot() == before_second, id + " undo restores previous frontier and budget")
	_check(_offered(world, second), id + " undo immediately restores grow availability at old tip")
	world.state.active = "buddy"
	world.state.actors.buddy = first_tip
	var buddy_state: Dictionary = world.snapshot().duplicate(true)
	_check(_grow(world).is_empty() and not world.act(second, true).ok and world.snapshot() == buddy_state, id + " companion cannot build even on tip")
	world.state.active = "luvie"
	_check(world.act(second).ok, id + " hero continues after switching back")
	var second_tip := str(world.state.growth.root.back())
	world.state.actors.buddy = second_tip
	var occupied: Dictionary = world.snapshot().duplicate(true)
	_check(not world.act("retract:root").ok and world.snapshot() == occupied, id + " predecessor cannot retract buddy support")
	_check(not world.act("retract:root", true).ok and world.snapshot() == occupied, id + " quiet retract cannot remove buddy support")
	world.state.actors.buddy = first_tip
	if not world.state.items.is_empty():
		var item_id: String = world.state.items.keys()[0]
		var original_item: Dictionary = world.state.items[item_id].duplicate(true)
		world.state.items[item_id] = {"tile":second_tip,"angle":0}
		occupied = world.snapshot().duplicate(true)
		_check(not world.act("retract:root").ok and world.snapshot() == occupied, id + " predecessor cannot retract item support")
		_check(not world.act("retract:root", true).ok and world.snapshot() == occupied, id + " quiet retract cannot remove item support")
		world.state.items[item_id] = original_item
	_check(_offered(world, "retract:root"), id + " safe predecessor can retract latest section")
	_check(world.act("retract:root").ok and world.state.growth.root.size() == 1, id + " retract does not remove standing predecessor")
	_check(world.move(origin).ok, id + " return to root remains possible")
	world.state.actors.buddy = origin
	_check(world.act("retract:root").ok and world.state.growth.root.is_empty(), id + " root recovery retract remains available")
	_check(_offered(world, first), id + " empty road returns construction to root")
	_check(root_before.growth.root.is_empty() and not second_tip.is_empty(), id + " fixture uses independent section identities")

func _aliases() -> void:
	var world := World.new("3-3")
	world.state.actors.luvie = "f:1:-4"
	_check(world.act("grow:root:right").ok, "alias setup grows first section")
	# Authored fixed/root overlaps can be selected under a fixed identity.
	# This synthetic boundary board is not presented as an actual game route.
	world.level.tiles.append({"id":"f:2:-4", "x":2, "z":-4, "h":0, "kind":"fixed"})
	world.state.actors.luvie = "f:2:-4"
	_check(_offered(world, "grow:root:right") and world.act("grow:root:right").ok, "same-coordinate same-height fixed alias counts as standing on frontier")
	world.level.tiles.append({"id":"test:upper", "x":3, "z":-4, "h":1, "kind":"fixed"})
	world.state.actors.luvie = "test:upper"
	_check(_grow(world).is_empty() and not world.act("grow:root:right", true).ok, "same XZ on another height cannot build")

func _preserved_rules() -> void:
	for water in [1, 2]:
		var world := World.new("3-3")
		world.state.actors.luvie = "f:1:-4"
		world.state.turns.water = water
		var previous: Dictionary = world.snapshot().duplicate(true)
		_check(not world.act("grow:root:right").ok and world.snapshot() == previous, "unwatered roots still reject growth: " + str(water))
	var world := World.new("3-3")
	world.state.actors.luvie = "f:1:-4"
	for direction: String in ["right", "right", "right", "down"]:
		_check(world.act("grow:root:" + direction).ok, "four-section sequential route grows " + direction)
		_check(world.move(str(world.state.growth.root.back())).ok, "walk onto each real section")
	_check(world.budget() == 0 and _grow(world).is_empty() and world.connected() and not world.flag("root"), "budget, connection and stability remain distinct")
	# Add an otherwise legal unused socket to isolate the budget boundary.
	world.level.roots[0].sockets.append([5,-3])
	var exhausted: Dictionary = world.snapshot().duplicate(true)
	_check(not world.act("grow:root:right", true).ok and world.snapshot() == exhausted, "quiet growth cannot exceed exhausted budget even at valid unused socket")
	var invalid := World.new("3-3")
	invalid.state.actors.luvie = "f:1:-4"
	_check(invalid.act("grow:root:right").ok and invalid.move("g:root:2:-4").ok, "illegal socket boundary starts at valid frontier")
	var invalid_before: Dictionary = invalid.snapshot().duplicate(true)
	_check(not invalid.act("grow:root:up", true).ok and invalid.snapshot() == invalid_before, "quiet growth cannot build outside sockets")
	for high in [0, 1]:
		var saved := _before("3-3", "valve:lift")
		saved.turns.water = 2; saved.turns.lift = high
		var lift := World.new("3-3", saved)
		_check(lift.act("valve:lift").ok == (high == 1), "no-power ascent blocked, descent allowed")
	var care := World.new("3-3", _before("3-3", "use:care"))
	_check(care.act("use:care").ok and care.flag("root"), "care still required to stabilize")
	_check(not _offered(care, "retract:root"), "stabilized roots cannot ordinary-retract")
	var first := World.new("1-1")
	_check(first.act("grow:root:down").ok and first.state.growth.root.size() == 1, "approved one-segment first garden keeps first build")
	_check(_grow(first).is_empty() and first.act("retract:root").ok and first.act("grow:root:right").ok, "first garden wrong branch recovery unchanged")

func _run() -> void:
	_boundaries("1-2", "grow:root:up", "grow:root:right")
	_boundaries("3-3", "grow:root:right", "grow:root:right")
	_boundaries("3-4", "grow:root:right", "grow:root:right")
	_aliases()
	_preserved_rules()
	print(JSON.stringify({"suite":"growth-frontier-domain", "checks":checks, "failures":failures, "passed":failures.is_empty(), "scope":"Prepared rule boundaries only; GPU separately proves body travel and inputs. Immutable original fixtures are read, never rewritten."}))
	quit(0 if failures.is_empty() else 1)
