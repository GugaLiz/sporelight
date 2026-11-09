extends "res://tests/rule_application.gd"
## Real HUD/controller lifecycle contracts with in-memory saves and observable
## view/audio adapters. Signal emission does not certify pointer hit testing,
## browser rendering, audible playback or operating-system dialogs.

const RealHUD := preload("res://ui/garden_hud.gd")

class ObservableView:
	extends QuietView
	var paused_state := false
	var applied_settings: Dictionary = {}
	func set_paused(value: bool) -> void:
		paused_state = value
	func set_settings(value: Dictionary) -> void:
		applied_settings = value.duplicate(true)

class ObservableAudio:
	extends QuietAudio
	var paused_state := false
	var applied_settings: Dictionary = {}
	func start() -> void:
		super.start()
		paused_state = false
	func pause(value: bool) -> void:
		paused_state = value
	func configure(value: Dictionary) -> void:
		applied_settings = value.duplicate(true)

func _real_app(id: String = "1-1", saved: Dictionary = {}) -> Node:
	var app := _app(id, saved)
	for child: Node in [app.hud, app.view, app.audio]:
		app.remove_child(child)
		child.free()
	app.view = ObservableView.new()
	app.audio = ObservableAudio.new()
	app.hud = RealHUD.new()
	app.add_child(app.view)
	app.add_child(app.audio)
	app.add_child(app.hud)
	app.hud.set_repository(app.repository)
	app.hud.command_requested.connect(app._on_command)
	app.hud.menu_requested.connect(app._show_menu)
	app.hud.level_requested.connect(app._enter_level)
	app.hud.settings_changed.connect(app._configure)
	app._apply_settings()
	app._sync_hud()
	return app

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

func _press(app: Node, text: String, label: String) -> void:
	var button := _find_button(app.hud, text)
	_check(button != null, label + "/actual-button-exists")
	if button == null:
		return
	_check(not button.disabled, label + "/actual-button-enabled")
	if not button.disabled:
		button.pressed.emit()

func _paused_modal(app: Node, label: String) -> void:
	_check(app.hud.is_modal_open(), label + "/modal-is-open")
	_check(app.paused and app.view.paused_state and app.audio.paused_state, label + "/controller-view-and-audio-are-paused")

func _returned(app: Node, label: String) -> void:
	_check(not app.hud.is_modal_open(), label + "/modal-is-actually-gone")
	_check(not app.paused and not app.view.paused_state and not app.audio.paused_state, label + "/controller-view-and-audio-resume-together")
	_check(not app._locked(), label + "/normal-actions-are-unlocked")

func _walk_once(app: Node, label: String) -> void:
	var point: Dictionary = app.session.world.point()
	var direction := ""
	var target := ""
	for neighbor: Dictionary in app.session.world.neighbors(str(point.id)):
		var delta := Vector2i(int(neighbor.x) - int(point.x), int(neighbor.z) - int(point.z))
		for candidate: String in Router.OFFSETS:
			if delta == Router.OFFSETS[candidate]:
				direction = candidate
				target = str(neighbor.id)
				break
		if not direction.is_empty():
			break
	_check(not direction.is_empty(), label + "/fixture-has-a-legal-cardinal-neighbor")
	if direction.is_empty():
		return
	var revision: int = app.session.revision
	app._step(direction)
	_drain(app, label)
	_check(app.session.revision == revision + 1 and app.session.world.state.actors.luvie == target, label + "/real-controller-direction-reaches-the-neighbor")

func _normal_return_paths() -> void:
	for entry: String in ["menu", "settings", "map-settings", "journal", "gallery", "save"]:
		var app := _real_app()
		var before: Dictionary = app.session.world.snapshot()
		if entry == "settings":
			app._on_command("settings")
		else:
			app._show_menu()
			if entry == "map-settings":
				_press(app, "设置", entry)
			elif entry == "journal":
				_press(app, "花园纪事", entry)
			elif entry == "gallery":
				_press(app, "图鉴", entry)
			elif entry == "save":
				_press(app, "导入 / 导出旅程", entry)
		_paused_modal(app, "normal/" + entry)
		_press(app, "继续当前关卡", "normal/" + entry)
		_returned(app, "normal/" + entry)
		_same(before, app.session.world.snapshot(), "normal/" + entry + "/navigation-does-not-change-the-world")
		_walk_once(app, "normal/" + entry)
		app.free()

