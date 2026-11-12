extends SceneTree
## Real CharacterBody3D movement; elapsed measurements exclude frame waits.
const Session = preload("res://application/game_session.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Movement = preload("res://application/native_movement.gd")
const Router = preload("res://application/input_router.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
var results: Array = []
var stage: Node2D
var session: RefCounted
var movement: RefCounted
var refresh_usec := 0
var crossings: Array = []

class UncachedMovement:
	extends Movement
	func _read_tiles() -> Array:
		# Empty input invokes the original core query behavior (rebuild per call).
		return []

class CountingWorld:
	extends World
	static var counting := false
	static var tile_calls := 0
	static var tile_usec := 0
	static var fork_calls := 0
	static var fork_usec := 0
	static var route_calls := 0
	static var route_usec := 0
	func _init(id: String = "1-1", saved: Dictionary = {}) -> void:
		super(id, saved)
	func tiles() -> Array:
		if not counting: return super.tiles()
		var start := Time.get_ticks_usec()
		var result: Array = super.tiles()
		tile_calls += 1
		tile_usec += Time.get_ticks_usec() - start
		return result
	func fork(saved: Dictionary) -> RefCounted:
		if not counting: return CountingWorld.new(str(level.id), saved)
		var start := Time.get_ticks_usec()
		var result := CountingWorld.new(str(level.id), saved)
		fork_calls += 1
		fork_usec += Time.get_ticks_usec() - start
		return result
	func path_to(id: String, who: String = "") -> Array:
		if not counting: return super.path_to(id, who)
		var start := Time.get_ticks_usec()
		var result: Array = super.path_to(id, who)
		route_calls += 1
		route_usec += Time.get_ticks_usec() - start
		return result

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_query_boundaries()
	for level_id: String in ["1-3", "3-4"]:
		await _setup(level_id)
		await _measure(level_id, "idle", "", 60)
		var start_id := str(session.world.state.actors.luvie)
		var target := ""
		var length := 0
		for tile: Dictionary in session.world.tiles():
			var path: Array = session.world.path_to(str(tile.id))
			if path.size() > length and path.size() <= 3:
				target = str(tile.id)
				length = path.size()
		_check(not target.is_empty(), level_id + " real reachable walking target exists")
		for batch: int in range(3):
			await _measure(level_id, "outbound-" + str(batch), target, 90)
			await _measure(level_id, "return-" + str(batch), start_id, 90)
		_check(session.world.normalize_saved(session.world.snapshot()).ok, level_id + " actual walked pose remains saveable")
		stage.queue_free()
		await process_frame
	print(JSON.stringify({"suite": "native-walk-performance", "passed": failures.is_empty(), "checks": checks, "failures": failures, "results": results, "scope": "Actual native motor plus synchronous stage refresh on support crossing; excludes HUD, disk save and GPU rendering."}))
	quit(0 if failures.is_empty() else 1)

func _test_query_boundaries() -> void:
	var probe := Movement.new()
	probe.session = Session.new("1-1")
	probe._query_active = true
	var before: Array = probe._read_tiles()
	_check(probe._point_for("g:root:1:0").is_empty(), "read scope starts with current absent growth")
	var outcome: RefCounted = probe.session.apply(GardenCommand.interact("grow:root:right"))
	_check(outcome.accepted and not probe._point_for("g:root:1:0").is_empty(), "committed revision invalidates the board within the same tick")
	_check(not before.any(func(tile: Dictionary) -> bool: return tile.id == "g:root:1:0"), "new revision never mutates a previously borrowed board")
	probe.session = Session.new("3-4")
	_check(probe._point_for("m:inner:-1:0").get("module", "") == "inner", "world replacement invalidates active query scope")
	probe._query_active = false
	probe.session = Session.new("1-1")
	probe._read_tiles()
	_check(probe.session.world.act("grow:root:right").ok, "direct domain action fixture succeeds outside tick")
	_check(not probe._point_for("g:root:1:0").is_empty(), "out-of-tick queries never retain stale boards even without session revision")

func _setup(level_id: String) -> void:
	session = Session.new(level_id)
	session.world = CountingWorld.new(level_id)
	stage = Stage.new()
	root.add_child(stage)
	stage.set_world(session.world)
	movement = UncachedMovement.new() if "--baseline" in OS.get_cmdline_user_args() else Movement.new()
	movement.setup(session, stage, Router.new())
	movement.support_changed.connect(_support_changed)
	for unused: int in range(5):
		await physics_frame
		movement.tick(1.0 / 60.0)

func _support_changed(who: String, result: RefCounted) -> void:
	var start := Time.get_ticks_usec()
	stage.refresh_world(session.world, true)
	refresh_usec += Time.get_ticks_usec() - start
	crossings.append({"who": who, "support": str(result.after.actors[who])})

func _measure(level_id: String, phase: String, target: String, frames: int) -> void:
	var expected_route: Array = session.world.path_to(target) if not target.is_empty() else []
	if not target.is_empty(): movement.request_path(expected_route)
	CountingWorld.tile_calls = 0
	CountingWorld.tile_usec = 0
	CountingWorld.fork_calls = 0
	CountingWorld.fork_usec = 0
	CountingWorld.route_calls = 0
	CountingWorld.route_usec = 0
	refresh_usec = 0
	crossings = []
	var times: Array = []
	var crossing_times: Array = []
	var steady_times: Array = []
	var max_floor_error := 0.0
	for unused: int in range(frames):
		await physics_frame
		var count := crossings.size()
		CountingWorld.counting = true
		var start := Time.get_ticks_usec()
		movement.tick(1.0 / 60.0)
		var elapsed := Time.get_ticks_usec() - start
		CountingWorld.counting = false
		times.append(elapsed)
		if count != crossings.size(): crossing_times.append(elapsed)
		else: steady_times.append(elapsed)
		for who: String in ["luvie", "buddy"]:
			var body: CharacterBody3D = stage.get_actor_body(who)
			max_floor_error = maxf(max_floor_error, absf(body.position.y - stage.support_height(body.position, str(session.world.state.actors[who]), who)))
	_check(max_floor_error < 0.2, level_id + " " + phase + " maintains physical support")
	if not target.is_empty():
		_check(str(session.world.state.actors.luvie) == target, level_id + " " + phase + " reaches actual requested support")
		_check(movement.click_path.is_empty(), level_id + " " + phase + " finishes physical route")
		for who: String in ["luvie", "buddy"]:
			var actual_route: Array = []
			for crossing: Dictionary in crossings:
				if crossing.who == who: actual_route.append(crossing.support)
			var expected: Array = expected_route if who == "luvie" or bool(session.world.state.follow) else []
			_check(actual_route == expected, level_id + " " + phase + " preserves exact legal support crossings for " + who)
	elif not "--baseline" in OS.get_cmdline_user_args():
		_check(CountingWorld.tile_calls == frames, level_id + " idle tick derives exactly one board")
	_check(not movement._query_active and movement._query_tiles.is_empty(), "query scope never survives a tick")
	results.append({"level": level_id, "phase": phase, "frames": frames, "tick": _stats(times), "steady": _stats(steady_times), "crossing": _stats(crossing_times), "tilesCalls": CountingWorld.tile_calls, "tilesMs": CountingWorld.tile_usec / 1000.0, "forkCalls": CountingWorld.fork_calls, "forkMs": CountingWorld.fork_usec / 1000.0, "routeCalls": CountingWorld.route_calls, "routeMs": CountingWorld.route_usec / 1000.0, "refreshMs": refresh_usec / 1000.0, "crossings": crossings.duplicate(true), "actors": session.world.state.runtime.poses.duplicate(true), "maxFloorError": max_floor_error})

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count": 0}
	values.sort()
	var sum := 0
	for value: int in values: sum += value
	return {"count": values.size(), "totalMs": sum / 1000.0, "medianMs": float(values[values.size() / 2]) / 1000.0, "p95Ms": float(values[mini(values.size() - 1, int(values.size() * 0.95))]) / 1000.0, "maxMs": float(values.back()) / 1000.0}

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
