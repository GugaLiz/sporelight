extends SceneTree
## Contract checks for the compact native HUD. These verify actual widgets and
## emitted intents; GPU artwork and pointer hit testing are separate QA.
const HUD := preload("res://ui/garden_hud.gd")
const Journey := preload("res://application/journey_view.gd")
var _checks := 0
var _failures: Array[String] = []
var _events: Array[String] = []
var _settings_events: Array[Dictionary] = []
var _level_events: Array[String] = []

class SampleWorld:
	extends RefCounted
	var level := {"id": "1-1", "title": "初生的孢子", "rule": "决定第一段路", "intro": "先观察缺口，再决定根须去哪里。", "roots": [{"id": "root", "budget": 1}], "total": 3, "dual": true, "story": "小花重新醒来了。"}
	var state := {"active": "luvie", "growth": {"root": []}, "items": {}, "collected": [], "observations": [], "completed": false, "follow": true}
	var hint_reads := 0
	func commands() -> Array:
		return [{"id": "switch", "label": "换手"}, {"id": "follow", "label": "同行"}, {"id": "grow:root:right", "label": "引芽 →"}, {"id": "grow:root:down", "label": "引芽 ↓"}, {"id": "observe:flower", "label": "看看小花"}]
	func can_undo() -> bool:
		return false
	func hint() -> Dictionary:
		hint_reads += 1
		return {"message": "测试用明确解法，默认不应出现。"}

class SampleRepository:
	extends RefCounted
	var data := {"cloud_discoveries": {"cloud-1": ["wind", "not-a-real-story"]}, "mainline": {"records": {}, "runs": {}, "memories": {}}}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result

func _find(node: Node, text: String) -> Button:
	for button: Button in _buttons(node):
		if button.text == text:
			return button
	return null

func _action(node: Node, id: String) -> Button:
	for button: Button in _buttons(node):
		if button.get_meta("action", "") == id:
			return button
	return null

func _cloud_story_button(node: Node, id: String) -> Button:
	for button: Button in _buttons(node):
		if button.get_meta("cloud_story_level", "") == id:
			return button
	return null

