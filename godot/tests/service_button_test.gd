extends "res://tests/rule_application.gd"
## Button intents run through the real controller/session. The store is memory
## only, and the real HUD is used for widget identity/settings assertions.
const RealHUD := preload("res://ui/garden_hud.gd")

func _real_app(id: String = "1-1") -> Node:
	var app: Node = _app(id)
	app.remove_child(app.hud)
	app.hud.free()
	app.hud = RealHUD.new()
	app.add_child(app.hud)
	app.hud.command_requested.connect(app._on_command)
	app.hud.menu_requested.connect(app._show_menu)
	app.hud.settings_changed.connect(app._configure)
	app._sync_hud()
	return app

func _frames(app: Node, count: int) -> void:
	for index in range(count):
		app._process(0.05)

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func _intent_sequence() -> void:
	var app: Node = _app()
	app._go("f:-2:0")
	app._process(0.0)
	app._on_command("undo")
	_check(app.pending_button == "undo" and app.route.is_empty() and app.input_router.held.is_empty(), "a button stops old continuation and retains one pending undo")
	_check(app.session.revision == 0 and app.repository.commits == 0, "queueing cannot commit or undo the unfinished preview")
	_drain(app, "buttons/queued-undo")
	_check(app.session.revision == 2 and app.repository.commits == 2 and app.session.world.state.actors.luvie == "f:0:0", "the move commits once before queued undo, and the old click route never resumes")
	app.free()

	app = _app()
	app._step("left")
	app._on_command("restart")
	app._on_command("undo")
	_check(app.pending_button == "undo", "latest button replaces the earlier pending action")
	_drain(app, "buttons/latest-intent")
	_check(app.session.revision == 2 and app.session.world.state.actors.luvie == "f:0:0", "only the latest intent runs after commit")
	app.free()

	app = _app()
	app._step("left")
	app._on_command("primary")
	app._on_command("primary")
	_drain(app, "buttons/duplicate-primary")
	_check(app.session.revision == 2 and app.repository.commits == 2 and app.session.world.state.growth.root == ["g:root:1:0"], "two clicks waiting on a move execute a single real seed action")
	app.free()

	app = _app()
	app._on_command("primary")
	app._on_command("primary")
	_check(app.pending_button.is_empty(), "a repeated click on the already executing seed action is not replayed as retraction")
	_drain(app, "buttons/current-action-repeat")
	_check(app.session.revision == 1 and app.session.world.state.growth.root == ["g:root:1:0"], "an in-flight seed transaction still commits exactly once")
	app.free()

	app = _app()
	app._step("left")
	app._on_command("grow:root:down")
	_drain(app, "buttons/local-command-recheck")
	_check(app.session.world.state.growth.root == ["g:root:0:1"] and app.session.revision == 2, "a queued explicit local command is checked and executed by real rules after arrival")
	app.free()

	app = _app()
	app._step("left")
	_drain(app, "buttons/before-leaving-root")
	app._step("left")
	app._on_command("grow:root:right")
	_drain(app, "buttons/arrival-rejects-stale-command")
	_check(app.session.revision == 2 and app.repository.commits == 2 and app.session.world.state.growth.root.is_empty(), "a formerly available command is rejected by arrival rules without spending a seed or creating another commit")
	_check("走近" in app.status_message, "arrival rejection explains the unmet interaction distance")
	app.free()

