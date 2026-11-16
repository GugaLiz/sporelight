extends SceneTree
## Optional third-tier guardian help must describe the actual return state.
const World = preload("res://core/garden_world.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const Journey = preload("res://application/journey_view.gd")
const Flow = preload("res://application/guardian_flow_guidance.gd")
var checks := 0
var failures: Array[String] = []
var records: Array = []
var fixture: Dictionary = {}
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); push_error(label)
	return value
func _world(index: int) -> RefCounted:
	return World.new("3-4", fixture.steps[index].snapshot)
func _probe(world: RefCounted, expected: String, label: String, forbidden: String = "") -> void:
	var before: Dictionary = world.snapshot().duplicate(true)
	var commands: Array = world.commands().duplicate(true)
	var message := str(world.hint().message)
	_check(message.contains(expected), label + " names current reachable phase: " + message)
	if not forbidden.is_empty(): _check(not message.contains(forbidden), label + " does not repeat an obsolete phase")
	_check(Snapshot.equivalent(before, world.snapshot()), label + " help is read-only")
	_check(world.commands() == commands, label + " help does not filter or add actions")
	_check(str(Journey.hint(world, 2).message) == message, label + " only explicit detailed tier consumes guidance")
	if not world.state.completed:
		# The new user request explicitly replaces the opaque static objective.
		# The optional detailed-help contract and all rule queries stay intact.
		_check(str(Journey.describe(world).next) == str(Flow.describe(world).goal), label + " current objective follows the newly requested flow presentation")
		_check(str(Journey.hint(world, 0).message) == "根路通向远岸，清水为升降台蓄力，光唤醒花坛。", label + " first optional tier describes actual roles")
		_check(str(Journey.hint(world, 1).message) == "储水罐灌满后不会流失；让光留在花坛上，再和伙伴回来照料。", label + " second optional tier separates stored water from live light")
	records.append({"label":label,"message":message})
func _walk(world: RefCounted, target: String) -> bool:
	if str(world.state.actors[world.actor()]) == target: return true
	var path: Array = world.path_to(target)
	if not _check(not path.is_empty(), "recovery path " + world.actor() + " to " + target): return false
	for id: String in path:
		if not _check(bool(world.move(id).ok), "recovery legal step " + id): return false
	return true
func _act(world: RefCounted, action: String) -> bool:
	var result: Dictionary = world.act(action)
	return _check(bool(result.ok), "recovery original action " + action + " " + str(result))
func _lower_lift_recovery() -> void:
	var saved: Dictionary = fixture.steps[48].snapshot.duplicate(true)
	saved.turns.lift = 0
	var world := World.new("3-4", saved)
	_check(Snapshot.equivalent(world.snapshot(), saved), "high-bank hero and low lift is a valid prepared save")
	_probe(world, "不能远程召台", "hero high / lift low")
	_check(not world.commands().any(func(command: Dictionary) -> bool: return command.id == "valve:lift"), "high bank has no invented remote lift command")
	_check(not world.has_path_to("m:lift:0:0", "luvie"), "hero cannot cross absent high landing")
	if not _act(world, "switch"): return
	if not _walk(world, "m:lift:0:0"): return
	if not _act(world, "valve:lift"): return
	if not _act(world, "switch"): return
	if not _walk(world, "m:lift:0:0"): return
	if not _act(world, "valve:lift"): return
	_check(int(world.point_for(str(world.state.actors.luvie)).h) == 0 and int(world.point_for(str(world.state.actors.buddy)).h) == 0, "companion actually rides up and brings both down")
	if not _walk(world, "f:1:-4"): return
	if not _walk(world, "m:inner:0:0"): return
	if not _act(world, "turn:inner"): return
	if not _walk(world, "f:-4:0"): return
	if not _act(world, "switch"): return
	if not _walk(world, "f:-4:0"): return
	if not _act(world, "switch"): return
	if not _act(world, "repair"): return
	_check(bool(world.state.completed), "prepared low-lift rescue completes with original rules")
func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if entry.name == "authored/3-4": fixture = entry
	_probe(World.new("3-4"), "向右三节", "cold")
	_probe(_world(46), "安全下降", "on light garden")
	_probe(_world(48), "安全下降", "screenshot high bank")
	_probe(_world(54), "安全下降", "on raised lift")
	_probe(_world(55), "露薇沿北侧固定归途", "after descending", "安全下降")
	_probe(_world(68), "露薇沿北侧固定归途", "inner aligned", "安全下降")
	_probe(_world(80), "露薇已到西岸", "hero home", "安全下降")
	_probe(_world(94), "两位也已在西岸会合", "both home", "安全下降")
	_probe(_world(95), str(_world(95).level.story), "complete")
	for condition: String in ["inner", "water", "light"]:
		var saved: Dictionary = fixture.steps[94].snapshot.duplicate(true)
		saved.turns[condition] = 0
		var world := World.new("3-4", saved)
		var live_condition := condition == "light"
		_probe(world, "光路现在没有照到西岸" if live_condition else "两位也已在西岸会合", "current " + condition)
		_check(world.ready() == not live_condition, "cultivation checks actual light but no arbitrary remote angle: " + condition)
	var already_home: RefCounted = _world(94)
	already_home.state.turns.lift = 1
	_probe(already_home, "两位也已在西岸会合", "home with lift high", "安全下降")
	var raised_buddy: Dictionary = fixture.steps[48].snapshot.duplicate(true)
	raised_buddy.actors = {"luvie":"f:-4:0","buddy":"f:8:2"}
	_probe(World.new("3-4", raised_buddy), "切换高岸的小苔灵", "companion high / hero low")
	for index: int in fixture.steps.size():
		var world: RefCounted = _world(index)
		var before: Dictionary = world.snapshot().duplicate(true)
		var actions: Array = world.commands().duplicate(true)
		for tier in range(3): Journey.hint(world, tier)
		_check(Snapshot.equivalent(world.snapshot(), before), "fixture " + str(index) + " help preserves full snapshot")
		_check(world.commands() == actions, "fixture " + str(index) + " help preserves exact original action set")
	_lower_lift_recovery()
	print(JSON.stringify({"suite":"guardian-guidance","checks":checks,"passed":failures.is_empty(),"failures":failures,"records":records,"scope":"Third help tier only; legal prepared low-lift rescue and original actions. Not GPU/physical-input proof."}))
	quit(0 if failures.is_empty() else 1)