func _completed_return_paths() -> void:
	var completed: Dictionary = _fixture("authored/1-1").steps.back().snapshot
	for entry: String in ["menu", "settings", "journal", "gallery", "save"]:
		var app := _real_app("1-1", completed)
		app.repository.stage_run(completed)
		var memory: Dictionary = app.repository.data.mainline.memories["1-1"].duplicate(true)
		var active: Dictionary = app.repository.data.mainline.runs["1-1"].duplicate(true)
		app.hud.show_ending(app.session.world.level, app.session.world.snapshot())
		_press(app, "返回地图", "completed/" + entry)
		if entry == "settings":
			_press(app, "设置", "completed/" + entry)
		elif entry == "journal":
			_press(app, "花园纪事", "completed/" + entry)
		elif entry == "gallery":
			_press(app, "图鉴", "completed/" + entry)
		elif entry == "save":
			_press(app, "导入 / 导出旅程", "completed/" + entry)
		_paused_modal(app, "completed/" + entry)
		_press(app, "继续当前关卡", "completed/" + entry)
		_returned(app, "completed/" + entry)
		_check(app.strolling and app.session.world.state.completed, "completed/" + entry + "/return-enters-completed-stroll")
		_walk_once(app, "completed/" + entry)
		_same(memory, app.repository.data.mainline.memories["1-1"], "completed/" + entry + "/walking-preserves-completion-memory")
		_same(active, app.repository.data.mainline.runs["1-1"], "completed/" + entry + "/walking-does-not-rewrite-the-run")
		app.free()

func _review_is_direct_stroll() -> void:
	var app := _real_app()
	var completed: Dictionary = _fixture("authored/1-1").steps.back().snapshot
	app.repository.stage_run(completed)
	app._step("left")
	_drain(app, "review/arrange-active-run")
	var active: Dictionary = app.repository.data.mainline.runs["1-1"].duplicate(true)
	var memory: Dictionary = app.repository.data.mainline.memories["1-1"].duplicate(true)
	app._show_menu()
	_press(app, "花园纪事", "review/journal")
	_press(app, "看看修复后的花园", "review/enter")
	_returned(app, "review/enter")
	_check(app.reviewing and app.strolling and app.session.world.state.completed, "review/enter-loads-the-memory-directly-as-a-stroll")
	_same(memory, app.session.world.snapshot(), "review/initial-world-is-the-archived-memory")
	_walk_once(app, "review/walking")
	_same(active, app.repository.data.mainline.runs["1-1"], "review/does-not-replace-the-active-run")
	_same(memory, app.repository.data.mainline.memories["1-1"], "review/does-not-replace-the-memory")
	app.free()

func _completed_undo_availability() -> void:
	var completed: Dictionary = _fixture("authored/1-1").steps.back().snapshot
	var app := _real_app("1-1", completed)
	app.repository.stage_run(completed)
	app.hud.show_ending(app.session.world.level, app.session.world.snapshot())
	_press(app, "留下看看", "completed-undo/enter-stroll")
	_walk_once(app, "completed-undo/create-real-history")
	_check(app.session.world.can_undo(), "completed-undo/real-completed-walk-creates-raw-history")
	app._sync_hud()
	var undo := _find_button(app.hud, "撤销")
	_check(undo != null, "completed-undo/actual-undo-tool-exists")
	var completed_reason := ""
	if undo != null:
		completed_reason = undo.tooltip_text.strip_edges()
		_check(undo.disabled, "completed-undo/tool-remains-disabled-despite-raw-history")
		_check(("修复" in completed_reason or "完成" in completed_reason) and ("退回" in completed_reason or "撤销" in completed_reason), "completed-undo/disabled-tooltip-explains-the-completion-rule")
	app._enter_level("1-1")
	_check(not app.session.world.state.completed, "completed-undo/ordinary-entry-creates-an-unfinished-run")
	_walk_once(app, "completed-undo/new-unfinished-history")
	app._sync_hud()
	undo = _find_button(app.hud, "撤销")
	_check(undo != null and app.session.world.can_undo() and not undo.disabled, "completed-undo/unfinished-legal-move-enables-undo-again")
	if undo != null:
		_check(not completed_reason.is_empty() and not undo.tooltip_text.contains(completed_reason), "completed-undo/unfinished-tool-clears-the-completion-only-reason")
	app.free()