func _directions_and_nonmutating_tools() -> void:
	for via_button: bool in [false, true]:
		var app: Node = _app()
		app._step("left")
		_frames(app, 2)
		if via_button:
			app._on_command("dir:up")
		else:
			var event := _key(KEY_UP)
			app._input(event)
			event.pressed = false
			app._input(event)
		_drain(app, "buttons/direction-buffer")
		_check(app.session.world.state.actors.luvie == "f:-1:-1" and app.session.revision == 2, "button and keyboard directions choose the same legal endpoint after the pending move")
		app.free()
	var app: Node = _app()
	app._step("left")
	var before: Dictionary = app.session.world.snapshot()
	app._on_command("mode")
	_check(app.rolling and not app.motion.is_empty() and app.pending_button.is_empty(), "movement-mode button responds while the current move finishes unchanged")
	app._on_command("hint")
	_check(app.view.hint_visible and not app.motion.is_empty() and app.pending_button.is_empty(), "hint responds immediately without queueing or mutating the puzzle")
	_same(before, app.session.world.snapshot(), "nonmutating tools leave the prepared movement transaction untouched")
	_drain(app, "buttons/tools-during-motion")
	_check(app.session.revision == 1, "nonmutating tools never duplicate the movement commit")
	app.free()

func _gui_direction_intents() -> void:
	for elapsed_frames: int in [0, 2, 4]:
		var app: Node = _real_app()
		app._step("left")
		_frames(app, elapsed_frames)
		var prepared_before: Dictionary = app.motion.before.duplicate(true)
		var prepared_after: Dictionary = app.motion.after.duplicate(true)
		_find_button(app.hud, "↑").pressed.emit()
		_check(app.pending_button == "dir:up" and app.input_router.buffered_direction.is_empty() and app.input_router.held.is_empty(), "GUI direction remains an explicit choice at movement frame " + str(elapsed_frames))
		_same(prepared_before, app.motion.before, "queued GUI direction preserves the pending transaction source")
		_same(prepared_after, app.motion.after, "queued GUI direction preserves the pending transaction target")
		_frames(app, 5 - elapsed_frames)
		_check(app.session.revision == 1 and not app.motion.is_empty() and app.motion.after.actors.luvie == "f:-1:-1" and app.view.clear_calls == 0, "GUI direction starts in the valid commit frame at any click time")
		_drain(app, "buttons/gui-direction-" + str(elapsed_frames))
		_frames(app, 10)
		_check(app.session.revision == 2 and app.repository.commits == 2 and app.session.world.state.actors.luvie == "f:-1:-1", "one GUI click produces one direction change without a later repeat")
		app.free()

	var app: Node = _real_app()
	app._on_command("primary")
	_find_button(app.hud, "←").pressed.emit()
	_check(app.pending_button == "dir:left" and app.session.revision == 0, "an early GUI direction waits through the entire seed action")
	_drain(app, "buttons/seed-then-gui-direction")
	_check(app.session.revision == 2 and app.session.world.state.actors.luvie == "f:-1:0" and app.session.world.state.growth.root == ["g:root:1:0"], "the seed commits once before an early clicked direction executes")
	app.free()

	app = _app()
	app._step("left")
	app._on_command("primary")
	app._on_command("dir:up")
	_drain(app, "buttons/gui-replaces-world-action")
	_check(app.session.revision == 2 and app.session.world.state.actors.luvie == "f:-1:-1" and app.session.world.state.growth.root.is_empty(), "a newer GUI direction replaces a waiting world action")
	app.free()

	app = _app()
	app._step("left")
	app._on_command("dir:up")
	app._on_command("grow:root:down")
	_drain(app, "buttons/world-action-replaces-gui")
	_check(app.session.revision == 2 and app.session.world.state.actors.luvie == "f:-1:0" and app.session.world.state.growth.root == ["g:root:0:1"], "a newer world action replaces a waiting GUI direction and rechecks arrival rules")
	app.free()

	app = _app()
	app._step("left")
	app._on_command("dir:up")
	app._on_command("dir:right")
	_drain(app, "buttons/latest-gui-direction")
	_check(app.session.revision == 2 and app.session.world.state.actors.luvie == "f:0:0", "only the newest GUI direction runs after arrival")
	app.free()

	app = _app()
	app._step("left")
	app._on_command("dir:up")
	_frames(app, 2)
	var right := _key(KEY_RIGHT)
	app._input(right)
	right.pressed = false
	app._input(right)
	_check(app.pending_button.is_empty(), "a new keyboard direction cancels an older GUI choice")
	_drain(app, "buttons/keyboard-replaces-gui")
	_check(app.session.revision == 2 and app.session.world.state.actors.luvie == "f:0:0", "the keyboard keeps its own short buffer when replacing a GUI choice")
	app.free()

	app = _app()
	app._input(_key(KEY_LEFT))
	app._input(_key(KEY_UP))
	app._on_command("dir:right")
	_check(app.input_router.held.is_empty() and app.input_router.buffered_direction.is_empty(), "a clicked direction clears prior held and buffered keyboard continuation")
	_drain(app, "buttons/gui-replaces-keyboard")
	_frames(app, 10)
	_check(app.session.revision == 2 and app.session.world.state.actors.luvie == "f:0:0", "a GUI choice executes once without resuming old held movement")
	app.free()

	app = _app()
	app._on_command("primary")
	var left := _key(KEY_LEFT)
	app._input(left)
	left.pressed = false
	app._input(left)
	_drain(app, "buttons/keyboard-early-tap-expiry")
	_check(app.session.revision == 1 and app.session.world.state.actors.luvie == "f:0:0" and app.pending_button.is_empty() and app.input_router.buffered_direction.is_empty(), "an early keyboard tap still expires during the long seed action")
	app.free()

	for boundary: String in ["pause", "level", "focus", "qa"]:
		app = _app()
		app._step("left")
		app._on_command("dir:up")
		if boundary == "pause":
			app._on_command("pause")
			app._on_command("resume")
		elif boundary == "level":
			app._enter_level("1-3")
		elif boundary == "focus":
			app._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else:
			app._qa_request([JSON.stringify({"type": "snapshot", "snapshot": Session.new("1-1").world.snapshot()})])
		var expected_tile: String = str(app.motion.after.actors.luvie) if not app.motion.is_empty() else str(app.session.world.state.actors.luvie)
		var expected_revision: int = app.session.revision + (0 if app.motion.is_empty() else 1)
		_check(app.pending_button.is_empty(), boundary + " clears a queued GUI direction")
		_drain(app, "buttons/gui-cancel-" + boundary)
		_check(app.session.revision == expected_revision and app.session.world.state.actors.luvie == expected_tile, boundary + " cannot replay a cancelled GUI direction")
		app.free()

