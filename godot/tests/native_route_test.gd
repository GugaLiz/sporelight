extends SceneTree
## Full authored routes through real bodies, collision, portals and application
## transactions. Fixtures provide player intentions, never actor teleports.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Router = preload("res://application/input_router.gd")
const Repository = preload("res://services/save_repository.gd")
const Command = preload("res://contracts/game_command.gd")
var checks := 0
var failures: Array[String] = []
var routes: Array = []
var app: Node
var samples := 0
var max_visual_penetration := 0.0
var max_body_surface_gap := 0.0
var _hard_base_failures: Dictionary = {}

class Harness:
	extends "res://application/main.gd"
	func _ready() -> void:
		pass

class AudioStub:
	extends Node
	func start() -> void: pass
	func play(_kind: String) -> void: pass
	func configure(_settings: Dictionary) -> void: pass
	func pause(_value: bool) -> void: pass

class MemoryRepository:
	extends "res://services/save_repository.gd"
	func persist(candidate: Dictionary = {}) -> Dictionary:
		var value := data if candidate.is_empty() else candidate
		var validation: Dictionary = _validate_store(value)
		if validation.ok:
			data = value.duplicate(true)
		return validation

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)
	return value

func _setup() -> void:
	app = Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_input(false)
	app.set_physics_process(false)
	app.levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	app.levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	app.input_router = Router.new()
	app.repository = MemoryRepository.new()
	app.repository.configure_levels(app.levels)
	app.repository.snapshot_validator = app._normalize_snapshot
	app.audio = AudioStub.new()
	app.add_child(app.audio)
	app.settings = Repository.default_settings()
	app.view = Stage.new()
	app.add_child(app.view)
	app.hud = HUD.new()
	app.add_child(app.hud)
	app.hud.command_requested.connect(app._on_command)
	app.hud.set_repository(app.repository)
	app.native_enabled = true

