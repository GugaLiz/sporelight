extends "res://application/main.gd"
## Reuse the game's HUD, navigation, movement and transactions. Only planning varies.
const Plan = preload("res://application/root_route_plan.gd")
const Stage = preload("res://prototypes/root_weaving_stage.gd")
var plan: RefCounted
var growth_queue: Array[String] = []
var phase := "explore"
var _playtest_clock := 0.0

class MemoryRepository:
	extends "res://services/save_repository.gd"
	func load_store() -> Dictionary:
		data.mainline.last_level = "1-2"
		return {"ok": true, "data": data.duplicate(true), "created": true}
	func persist(candidate: Dictionary = {}) -> Dictionary:
		var value := data if candidate.is_empty() else candidate
		var validation: Dictionary = _validate_store(value)
		if validation.ok: data = value.duplicate(true)
		return validation

func _create_repository() -> RefCounted:
	return MemoryRepository.new()

func _create_native_view() -> Node2D:
	return Stage.new()

func _ready() -> void:
	set_meta("playtest_controller", true)
	super._ready()
	view.world_clicked.connect(_world_click)
	_enter_level("1-2")

func _is_weaving() -> bool:
	return session != null and str(session.world.level.id) == "1-2"

func _enter_level(level_id: String, review: bool = false) -> void:
	plan = null
	growth_queue.clear()
	phase = "explore"
	view.planning = false
	view.draft.clear()
	view.options.clear()
	super._enter_level(level_id, review)
	if _is_weaving():
		phase = "won" if session.world.state.completed else "crossing" if session.world.connected() else "explore"
		view.overview = true
		hud.set_overview(true)
		_sync_hud()

func _show_menu() -> void:
	# Disposable playtest navigation does not invent real completion records.
	var progress: Dictionary = repository.data.mainline.duplicate(true)
	progress["unlock_all"] = true
	hud.show_menu(levels, progress)

func _locked() -> bool:
	return super._locked() or (_is_weaving() and phase in ["planning", "growing"])

func _native_interaction_context() -> Dictionary:
	var context := super._native_interaction_context()
	if not _is_weaving(): return context
	if phase in ["planning", "growing"]:
		return {"id": "weave:confirm", "label": "让根桥生长" if phase == "planning" else "根桥生长中", "choices": [], "tile": session.world.point_for("f:1:1")}
	if not session.world.connected():
		for choice: Dictionary in context.get("choices", []):
			if str(choice.id).begins_with("grow:root:"):
				return {"id": "weave:plan", "label": "规划根桥", "tile": session.world.point_for("f:1:1"), "choices": [{"id": "weave:plan", "label": "规划根桥"}]}
	return context

func _on_command(id: String) -> void:
	if not _is_weaving():
		super._on_command(id)
		return
	if not paused and not _portrait_blocked and not home_active:
		if phase == "planning":
			if id == "undo":
				if plan.commands.is_empty():
					plan = null
					phase = "explore"
				else: plan.trim(plan.commands.size() - 1)
				_sync_hud()
				return
			if id in ["primary", "weave:confirm"]:
				if plan.ready():
					growth_queue.assign(plan.commands)
					plan = null
					phase = "growing"
					_sync_hud()
				return
			if id.begins_with("dir:") or id.begins_with("grow:root:"):
				plan.append("grow:root:" + id.get_slice(":", id.get_slice_count(":") - 1))
				_sync_hud()
				return
			if id in ["jump", "switch", "mode"]: return
		if phase in ["planning", "growing"]:
			if id == "restart":
				# Restart owns the whole pending route, including its current preview.
				growth_queue.clear()
				plan = null
				phase = "explore"
				motion.clear()
			elif id not in ["hint", "hint_next", "overview", "settings", "map", "home", "pause", "resume", "continue"]:
				# Numeric shortcuts and nearby discoveries cannot mutate the world
				# behind the disposable draft or between queued growth commits.
				return
		if phase == "explore" and motion.is_empty() and (id == "weave:plan" or id.begins_with("grow:root:") or (id == "primary" and _native_interaction_context().get("id", "") == "weave:plan")):
			native_movement.stop()
			input_router.clear()
			route.clear()
			hud.close_context_choices()
			plan = Plan.new(session.world)
			phase = "planning"
			_sync_hud()
			return
	super._on_command(id)

func _advance_actions(delta: float) -> void:
	if _is_weaving() and phase == "growing":
		if paused or _portrait_blocked or not motion.is_empty(): return
		if growth_queue.is_empty():
			phase = "crossing" if session.world.connected() else "explore"
			_sync_hud()
		else:
			_execute(Command.interact(growth_queue[0]), growth_queue[0])
			if motion.is_empty():
				growth_queue.clear()
				phase = "explore"
				_sync_hud()
		return
	super._advance_actions(delta)

