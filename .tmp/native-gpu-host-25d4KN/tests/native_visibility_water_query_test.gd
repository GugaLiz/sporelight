extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var stage: Node2D
var checks := 0
var failures: Array[String] = []

class CountedWorld:
	extends World
	static var calls := 0
	func _init(id: String = "1-1", saved: Dictionary = {}) -> void: super(id, saved)
	func tiles() -> Array:
		calls += 1
		return super.tiles()
	func fork(saved: Dictionary) -> RefCounted: return CountedWorld.new(str(level.id), saved)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	await process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) == "authored/3-1":
			_visibility(entry.initial.snapshot)
			for step: Dictionary in entry.steps: _visibility(step.snapshot)
		if str(entry.name) == "authored/3-4":
			_water_state(entry.initial.snapshot)
			var prior: Dictionary = entry.initial.snapshot
			for step: Dictionary in entry.steps:
				if str(step.command.kind) == "act":
					_water_state(step.snapshot)
					_water_motion(prior, step.snapshot, str(step.command.value))
				prior = step.snapshot
	print(JSON.stringify({"suite": "native-visibility-water-query", "passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "3-1 every authored state's visibility and refresh; 3-4 all authored actions, water endpoints at five motion phases, reversal, clear, state replacement and uncached fallback."}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _visibility(saved: Dictionary) -> void:
	var world := CountedWorld.new("3-1", saved)
	var before: Dictionary = world.snapshot()
	var board: Array = world.tiles()
	var board_before: Array = board.duplicate(true)
	for tile: Dictionary in board:
		var expected: bool = world.visible(tile)
		CountedWorld.calls = 0
		_check(world.visible(tile, board) == expected, "scope preserves 3-1 visibility of " + str(tile.id))
		_check(CountedWorld.calls == 0, "visibility uses supplied board without rebuilding it")
	stage.set_world(world)
	CountedWorld.calls = 0
	stage.refresh_world(world, true)
	_check(CountedWorld.calls == 1, "complete 3-1 refresh derives exactly one current board")
	for tile: Dictionary in board:
		_check(stage._surfaces[str(tile.id)].visible == world.visible(tile, board), "rendered surface visibility remains exact")
	_check(world.snapshot() == before and board == board_before, "visibility preserves world state and borrowed board")

func _water_state(saved: Dictionary) -> void:
	stage.clear_motion(false)
	var world := CountedWorld.new("3-4", saved)
	var oracle := World.new("3-4", saved)
	stage.set_world(world)
	var before: Dictionary = world.snapshot()
	for tile: Dictionary in oracle.tiles():
		var id := str(tile.id)
		var expected := _old_point(oracle, id)
		CountedWorld.calls = 0
		_check(stage._water_anchor_point(world, id).is_equal_approx(expected), "static water endpoint preserves geometry " + id)
		_check(CountedWorld.calls == 0, "refreshed board or module formula supplies endpoint " + id)
	world.state["runtime"] = {"version": 1, "poses": {}}
	CountedWorld.calls = 0
	stage._water_anchor_point(world, "f:0:-4")
	_check(CountedWorld.calls == 0, "foot pose changes do not invalidate derived board")
	# Before a refresh, a direct non-runtime state change must use fresh rules.
	world.state.flags.append("query-test-state-change")
	CountedWorld.calls = 0
	var actual: Vector3 = stage._water_anchor_point(world, "f:0:-4")
	_check(CountedWorld.calls == 1, "direct state mutation falls back instead of reusing stale tile map")
	_check(actual.is_equal_approx(_old_point(world, "f:0:-4")), "direct state fallback preserves current point")
	world.state = before
	CountedWorld.calls = 0
	stage._water_anchor_point(oracle, "f:0:-4")
	_check(CountedWorld.calls == 0, "external world uses its own point query, never the counted stage world")
	_check(world.snapshot() == before, "water checks restore the native snapshot exactly")

func _water_motion(raw_before: Dictionary, raw_after: Dictionary, action: String) -> void:
	var before: Dictionary = World.new("3-4", raw_before).snapshot()
	var after: Dictionary = World.new("3-4", raw_after).snapshot()
	for reverse: bool in [false, true]:
		var first: Dictionary = after if reverse else before
		var last: Dictionary = before if reverse else after
		stage.clear_motion(false)
		stage.set_world(CountedWorld.new("3-4", first))
		stage.set_motion(first, last, 0.0, action)
		var from_world := World.new("3-4", first)
		var to_world := World.new("3-4", last)
		for progress: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			CountedWorld.calls = 0
			stage.set_motion(first, last, progress, action)
			_check(CountedWorld.calls == 0, "warm water motion uses immutable snapshot indexes")
			var eased := progress * progress * (3 - 2 * progress)
			for link: Dictionary in stage._water_links:
				var a := _old_between(from_world, to_world, str(link.from), eased) + Vector3(0, 0.065, 0)
				var b := _old_between(from_world, to_world, str(link.to), eased) + Vector3(0, 0.065, 0)
				_check(link.source.position.is_equal_approx(a) and link.receiver.position.is_equal_approx(b), "real water anchors match original interpolation " + action + " phase=" + str(progress) + " reverse=" + str(reverse))
				var expected_visible: bool = stage._water_route_enabled(link.route, to_world) and (stage._water_route_enabled(link.route, from_world) or progress >= 0.9999)
				_check(link.node.visible == expected_visible, "supply gate still waits for alignment")
		stage.clear_motion(false)
		CountedWorld.calls = 0
		stage._update_water_presentation()
		_check(CountedWorld.calls == 0, "clear and undo destination reuse refreshed static board")
		_check(stage.world.snapshot() == last, "water does not mutate the destination snapshot")

func _old_point(world: RefCounted, id: String) -> Vector3:
	var parts := id.split(":")
	return stage.tile_position(world.module_point(parts[1], [int(parts[2]), int(parts[3])])) if parts.size() == 4 and parts[0] == "m" else stage.tile_position(world.point_for(id))

func _old_between(before: RefCounted, after: RefCounted, id: String, progress: float) -> Vector3:
	var first := _old_point(before, id)
	var last := _old_point(after, id)
	var parts := id.split(":")
	if parts.size() != 4 or parts[0] != "m": return first.lerp(last, progress)
	for module: Dictionary in before.level.modules:
		if str(module.id) != parts[1] or str(module.kind) != "rotate": continue
		var from_center: Vector3 = stage.tile_position(before.module_point(str(module.id), [0, 0]))
		var to_center: Vector3 = stage.tile_position(after.module_point(str(module.id), [0, 0]))
		var delta := posmod(int(after.state.turns.get(module.id, 0)) - int(before.state.turns.get(module.id, 0)), 4)
		var angle := float(delta if delta <= 2 else delta - 4) * PI / 2 * progress
		var local := first - from_center
		var rotated := Vector2(local.x, local.z).rotated(angle)
		var center := from_center.lerp(to_center, progress)
		return Vector3(center.x + rotated.x, lerpf(first.y, last.y, progress), center.z + rotated.y)
	return first.lerp(last, progress)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