func _tick() -> void:
	await physics_frame
	app._process(1.0 / 60.0)
	app._physics_process(1.0 / 60.0)
	if not app.motion.is_empty():
		return
	for who: String in ["luvie", "buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		var support: String = str(app.session.world.state.actors[who])
		var floor_height: float = app.view.support_height(body.position, support, who)
		if not app.view.prop_physical_point_clear(body.position,who):
			var failure_key: String = str(app.session.world.level.id)+"/"+who
			if not _hard_base_failures.has(failure_key):
				_hard_base_failures[failure_key]=true
				_check(false,failure_key+" physical route entered a hard prop base at "+str(body.position))
		max_body_surface_gap = maxf(max_body_surface_gap, absf(body.position.y - floor_height))
		var visual: Node3D = app.view.actor_visual_root(who)
		if visual != null:
			max_visual_penetration = maxf(max_visual_penetration, absf(body.position.y + visual.position.y - floor_height))
		samples += 1

func _drain(limit: int = 240) -> bool:
	for unused in range(limit):
		await _tick()
		if app.motion.is_empty() and not app.native_movement.is_moving() and not app.waiting_repair:
			return true
	return false

func _walk_to(id: String, label: String) -> bool:
	# The old 1-2 landing was a fixed tile overlapping its fourth root.
	# Preserve the recorded player destination while requiring the grown tile.
	if str(app.session.world.level.id) == "1-2" and id == "f:3:1": id = "g:root:3:1"
	var current: String = str(app.session.world.state.actors[app.session.world.actor()])
	if id == current:
		return true
	var path: Array = app.session.world.path_to(id)
	if not _check(not path.is_empty(), label + " has a permitted route from " + current):
		return false
	app._execute(Command.move_to(id), "move")
	# A real hard base can require a longer physical detour than the rule-grid
	# route. Budget for the actual planned supports; keep the same stop and
	# destination assertions instead of treating a valid detour as a deadlock.
	var physical_steps: int = app.native_movement.click_path.size()
	var drained := await _drain(maxi(240, maxi(path.size() * 60, physical_steps * 90)))
	if not _check(drained, label + " physical route settles"):
		print("ROUTE STALL ", JSON.stringify(app.native_movement.qa_state()))
		var body: CharacterBody3D = app.view.get_actor_body(app.session.world.actor())
		for collision_index in range(body.get_slide_collision_count()):
			var collision := body.get_slide_collision(collision_index)
			var collider := collision.get_collider() as Node
			print("STALL COLLISION ", collision.get_position(), " normal=", collision.get_normal(), " support=", collider.get_meta("support_id", "") if collider != null else "")
		return false
	var reached: bool = str(app.session.world.state.actors[app.session.world.actor()]) == id
	# A core's stone base can occupy its entire logical centre. Preserve the
	# fixture's request and the domain's existing near(core) interaction range;
	# the physical endpoint must be a clear reachable approach, not inside it.
	if not reached and app.native_movement._uses_prop_obstacles() and app.native_movement._is_core_request(id):
		var core_waypoint: Dictionary = app.native_movement._prop_waypoint(app.session.world.point_for(id),app.session.world.actor())
		if core_waypoint.is_empty():
			var body: CharacterBody3D = app.view.get_actor_body(app.session.world.actor())
			reached = app.session.world.near(id) and app.view.prop_point_clear(body.position,app.session.world.actor())
	if not _check(reached, label + " reaches " + id):
		print("ROUTE WRONG SUPPORT ", JSON.stringify(app.native_movement.qa_state()))
	return reached

func _replay(id: String, steps: Array, initial: Dictionary) -> void:
	app._enter_level(id)
	await _tick()
	await _tick()
	var success := true
	var expected_before := initial
	var executed := 0
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		var command: Dictionary = step.command
		var label := "%s/%d/%s/%s" % [id, index, command.kind, command.value]
		if str(command.kind) == "move":
			success = await _walk_to(str(command.value), label)
		elif str(command.kind) == "act":
			# The original auto-follow advanced one logical tile per hero step.
			# If the new physical follower arrives elsewhere, walk the now active
			# character to the fixture's intended interaction support legally.
			var actor: String = app.session.world.actor()
			var intended: String = str(expected_before.get("actors", {}).get(actor, expected_before.get("tile", "")))
			# Interactions follow the authored marker when its location changes.
			if id == "1-1" and str(command.value) == "repair":
				for mark: Dictionary in app.session.world.level.get("marks", []):
					if str(mark.kind) == "core": intended = str(mark.tile)
			if not intended.is_empty() and intended != str(app.session.world.state.actors[actor]):
				if not await _walk_to(intended, label + "/approach"):
					success = false
					break
			var revision: int = app.session.revision
			app._on_command(str(command.value))
			var drained := await _drain()
			success = _check(drained, label + " action and passengers settle")
			if not drained: print("ROUTE ACTION STALL ",JSON.stringify({"motion":app.motion,"waiting_repair":app.waiting_repair,"status":app.status_message,"movement":app.native_movement.qa_state()}))
			if success:
				success = _check(app.session.revision > revision or bool(app.session.world.state.completed), label + " accepted through application transaction: " + app.status_message)
		else:
			success = _check(false, label + " unsupported route operation")
		if not success:
			break
		executed += 1
		expected_before = step.snapshot
		var normalized: Dictionary = app.session.world.normalize_saved(app.session.world.snapshot())
		if not _check(normalized.get("ok", false), label + " stable native save valid"):
			success = false
			break
	var completed := bool(app.session.world.state.completed)
	_check(success and completed, id + " authored route completes with native bodies")
	routes.append({"level": id, "completed": completed, "success": success, "steps": executed, "expectedSteps": steps.size()})
	print("NATIVE ROUTE ", JSON.stringify(routes.back()))

func _run() -> void:
	_setup()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var selected := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			selected = argument.trim_prefix("--level=")
	for fixture: Dictionary in reference.cases:
		if str(fixture.name).begins_with("authored/") and (selected.is_empty() or selected == str(fixture.levelId)):
			await _replay(str(fixture.levelId), fixture.steps, fixture.initial.snapshot)
	var cloud: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for fixture: Dictionary in cloud.levels:
		if selected.is_empty() or selected == str(fixture.id):
			await _replay(str(fixture.id), fixture.steps, fixture.initial)
	print(JSON.stringify({"suite": "native-full-routes", "passed": failures.is_empty(), "checks": checks, "routes": routes, "samples": samples, "maxBodySurfaceGap": max_body_surface_gap, "maxVisualContactError": max_visual_penetration, "failures": failures}))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