func _ending_caption_follows_catalog() -> void:
	for sample: Dictionary in [
		{"id": "1-1", "reverse": false, "caption": "去下一片微光 ↗"},
		{"id": "3-4", "reverse": false, "caption": "看看一路的纪事 ↗"},
		{"id": "1-1", "reverse": true, "caption": "看看一路的纪事 ↗"},
		{"id": "3-4", "reverse": true, "caption": "去下一片微光 ↗"}
	]:
		var completed: Dictionary = _fixture("authored/" + str(sample.id)).steps.back().snapshot
		var app := _real_app(str(sample.id), completed)
		app.levels = _levels.duplicate()
		if sample.reverse:
			app.levels.reverse()
		var original_level: Dictionary = app.session.world.level.duplicate(true)
		app._show_ending()
		var next := _find_button(app.hud, str(sample.caption))
		var label := "ending-caption/%s/reversed-%s" % [sample.id, str(sample.reverse)]
		_check(next != null and next.get_meta("action", "") == "next", label + "/caption-matches-the-actual-catalog-navigation")
		_same(original_level, app.session.world.level, label + "/UI-property-does-not-change-the-rule-level")
		app.free()

func _resume_cannot_bypass_a_modal() -> void:
	var app := _real_app()
	app._on_command("settings")
	var before: Dictionary = app.session.world.snapshot()
	app._on_command("resume")
	_paused_modal(app, "resume/visible-modal")
	app._step("left")
	_check(app.motion.is_empty(), "resume/visible-modal-cannot-start-a-background-move")
	_same(before, app.session.world.snapshot(), "resume/visible-modal-preserves-the-world")
	_press(app, "继续当前关卡", "resume/actual-close")
	_returned(app, "resume/actual-close")
	app.free()

func _set_import_text(app: Node, value: String) -> void:
	var editors: Array[Node] = app.hud._overlay.find_children("", "TextEdit", true, false)
	_check(editors.size() == 1, "import/real-editor-exists")
	if editors.size() == 1:
		editors[0].text = value
	_press(app, "检查粘贴的旅程", "import/preview")

func _import_candidate() -> Dictionary:
	var candidate: Dictionary = Repository.empty_store()
	candidate.player.name = "生命周期校验"
	candidate.settings.safeCamera = true
	candidate.settings.continuousInput = false
	candidate.settings.bgm = 0.18
	candidate.settings["futurePreference"] = {"enabled": true}
	candidate.mainline.last_level = "1-2"
	candidate.mainline.runs["1-2"] = _fixture("authored/1-2").initial.snapshot.duplicate(true)
	return candidate

