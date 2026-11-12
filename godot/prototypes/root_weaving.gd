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

func _planned_count() -> int:
	return session.world.state.growth.root.size() + (plan.commands.size() if plan != null else 0)

func _root_budget() -> int:
	return int(session.world.level.roots[0].budget)

func _native_interaction_context() -> Dictionary:
	var context := super._native_interaction_context()
	if not _is_weaving(): return context
	if phase in ["planning", "growing"]:
		# The goal text is hidden on short landscape screens. Keep progress in
		# the existing primary action, where both mouse and touch can read it.
		var label := "根桥生长 %d/%d" % [_planned_count(), _root_budget()]
		if phase == "planning":
			label = "让根桥生长" if plan != null and plan.ready() else "规划根桥 %d/%d" % [_planned_count(), _root_budget()]
		return {"id": "weave:confirm", "label": label, "choices": [], "tile": session.world.point_for("f:1:1")}
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
	if not session.world.state.completed:
		hud.set_journey(_weaving_journey())
	if phase in ["planning", "growing"]:
		hud.set_action_enabled("undo", phase == "planning" and not paused)
		var ready: bool = phase == "planning" and plan != null and plan.ready()
		hud.set_action_enabled("primary", ready and not paused)
		var reason := "根桥正在生长，等它落稳。" if phase == "growing" else "还需规划 %d 节，接到对岸后才能生长。" % (_root_budget() - _planned_count())
		hud.set_action_feedback("weave:confirm", {"weave:confirm": {"available": ready, "reason": reason}})
	elif _native_interaction_context().get("id", "") == "weave:plan":
		hud.set_action_feedback("weave:plan", {"weave:plan": {"available": true}})
	# Refresh only help the player already opened; never reveal a solution or
	# reopen a dismissed hint as the route changes.
	if hud.is_hint_visible(): hud.show_hint_content(_weaving_hint(), _hint_tier)
	view.queue_redraw()
	_publish_qa()

func _weaving_journey() -> Dictionary:
	var goal := "为岩石另一侧的小花找到一条路。"
	var next := "像上一片花园一样走近根台，这次先规划，再让根桥生长。"
	match phase:
		"planning":
			goal = "路线已接到对岸，确认后根桥才会生长。" if plan.ready() else "规划根桥 %d / %d · 还可安排 %d 节" % [_planned_count(), _root_budget(), _root_budget() - _planned_count()]
			next = "点击发光落点或按方向键；撤销可退一步，空草稿再撤销可退出。"
		"growing":
			goal = "根桥正沿路线生长 %d / %d。" % [_planned_count(), _root_budget()]
			next = "等它落稳，再走向对岸花坛。"
		"crossing":
			goal = "根桥已接通，去对岸照料第一朵花。"
			next = "走到花坛旁互动；沿途微光可以自由收集。"
	return {"goal": goal, "next": next}

func _weaving_hint() -> String:
	if session.world.state.completed: return str(Journey.hint(session.world, _hint_tier).message)
	var messages: Array = []
	match phase:
		"planning":
			if plan.ready():
				messages = ["路线已接到对岸，现在仍是草稿。", "确认后根桥才会逐节长出；想改路线，可以先撤销。", "点击“让根桥生长”或按 E，等根桥落稳后再过桥。"]
			else:
				messages = ["正在规划，根桥还没有长出；还可安排 %d 节。" % (_root_budget() - _planned_count()), "每一节都从根尖继续。点发光的＋或按方向键；撤销可以退一步。", "沿岩石上侧或下侧连续绕行，最后一节接回对岸入口，再确认生长。"]
		"growing":
			messages = ["根桥正在沿你安排的路线生长。", "等最后一节落稳，就可以走到对岸。", "现在不需要再选落点；根桥接通后，走到花坛旁互动。"]
		"crossing":
			messages = ["你安排的根桥已经接通，小花还在对岸等你。", "接通道路后，还需要亲自到花坛旁照料它。", "点击对岸花坛所在的地面前往，再用主操作按钮或 E 照料；不必收齐微光。"]
		_:
			messages = ["岩石挡住了直路，周围还留有空隙。", "这次有四节根芽。走近根台先规划路线，确认后再一起生长。", "开始规划后，点发光落点从岩石上侧或下侧绕行；四节接到对岸，再确认。"]
	return str(messages[clampi(_hint_tier, 0, 2)])

func _apply_native_hint(event: String) -> void:
	if not _is_weaving():
		super._apply_native_hint(event)
		return
	var next := HintNavigation.transition(_hint_tier, hud.is_hint_visible(), event)
	_hint_tier = int(next.tier)
	if next.visible:
		hud.show_hint_content(_weaving_hint(), _hint_tier)
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
