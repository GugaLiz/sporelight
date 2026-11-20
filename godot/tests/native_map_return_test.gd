extends "res://tests/service_modal_lifecycle_test.gd"
## Current-session selection must not depend on the last movement save.
func _run() -> void:
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	_levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	_reference = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var app := _real_app("3-4")
	app.unlock_all_levels = true
	for id: String in ["3-2","2-2","2-4","1-3"]:
		app._enter_level(id)
		app.repository.data.mainline.last_level = "3-4"
		var saved: Dictionary = app.repository.data.duplicate(true)
		app._on_command("map")
		_check(app.hud._chapter_map.selected_id == id, id + " immediately returns to its own map node despite stale 3-4 save")
		_same(saved,app.repository.data,id + " map selection never rewrites saves")
		app.hud.close_overlay()
	app._show_home(false)
	app._show_menu()
	_check(app.hud._chapter_map.selected_id == "3-4", "home map still uses saved journey instead of the dormant session")
	app.free()
	print(JSON.stringify({"suite":"map-return","checks":_checks,"failures":_failures,"passed":_failures.is_empty()}))
	quit(0 if _failures.is_empty() else 1)
