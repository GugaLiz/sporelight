extends SceneTree
## Import validation must report whether legacy normalization succeeded, never trust fallback.
const World = preload("res://core/garden_world.gd")
var _checks: int = 0
var _failures: Array = []

func _initialize() -> void:
	var source = World.new("1-1")
	source.move("f:-1:0")
	var live: Dictionary = source.snapshot()
	var valid: Dictionary = World.new("1-1").snapshot()
	var accepted: Dictionary = source.normalize_saved(valid)
	_check(accepted.ok and _equal(accepted.snapshot, valid), "Current valid initial snapshot is explicitly accepted")
	_check(_equal(source.snapshot(), live) and source.can_undo(), "Normalization does not mutate the live state or Undo history")
	var invalid: Dictionary = valid.duplicate(true)
	invalid.actors = {"luvie": "void", "buddy": "void"}
	var rejected: Dictionary = source.normalize_saved(invalid)
	_check(not rejected.ok and rejected.snapshot.is_empty(), "A rejected position is not reported as a valid initial fallback")
	invalid = valid.duplicate(true)
	invalid.designVersion = 99
	_check(not source.normalize_saved(invalid).ok, "Unsupported state versions are rejected")
	invalid = valid.duplicate(true)
	invalid.levelId = "1-2"
	_check(not source.normalize_saved(invalid).ok, "A snapshot cannot be normalized as a different level")
	invalid = valid.duplicate(true)
	invalid.shadowMemory = [{"x": 1, "z": 0, "h": false}, {"x": 2, "z": 0, "h": 0}]
	_check(not source.normalize_saved(invalid).ok, "Boolean shadow height is rejected rather than coerced to numeric zero")

	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id: String in ["2-1", "3-3"]:
		var carried: Dictionary = {}
		for entry: Dictionary in fixture.cases:
			if entry.name != "authored/" + id: continue
			for step: Dictionary in entry.steps:
				if step.command.kind == "act" and step.command.value == "take:dew":
					carried = step.snapshot.duplicate(true)
					break
		_check(not carried.is_empty(), id + " has a real carried-dew fixture")
		var legacy: Dictionary = carried.duplicate(true)
		legacy.erase("discovered")
		legacy.items.dew.erase("picked")
		var original: String = JSON.stringify(legacy)
		var world = World.new(id)
		var normalized: Dictionary = world.normalize_saved(legacy)
		_check(normalized.ok, id + " valid old save with missing optional presentation fields imports")
		_check(_equal(normalized.snapshot, carried), id + " normalization fills fields without resetting progress or position")
		_check(JSON.stringify(legacy) == original, id + " the source backup remains unchanged")

	var save_cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save-cases.json"))
	for entry: Dictionary in save_cases.cases:
		if not str(entry.name).ends_with("json-numeric-enums"): continue
		var world = World.new(str(entry.levelId))
		var normalized: Dictionary = world.normalize_saved(entry.input)
		if entry.levelId == "2-1":
			# Raising this initial fixture submerges its uncarried dew; JS constructor also rejects it.
			_check(not normalized.ok, "2-1 numeric enum fixture still rejects a submerged critical item")
		else:
			_check(normalized.ok and _equal(normalized.snapshot, entry.expected), str(entry.name) + " JSON float enum values preserve rules")
	for pair: Array in [["2-1", "valve:water"], ["3-2", "freeze"]]:
		for entry: Dictionary in fixture.cases:
			if entry.name != "authored/" + str(pair[0]): continue
			for step: Dictionary in entry.steps:
				if step.command.kind != "act" or step.command.value != pair[1]: continue
				var world = World.new(str(pair[0]))
				var normalized: Dictionary = world.normalize_saved(step.snapshot)
				_check(normalized.ok and _equal(normalized.snapshot, step.snapshot), str(pair[0]) + " actual saved numeric water/frozen state is accepted without fallback")
				break

	var root_world = World.new("1-2")
	var bad_root: Dictionary = root_world.snapshot()
	bad_root.growth.root = [123]
	_check(not root_world.normalize_saved(bad_root).ok, "Malformed root members are rejected before deriving geometry")
	var mirror_world = World.new("2-2")
	var two_hands: Dictionary = mirror_world.snapshot()
	for item: Dictionary in two_hands.items.values():
		item.tile = ""
		item.holder = "luvie"
	_check(not mirror_world.normalize_saved(two_hands).ok, "Import cannot normalize two objects into one character's hands")
	print(JSON.stringify({"suite": "garden-snapshot-normalization", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)

func _equal(a: Variant, b: Variant) -> bool:
	# JSON canonicalizes harmless int/float storage representation; field/array values remain exact.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error(label)
