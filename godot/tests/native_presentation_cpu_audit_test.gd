extends SceneTree
## Headless read-only profiling. Counts are deterministic; concurrent machine
## load affects timings. No claim about GPU pixels or browser frame rate.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Session = preload("res://application/game_session.gd")
const Movement = preload("res://application/native_movement.gd")
const Router = preload("res://application/input_router.gd")
const Rays = preload("res://presentation/native/rule_ray_presentation.gd")
const Repository = preload("res://services/save_repository.gd")
var results: Array = []
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var walk_session: RefCounted

class Meter:
	static var enabled := false
	static var tiles := 0
	static var tile_usec := 0
	static var visible := 0
	static var visible_usec := 0
	static var rays := 0
	static var lamp := 0
	static func reset() -> void:
		tiles = 0
		tile_usec = 0
		visible = 0
		visible_usec = 0
		rays = 0
		lamp = 0

class CountedWorld:
	extends World
	func _init(id: String = "1-1", saved: Dictionary = {}) -> void: super(id, saved)
	func fork(saved: Dictionary) -> RefCounted: return CountedWorld.new(str(level.id), saved)
	func tiles() -> Array:
		if not Meter.enabled: return super.tiles()
		var start := Time.get_ticks_usec()
		var result: Array = super.tiles()
		Meter.tiles += 1
		Meter.tile_usec += Time.get_ticks_usec() - start
		return result
	func visible(tile: Dictionary, world_tiles: Array = []) -> bool:
		if not Meter.enabled: return super.visible(tile, world_tiles)
		var start := Time.get_ticks_usec()
		var result: bool = super.visible(tile, world_tiles)
		Meter.visible += 1
		Meter.visible_usec += Time.get_ticks_usec() - start
		return result
	func rays() -> Array:
		if Meter.enabled: Meter.rays += 1
		return super.rays()
	func lamp_ray() -> Array:
		if Meter.enabled: Meter.lamp += 1
		return super.lamp_ray()

class CountedCloud:
	extends Cloud
	func _init(id: String = "cloud-1", saved: Dictionary = {}) -> void: super(id, saved)
	func fork(saved: Dictionary) -> RefCounted: return CountedCloud.new(str(level.id), saved)
	func tiles() -> Array:
		if not Meter.enabled: return super.tiles()
		var start := Time.get_ticks_usec()
		var result: Array = super.tiles()
		Meter.tiles += 1
		Meter.tile_usec += Time.get_ticks_usec() - start
		return result
	func visible(tile: Dictionary, world_tiles: Array = []) -> bool:
		if Meter.enabled: Meter.visible += 1
		return super.visible(tile, world_tiles)
	func rays() -> Array:
		if Meter.enabled: Meter.rays += 1
		return super.rays()
	func lamp_ray() -> Array:
		if Meter.enabled: Meter.lamp += 1
		return super.lamp_ray()

class TimedStage:
	extends Stage
	var water_usec := 0
	var water_tiles := 0
	func _update_water_presentation() -> void:
		var start := Time.get_ticks_usec()
		var old_tiles := Meter.tiles
		super._update_water_presentation()
		if Meter.enabled:
			water_usec += Time.get_ticks_usec() - start
			water_tiles += Meter.tiles - old_tiles

func _initialize() -> void:
	call_deferred("_run")

func _world(id: String, saved: Dictionary = {}) -> RefCounted:
	return CountedCloud.new(id, saved) if id.begins_with("cloud-") else CountedWorld.new(id, saved)