func _label_texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	for child: Node in node.get_children():
		if child is Label:
			result.append(child.text)
		result.append_array(_label_texts(child))
	return result

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func _pad(button: JoyButton, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event

func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

func _settle() -> void:
	for unused in 4:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hud := HUD.new()
	root.add_child(hud)
	hud.command_requested.connect(func(id: String) -> void: _events.append(id))
	hud.settings_changed.connect(func(value: Dictionary) -> void: _settings_events.append(value))
	hud.level_requested.connect(func(id: String) -> void: _level_events.append(id))
	hud.menu_requested.connect(func() -> void: _events.append("menu"))
	var world := SampleWorld.new()
	hud.update_state(world)
	hud.set_journey(Journey.describe(world))
	hud.set_interaction_context("grow:root:right", "照料根台", world.commands())
	await _settle()
	_check(world.hint_reads == 0, "Default HUD and journey never consult the solution helper")
	_check(not hud._panel.visible and not hud._pad.visible, "Desktop has no persistent command card or direction pad")
	_check(not hud._journey_steps.visible and not hud._journey_count.visible, "Future puzzle steps stay off the play screen")
	_check(hud._rule.visible and hud._rule.text == Journey.describe(world).goal, "A short natural goal remains readable without exposing solution steps")
	_check(hud._status.text.contains("芽节 1/1"), "Seed budget remains readable")
	_check(_action(hud, "undo").disabled, "Undo cannot advertise nonexistent history")
	_check(_action(hud, "primary").text.contains("照料根台"), "Primary action names the current object")
	var repair_command := {"id": "repair", "label": "一起种下微光 ✧"}
	var raw_repair := JSON.stringify(repair_command)
	hud.set_action_label("primary", repair_command.label + " · E")
	_check(not _action(hud, "primary").text.contains("✧") and _action(hud, "primary").text.contains("一起种下微光") and _action(hud, "primary").text.ends_with("E"), "The actual primary caption keeps its verb and key without the missing star glyph")
	hud.show_context_choices([repair_command])
	var repair_button: Button
	for button: Button in _buttons(hud._commands):
		if button.get_meta("command_id", "") == "repair":
			repair_button = button
	_check(repair_button != null and repair_button.text == "一起种下微光" and JSON.stringify(repair_command) == raw_repair, "Context display removes the unsupported star while preserving the rule command verbatim")
	_events.clear()
	repair_button.pressed.emit()
	_check(_events == ["repair"], "Sanitized display still emits the original repair command exactly once")
	hud.show_context_choices([{"id": "grow:root:right", "label": "引芽 →"}, {"id": "grow:root:down", "label": "引芽 ↓"}], "让根须向哪里长？")
	await _settle()
	_check(hud.is_context_open(), "Context choices open explicitly")
	_check(_find(hud._commands, "看看小花") != null, "Other nearby object commands remain accessible")
	_events.clear()
	hud.handle_context_key(_key(KEY_DOWN))
	_check(_events == ["grow:root:down"] and not hud.is_context_open(), "The player's direction selects the root branch without solver defaults")
	hud.show_context_choices(world.commands())
	_events.clear()
	_find(hud._panel, "×").pressed.emit()
	_check(not hud.is_context_open() and _events.is_empty(), "Touch cancellation closes choices without executing anything")
	hud.show_context_choices([{"id": "grow:root:right", "label": "引芽 →", "disabled": true, "reason": "芽节不足"}])
	_events.clear()
	hud.handle_context_key(_key(KEY_RIGHT))
	_check(_events.is_empty() and hud.is_context_open(), "An unavailable direction cannot execute")
	_check(_find(hud._commands, "引芽 →").disabled and _find(hud._commands, "引芽 →").tooltip_text == "芽节不足", "Unavailable choices expose a concrete reason")
	hud.close_context_choices()
	hud.show_context_choices([{"id": "grow:root:right", "label": "引芽 →"}, {"id": "grow:root:down", "label": "引芽 ↓"}])
	_events.clear()
	_check(hud.handle_context_event(_pad(JOY_BUTTON_DPAD_DOWN)), "Context consumes a gamepad navigation event")
	_check(_events.is_empty(), "Gamepad navigation previews a choice without executing it")
	_check(hud.handle_context_event(_pad(JOY_BUTTON_A)), "Context consumes gamepad confirmation before world input")
	_check(_events == ["grow:root:down"] and not hud.is_context_open(), "Gamepad A confirms exactly the player-selected direction")
	hud.show_context_choices([{"id": "grow:root:right", "label": "引芽 →"}, {"id": "grow:root:down", "label": "引芽 ↓"}])
	_events.clear()
	_check(hud.handle_context_event(_axis(JOY_AXIS_LEFT_Y, 0.85)), "Context consumes stick navigation")
	_check(hud._context_index == 1 and _events.is_empty(), "Stick navigation selects without moving the world")
	hud.handle_context_event(_axis(JOY_AXIS_LEFT_Y, 0.86))
	_check(hud._context_index == 1, "Unchanged stick events do not race through choices")
	hud.handle_context_event(_axis(JOY_AXIS_LEFT_Y, 0.0))
	_check(hud.handle_context_event(_pad(JOY_BUTTON_B)) and not hud.is_context_open() and _events.is_empty(), "Gamepad B cancels without accepting or sending a world command")
	_check(not hud.handle_context_event(_pad(JOY_BUTTON_A)), "Closed contexts release future gamepad events to the application")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(568, 320), Vector2i(594, 462), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]:
		root.size = dimensions
		hud.set_message("根须已长好，可以试着走上去了。")
		await _settle()
		var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
		for region: Dictionary in hud.layout_regions():
			var r: Array = region.rect
			_check(viewport.grow(1).encloses(Rect2(r[0], r[1], r[2], r[3])), "%s: visible %s remains inside viewport" % [dimensions, region.name])
		var safe: Rect2 = hud.safe_world_rect()
		_check(safe.size.x >= dimensions.x * 0.55 and safe.size.y >= dimensions.y * 0.3, "%s: a substantial world view survives compact HUD" % dimensions)
		var tools := hud._tools.get_global_rect()
		for button: Button in _buttons(hud._tools):
			if button.is_visible_in_tree():
				_check(tools.grow(1).encloses(button.get_global_rect()), "%s: %s has a contained hit area" % [dimensions, button.text])
		hud.show_context_choices(world.commands(), "选择操作")
		await _settle()
		_check(viewport.grow(1).encloses(hud._panel.get_global_rect()), "%s: context stays onscreen" % dimensions)
		hud.close_context_choices()
	root.size = Vector2i(568, 320)
	hud.update_state(world)
	hud.set_message(world.level.intro)
	await _settle()
	_check(not hud._message_panel.visible, "Low landscape does not repeat the introduction in a large message card")
	_check(hud._tools.size.y <= 50, "Low landscape keeps a single shallow tool row")
	for button: Button in _buttons(hud._tools):
		if button.is_visible_in_tree():
			_check(button.size.y >= 44, "Compact tools retain a usable touch height")
	var stable_safe := hud.safe_world_rect()
	_check(stable_safe.size.y >= 185, "568x320 reserves a substantial stable world height")
	hud.set_message("这里暂时还没有通路。")
	await _settle()
	_check(hud._message_panel.size.y <= 28 and hud.safe_world_rect() == stable_safe, "Transient feedback stays shallow and cannot reframe the camera")
	hud.show_context_choices(world.commands())
	await _settle()
	_check(hud.safe_world_rect() == stable_safe, "Object choices do not resize the world's camera frame")
	hud.close_context_choices()
	hud._process(6.0)
	_check(not hud._message_panel.visible, "Transient messages leave the world after their reading interval")
	hud.apply_settings({"touchControls": true})
	hud.set_touch_mode(true)
	await _settle()
	_check(hud._pad.visible, "Touch directions are available by explicit preference")
	hud.set_touch_mode(false)
	_check(not hud._pad.visible, "Desktop stays clear even if touch preference was saved")
	root.size = Vector2i(1280, 720)
	hud.show_hint(world, 0)
	_check(not hud.is_modal_open() and hud._hint_button.visible and world.hint_reads == 0, "First hint stays inline without pausing or reading solution")
	hud.show_hint(world, 1)
	_check(world.hint_reads == 0, "Second hint explains a relationship without calling the solver")
	hud.show_hint(world, 2)
	_check(world.hint_reads == 1, "Only an explicit third request reads detailed guidance")
	hud._hint_button.pressed.emit()
	_check(_events.has("hint_next"), "Inline text requests next hint independently from visibility toggle")
	for dimensions: Vector2i in [Vector2i(1280,720), Vector2i(390,844), Vector2i(568,320)]:
		root.size = dimensions
		await _settle()
		var safe := hud.safe_world_rect()
		hud.show_hint(world, 0)
		await _settle()
		_check(hud.safe_world_rect() == safe, "Hint never reframes camera")
		_check(hud._message_panel.get_rect().end.y < hud._tools.position.y, "Hint text stays above bottom tools")
		_check(hud._message_panel.position.y >= 0, "Hint fits short landscape and portrait")
		hud._process(20)
		_check(hud._message_panel.visible, "Hint remains readable until replaced")
	hud.set_message("普通操作反馈")
	await _settle()
	_check(hud._message.size.y >= hud._message.get_parent().size.y - 1 and hud._message.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "Feedback fills its container and centers vertically")
	_check(not hud._hint_button.visible and hud._message.visible, "Action feedback replaces hint cleanly")
	root.size = Vector2i(1280,720)
	var levels := [{"id": "1-1", "title": "一", "chapter": "valley"}, {"id": "1-2", "title": "二", "chapter": "valley"}, {"id": "1-3", "title": "三", "chapter": "valley"}, {"id": "cloud-1", "title": "云庭", "chapter": "cloud"}]
	hud.show_menu(levels, {"last_level": "1-2", "records": {"1-1": {"completed": true}}})
	await _settle()
	_check(hud._chapter_map.selected_id == "1-2" and not hud._chapter_map.preferred_focus.disabled, "Map opens at the saved last level with its real unlock state")
	_check(root.gui_get_focus_owner() == hud._chapter_map.preferred_focus, "Map focuses the selected playable entry rather than utility tools")
	hud._chapter_map.select_level("1-3")
	var locked_level := _find(hud._overlay, "等待前一关苏醒")
	_check(locked_level != null and locked_level.disabled and locked_level.focus_mode == Control.FOCUS_NONE, "Locked chapter markers can be inspected but their entry stays disabled")
	_level_events.clear()
	locked_level.pressed.emit()
	_check(_level_events.is_empty() and hud.is_modal_open(), "Even a directly emitted locked-entry intent cannot start a level")
	hud._focus_cloud_entry()
	_check(hud._chapter_map.chapter == "cloud" and not hud._chapter_map.preferred_focus.disabled, "Independent cloud gardens remain accessible from the real shortcut")
	hud._chapter_map.preferred_focus.pressed.emit()
	_check(_level_events == ["cloud-1"] and not hud.is_modal_open(), "Cloud level selection emits its own destination")
	var archive := SampleRepository.new()
	hud.set_repository(archive)
	hud.show_menu(levels, {})
	hud._focus_cloud_entry()
	var pocket := _cloud_story_button(hud._overlay, "cloud-1")
	_check(pocket != null and pocket.text.contains("1/2"), "Cloud map reads permanent discoveries even without a completion record")
	pocket.pressed.emit()
	var cloud: Dictionary = hud._cloud_level("cloud-1")
	var seen_story := ""
	var hidden_story := ""
	var hidden_label := ""
	for mark: Dictionary in cloud.marks:
		if mark.id == "wind":
			seen_story = str(mark.text)
		if mark.id == "letter":
			hidden_story = str(mark.text)
			hidden_label = str(mark.label)
	var texts := _label_texts(hud._overlay)
	_check(texts.has(seen_story), "A previously found cloud story remains readable in an uncompleted/restarted run")
	_check(not texts.has(hidden_story) and not texts.has(hidden_label), "An undiscovered cloud story does not leak its title or text")
	_check(world.state.observations == [], "Reading historical stories does not add observations to the current puzzle")
	hud.navigate_back()
	_check(hud._page_kind == "map", "A cloud story page returns to the originating map")
	hud.show_journal(levels, {})
	_cloud_story_button(hud._overlay, "cloud-1").pressed.emit()
	hud.navigate_back()
	_check(hud._page_kind == "journal", "The same cloud story page returns to the journal when opened there")
	hud.show_cloud_stories("cloud-2")
	_check(hud._cloud_found("cloud-2").is_empty(), "Missing history starts empty without errors or invented discoveries")
	hud.close_overlay(false)
	hud.set_repository(null)
	hud.show_settings({"bgm": 0.35, "continuousInput": true})
	var has_obsolete_option := false
	var touch_option: CheckButton
	for child: Node in hud._overlay.find_children("", "CheckButton", true, false):
		if child.get_meta("setting_id", "") in ["continuousInput", "safeCamera"]:
			has_obsolete_option = true
		if child.get_meta("setting_id", "") == "touchControls":
			touch_option = child
	_check(not has_obsolete_option, "Native movement and framing are standard behavior, not legacy experiment switches")
	_check(touch_option != null, "Optional touch controls remain a real setting")
	touch_option.button_pressed = not touch_option.button_pressed
	_check(not _settings_events.is_empty() and _settings_events.back().has("touchControls"), "Settings still emit a saved preference")
	_check(_action(hud._overlay, "restart") != null and _action(hud._overlay, "mode") != null and _action(hud._overlay, "jump") != null, "Optional movement actions and restart remain reachable without permanent HUD buttons")
	hud.show_menu(levels)
	hud.show_settings({"bgm": 0.4})
	_events.clear()
	hud.navigate_back()
	_check(hud.is_modal_open() and hud._page_kind == "map" and not _events.has("resume"), "Backing out of map settings returns to the map without resuming the level")
	hud.show_gallery({"mainline": {"records": {"1-1": {"completed": true}}}})
	_find(hud._overlay, "读一段微光故事").pressed.emit()
	hud.navigate_back()
	_check(hud._page_kind == "gallery", "A gallery story returns to its gallery")
	hud.navigate_back()
	_check(hud._page_kind == "map" and not _events.has("resume"), "A map child retains the real map source through deeper pages")
	hud.close_overlay(false)
	hud.show_settings({})
	_events.clear()
	hud.navigate_back()
	_check(not hud.is_modal_open() and _events == ["resume"], "A pause opened directly from play has an explicit route back to play")
	hud.show_ending(world, {"collected": 2, "total": 3})
	_events.clear()
	_action(hud, "next").pressed.emit()
	_check(_events == ["next"] and not hud.is_modal_open(), "Completion navigation does not resume the previous scene")
	hud.show_ending(world)
	_events.clear()
	_find(hud._overlay, "留下看看").pressed.emit()
	_check(_events == ["resume", "stay"] and not hud.is_modal_open(), "Staying resumes the same garden")
	hud.show_journal(levels, {"records": {"1-1": {"completed": true}}})
	_check(_find(hud._overlay, "看看修复后的花园") == null, "An old record cannot invent a completion memory")
	hud.show_journal(levels, {"records": {"1-1": {"completed": true}}, "memories": {"1-1": {"completed": true}}})
	_events.clear()
	_find(hud._overlay, "看看修复后的花园").pressed.emit()
	_check(_events == ["review:1-1"], "Journal revisit identifies an isolated completion memory")
	hud.show_home(levels, {}, false)
	await _settle()
	_check(not hud.is_game_interface_visible() and not hud._heading.visible and not hud._tools.visible, "Home hides play controls")
	_check(_action(hud, "continue").disabled, "A new player cannot continue an unstarted run")
	_check(root.gui_get_focus_owner() == _action(hud._overlay, "map"), "Gamepad home navigation has a real focused destination without a mouse")
	hud.show_gallery({})
	_events.clear()
	hud.navigate_back()
	_check(hud._page_kind == "home" and not hud.is_game_interface_visible() and not _events.has("resume"), "Home child pages return to the home screen")
	hud.close_overlay(false)
	hud.set_game_interface_visible(true)
	hud.show_gallery({"mainline": {"records": {"1-1": {"completed": true}}}})
	_check(_find(hud._overlay, "读一段微光故事") != null, "Existing gallery assets and story access remain available")
	hud.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-ui", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "scope": "Actual HUD controls, layout and intents; not GPU/pointer/audio verification."}))
	quit(0 if _failures.is_empty() else 1)
