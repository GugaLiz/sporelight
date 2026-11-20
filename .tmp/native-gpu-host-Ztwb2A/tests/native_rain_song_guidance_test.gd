extends SceneTree
const World = preload("res://core/garden_world.gd")
const Guidance = preload("res://application/rain_song_guidance.gd")
const Interaction = preload("res://application/native_interaction.gd")
const Journey = preload("res://application/journey_view.gd")
const HUD = preload("res://ui/garden_hud.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var world := World.new("2-3")
	world.state.actors.luvie = "f:-4:0"
	var before: Dictionary = world.snapshot()
	_check(Guidance.sequence(world).find("转庭") < Guidance.sequence(world).find("升台"), "notation describes the current default order")
	_check(Guidance.progress(world).contains("0/3") and Guidance.last_effect(world).contains("尚无"), "cold notation states only the execution progress")
	var summary := Guidance.summary(world)
	_check(not summary.contains("露薇") and not summary.contains("小苔灵") and not summary.contains("下一") and not summary.contains("北岸") and not summary.contains("先转"), "piano notation contains no actor assignment, next destination or solution instructions")
	world.state.song = ["rise", "rest", "turn"]
	_check(Guidance.sequence(world).begins_with("1 升台"), "notation reads reordered leaves without choosing an order")
	world = World.new("2-3", before)
	var commands := _commands(world)
	var availability := _availability(commands)
	availability["swap:0"] = {"available":false, "reason":"original denial"}
	var context := Interaction.context(world, commands, availability, _position(world.point()), _position)
	var original_song: Array = commands.filter(func(row: Dictionary) -> bool: return Guidance.is_song_action(str(row.id)))
	var shown_song: Array = context.choices.filter(func(row: Dictionary) -> bool: return Guidance.is_song_action(str(row.id)))
	_check(shown_song.size() == original_song.size(), "all original song commands remain in the nearby menu")
	for index in range(original_song.size()):
		_check(shown_song[index].id == original_song[index].id and shown_song[index].label == original_song[index].label, "original command order and labels remain unchanged at " + str(index))
	_check(shown_song[0].disabled and shown_song[0].reason == "original denial", "original availability and denial reason remain visible")
	_check(not context.has("menu_required") and Interaction.context(world, commands, availability, Vector3(30, 0, 30), _position).is_empty(), "notation neither adds a forced-menu policy nor extends physical interaction range")
	var single := Interaction.context(world, [{"id":"resetSong", "label":"original reset"}], {"resetSong":{"available":true}}, _position(world.point()), _position)
	_check(single.id == "resetSong" and single.choices.size() == 1, "single nearby operation retains its original direct-action semantics")
	_check(Journey.describe(world).goal == Journey.GOALS["2-3"][0] and Journey.hint(world, 1).message == Journey.GOALS["2-3"][2], "journey goal and opt-in hint tiers retain their original behavior")
	_check(world.snapshot() == before, "notation and nearby queries do not mutate play state")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var played: Dictionary = {}
	for entry: Dictionary in reference.cases:
		if str(entry.name) != "authored/2-3": continue
		for step: Dictionary in entry.steps:
			if int(step.snapshot.beat) == 1:
				played = step.snapshot.duplicate(true)
				break
	world = World.new("2-3", played)
	_check(Guidance.progress(world).contains("1/3") and Guidance.last_effect(world).contains("第1拍") and Guidance.last_effect(world).contains("已转动"), "played notation reports an already executed action and actual effect")
	world.state.beat = 3
	world.state.playing = false
	_check(Guidance.progress(world) == "已执行 3/3 · 未播放", "completed execution describes the actual playback boolean without implying a new terminal restriction")
	root.size = Vector2i(844, 390)
	var hud := HUD.new()
	root.add_child(hud)
	world = World.new("2-3", before)
	commands = _commands(world)
	hud.update_state(world, false, "原有反馈", false)
	hud.set_journey(Journey.describe(world))
	hud.show_context_choices(commands, "选择操作")
	for unused in range(5): await process_frame
	_check(hud._rain_summary.visible and hud._rain_summary.text == Guidance.summary(world), "only the opened piano menu contains read-only notation")
	_check(not hud._journey_count.visible and hud._context_title.text == "选择操作", "no new default strategy instructions or control-mode title are introduced")
	var buttons: Array = hud._commands.get_children().filter(func(node: Node) -> bool: return node is Button)
	_check(buttons.size() == commands.size(), "menu retains every original operation without filtering")
	for index in range(commands.size()):
		_check(buttons[index].get_meta("command_id") == commands[index].id and buttons[index].text == commands[index].label, "actual nearby button keeps original order and label at " + str(index))
	_check(hud._panel.position.y >= 0 and hud._panel.position.y + hud._panel.size.y <= hud._tools.position.y - 9, "small viewport menu remains above the toolbar")
	var scroll := hud._context_scroll
	_check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO and scroll.get_v_scroll_bar().max_value > scroll.size.y, "long original operation list has an internal scrolling path")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	for unused in range(3): await process_frame
	var last: Button = buttons[-1]
	_check(last.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1 and last.get_global_rect().position.y >= scroll.get_global_rect().position.y - 1, "last original operation is reachable through scrolling")
	hud.queue_free()
	await process_frame
	_recovery_contexts()
	await _playback_menu_refresh()
	print(JSON.stringify({"suite":"native-rain-song-guidance", "checks":checks, "failures":failures, "passed":failures.is_empty(), "gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)

func _commands(world: RefCounted) -> Array:
	return world.commands().filter(func(row: Dictionary) -> bool: return not str(row.id) in ["switch", "follow"])

func _availability(commands: Array) -> Dictionary:
	var result := {}
	for row: Dictionary in commands: result[str(row.id)] = {"available":true, "reason":""}
	return result

func _position(tile: Dictionary) -> Vector3:
	return Vector3(float(tile.x), float(tile.get("h", 0)) * 0.65, float(tile.z))

func _act(world: RefCounted, id: String, internal: bool = false) -> void:
	_check(bool(world.act(id, internal).get("ok", false)), "original action accepted: " + id)

func _walk(world: RefCounted, id: String) -> void:
	_check(world.has_path_to(id), "original route exists: " + id)
	for tile: String in world.path_to(id):
		_check(bool(world.move(tile).get("ok", false)), "original support move accepted: " + tile)
	_check(str(world.state.actors[world.actor()]) == id, "actor reaches original support: " + id)

func _world_availability(world: RefCounted) -> Dictionary:
	var result := {}
	for command: Dictionary in _commands(world):
		var outcome: Dictionary = world.fork(world.snapshot()).act(str(command.id))
		result[str(command.id)] = {"available": bool(outcome.get("ok", false)), "reason": "" if bool(outcome.get("ok", false)) else str(outcome.get("message", ""))}
	return result

func _context(world: RefCounted, commands: Array = []) -> Dictionary:
	return Interaction.context(world, _commands(world) if commands.is_empty() else commands, _world_availability(world), _position(world.point()), _position)

func _recovery_contexts() -> void:
	var reverse := World.new("2-3")
	_act(reverse, "switch")
	_walk(reverse, "m:stage:0:1")
	_act(reverse, "switch")
	for unused in range(3): _act(reverse, "beat")
	_act(reverse, "switch")
	var before: Dictionary = reverse.snapshot()
	var remote := _context(reverse)
	_check(remote.get("id", "") == "context" and not remote.has("menu_required"), "reverse division retains the ordinary multi-action menu")
	_check(remote.get("choices", []).map(func(row: Dictionary) -> String: return str(row.id)) == ["play", "resetSong"], "remote rehearsal retains the two originally offered actions in order")
	_check(str(remote.get("tile", {}).get("id", "")) == str(reverse.point().id), "remote rehearsal uses the current actor anchor")
	_check(reverse.snapshot() == before, "remote menu query does not change division, phrase or platform")
	var unavailable := _world_availability(reverse)
	unavailable.resetSong = {"available": false, "reason": "original denial"}
	remote = Interaction.context(reverse, _commands(reverse), unavailable, _position(reverse.point()), _position)
	_check(remote.choices[1].disabled and remote.choices[1].reason == "original denial", "remote fallback keeps domain availability and reason")
	var single := Interaction.context(reverse, [{"id": "resetSong", "label": "original reset"}], {"resetSong": {"available": true}}, _position(reverse.point()), _position)
	_check(single.id == "resetSong" and single.choices.size() == 1 and not single.has("menu_required"), "one offered remote action retains direct-action semantics")

	var trapped := World.new("2-3")
	for id: String in ["swap:0", "swap:1", "swap:0"]: _act(trapped, id)
	_act(trapped, "switch")
	_walk(trapped, "m:stage:0:1")
	_act(trapped, "switch")
	_act(trapped, "beat")
	_walk(trapped, "m:stage:0:0")
	_act(trapped, "play")
	_act(trapped, "beat", true)
	_act(trapped, "beat", true)
	var reloaded := World.new("2-3", trapped.snapshot())
	_check(not reloaded.can_undo() and not reloaded.has_path_to("f:-4:0") and not reloaded.has_path_to("f:0:-4"), "legal two-passenger reload has no history or walking route to either shore")
	var offered: Array = _commands(reloaded)
	remote = _context(reloaded)
	_check(remote.choices.map(func(row: Dictionary) -> String: return str(row.id)) == offered.map(func(row: Dictionary) -> String: return str(row.id)), "two-passenger reload exposes every originally offered recovery action")
	_act(reloaded, "resetSong")
	_check(not reloaded.flag("raised") and int(reloaded.state.beat) == 0 and str(reloaded.state.actors.luvie) == "f:-4:0" and str(reloaded.state.actors.buddy) == "m:stage:0:1", "original rehearsal reset restores the two legal starting supports")

	var nearby := World.new("2-3")
	_walk(nearby, "m:stage:0:0")
	_act(nearby, "switch")
	_walk(nearby, "f:-4:0")
	_act(nearby, "beat")
	_act(nearby, "beat")
	_act(nearby, "switch")
	_walk(nearby, "f:0:-4")
	var local_commands: Array = _commands(nearby).filter(func(row: Dictionary) -> bool: return str(row.id) in ["use:latch", "play", "resetSong"])
	var local := _context(nearby, local_commands)
	_check(local.id == "use:latch" and local.choices.size() == 1, "nearby real latch keeps priority and its original direct action")
	_act(nearby, "use:latch")
	_check(not _commands(nearby).any(func(row: Dictionary) -> bool: return str(row.id) in ["play", "resetSong"]), "fixed return path retains original remote command removal")
	_check(Interaction.context(nearby, [{"id": "resetSong", "label": "not offered"}], {"resetSong": {"available": true}}, Vector3(30, 0, 30), _position).is_empty(), "fallback does not extend recovery after the original latch boundary")

func _sync_context(hud: Variant, world: RefCounted) -> Dictionary:
	hud.update_state(world, false, "", false)
	var context := _context(world)
	hud.set_action_feedback(str(context.get("id", "")), _world_availability(world))
	hud.set_interaction_context(str(context.get("id", "")), str(context.get("label", "")), context.get("choices", []))
	return context

func _menu_button(hud: Variant, id: String) -> Button:
	for child in hud._commands.get_children():
		if child is Button and str(child.get_meta("command_id", "")) == id:
			return child
	return null

func _playback_menu_refresh() -> void:
	var world := World.new("2-3")
	_act(world, "play")
	var hud := HUD.new()
	root.add_child(hud)
	var context := _sync_context(hud, world)
	hud.show_context_choices(context.choices, str(context.label))
	for unused in range(5): await process_frame
	var reset := _menu_button(hud, "resetSong")
	reset.grab_focus()
	hud._context_scroll.scroll_vertical = int(hud._context_scroll.get_v_scroll_bar().max_value)
	for unused in range(3): await process_frame
	var scroll: int = hud._context_scroll.scroll_vertical
	var button_id: int = reset.get_instance_id()
	_sync_context(hud, world)
	for unused in range(3): await process_frame
	_check(_menu_button(hud, "resetSong").get_instance_id() == button_id, "unchanged menu content keeps existing buttons")
	for beat in range(3):
		_act(world, "beat", true)
		_sync_context(hud, world)
		for unused in range(3): await process_frame
		_check(hud.is_context_open() and hud._rain_summary.text == Guidance.summary(world), "opened menu follows executed beat " + str(beat + 1))
		var play := _menu_button(hud, "play")
		var original: Array = _commands(world).filter(func(row: Dictionary) -> bool: return str(row.id) == "play")
		_check(play.text == original[0].label, "opened menu follows the original pause/continue label at beat " + str(beat + 1))
		_check(bool(world.state.playing) == (beat < 2), "menu refresh does not pause automatic playback at beat " + str(beat + 1))
		var scrollbar: VScrollBar = hud._context_scroll.get_v_scroll_bar()
		var retained_scroll := mini(scroll, maxi(0, int(scrollbar.max_value - scrollbar.page)))
		_check(get_root().gui_get_focus_owner() == _menu_button(hud, "resetSong") and hud._context_scroll.scroll_vertical == retained_scroll, "menu refresh preserves selected command, focus and legal scrolling at beat " + str(beat + 1))
	var dispatched := {"id": "", "accepted": false}
	hud.command_requested.connect(func(id: String) -> void:
		dispatched.id = id
		dispatched.accepted = bool(world.act(id).get("ok", false)))
	_menu_button(hud, "resetSong").pressed.emit()
	_check(dispatched.id == "resetSong" and dispatched.accepted and int(world.state.beat) == 0, "actual menu button dispatches the original rehearsal reset")
	hud.queue_free()
	await process_frame