func _cancellation_boundaries() -> void:
	for boundary: String in ["pause", "level", "focus", "qa"]:
		var app: Node = _app()
		app._step("left")
		app._on_command("primary")
		if boundary == "pause":
			app._on_command("pause")
			app._on_command("resume")
		elif boundary == "level":
			app._enter_level("1-3")
		elif boundary == "focus":
			app._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else:
			var reset: Dictionary = Session.new("1-1").world.snapshot()
			app._qa_request([JSON.stringify({"type": "snapshot", "snapshot": reset})])
		_check(app.pending_button.is_empty(), boundary + " clears a waiting button intent")
		_drain(app, "buttons/cancel-" + boundary)
		if boundary != "level":
			_check(app.session.world.state.growth.root.is_empty(), boundary + " cannot trigger a ghost seed action later")
		app.free()

func _hud_identity_and_settings() -> void:
	var app: Node = _real_app()
	var nodes: Dictionary = {}
	for child in app.hud._commands.get_children():
		if child is Button:
			nodes[str(child.get_meta("command_id"))] = child.get_instance_id()
	app._step("left")
	for child in app.hud._commands.get_children():
		if child is Button:
			_check(nodes.get(str(child.get_meta("command_id")), -1) == child.get_instance_id() and not child.disabled, "busy changes preserve the actual command widget and keep its intent clickable")
	var undo: Button
	for button in app.hud._tool_buttons:
		if button.get_meta("action") == "undo":
			undo = button
	_check(undo != null and not undo.disabled, "the first pending move already permits an undo intent for its eventual history")
	_drain(app, "buttons/stable-widget")
	for child in app.hud._commands.get_children():
		if child is Button:
			_check(nodes.get(str(child.get_meta("command_id")), -1) == child.get_instance_id(), "commit retains widgets when the command list has not changed")
	var refreshes: int = app.hud._message_refreshes
	app._message("这里尚未连通。")
	app._message("这里尚未连通。")
	_check(app.hud._message_refreshes == refreshes + 2, "identical repeated rejection text visibly refreshes twice")
	app.settings.bgm = 0.15
	app.settings.sfx = 0.8
	app.settings.safeCamera = true
	app.settings.continuousInput = false
	app._show_menu()
	var menu_settings := _find_button(app.hud._overlay, "设置")
	_check(menu_settings != null, "map exposes its settings button")
	menu_settings.pressed.emit()
	_check(app.hud._settings.bgm == 0.15 and app.hud._settings.sfx == 0.8 and app.hud._settings.safeCamera and not app.hud._settings.continuousInput, "first map-to-settings entry displays the live loaded settings")
	app._configure({"bgm": 0.25})
	_check(app.settings.bgm == 0.25 and app.settings.sfx == 0.8 and app.settings.safeCamera and not app.settings.continuousInput, "a partial settings edit preserves all unrelated live preferences")
	app.hud.close_overlay()
	app.free()

	app = _real_app("1-4")
	var follow: Button = app.hud._follow
	_check(follow != null and follow.is_visible_in_tree(), "the compact HUD exposes the companion toggle in dual gardens")
	var identity: int = follow.get_instance_id()
	var previous_text: String = follow.text
	app._on_command("follow")
	_check(is_instance_valid(follow) and follow.get_instance_id() == identity and follow.text != previous_text, "a command label/state change updates the same button instead of deleting a pressed widget")
	app.free()

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

