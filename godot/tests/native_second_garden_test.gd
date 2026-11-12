extends "res://tests/native_route_test.gd"

const World = preload("res://core/garden_world.gd")
const Terrain = preload("res://presentation/native/second_garden_profile.gd")

func _action(id: String) -> void:
	var revision: int = app.session.revision
	app._on_command(id)
	_check(await _drain(), id + " transaction settles")
	_check(app.session.revision > revision, id + " accepted")

func _check_progress(count: int) -> void:
	var before: Dictionary = app.session.world.snapshot()
	var context: Dictionary = app._native_interaction_context()
	_check(context.get("label", "") == "根路 %d/4" % count, "committed path progress stays in the primary action")
	_check(context.get("id", "") == "context", "progress does not auto-select a root action")
	_check(app.session.world.snapshot() == before, "reading progress never changes rules or support")

func _run() -> void:
	_setup()
	for directions: Array in [["up","right","right","down"], ["down","right","right","up"]]:
		app._enter_level("1-2")
		await _tick()
		await _walk_to("f:1:1", "approach seedbed")
		_check_progress(0)
		_check(app.session.world.budget() == 4, "four-segment budget retained")
		_check(not app.session.world.act("grow:root:right").ok, "rock blocks the direct route")
		for direction: String in directions:
			var before: Dictionary = app.session.world.snapshot()
			app._on_command("grow:root:" + direction)
			_check(not app.motion.is_empty(), "each segment has a preview")
			_check(app.session.world.state.growth == before.growth, "preview never opens traversable roots")
			await _drain()
			_check_progress(app.session.world.state.growth.root.size())
			var restored := World.new("1-2", app.session.world.snapshot())
			_check(restored.state.growth == app.session.world.state.growth, "partial route survives save restore")
		_check(app.session.world.budget() == 0, "four segments exhaust the seed")
		_check(not app.session.world.act("grow:root:right").ok, "no fifth segment")
		await _walk_to("f:4:1", "both detours reach the original flowerbed")
		var hero: CharacterBody3D = app.view.get_actor_body("luvie")
		var position_before := hero.position
		app.native_movement.capture()
		app.native_movement.restore()
		_check(hero.position.distance_to(position_before) < 0.002, "widened island restores normalized saved position")
		app._on_command("hint")
		_check(app.hud.is_hint_visible() and not app.paused, "second garden uses inline hints")
		app._on_command("hint_next")
		app._on_command("hint")
		_check(not app.hud.is_hint_visible() and app._hint_tier == 1, "hint toggle preserves reading position")
		await _walk_to("f:5:0", "upper terrace stair flight")
		await _walk_to("f:5:2", "optional observation terrace")
		await _walk_to("f:4:1", "return to flowerbed")
		_check(app.session.world.state.collected.is_empty(), "collection remains optional")
		await _action("repair")
		_check(app.session.world.state.completed, "both authored solutions complete")
		_check(World.new("1-2", app.session.world.snapshot()).state.completed, "completion survives save restore")
	app._enter_level("1-2")
	await _tick()
	await _walk_to("f:1:1", "try a direction")
	await _action("grow:root:up")
	app._on_command("undo")
	_check(app.session.world.state.growth.root.is_empty(), "undo restores budget and topology")
	_check_progress(0)
	await _action("grow:root:up")
	await _action("retract:root")
	_check(app.session.world.state.growth.root.is_empty(), "retract removes the last segment")
	app._on_command("grow:root:down")
	app._show_home()
	_check(app.session.world.state.growth.root.is_empty() and app.motion.is_empty(), "home cancels uncommitted path growth")
	app._on_command("continue")
	_check(not app.home_active and app.native_movement.is_stable(), "continue releases action ownership")
	# Explicit growth direction on a turning flat path, including shader cleanup.
	var initial := World.new("1-2")
	initial.state.actors.luvie = "f:1:1"
	for direction: String in ["down","right","right"]:
		var before: Dictionary = initial.snapshot()
		initial.act("grow:root:" + direction)
		var after: Dictionary = initial.snapshot()
		app.view.set_world(initial.fork(before))
		app.view.set_motion(before,after,0.5,"grow:root:" + direction)
		var id := str(after.growth.root.back())
		var surface: Node3D = app.view._surfaces[id]
		var axis := Vector3.BACK if direction == "down" else Vector3.RIGHT
		for part: MeshInstance3D in surface._growth_overrides:
			_check(part.material_override.get_shader_parameter("growth_axis") == axis, "root unfolds from its predecessor")
		_check(is_equal_approx(surface.sample_height(surface.position),0.0), "flat root never inherits an island stair")
		surface.set_growth_reveal(1.0)
		_check(surface._growth_overrides.is_empty(), "reveal returns shared materials")
	app.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"second-garden", "checks":checks, "passed":failures.is_empty(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
