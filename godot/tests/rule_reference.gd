extends SceneTree
## Run with --headless --path godot --script res://tests/rule_reference.gd.
## All fixtures come from the unchanged JS model, including per-tile movement.

const World = preload("res://core/garden_world.gd")
var _checks: int = 0
var _commands: int = 0
var _cases: int = 0
var _failed: bool = false

func _initialize() -> void:
	var reference_path: String = "res://tests/fixtures/reference.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--reference="): reference_path = argument.trim_prefix("--reference=")
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	if not fixture is Dictionary or fixture.get("format") != "sporelight.rule-reference":
		push_error("Missing or invalid JS rule reference: " + reference_path)
		quit(2)
		return
	for entry: Dictionary in fixture.cases:
		var world = World.new(str(entry.levelId), entry.get("saved", {}))
		_check(entry.initial, _observe(world), str(entry.name) + "/initial")
		for index: int in range(entry.steps.size()):
			if _failed: break
			var step: Dictionary = entry.steps[index]
			var command: Dictionary = step.command
			var result: Dictionary = {}
			match str(command.kind):
				"move": result = world.move(str(command.value))
				"act": result = world.act(str(command.value), command.get("internal", false))
				"undo": result = {"ok": world.undo()}
				"restore":
					world = World.new(str(entry.levelId), world.snapshot())
					result = {"ok": true}
			var actual: Dictionary = _observe(world)
			actual.command = command
			actual.result = result
			var label: String = "%s/step-%d/%s/%s" % [entry.name, index, command.kind, command.value]
			_check(step, actual, label)
			var restored = World.new(str(entry.levelId), JSON.parse_string(JSON.stringify(world.snapshot())))
			_check(world.snapshot(), restored.snapshot(), label + "/snapshot-roundtrip")
			_check(world.tiles(), world.tiles_for_state(world.snapshot()), label + "/future-world-isolation")
			_commands += 1
		_cases += 1
		if _failed: break
	if not _failed:
		_validate_saves(reference_path.get_base_dir().path_join("save-cases.json"))
	print(JSON.stringify({"suite": "garden-rule-reference", "passed": not _failed, "cases": _cases, "commands": _commands, "checks": _checks, "referenceCommit": fixture.referenceCommit}))
	quit(1 if _failed else 0)

func _observe(world: RefCounted) -> Dictionary:
	return {"snapshot": world.snapshot(), "tiles": world.tiles(), "commands": world.commands(), "ready": world.ready(), "together": world.together(), "budget": world.budget(), "rays": world.rays(), "lampRay": world.lamp_ray(), "hint": world.hint(), "canUndo": world.can_undo()}

func _validate_saves(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		_failed = true
		push_error("Missing save fixtures: " + path)
		return
	for entry: Dictionary in data.cases:
		var world = World.new(str(entry.levelId), entry.input)
		_check(entry.expected, world.snapshot(), "save/" + str(entry.name))
		if _failed: return

func _check(expected: Variant, actual: Variant, label: String) -> void:
	_checks += 1
	var difference: String = _difference(expected, actual, "$")
	if difference != "":
		_failed = true
		push_error(label + ": " + difference)

func _difference(expected: Variant, actual: Variant, path: String) -> String:
	if expected == null or actual == null:
		return "" if expected == actual else "%s expected %s; got %s" % [path, expected, actual]
	if (expected is int or expected is float) and (actual is int or actual is float):
		return "" if float(expected) == float(actual) else "%s expected %s; got %s" % [path, expected, actual]
	if expected is Dictionary and actual is Dictionary:
		if expected.size() != actual.size(): return "%s keys expected %s; got %s" % [path, expected.keys(), actual.keys()]
		for key: Variant in expected:
			if not actual.has(key): return "%s missing key %s" % [path, key]
			var difference: String
			if key == "trial" and expected[key] is String and actual[key] is String:
				difference = _difference(JSON.parse_string(expected[key]), JSON.parse_string(actual[key]), path + ".trial(JSON)")
			else:
				difference = _difference(expected[key], actual[key], path + "." + str(key))
			if difference != "": return difference
		return ""
	if expected is Array and actual is Array:
		if expected.size() != actual.size(): return "%s length expected %d; got %d" % [path, expected.size(), actual.size()]
		for index: int in range(expected.size()):
			var difference: String = _difference(expected[index], actual[index], "%s[%d]" % [path, index])
			if difference != "": return difference
		return ""
	return "" if expected == actual else "%s expected %s; got %s" % [path, expected, actual]
