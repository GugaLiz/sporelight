extends "res://tests/rule_reference.gd"
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save-cases.json"))
	for entry: Dictionary in source.cases:
		if str(entry.name) != "1-2/json-numeric-enums": continue
		var normalized: Dictionary = World.new("1-2").normalize_saved(entry.input)
		var expected: Dictionary = entry.expected.duplicate(true)
		var original := _difference(expected,normalized.snapshot,"$")
		expected.layoutRevision = 2
		print(JSON.stringify({"ok":normalized.ok,"original_difference":original,"difference_after_explicit_revision2":_difference(expected,normalized.snapshot,"$"),"normalized":normalized.snapshot}))
	quit()