func _import_lifecycle() -> void:
	var app := _real_app()
	app.hud.show_save_tools(app.repository)
	_paused_modal(app, "import/before-confirm")
	var candidate := _import_candidate()
	_set_import_text(app, JSON.stringify(candidate))
	_press(app, "确认导入", "import/confirm")
	_returned(app, "import/success")
	_check(app.storage_ready and app.session.world.level.id == "1-2", "import/success-enters-the-imported-level")
	_check(app.repository.commits == 1, "import/success-does-not-add-an-extra-save")
	_check(app.safe_camera and not app.input_router.continuous and app.settings.bgm == 0.18, "import/success-applies-the-imported-runtime-settings")
	_same(candidate.settings.futurePreference, app.settings.futurePreference, "import/success-retains-unknown-settings")
	_same(app.settings, app.view.applied_settings, "import/success-applies-view-settings")
	_same(app.settings, app.audio.applied_settings, "import/success-applies-audio-settings")
	_same(app.repository.persisted, app.repository.data, "import/success-runtime-entry-does-not-change-the-accepted-store")
	app.free()
	for failure: String in ["invalid-json", "write-failure"]:
		app = _real_app()
		var before: Dictionary = app.session.world.snapshot()
		var store: Dictionary = app.repository.data.duplicate(true)
		app.hud.show_save_tools(app.repository)
		if failure == "invalid-json":
			_set_import_text(app, "{broken")
			var confirm := _find_button(app.hud, "确认导入")
			_check(confirm != null and confirm.disabled, "import/invalid-json-cannot-be-confirmed")
		else:
			_set_import_text(app, JSON.stringify(_import_candidate()))
			app.repository.fail_writes = true
			_press(app, "确认导入", "import/write-failure")
		_paused_modal(app, "import/" + failure)
		_same(before, app.session.world.snapshot(), "import/" + failure + "/preserves-the-active-world")
		_same(store, app.repository.data, "import/" + failure + "/preserves-the-store")
		app.free()

func _modal_resize_contract() -> void:
	for dimensions: Vector2i in [Vector2i(594, 462), Vector2i(390, 844), Vector2i(568, 320), Vector2i(1280, 720)]:
		root.size = Vector2i(1280, 720)
		var app := _real_app()
		app._on_command("settings")
		await process_frame
		await process_frame
		root.size = dimensions
		await process_frame
		await process_frame
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		var scrollers: Array[Node] = app.hud._overlay.find_children("", "ScrollContainer", true, false)
		var label := "resize/%dx%d" % [dimensions.x, dimensions.y]
		_check(scrollers.size() == 1, label + "/real-modal-scroll-exists")
		if scrollers.size() == 1:
			var scroll: ScrollContainer = scrollers[0]
			var paper: PanelContainer
			var ancestor: Node = scroll.get_parent()
			while ancestor != null and ancestor != app.hud._overlay:
				if ancestor is PanelContainer:
					paper = ancestor
				ancestor = ancestor.get_parent()
			_check(paper != null, label + "/scroll-has-an-actual-paper-ancestor")
			if paper != null:
				_check(viewport.grow(0.5).encloses(paper.get_global_rect()), label + "/paper-stays-in-the-viewport")
			_check(viewport.grow(0.5).encloses(scroll.get_global_rect()), label + "/scroll-hit-region-stays-in-the-viewport")
			scroll.scroll_vertical = ceili(scroll.get_v_scroll_bar().max_value)
			await process_frame
			await process_frame
			var back := _find_button(app.hud, "继续当前关卡")
			_check(back != null, label + "/return-button-exists")
			if back != null:
				var hit := back.get_global_rect().intersection(scroll.get_global_rect()).intersection(viewport)
				_check(hit.size.x >= 44.0 and hit.size.y >= 40.0, label + "/scrolled-return-retains-a-real-hit-area")
		app.free()
	root.size = Vector2i(1280, 720)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	_levels = content.levels
	_reference = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	_normal_return_paths()
	_completed_return_paths()
	_review_is_direct_stroll()
	_completed_undo_availability()
	_ending_caption_follows_catalog()
	_resume_cannot_bypass_a_modal()
	_import_lifecycle()
	await _modal_resize_contract()
	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite": "service-modal-lifecycle", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "scope": "Real HUD/controller with in-memory saves and observable view/audio adapters; emitted pressed signals and headless layout are not real pointer, GPU or audible-playback verification."}))
	quit(0 if _failures.is_empty() else 1)