func _import_settings() -> void:
	var app: Node = _real_app()
	var imported: Dictionary = Repository.empty_store()
	imported.settings.safeCamera = true
	imported.settings.continuousInput = false
	imported.settings.bgm = 0.18
	imported.settings["futurePreference"] = {"enabled": true, "revision": 7}
	imported.legacy_raw["sporelight.cloud-gardens.v1"] = "opaque-data-retained"
	app.hud.show_save_tools(app.repository)
	var editor: TextEdit = app.hud._overlay.find_children("", "TextEdit", true, false)[0]
	editor.text = JSON.stringify(imported)
	var preview := _find_button(app.hud._overlay, "检查粘贴的旅程")
	preview.pressed.emit()
	var confirm := _find_button(app.hud._overlay, "确认导入")
	_check(confirm != null and not confirm.disabled, "real save-tools preview accepts nondefault imported preferences")
	confirm.pressed.emit()
	_check(app.storage_ready and app.safe_camera and not app.input_router.continuous, "successful import applies safe-camera and independent continuous-input settings immediately")
	_check(app.repository.commits == 1, "import settings refresh does not persist the accepted store a second time")
	_check(app.settings.bgm == 0.18 and Repository.json_equivalent(app.settings.get("futurePreference"), imported.settings.futurePreference), "runtime settings retain imported values and unknown preference fields")
	_check(Repository.json_equivalent(app.repository.data.settings.get("futurePreference"), imported.settings.futurePreference) and app.repository.data.legacy_raw["sporelight.cloud-gardens.v1"] == "opaque-data-retained", "settings refresh preserves unknown preferences and independent saved data")
	_check(Repository.json_equivalent(app.repository.persisted, app.repository.data), "runtime refresh leaves the already persisted import unchanged")
	app._show_menu()
	_find_button(app.hud._overlay, "设置").pressed.emit()
	_check(app.hud._settings.safeCamera and not app.hud._settings.continuousInput and app.hud._settings.bgm == 0.18, "first map settings entry shows the newly imported preferences")
	app.hud.close_overlay()
	app.free()

func _run() -> void:
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	_levels = content.levels
	_intent_sequence()
	_directions_and_nonmutating_tools()
	_gui_direction_intents()
	_cancellation_boundaries()
	_hud_identity_and_settings()
	_import_settings()
	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite": "service-button-intents", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)
