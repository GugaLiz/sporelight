extends "res://tests/service_modal_lifecycle_test.gd"
## Home is a separate destination, not a closed pause overlay over 1-1.
## These are real HUD/controller contracts with memory-only saves. Emitted
## signals do not certify actual pointer hit testing, GPU pixels or audio.

func _home_app(id: String = "1-1", saved: Dictionary = {}) -> Node:
	var app := _real_app(id, saved)
	app.has_active_game = true
	return app

func _find_action(node: Node, action: String) -> Button:
	if node is Button and node.get_meta("action", "") == action and node.is_visible_in_tree():
		return node
	for child: Node in node.get_children():
		var found := _find_action(child, action)
		if found != null:
			return found
	return null

func _press_action(app: Node, action: String, label: String) -> void:
	var button := _find_action(app.hud, action)
	_check(button != null and not button.disabled, label + "/actual-visible-action-exists")
	if button != null and not button.disabled:
		button.pressed.emit()

func _hidden_game(app: Node, label: String) -> void:
	_check(app.home_active and app.paused, label + "/home-owns-navigation-and-pause")
	_check(not app.view.visible, label + "/level-world-is-hidden")
	_check(app.view.paused_state and app.audio.paused_state, label + "/world-and-audio-remain-paused")
	for node: Control in [app.hud._heading, app.hud._panel, app.hud._tools, app.hud._message_panel, app.hud._nav, app.hud._pad, app.hud._overview]:
		_check(not node.is_visible_in_tree(), label + "/level-control-hidden/" + str(node.name))

func _home(app: Node, label: String) -> void:
	_hidden_game(app, label)
	_check(app.hud.is_modal_open(), label + "/home-interface-is-present")
	_check(_find_action(app.hud, "map") != null, label + "/home-offers-start-journey")
	_check(_find_action(app.hud, "continue") != null, label + "/home-offers-an-explicit-continue-control")
	_check(_find_button(app.hud._overlay, "继续当前关卡") == null, label + "/home-does-not-pretend-to-be-a-pause-overlay")

func _active(app: Node, label: String) -> void:
	_returned(app, label)
	_check(not app.home_active and app.view.visible, label + "/actual-level-world-is-restored")
	_check(app.hud._heading.is_visible_in_tree() and app.hud._tools.is_visible_in_tree() and not app.hud._pad.is_visible_in_tree(), label + "/compact-desktop-controls-return-without-a-touch-pad")

