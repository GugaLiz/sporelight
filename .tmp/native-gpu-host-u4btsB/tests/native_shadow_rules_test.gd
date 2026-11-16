extends SceneTree
## Original 3-2 semantics: frozen TS trace plus independent boundary assertions.
## Feedback wording is deliberately excluded; command IDs and state are not.
const World = preload("res://core/garden_world.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const FIXTURE_SHA := "71b09202d5fb185006c63c47e3e8e2167d3821417270a717ce5013ea8be2fbc5"
var checks := 0
var failures: Array[String] = []
var fixture: Dictionary

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _same(actual: Variant, expected: Variant, label: String) -> void:
	_check(Snapshot.equivalent(actual, expected), label)

func _commands(commands: Array) -> Array:
	var result: Array = commands.duplicate(true)
	for command: Dictionary in result: command.erase("label")
	return result

func _observe(world: RefCounted, expected: Dictionary, label: String) -> void:
	_same(world.snapshot(), expected.snapshot, label + " exact original snapshot")
	_same(world.tiles(), expected.tiles, label + " exact original geometry")
	_same(_commands(world.commands()), _commands(expected.commands), label + " exact original commands and selections")
	_check(world.ready() == expected.ready and world.together() == expected.together, label + " original readiness and reunion")
	_check(world.can_undo() == expected.canUndo, label + " original undo availability")
	_same(world.rays(), expected.rays, label + " unchanged mirror rays")
	_same(world.lamp_ray(), expected.lampRay, label + " unchanged lamp rays")

func _act(world: RefCounted, id: String) -> Dictionary:
	var result: Dictionary = world.act(id)
	_check(result.ok, "legal original action " + id)
	return result

func _go(world: RefCounted, target: String) -> void:
	var route: Array = world.path_to(target)
	_check(not route.is_empty() or str(world.state.actors[world.actor()]) == target, "original route to " + target)
	for tile: String in route: _check(world.move(tile).ok, "original move " + tile)

func _original_route() -> void:
	var world := World.new("3-2")
	_observe(world, fixture.initial, "cold")
	_check(fixture.steps.size() == 36, "frozen TS reference contains original 36 intentions")
	for index: int in fixture.steps.size():
		var step: Dictionary = fixture.steps[index]
		var result: Dictionary = world.move(str(step.command.value)) if step.command.kind == "move" else world.act(str(step.command.value))
		_check(result.ok == step.result.ok, "original step " + str(index) + " acceptance")
		_observe(world, step, "original step " + str(index))
	_check(world.state.completed, "unchanged original route completes")

func _both_orders() -> void:
	for first: int in [0, 1]:
		var world := World.new("3-2", fixture.steps[23].snapshot)
		if first == 1: _act(world, "valve:mode")
		_act(world, "freeze")
		var saved: Array = world.state.shadowMemory.duplicate(true)
		_check(world.state.frozen == first, "either first shadow may be retained")
		_go(world, "f:-1:0")
		_act(world, "valve:mode")
		_same(world.state.shadowMemory, saved, "time switch preserves actual saved coordinates")
		_check(world.ready() and world.has_path_to("f:3:4"), "both retention orders connect the original route")
		_go(world, "f:3:4")
		_act(world, "repair")
		_check(world.state.completed, "retaining mode " + str(first) + " first permits completion")

func _memory_follows_saved_shape() -> void:
	var world := World.new("3-2", fixture.steps[24].snapshot)
	var saved: Array = world.state.shadowMemory.duplicate(true)
	_same(saved, [{"x": 1, "z": 0, "h": 0}, {"x": 2, "z": 0, "h": 0}], "sun memory is the actual arranged shape")
	_go(world, "f:0:0")
	_act(world, "take:sunPost")
	_check(world.projection(0).is_empty(), "carried pillar creates no real-time projection")
	_same(world.state.shadowMemory, saved, "pickup never erases saved shadow")
	_check(not world.point_for("shadow:sun").is_empty(), "saved road survives its pillar being held")
	_go(world, "f:-2:-1")
	_act(world, "drop:sunPost:f:-2:-1")
	_same(world.projection(0), [{"x": -1, "z": -1, "h": 0}, {"x": 0, "z": -1, "h": 0}], "arbitrary legal ground changes actual projection without a required slot")
	_same(world.state.shadowMemory, saved, "moving and dropping pillar never rewrites memory")
	_check(int(world.point_for("shadow:sun").x) == 1, "memory takes precedence even while current light has the same mode")
	var current: Dictionary = world.snapshot()
	_check(world.undo(), "placement can be undone")
	_check(world.state.items.sunPost.get("holder", "") == "luvie", "undo restores actual carried identity")
	world = World.new("3-2", current)
	_same(world.snapshot(), current, "reload restores real column position and retained coordinates")
	_go(world, "f:-1:1")
	_act(world, "freeze")
	_same(world.state.shadowMemory, [{"x": -1, "z": -1, "h": 0}, {"x": 0, "z": -1, "h": 0}], "re-freeze replaces memory with current actual projection")
	_check(not world.has_path_to("f:2:0"), "wrong saved position does not become a preset correct bridge")
	_act(world, "valve:mode")
	_act(world, "freeze")
	_same(world.state.shadowMemory, [{"x": 2, "z": 1, "h": 0}, {"x": 2, "z": 2, "h": 0}], "moon replaces the single saved sun shape")
	_check(world.state.frozen == 1 and not world.ready(), "retaining current moon does not preserve a second sun memory")
	_check(world.undo() and world.state.frozen == 0, "undo restores previous memory identity")

func _missing_projection_and_roles() -> void:
	var world := World.new("3-2")
	_go(world, "f:-1:0")
	var commands: Array = world.commands()
	_check(commands.any(func(c: Dictionary) -> bool: return c.id == "take:sunPost" and c.label == "搬起日影柱"), "sun pickup has its own identity")
	_act(world, "take:sunPost")
	var before: Dictionary = world.snapshot()
	var result: Dictionary = world.act("freeze")
	_check(not result.ok and str(result.message).contains("日影柱") and not str(result.message).contains("槽"), "held current column cannot supply memory and reason names actual cause")
	_same(world.snapshot(), before, "failed freeze leaves all state untouched")
	_check(not world.has_path_to("f:2:0"), "missing live sun column cannot bypass gap")
	_check(world.commands().any(func(c: Dictionary) -> bool: return str(c.id).begins_with("drop:sunPost:") and str(c.label).begins_with("日影柱：")), "drop retains carried pillar identity")
	_act(world, "switch")
	_check(not world.commands().any(func(c: Dictionary) -> bool: return str(c.id).begins_with("take:") and str(c.id).ends_with("Post")), "buddy gains no new pillar carrying ability")
	_check(world.commands().any(func(c: Dictionary) -> bool: return c.id == "valve:mode") and world.commands().any(func(c: Dictionary) -> bool: return c.id == "freeze"), "buddy retains original time and memory controls")
	result = _act(world, "valve:mode")
	_check(str(result.message).contains("月光") and not str(result.message).contains("水位"), "switch feedback names actual moonlight rather than water")
	_act(world, "freeze")
	_same(world.state.shadowMemory, [{"x": -3, "z": 3, "h": 0}, {"x": -3, "z": 4, "h": 0}], "initial misplaced moon still produces its own actual shape")
	_check(not world.has_path_to("f:3:4"), "wrongly positioned moon cannot create correct route")

func _occupied_memory_protection() -> void:
	for occupant: String in ["buddy", "item"]:
		var saved: Dictionary = fixture.steps[26].snapshot.duplicate(true)
		saved.follow = false
		if occupant == "buddy": saved.actors.buddy = "shadow:sun"
		else: saved.items.sunPost.tile = "shadow:sun"
		var world := World.new("3-2", saved)
		var before: Dictionary = world.snapshot()
		_check(world.state.frozen == 0 and not world.point_for("shadow:sun").is_empty(), "prepared occupied memory is valid")
		_check(not world.act("freeze").ok, "replacement cannot remove road under " + occupant)
		_same(world.snapshot(), before, "denied replacement preserves " + occupant + " and memory")

func _run() -> void:
	_check(FileAccess.get_sha256("res://tests/fixtures/reference.json") == FIXTURE_SHA, "original TS fixture is unchanged")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for candidate: Dictionary in reference.cases:
		if candidate.name == "authored/3-2": fixture = candidate
	_check(not fixture.is_empty(), "original 3-2 fixture exists")
	if not fixture.is_empty():
		_original_route()
		_both_orders()
		_memory_follows_saved_shape()
		_missing_projection_and_roles()
		_occupied_memory_protection()
	print(JSON.stringify({"suite": "native-shadow-rules", "checks": checks, "passed": failures.is_empty(), "failures": failures, "fixtureSha256": FIXTURE_SHA, "gpuPixelsVerified": false, "scope": "Unmodified original TS 36-step trace: exact snapshots, commands excluding labels, geometry and readiness; both retention orders, actual saved shapes, arbitrary ground placement, carried projection absence, role permissions, replacement occupancy protection, undo and reload. Prepared boundary states are not a claim of native movement or GPU input."}))
	quit(0 if failures.is_empty() else 1)