func _commit(prepared: GardenCommandResult) -> void:
	super._commit(prepared)
	if _is_weaving() and not growth_queue.is_empty():
		if str(prepared.command.value) == growth_queue[0] and session.world.snapshot().growth == prepared.after.growth:
			growth_queue.pop_front()
		else: growth_queue.clear()

func _after_motion() -> void:
	if _is_weaving():
		if session.world.state.completed: phase = "won"
		elif phase != "growing": phase = "crossing" if session.world.connected() else "explore"
	super._after_motion()

func _input(event: InputEvent) -> void:
	if _is_weaving() and phase == "planning" and not paused and not _portrait_blocked and event is InputEventKey:
		if event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			var key: int = event.physical_keycode if event.physical_keycode else event.keycode
			var focus: Control = get_viewport().gui_get_focus_owner()
			if key == KEY_ENTER and not focus is BaseButton: _on_command("primary")
			elif key == KEY_BACKSPACE: _on_command("undo")
			elif Router.DIRECTIONS.has(key): _on_command("dir:" + str(Router.DIRECTIONS[key]))
			else:
				super._input(event)
				return
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _world_click(at: Vector2) -> void:
	if phase != "planning" or paused or _portrait_blocked or home_active: return
	var closest := ""
	var distance := 27.0
	for choice: Dictionary in plan.choices():
		var d: float = at.distance_to(view.target_position(choice.target))
		if d < distance:
			distance = d
			closest = str(choice.id)
	if not closest.is_empty(): plan.append(closest)
	else:
		for i in range(plan.targets.size()):
			if at.distance_to(view.target_position(plan.targets[i])) < 22:
				plan.trim(i)
				break
	_sync_hud()

func _sync_hud() -> void:
	view.planning = _is_weaving() and phase == "planning"
	view.draft.assign(plan.targets if plan != null else [])
	view.options = plan.choices() if view.planning else []
	super._sync_hud()
	if not _is_weaving(): return
	if phase in ["planning", "growing"]:
		var count: int = session.world.state.growth.root.size() + (plan.commands.size() if plan != null else 0)
		var goal := "点亮落点，规划根桥 %d / 4" % count if phase == "planning" else "根桥正沿路线逐节生长。"
		hud.set_journey({"goal": goal, "next": "撤销可退一步；空草稿再撤销可退出规划。" if phase == "planning" else "等它落稳，再走向对岸花坛。"})
		hud.set_action_enabled("undo", phase == "planning" and not paused)
		var ready: bool = phase == "planning" and plan != null and plan.ready()
		hud.set_action_enabled("primary", ready and not paused)
		hud.set_action_feedback("weave:confirm", {"weave:confirm": {"available": ready, "reason": "先用剩余芽节把路线接到对岸。"}})
	elif _native_interaction_context().get("id", "") == "weave:plan":
		hud.set_action_feedback("weave:plan", {"weave:plan": {"available": true}})
	view.queue_redraw()
	_publish_qa()

func _apply_native_hint(event: String) -> void:
	if not _is_weaving() or session.world.connected():
		super._apply_native_hint(event)
		return
	var next := HintNavigation.transition(_hint_tier, hud.is_hint_visible(), event)
	_hint_tier = int(next.tier)
	if next.visible:
		var messages := ["走近根台，开始规划一条绕过岩石的根桥。", "点击发光落点，连续安排四节芽；撤销可以退一步。", "沿岩石上侧或下侧绕行，接到对岸后确认生长，再走到花坛旁。"]
		hud.show_hint_content(messages[_hint_tier], _hint_tier)
	else: hud.hide_hint()

func _process(delta: float) -> void:
	super._process(delta)
	_playtest_clock += delta
	if _playtest_clock > 0.1:
		_playtest_clock = 0.0
		_publish_qa()

func _publish_qa() -> void:
	super._publish_qa()
	if not OS.has_feature("web") or not OS.is_debug_build() or session == null or hud == null: return
	var choices: Array = []
	if plan != null:
		for choice: Dictionary in plan.choices():
			var at: Vector2 = view.target_position(choice.target)
			choices.append({"id": choice.id, "target": choice.target, "x": at.x, "y": at.y})
	var buttons: Array = []
	_qa_buttons(hud, buttons)
	var controls: Array = []
	_qa_controls(hud, controls)
	var targets: Array = []
	for tile: Dictionary in session.world.tiles():
		var at: Vector2 = view.project(tile)
		targets.append({"id": tile.id, "x": at.x, "y": at.y})
	var payload := {"phase": phase, "paused": paused, "portrait": _portrait_blocked, "draft": [] if plan == null else plan.targets,
		"choices": choices, "buttons": buttons, "controls": controls, "snapshot": session.world.snapshot(),
		"moving": native_movement != null and native_movement.is_moving(), "targets": targets,
		"hintVisible": hud.is_hint_visible(), "hintTier": _hint_tier, "modalOpen": hud.is_modal_open()}
	JavaScriptBridge.eval("window.__rootWeaving=" + JSON.stringify(payload) + ";")
