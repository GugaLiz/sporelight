extends SceneTree
const Interaction = preload("res://application/native_interaction.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Repository = preload("res://services/save_repository.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Array = []

class CountedWorld:
	extends World
	var tile_calls := 0
	var ignore_scope := false
	func _init(id: String = "1-1", saved: Dictionary = {}) -> void: super(id, saved)
	func tiles() -> Array:
		tile_calls += 1
		return super.tiles()
	func point_for(id: String, world_tiles: Array = []) -> Dictionary:
		return super.point_for(id, [] if ignore_scope else world_tiles)

class CountedCloud:
	extends Cloud
	var tile_calls := 0
	var ignore_scope := false
	func _init(id: String = "cloud-1", saved: Dictionary = {}) -> void: super(id, saved)
	func tiles() -> Array:
		tile_calls += 1
		return super.tiles()
	func point_for(id: String, world_tiles: Array = []) -> Dictionary:
		return super.point_for(id, [] if ignore_scope else world_tiles)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if not str(entry.name).begins_with("authored/"): continue
		_test_state(str(entry.levelId), entry.initial.snapshot)
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act": _test_state(str(entry.levelId), step.snapshot)
	var cloud: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for entry: Dictionary in cloud.levels:
		_test_state(str(entry.id), entry.initial)
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act": _test_state(str(entry.id), step.snapshot)
	print(JSON.stringify({"suite": "native-interaction-query", "passed": failures.is_empty(), "checks": checks, "failures": failures, "measurements": measurements}))
	quit(0 if failures.is_empty() else 1)

func _test_state(id: String, saved: Dictionary) -> void:
	var world: RefCounted = CountedCloud.new(id, saved) if id.begins_with("cloud-") else CountedWorld.new(id, saved)
	var snapshot: Dictionary = world.snapshot()
	var commands: Array = world.commands()
	# Exercise enabled/disabled grouping deterministically; separate priority
	# tests verify the real action availability and denial reasons.
	var availability: Dictionary = {}
	for command: Dictionary in commands:
		availability[str(command.id)] = {"available": posmod(hash(str(command.id)), 3) != 0, "reason": "fixture-reason"}
	var tile: Dictionary = world.point()
	var position := _position(tile) + Vector3(0.17, 0, -0.13)
	world.ignore_scope = true
	world.tile_calls = 0
	var expected: Dictionary = Interaction.context(world, commands, availability, position, _position)
	var uncached_calls: int = world.tile_calls
	world.ignore_scope = false
	world.tile_calls = 0
	var actual: Dictionary = Interaction.context(world, commands, availability, position, _position)
	var scoped_calls: int = world.tile_calls
	_check(Repository.json_equivalent(actual, expected), id + " complete context matches uncached query semantics")
	_check(world.snapshot() == snapshot, id + " query leaves domain snapshot unchanged")
	if not "--baseline" in OS.get_cmdline_user_args():
		_check(scoped_calls == (0 if commands.is_empty() else 1), id + " one board per command context")
		var board: Array = world.tiles()
		var board_before: Array = board.duplicate(true)
		world.tile_calls = 0
		var query: Callable = Interaction.context
		var supplied: Dictionary = query.call(world, commands, availability, position, _position, {}, board)
		_check(world.tile_calls == 0 and Repository.json_equivalent(supplied, expected), id + " supplied board preserves context without rebuild")
		_check(board == board_before, id + " shared query board remains immutable")
	measurements.append({"level": id, "commands": commands.size(), "uncachedTiles": uncached_calls, "scopedTiles": scoped_calls})

func _position(tile: Dictionary) -> Vector3:
	return Vector3(float(tile.get("x", 0)), float(tile.get("h", 0)) * 0.65, float(tile.get("z", 0)))

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