func _run() -> void:
	var actions := {"1-1": "grow:root:right", "1-2": "grow:root:up", "1-3": "turn:garden", "1-4": "use:hold", "2-1": "valve:water", "2-2": "angle:mirrorA", "2-3": "beat", "2-4": "turn:boat", "3-1": "use:window", "3-2": "valve:mode", "3-3": "turn:water", "3-4": "turn:light", "cloud-1": "rotate", "cloud-2": "lift", "cloud-3": "rotate"}
	for id: String in Repository.LEVEL_IDS:
		stage = TimedStage.new()
		root.add_child(stage)
		stage.set_process(false)
		stage.set_world(_world(id))
		await process_frame
		var snapshot: Dictionary = stage.world.snapshot()
		_measure(id, "initial_process", func(_frame: int) -> void: stage._process(1.0 / 60.0))
		_measure(id, "initial_growth_choices", func(_frame: int) -> void: stage.growth_choice_layout())
		_measure(id, "initial_water", func(_frame: int) -> void: stage._update_water_presentation())
		_check(stage.world.snapshot() == snapshot, id + " frame presentation does not mutate domain")
		var pair := _pair(id, str(actions[id]))
		if not pair.is_empty():
			stage.set_world(_world(id, pair[1]))
			stage.set_motion(pair[0], pair[1], 0.0, str(actions[id]))
			_measure(id, "warm_motion", func(frame: int) -> void: stage.set_motion(pair[0], pair[1], float(frame) / 59, str(actions[id])))
			_measure(id, "motion_ray_policy", func(frame: int) -> void: Rays.update_motion(stage, stage._motion_before, stage._motion_after, float(frame) / 59))
			_check(stage._motion_before.snapshot() == pair[0] and stage._motion_after.snapshot() == pair[1], id + " motion presentation preserves both snapshots")
			stage.clear_motion()
			_measure(id, "after_action_process", func(_frame: int) -> void: stage._process(1.0 / 60.0))
		if id == "3-1": await _audit_discovery_crossing()
		stage.queue_free()
		await process_frame
	print(JSON.stringify({"suite": "native-presentation-cpu-audit", "passed": failures.is_empty(), "checks": checks, "failures": failures, "results": results, "timingsInclusive": true, "gpuPixelsVerified": false, "timingEnvironment": "Concurrent browser QA/build/test work; call counts reliable, timings diagnostic."}))
	quit(0 if failures.is_empty() else 1)

func _measure(id: String, phase: String, action: Callable, frames: int = 60) -> void:
	Meter.reset()
	stage.water_usec = 0
	stage.water_tiles = 0
	Meter.enabled = true
	var start := Time.get_ticks_usec()
	for frame: int in range(frames): action.call(frame)
	var elapsed := Time.get_ticks_usec() - start
	Meter.enabled = false
	_record(id, phase, frames, elapsed)

func _record(id: String, phase: String, frames: int, elapsed: int) -> void:
	var record := {"level": id, "phase": phase, "frames": frames, "elapsedUsec": elapsed, "tilesCalls": Meter.tiles, "tilesUsec": Meter.tile_usec, "visibleCalls": Meter.visible, "visibleUsec": Meter.visible_usec, "rayCalls": Meter.rays, "lampRayCalls": Meter.lamp, "waterUsec": stage.water_usec, "waterTiles": stage.water_tiles, "surfaces": stage._surfaces.size(), "waterLinks": stage._water_links.size()}
	results.append(record)
	print("PRESENTATION CPU " + JSON.stringify(record))

func _pair(id: String, action: String) -> Array:
	var cloud := id.begins_with("cloud-")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json" if cloud else "res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.levels if cloud else fixture.cases:
		if (str(entry.id) != id if cloud else str(entry.name) != "authored/" + id): continue
		var before: Dictionary = entry.initial if cloud else entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act" and str(step.command.value) == action:
				var world := _world(id, before)
				var native_before: Dictionary = world.snapshot()
				_check(bool(world.act(action, true).ok), id + " authored motion action is legal")
				return [native_before, world.snapshot()]
			before = step.snapshot
	_check(false, id + " authored motion exists: " + action)
	return []

func _audit_discovery_crossing() -> void:
	walk_session = Session.new("3-1")
	walk_session.world = _world("3-1")
	stage.set_world(walk_session.world)
	var movement := Movement.new()
	movement.setup(walk_session, stage, Router.new())
	movement.support_changed.connect(_discovery_crossed)
	var target := ""
	var length := 0
	for tile: Dictionary in walk_session.world.tiles():
		var path: Array = walk_session.world.path_to(str(tile.id))
		if path.size() > length and path.size() <= 3:
			target = str(tile.id)
			length = path.size()
	movement.request_path(walk_session.world.path_to(target))
	for unused: int in range(90):
		await physics_frame
		movement.tick(1.0 / 60.0)
	_check(str(walk_session.world.state.actors.luvie) == target, "3-1 discovery audit physically crosses the requested supports")

func _discovery_crossed(who: String, result: RefCounted) -> void:
	var builds: int = stage._build_count
	_measure("3-1", "crossing_refresh/" + who + "/" + str(result.after.actors[who]), func(_frame: int) -> void: stage.refresh_world(walk_session.world, true), 1)
	results.back()["terrainRebuilds"] = stage._build_count - builds

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
