extends SceneTree
const Cloud = preload("res://core/cloud_garden_world.gd")
var checked := 0
var failures: Array[String] = []

func verify(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		failures.append(message)
		push_error(message)

func compare(world: RefCounted, expected: Dictionary, context: String) -> void:
	var actual: Dictionary = world.snapshot()
	verify(actual.levelId == expected.levelId, context + " level")
	verify(actual.actors.luvie == expected.tile, context + " position")
	verify(int(actual.turns.bridge) == (1 if expected.bridge == "east" else 0), context + " bridge")
	verify(int(actual.turns.lift) == (1 if expected.lift == "high" else 0), context + " lift")
	verify(actual.cloudSeed == expected.seed, context + " seed")
	verify(actual.cloudLatch == expected.latch, context + " latch")
	verify(actual.cloudBuddy == expected.buddy, context + " companion mode")
	verify(actual.completed == expected.repaired, context + " completed")
	verify(actual.observations == expected.found, context + " discoveries")
	verify(world.normalize_saved(actual).get("ok", false), context + " own save valid")
	var imported := Cloud.new(str(expected.levelId), expected)
	verify(imported.state.actors.luvie == expected.tile, context + " legacy position")
	verify(imported.state.observations == expected.found, context + " legacy discoveries")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for fixture: Dictionary in fixtures.levels:
		var world := Cloud.new(str(fixture.id))
		compare(world, fixture.initial, str(fixture.id) + " initial")
		verify(not world.move("floor:999:999").ok, "illegal movement refused")
		for index: int in fixture.steps.size():
			var step: Dictionary = fixture.steps[index]
			var before: Dictionary = world.snapshot()
			var outcome: Dictionary = world.move(str(step.command.value)) if step.command.kind == "move" else world.act(str(step.command.value))
			verify(outcome.ok, "%s step %d accepted: %s" % [fixture.id, index, step.command.value])
			compare(world, step.snapshot, "%s step %d" % [fixture.id, index])
			var copy := world.fork(world.snapshot())
			verify(copy.state == world.state, "cloud fork exact")
			if not world.state.completed:
				var after: Dictionary = world.snapshot()
				verify(world.undo(), "cloud undo succeeds")
				verify(world.state == before, "cloud undo restores")
				outcome = world.move(str(step.command.value)) if step.command.kind == "move" else world.act(str(step.command.value))
				verify(outcome.ok and world.state == after, "cloud replay deterministic")
		verify(world.state.completed and world.state.observations.size() == 2, "repair with both discoveries")
		var invalid: Dictionary = world.snapshot()
		invalid.actors.luvie = "floor:999:999"
		verify(not world.normalize_saved(invalid).get("ok", false), "bad support rejected")
	var first := Cloud.new("cloud-1")
	first.state.actors.luvie = "floor:10:3"
	var result: Dictionary = first.act("repair")
	verify(not result.ok and not first.state.completed, "cannot repair tower without seed")
	var third := Cloud.new("cloud-3")
	third.state.actors.luvie = "floor:3:6"
	verify(third.act("wait").ok, "companion holds gate")
	verify(not third.act("call").ok, "cannot call companion before latch")
	var softlock := Cloud.new("cloud-3")
	var sit: Dictionary = softlock.snapshot()
	sit.cloudBuddy = "sit"
	var fixed: Dictionary = softlock.normalize_saved(sit)
	verify(fixed.get("ok", false) and fixed.snapshot.cloudBuddy == "follow", "uncompleted sitting state normalizes safely")
	var wait_state: Dictionary = softlock.snapshot()
	wait_state.cloudBuddy = "wait"
	wait_state.runtime = {"version": 1, "poses": {"buddy": {"support": wait_state.actors.buddy, "offset": [0, 0, 0], "facing": "front"}}}
	var normalized: Dictionary = softlock.normalize_saved(wait_state)
	verify(normalized.get("ok", false), "wait state canonicalizes companion support")
	verify(normalized.snapshot.actors.buddy == "floor:3:6" and not normalized.snapshot.runtime.poses.has("buddy"), "stale companion pose removed")
	verify(softlock.normalize_saved(normalized.snapshot).get("ok", false), "canonical wait state is idempotently valid")
	softlock.state.cloudLatch = true
	softlock.state.actors.luvie = "floor:8:1"
	softlock.state.actors.buddy = "floor:1:7"
	verify(not softlock.together(), "follow mode alone is not physical reunion")
	verify(not softlock.act("repair").ok, "distant companion cannot finish star lamp")
	print("Native cloud rules: %d checks, %d failures" % [checked, failures.size()])
	quit(0 if failures.is_empty() else 1)
