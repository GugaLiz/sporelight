extends "res://tests/service_modal_lifecycle_test.gd"
## Actual HUD/controller and in-memory saves; no user repository is read.
func _action(app: Node, action: String) -> Button:
	for button: Node in app.hud.find_children("*", "Button", true, false):
		if button.get_meta("action", "") == action and button.is_visible_in_tree(): return button
	return null

func _run() -> void:
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	_levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	_reference = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var app := _real_app()
	app.has_active_game = false
	app._show_home(false)
	for unused in 5: await process_frame
	_check(_action(app,"continue") == null, "first visit has no unavailable continue control")
	_check(_action(app,"journey_start").text == "开始旅程", "first visit offers start journey")
	for label: String in ["图鉴", "纪事", "设置"]:
		_check(_find_button(app.hud,label).is_visible_in_tree(), "permanent home entry " + label)
	_action(app,"journey_start").pressed.emit()
	_check(not app.home_active and not app.paused and str(app.session.world.level.id) == "1-1", "start directly enters a real first garden")
	app.free()
	app = _real_app("1-2")
	app.repository.data.mainline.records["1-1"] = {"completed":true,"collected":2,"stars":2}
	app.repository.data.mainline.memories["1-1"] = _fixture("authored/1-1").steps.back().snapshot.duplicate(true)
	app.repository.data.gallery["first-sprout"] = {"seen":true}
	app.repository.data.mainline.runs["1-1"] = _fixture("authored/1-1").steps[1].snapshot.duplicate(true)
	app.has_active_game = true
	app._show_home()
	for unused in 5: await process_frame
	var records: Dictionary = app.repository.data.mainline.records.duplicate(true)
	var memories: Dictionary = app.repository.data.mainline.memories.duplicate(true)
	var gallery: Dictionary = app.repository.data.gallery.duplicate(true)
	var other_run: Dictionary = app.repository.data.mainline.runs["1-2"].duplicate(true)
	var saved_before: Dictionary = app.repository.data.duplicate(true)
	var world_before: Dictionary = app.session.world.snapshot().duplicate(true)
	_action(app,"ending_preview").pressed.emit()
	for unused in 3: await process_frame
	_check(is_instance_valid(app.hud._journey_ending), "home debug entry opens the actual ending")
	_check(app.home_active and app.paused, "preview keeps the home session paused")
	_find_button(app.hud,"留下看看").pressed.emit()
	for unused in 3: await process_frame
	_check(app.hud._page_kind == "home", "preview stay returns to home without a completed game")
	_action(app,"ending_preview").pressed.emit()
	app.hud.navigate_back()
	for unused in 8: await process_frame
	_check(app.hud._page_kind == "home", "preview back restores home")
	_same(saved_before,app.repository.data,"ending preview preserves all save data")
	_same(world_before,app.session.world.snapshot(),"ending preview preserves current puzzle")
	var resume := _action(app,"continue")
	var restart := _action(app,"journey_start")
	_check(resume.get_global_rect().end.y <= restart.get_global_rect().position.y, "continue is above restart")
	_check(resume.get_meta("cover_primary",false) and not restart.get_meta("cover_primary",false), "only continue carries the primary paper treatment")
	restart.pressed.emit()
	_check(str(app.session.world.level.id) == "1-1" and app.session.world.state.growth.root.is_empty() and not app.session.world.state.completed, "restart enters a fresh first puzzle")
	_same(records,app.repository.data.mainline.records,"restart retains unlocked completion records")
	_same(memories,app.repository.data.mainline.memories,"restart retains journal memories")
	_same(gallery,app.repository.data.gallery,"restart retains collection gallery")
	_same(other_run,app.repository.data.mainline.runs["1-2"],"restart retains other unfinished gardens")
	app.free()
	print(JSON.stringify({"suite":"menu-home-entry","checks":_checks,"failures":_failures,"passed":_failures.is_empty()}))
	quit(0 if _failures.is_empty() else 1)
