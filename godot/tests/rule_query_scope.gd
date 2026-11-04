extends SceneTree
## Pure-command query owns one board; no cache survives an action and tiles remain independent.
const World = preload("res://core/garden_world.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")

class CountedWorld:
	extends "res://core/garden_world.gd"
	var tile_calls: int = 0
	func tiles() -> Array:
		tile_calls += 1
		return super.tiles()

var failures: Array = []
var checks: int = 0
var logger = ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	for id: String in ["1-1", "2-2"]:
		var world = CountedWorld.new(id)
		var before: Dictionary = world.snapshot()
		world.tile_calls = 0
		var commands: Array = world.commands()
		_check(world.tile_calls == 1, id + "/one derived board supplies all command proximity checks")
		_check(Snapshot.equivalent(before, world.snapshot()) and not world.can_undo(), id + "/command query changes neither state nor history")
		var first: Array = world.tiles()
		var second: Array = world.tiles()
		var expected: Array = second.duplicate(true)
		first.pop_back()
		first[0].x = -999
		_check(Snapshot.equivalent(second, expected) and Snapshot.equivalent(world.tiles(), expected), id + "/separate tile arrays and entries do not alias")
		if id == "1-1":
			var old_board: Array = world.tiles()
			_check(world.act("grow:root:right").ok, id + "/real action succeeds after querying")
			var new_board: Array = world.tiles()
			var old_has: bool = old_board.any(func(tile: Dictionary) -> bool: return tile.id == "g:root:1:0")
			var new_has: bool = new_board.any(func(tile: Dictionary) -> bool: return tile.id == "g:root:1:0")
			_check(not old_has and new_has, id + "/the next action sees new geometry rather than a previous query board")
		else:
			_check(world.act("switch").ok, id + "/switch succeeds after querying")
			var next_commands: Array = world.commands()
			var old_switch: String = ""
			var new_switch: String = ""
			for command: Dictionary in commands:
				if command.id == "switch": old_switch = command.label
			for command: Dictionary in next_commands:
				if command.id == "switch": new_switch = command.label
			_check(old_switch != new_switch and new_switch == "换手：操控露薇", id + "/the next command query uses the new actor")
	failures.append_array(logger.captured_errors())
	print(JSON.stringify({"suite": "garden-query-scope", "passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)
