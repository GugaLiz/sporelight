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
	var selected_level := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="): selected_level = argument.trim_prefix("--level=")
		if argument.begins_with("--reference="): reference_path = argument.trim_prefix("--reference=")
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	if not fixture is Dictionary or fixture.get("format") != "sporelight.rule-reference":
		push_error("Missing or invalid JS rule reference: " + reference_path)
		quit(2)
		return
	for entry: Dictionary in fixture.cases:
		if not selected_level.is_empty() and str(entry.levelId) != selected_level: continue
		var world = World.new(str(entry.levelId), entry.get("saved", {}))
		_check(_shadow_feedback_reference(entry.initial) if entry.levelId == "3-2" else entry.initial, _observe(world), str(entry.name) + "/initial")
		for index: int in range(entry.steps.size()):
			if _failed: break
			var step: Dictionary = entry.steps[index]
			var command: Dictionary = step.command
			var before_state: Dictionary = world.snapshot()
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
			_check(_shadow_feedback_reference(step, before_state) if entry.levelId == "3-2" else step, actual, label)
			var restored = World.new(str(entry.levelId), JSON.parse_string(JSON.stringify(world.snapshot())))
			_check(world.snapshot(), restored.snapshot(), label + "/snapshot-roundtrip")
			_check(world.tiles(), world.tiles_for_state(world.snapshot()), label + "/future-world-isolation")
			_commands += 1
		_cases += 1
		if _failed: break
	if not _failed and selected_level.is_empty():
		_validate_saves(reference_path.get_base_dir().path_join("save-cases.json"))
	print(JSON.stringify({"suite": "garden-rule-reference", "passed": not _failed, "cases": _cases, "commands": _commands, "checks": _checks, "referenceCommit": fixture.referenceCommit}))
	quit(1 if _failed else 0)

func _observe(world: RefCounted) -> Dictionary:
	return {"snapshot": world.snapshot(), "tiles": world.tiles(), "commands": world.commands(), "ready": world.ready(), "together": world.together(), "budget": world.budget(), "rays": world.rays(), "lampRay": world.lamp_ray(), "hint": world.hint(), "canUndo": world.can_undo()}

func _shadow_feedback_reference(expected: Dictionary, before_state: Dictionary = {}) -> Dictionary:
	# Explicit 2026-11-14 presentation copy migration only. Keep the immutable
	# TS fixture and compare every command, field and result, including exact
	# new text. Unknown old wording is never silently ignored or normalized.
	var result: Dictionary = expected.duplicate(true)
	const DROP_LABELS := {
		"日影柱": {"放在脚边的固定地面": "日影柱：放在脚边的固定地面", "放到日影柱槽": "日影柱：放到日影柱槽", "放到月影柱槽": "日影柱：放到月影柱槽"},
		"月影柱": {"放在脚边的固定地面": "月影柱：放在脚边的固定地面", "放到日影柱槽": "月影柱：放到日影柱槽", "放到月影柱槽": "月影柱：放到月影柱槽"}
	}
	for command: Dictionary in result.get("commands", []):
		var id := str(command.id)
		if id == "switch":
			const SWITCH_LABELS := {"换手：操控小苔灵": "切换角色：操控小苔灵", "换手：操控露薇": "切换角色：操控露薇", "换手看看花园": "切换角色看看花园"}
			command.label = SWITCH_LABELS.get(command.label, command.label)
		elif id == "take:sunPost" and command.label == "搬起日月影柱": command.label = "搬起日影柱"
		elif id == "take:moonPost" and command.label == "搬起日月影柱": command.label = "搬起月影柱"
		elif id.begins_with("drop:sunPost:") or id.begins_with("drop:moonPost:"):
			var name := "日影柱" if id.begins_with("drop:sunPost:") else "月影柱"
			command.label = DROP_LABELS[name].get(command.label, command.label)
	if not result.has("command") or result.command.kind != "act" or not result.result.has("message"): return result
	var id := str(result.command.value)
	var message := str(result.result.message)
	if id == "take:sunPost" and message == "稳稳带好了，沿接通的路继续走吧。": result.result.message = "日影柱已收进叶包。"
	elif id == "take:moonPost" and message == "稳稳带好了，沿接通的路继续走吧。": result.result.message = "月影柱已收进叶包。"
	elif id.begins_with("drop:sunPost:") and message == "稳稳放好了，看看光与道路有没有一起改变。": result.result.message = "日影柱已放稳。"
	elif id.begins_with("drop:moonPost:") and message == "稳稳放好了，看看光与道路有没有一起改变。": result.result.message = "月影柱已放稳。"
	elif id == "valve:mode" and message == "水位与落岸变化了，脚下的旅人和物件也一起移动。":
		result.result.message = ("庭院转为日光。" if int(result.snapshot.mode) == 0 else "庭院转为月光。") + ("留影苔记住的道路保持原样。" if result.snapshot.frozen != null else "")
	elif id == "freeze" and message == "留影苔记住了这段实际投影，再换一个时刻看看。":
		var name := "日影" if int(result.snapshot.mode) == 0 else "月影"
		result.result.message = "留影苔已用当前" + name + "替换上一次留影。" if before_state.get("frozen") != null else "留影苔记住了当前" + name + "。"
	elif id == "freeze" and message == "先把当前光照对应的影柱放到槽中，再留影。":
		var post_id := "sunPost" if int(before_state.get("mode", 0)) == 0 else "moonPost"
		var name := "日影柱" if post_id == "sunPost" else "月影柱"
		result.result.message = name + "还在手中，没有可留住的投影。" if before_state.get("items", {}).get(post_id, {}).get("holder", "") != "" else "当前没有可留住的投影。"
	return result

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