func _event(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _home_is_a_real_destination() -> void:
	var app := _home_app()
	var before: Dictionary = app.session.world.snapshot()
	app._on_command("settings")
	_press(app, "返回主界面", "settings/home")
	_home(app, "settings/home")
	_same(before, app.session.world.snapshot(), "settings/home/does-not-mutate-the-puzzle")
	var revision: int = app.session.revision
	app._input(_event(KEY_LEFT))
	app._input(_event(KEY_LEFT, false))
	app._input(_event(KEY_E))
	app._step("left")
	app._go("f:-1:0")
	for unused: int in range(20):
		app._process(0.05)
	_same(before, app.session.world.snapshot(), "home/keyboard-and-world-click-cannot-change-the-hidden-level")
	_check(app.session.revision == revision and app.motion.is_empty(), "home/input-cannot-create-hidden-history-or-motion")
	app._on_command("resume")
	_home(app, "home/direct-resume-is-not-continue")
	app.hud.close_overlay()
	_home(app, "home/closing-the-home-surface-does-not-expose-1-1")
	app._input(_event(KEY_ESCAPE))
	_home(app, "home/escape-keeps-the-main-interface")
	_press_action(app, "continue", "home/continue")
	_active(app, "home/continue")
	_same(before, app.session.world.snapshot(), "home/continue-restores-the-stable-world")
	_walk_once(app, "home/continue-restores-real-controller-input")
	app.free()

func _home_map_and_child_pages() -> void:
	var app := _home_app()
	app._show_home(false)
	var before: Dictionary = app.session.world.snapshot()
	_press_action(app, "map", "home/start")
	_hidden_game(app, "home/map")
	var first: Button
	for node: Node in app.hud._overlay.find_children("", "Button", true, false):
		if node.text.begins_with("1-1  "):
			first = node
	_check(first != null and not first.disabled, "home/start/shows-a-real-unlocked-first-garden")
	_press(app, "返回主界面", "home/map/back")
	_home(app, "home/map/back")
	for entry: String in ["设置", "花园纪事", "图鉴", "导入 / 导出旅程"]:
		if entry in ["花园纪事", "图鉴"]:
			var exploration := _find_action(app.hud, "home_explore")
			exploration.button_pressed = true
		elif entry == "导入 / 导出旅程":
			_press(app, "设置", "home/child/save-settings")
		_press(app, entry, "home/child/" + entry)
		_hidden_game(app, "home/child/" + entry)
		_check(_find_button(app.hud._overlay, "继续当前关卡") == null, "home/child/" + entry + "/no-misleading-pause-resume")
		app._input(_event(KEY_ESCAPE))
		if entry == "导入 / 导出旅程":
			_check(app.hud._page_kind == "settings", "home/save/escape-restores-settings-first")
			app._input(_event(KEY_ESCAPE))
		_home(app, "home/child/" + entry + "/escape")
		_same(before, app.session.world.snapshot(), "home/child/" + entry + "/keeps-the-hidden-world-stable")
	_press_action(app, "map", "home/map/select")
	first = null
	for node: Node in app.hud._overlay.find_children("", "Button", true, false):
		if node.text.begins_with("1-1  "):
			first = node
	if first != null:
		first.pressed.emit()
	_active(app, "home/map/select")
	_same(before, app.session.world.snapshot(), "home/map/select/loads-the-real-stable-run")
	app.free()

func _home_discards_uncommitted_actions() -> void:
	for kind: String in ["growth-with-pending-undo", "mouse-route", "held-direction"]:
		var app := _home_app()
		var before: Dictionary = app.session.world.snapshot()
		if kind == "growth-with-pending-undo":
			app._on_command("primary")
			app._process(0.05)
			app._on_command("undo")
			_check(not app.pending_button.is_empty(), "home/cancel/" + kind + "/has-a-real-pending-intent")
		elif kind == "mouse-route":
			app._go("f:-2:0")
			app._process(0.0)
			_check(not app.route.is_empty(), "home/cancel/" + kind + "/has-a-real-remaining-route")
		else:
			app._input(_event(KEY_LEFT))
			_check(not app.input_router.held.is_empty(), "home/cancel/" + kind + "/has-a-real-held-key")
		_check(not app.motion.is_empty() and app.session.revision == 0, "home/cancel/" + kind + "/starts-before-the-original-command-commits")
		app._on_command("home")
		_home(app, "home/cancel/" + kind)
		_check(app.motion.is_empty() and app.route.is_empty() and app.pending_button.is_empty() and not app.waiting_repair, "home/cancel/" + kind + "/clears-old-motion-route-and-intents")
		_check(app.input_router.held.is_empty() and app.input_router.buffered_direction.is_empty(), "home/cancel/" + kind + "/clears-held-and-buffered-input")
		_same(before, app.session.world.snapshot(), "home/cancel/" + kind + "/never-commits-the-preview")
		_same(before, app.repository.data.mainline.runs["1-1"], "home/cancel/" + kind + "/saves-only-the-last-committed-world")
		_press_action(app, "continue", "home/cancel/" + kind + "/continue")
		_active(app, "home/cancel/" + kind + "/continue")
		for unused: int in range(30):
			app._process(0.05)
		_same(before, app.session.world.snapshot(), "home/cancel/" + kind + "/cannot-replay-a-ghost-action")
		_check(app.session.revision == 0, "home/cancel/" + kind + "/does-not-invent-history")
		app.free()

func _continue_preserves_seed_roads() -> void:
	var app := _home_app()
	app._on_command("primary")
	_drain(app, "home/road/plant")
	var planted: Dictionary = app.session.world.snapshot()
	_check(planted.growth.root == ["g:root:1:0"], "home/road/the-original-seed-rule-opens-the-road")
	app._step("right")
	app._process(0.05)
	_check(not app.motion.is_empty(), "home/road/returns-during-a-real-uncommitted-walk")
	app._on_command("home")
	_same(planted, app.repository.data.mainline.runs["1-1"], "home/road/saved-road-and-position-are-the-committed-state")
	_press_action(app, "continue", "home/road/continue")
	_active(app, "home/road/continue")
	_same(planted, app.session.world.snapshot(), "home/road/continue-keeps-the-original-grown-road")
	app._step("right")
	_drain(app, "home/road/walk-after-continue")
	_check(app.session.world.state.actors.luvie == "g:root:1:0", "home/road/the-restored-seed-road-is-actually-walkable")
	app.free()

func _continue_setting_is_separate_from_home() -> void:
	var app := _home_app()
	app._on_command("primary")
	app._process(0.05)
	app._on_command("settings")
	_press(app, "继续当前关卡", "settings/continue-current")
	_check(not app.home_active and app.view.visible and not app.paused and not app.hud.is_modal_open(), "settings/continue-current/returns-to-the-existing-level")
	_check(not app.motion.is_empty() and app.session.revision == 0, "settings/continue-current/keeps-the-paused-transaction-uncommitted")
	_drain(app, "settings/continue-current/finish")
	_check(app.session.revision == 1 and app.session.world.state.growth.root == ["g:root:1:0"], "settings/continue-current/original-growth-commits-once")
	app.free()

func _review_home_does_not_replace_progress() -> void:
	var app := _home_app()
	var completed: Dictionary = _fixture("authored/1-1").steps.back().snapshot
	app.repository.stage_run(completed)
	app._step("left")
	_drain(app, "home/review/active-run")
	var active: Dictionary = app.repository.data.mainline.runs["1-1"].duplicate(true)
	var memory: Dictionary = app.repository.data.mainline.memories["1-1"].duplicate(true)
	app._on_command("review:1-1")
	_check(app.reviewing and app.session.world.state.completed, "home/review/starts-from-a-real-completion-memory")
	app._on_command("home")
	_home(app, "home/review/return")
	_same(active, app.repository.data.mainline.runs["1-1"], "home/review/return-does-not-overwrite-the-active-run")
	_same(memory, app.repository.data.mainline.memories["1-1"], "home/review/return-does-not-overwrite-the-memory")
	_press_action(app, "continue", "home/review/continue")
	_active(app, "home/review/continue")
	_check(not app.reviewing and not app.session.world.state.completed, "home/review/continue-resumes-the-active-journey-not-the-archive")
	_same(active, app.session.world.snapshot(), "home/review/continue-restores-the-active-snapshot")
	_same(memory, app.repository.data.mainline.memories["1-1"], "home/review/continue-preserves-the-archive")
	app.free()

func _new_home_cannot_continue_a_hidden_initial_level() -> void:
	var app := _home_app()
	app.has_active_game = false
	app._show_home(false)
	_home(app, "home/new-journey")
	var button := _find_action(app.hud, "continue")
	_check(button != null and button.disabled, "home/new-journey/continue-is-unavailable-without-a-started-or-saved-journey")
	app._on_command("continue")
	_home(app, "home/new-journey/rejected-continue")
	app.free()

func _home_art_bytes_are_preserved() -> void:
	var repository := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	for path: String in ["main/bg.png", "material-ready/menu-logo.png"]:
		var actual := FileAccess.get_sha256("res://assets/images/" + path)
		var original := FileAccess.get_sha256(repository.path_join("assets/images/" + path))
		_check(not actual.is_empty() and actual == original, "home/art/" + path + "/uses-the-original-image-bytes")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	_levels = content.levels
	_reference = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	_home_is_a_real_destination()
	_home_map_and_child_pages()
	_home_discards_uncommitted_actions()
	_continue_preserves_seed_roads()
	_continue_setting_is_separate_from_home()
	_review_home_does_not_replace_progress()
	_new_home_cannot_continue_a_hidden_initial_level()
	_home_art_bytes_are_preserved()
	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite": "service-home-navigation", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "scope": "Real HUD/controller with memory saves and observable view/audio adapters. Emitted pressed signals and state assertions do not certify real pointer hit testing, artwork pixels or audible playback."}))
	quit(0 if _failures.is_empty() else 1)
