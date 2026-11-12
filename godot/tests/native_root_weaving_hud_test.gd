extends SceneTree
const Prototype = preload("res://prototypes/root_weaving.gd")
const HUD = preload("res://ui/garden_hud.gd")
var checks := 0
var failures: Array[String] = []

class QuietAudio:
	extends Node
	func start() -> void: pass
	func play(_kind: String) -> void: pass
	func configure(_settings: Dictionary) -> void: pass
	func pause(_value: bool) -> void: pass

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func drain(app: Node) -> void:
	for i in range(100):
		app._process(0.05)
		await process_frame
		if app.phase != "growing" and app.motion.is_empty(): break

func _run() -> void:
	var app := Prototype.new()
	root.add_child(app)
	app.audio.free()
	app.audio = QuietAudio.new()
	app.add_child(app.audio)
	app.set_process(false)
	app.set_physics_process(false)
	app.set_process_input(false)
	check(app.hud is HUD and not app.hud.is_modal_open(), "prototype uses original GardenHUD directly")
	check(app.repository is Prototype.MemoryRepository and app.session.world.level.id == "1-2", "direct playtest uses disposable save adapter")
	for id in ["f:4:0", "f:5:0"]:
		var tile: Dictionary = app.session.world.point_for(id)
		var position: Vector3 = app.view.tile_position(tile)
		check(is_equal_approx(position.y, 0.45) and is_equal_approx(app.view.support_height(position, id), position.y), "rear courtyard visual and collision support agree: " + id)
		check(app.view._terrain_profile.stair_spec(Vector2(tile.x, tile.z)).is_empty(), "rear courtyard no longer presents unused stairs: " + id)
	var initial: Dictionary = app.session.world.snapshot()
	app._on_command("primary")
	check(app.phase == "planning", "original main action enters route planning")
	check(app.hud._interaction_label == "规划根桥 0/4", "primary action exposes draft progress even when the landscape heading is hidden")
	check(app.view.draft_origin().is_equal_approx(app.view.project(app.session.world.point_for("f:1:1"))), "fresh draft starts at the seedbed")
	app._on_command("dir:up")
	app._on_command("dir:right")
	check(app.session.world.snapshot() == initial, "planning never mutates gameplay")
	app._on_command("undo")
	check(app.plan.targets.size() == 1, "original undo trims draft")
	check(app.hud._interaction_label == "规划根桥 1/4", "undo updates primary draft progress")
	app._on_command("hint")
	check(app.hud.is_hint_visible() and not app.paused, "original inline hint opens during planning")
	check("还可安排 3 节" in app.hud._hint_label.text, "opened help describes the current draft instead of sending player back to the seedbed")
	app._on_command("dir:right")
	check("还可安排 2 节" in app.hud._hint_label.text and app._hint_tier == 0, "visible help refreshes progress without advancing its tier")
	app._on_command("undo")
	app._on_command("hint_next")
	check(app._hint_tier == 1 and app.hud.is_hint_visible(), "hint text advances content")
	app._on_command("hint")
	check(not app.hud.is_hint_visible(), "hint button toggles closed")
	app._on_command("settings")
	check(app.paused and app.hud.is_modal_open(), "original settings owns pause")
	app.hud.close_overlay()
	check(not app.paused and app.plan.targets.size() == 1, "return from settings preserves draft")
	app._show_menu()
	check(app.paused and app.hud.is_modal_open(), "original map owns pause")
	app.hud.close_overlay()
	check(not app.paused and app.plan.targets.size() == 1, "return from map preserves draft")
	app._on_command("undo")
	app._on_command("undo")
	check(app.phase == "explore" and app.session.world.snapshot() == initial, "empty draft undo cancels without spending seeds")
	app._on_command("primary")
	for direction in ["up", "right", "right", "down"]: app._on_command("dir:" + direction)
	check(app.hud._interaction_label == "让根桥生长" and "确认" in app.hud._rule.text, "ready route has an explicit confirmation state")
	check(not app.hud.is_hint_visible(), "planning never reopens dismissed help")
	app._on_command("hint")
	check("确认后" in app.hud._hint_label.text, "ready hint explains that the road has not grown yet")
	app._on_command("primary")
	check("最后一节" in app.hud._hint_label.text, "growth help replaces obsolete planning instructions")
	app._process(0.05)
	check(app.phase == "growing" and not app.motion.is_empty(), "confirmation uses original motion transaction")
	app._on_command("settings")
	var elapsed: float = app.motion.elapsed
	app._process(1.0)
	check(app.motion.elapsed == elapsed, "pause freezes pending growth")
	app.hud.close_overlay()
	# Home cancels the pending presentation. Queue keeps the uncommitted step.
	app._show_home()
	check(app.home_active and app.motion.is_empty(), "original home clears pending visual motion")
	app._on_command("continue")
	await drain(app)
	check(app.phase == "crossing" and app.session.world.state.growth.root.size() == 4, "continue resumes uncommitted route without skipping a segment")
	if not app.hud.is_hint_visible(): app._on_command("hint")
	else: app._sync_hud()
	check("花坛" in app.hud._hint_label.text and "照料" in app.hud._rule.text, "connected bridge directs player toward tending the flower")
	app._on_command("undo")
	check(app.phase == "explore" and app.session.world.state.growth.root.size() == 3, "ordinary undo still rolls back actual growth")
	app._on_command("weave:plan")
	check(app.view.draft_origin().is_equal_approx(app.view.target_position("g:root:3:0")), "resumed draft begins at the actual third root, never across the central rock")
	app._on_command("retract:root")
	check(app.phase == "planning" and app.motion.is_empty() and app.session.world.state.growth.root.size() == 3, "legacy domain shortcuts cannot invalidate a draft")
	app._on_command("dir:down")
	check(app.plan.ready(), "remaining seed can be replanned after ordinary undo")
	check(app.view.draft_number(0) == 4 and app.view.draft.size() == 1, "resumed route numbers the new segment four and keeps committed roots out of the editable draft")
	app._world_click(app.view.target_position("g:root:3:1"))
	check(app.plan.targets.is_empty() and app.session.world.state.growth.root.size() == 3 and app.hud._interaction_label == "规划根桥 3/4", "clicking resumed draft removes only the uncommitted fourth segment")
	app._on_command("dir:down")
	app._on_command("primary")
	await drain(app)
	check(app.phase == "crossing" and app.session.world.connected(), "resumed draft reconnects the bridge")
	app._on_command("restart")
	check(app.phase == "explore" and app.plan == null and app.growth_queue.is_empty() and app.session.world.state.growth.root.is_empty(), "restart clears prototype and domain state together")
	app._on_command("primary")
	for direction in ["down", "right", "right", "up"]: app._on_command("dir:" + direction)
	app._on_command("primary")
	app._process(0.05)
	app._on_command("restart")
	check(app.phase == "explore" and app.motion.is_empty() and app.growth_queue.is_empty() and app.session.world.state.growth.root.is_empty(), "restart during growth immediately cancels pending queue")
	app._on_command("primary")
	app._on_command("dir:down")
	app._show_menu()
	app.hud.level_requested.emit("1-1")
	check(app.session.world.level.id == "1-1" and not app.view.planning and not app.paused and app.plan == null, "map transition clears draft and restores normal level behavior")
	app._on_command("primary")
	check(app.hud.is_context_open(), "first garden keeps original explicit growth choices")
	app._enter_level("1-2")
	check(app.phase == "explore" and app.session.world.state.growth.root.is_empty(), "returning to playtest has no stale planning controls")
	app.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "root-weaving-hud", "checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
