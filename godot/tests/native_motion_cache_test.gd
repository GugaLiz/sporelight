extends SceneTree
## CPU query cost and exact geometry; this test does not claim GPU frame rates.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var measurements: Array = []

class UncachedStage:
	extends Stage
	func _motion_point(snapshot_world: RefCounted, id: String) -> Dictionary:
		return snapshot_world.point_for(id)

class CountingWorld:
	extends World
	static var tile_calls := 0
	func _init(level_id: String = "1-1", saved: Dictionary = {}) -> void:
		super(level_id, saved)
	func tiles() -> Array:
		tile_calls += 1
		return super.tiles()
	func fork(saved: Dictionary) -> RefCounted:
		return CountingWorld.new(str(level.id), saved)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = UncachedStage.new() if "--baseline" in OS.get_cmdline_user_args() else Stage.new()
	root.add_child(stage)
	await process_frame
	_benchmark()
	if not "--baseline" in OS.get_cmdline_user_args():
		for spec: Array in [["3-4", "turn:light"], ["3-4", "turn:inner"], ["2-1", "valve:water"], ["2-4", "turn:boat"], ["3-2", "valve:mode"], ["1-2", "grow:root:up"], ["3-3", "use:care"]]:
			_test_geometry(str(spec[0]), str(spec[1]))
	print(JSON.stringify({"suite": "native-motion-cache", "passed": failures.is_empty(), "checks": checks, "failures": failures, "measurements": measurements, "gpuPixelsVerified": false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _pair(level_id: String, action: String) -> Array:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) != "authored/" + level_id: continue
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act" and str(step.command.value) == action:
				var from_world := World.new(level_id, before)
				var from_snapshot: Dictionary = from_world.snapshot()
				_check(bool(from_world.act(action, true).ok), "real motion action succeeds: " + action)
				return [from_snapshot, from_world.snapshot()]
			before = step.snapshot
	_check(false, "authored motion exists: " + level_id + "/" + action)
	return []

func _benchmark() -> void:
	var pair := _pair("3-4", "turn:light")
	var world := CountingWorld.new("3-4", pair[1])
	stage.set_world(world)
	stage.set_motion(pair[0], pair[1], 0.0, "turn:light")
	for batch: int in range(4):
		CountingWorld.tile_calls = 0
		var started := Time.get_ticks_usec()
		for frame: int in range(60):
			var progress := float(frame) / 59
			stage.set_motion(pair[0], pair[1], progress, "turn:light")
			for who: String in ["luvie", "buddy"]:
				stage.sample_tile_position(pair[0], pair[1], str(pair[0].actors[who]), progress)
		measurements.append({"batch": batch, "frames": 60, "elapsedMs": (Time.get_ticks_usec() - started) / 1000.0, "tilesCalls": CountingWorld.tile_calls, "surfaces": stage._surfaces.size()})
		if not "--baseline" in OS.get_cmdline_user_args():
			# This guards against returning to per-surface board rebuilds. Water
			# endpoints now also reuse the immutable motion indexes.
			_check(CountingWorld.tile_calls <= 240, "warm animation has bounded tile queries instead of per-surface rebuilds")
	CountingWorld.tile_calls = 0
	var sample_started := Time.get_ticks_usec()
	for frame: int in range(60):
		for who: String in ["luvie", "buddy"]:
			stage.sample_tile_position(pair[0], pair[1], str(pair[0].actors[who]), float(frame) / 59)
	measurements.append({"actorSamples": 120, "elapsedMs": (Time.get_ticks_usec() - sample_started) / 1000.0, "tilesCalls": CountingWorld.tile_calls})
	if not "--baseline" in OS.get_cmdline_user_args():
		_check(CountingWorld.tile_calls == 0, "warm actor samples do not rebuild tiles")
	stage.clear_motion()

func _test_geometry(level_id: String, action: String) -> void:
	var pair := _pair(level_id, action)
	var original: Array = pair.duplicate(true)
	var world := CountingWorld.new(level_id, pair[1])
	stage.set_world(world)
	for reverse: bool in [false, true]:
		var before: Dictionary = pair[1] if reverse else pair[0]
		var after: Dictionary = pair[0] if reverse else pair[1]
		var from_world := World.new(level_id, before)
		var to_world := World.new(level_id, after)
		var ids: Dictionary = {"missing-tile": true}
		for tile: Dictionary in from_world.tiles() + to_world.tiles(): ids[str(tile.id)] = true
		stage.set_motion(before, after, 0.0, action)
		for progress: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			stage.set_motion(before, after, progress, action)
			for id: String in ids:
				var expected := _oracle(from_world, to_world, id, progress)
				CountingWorld.tile_calls = 0
				var sampled: Vector3 = stage.sample_tile_position(before, after, id, progress)
				_check(sampled.is_equal_approx(expected), level_id + " geometry " + id + " at " + str(progress) + " reverse=" + str(reverse))
				_check(CountingWorld.tile_calls == 0, "snapshot query reuses tiles for " + id)
				if stage._surfaces.has(id) and not to_world.point_for(id).is_empty():
					var eased := progress * progress * (3 - 2 * progress)
					_check(stage._surfaces[id].position.is_equal_approx(_oracle(from_world, to_world, id, eased)), level_id + " surface follows original easing " + id)
		stage.clear_motion()
		_check(stage._motion_before == null and stage._motion_after == null, "clear releases snapshots")
		var id := str(before.actors.luvie)
		_check(stage.sample_tile_position(before, after, id, 0.5).is_equal_approx(_oracle(from_world, to_world, id, 0.5)), "uncached independent sampling remains exact")
		stage.set_world(World.new("1-1"))
		stage.set_world(world)
		stage.set_motion(before, after, 0.5, action)
		_check(stage.sample_tile_position(before, after, id, 0.5).is_equal_approx(_oracle(from_world, to_world, id, 0.5)), "re-entry rebuilds correct motion cache")
		stage.set_world(World.new("1-1"))
		_check(stage._motion_before == null and stage._motion_after == null and stage._motion_before_tiles.is_empty() and stage._motion_after_tiles.is_empty(), "cross-level switch releases active motion and both indexes")
		stage.set_world(world)
		stage.set_motion(before, after, 0.5, action)
		_check(stage.sample_tile_position(before, after, id, 0.5).is_equal_approx(_oracle(from_world, to_world, id, 0.5)), "interrupted motion re-entry restores exact position")
		stage.clear_motion(false)
	_check(pair == original and world.snapshot() == pair[1], level_id + " rendering never mutates snapshots or live rules")

func _oracle(from_world: RefCounted, to_world: RefCounted, id: String, progress: float) -> Vector3:
	# Module transforms exist even when a logical tile is hidden by overlap.
	# Resolve that endpoint independently before testing the cached sampler.
	var first: Dictionary = from_world.point_for(id)
	var last: Dictionary = to_world.point_for(id)
	var parts := id.split(":")
	var module_moves := false
	if parts.size() == 4 and parts[0] == "m":
		for module: Dictionary in from_world.level.modules:
			if str(module.id) == parts[1]:
				module_moves = (str(module.kind) == "rotate" and from_world.state.turns[module.id] != to_world.state.turns[module.id]) or from_world.module_point(module.id, [0, 0]) != to_world.module_point(module.id, [0, 0])
	if module_moves:
		if first.is_empty():
			first = from_world.module_point(parts[1], [int(parts[2]), int(parts[3])])
			first["module"] = parts[1]
		if last.is_empty():
			last = to_world.module_point(parts[1], [int(parts[2]), int(parts[3])])
			last["module"] = parts[1]
	if first.is_empty(): first = last
	if last.is_empty(): last = first
	var a: Vector3 = stage.tile_position(first)
	var b: Vector3 = stage.tile_position(last)
	for module: Dictionary in from_world.level.get("modules", []):
		if str(module.id) != str(first.get("module", "")) or str(module.get("kind", "")) != "rotate": continue
		var delta := posmod(int(to_world.state.turns.get(module.id, 0)) - int(from_world.state.turns.get(module.id, 0)), 4)
		var angle := float(delta if delta <= 2 else delta - 4) * PI / 2 * progress
		var offset := Vector2(a.x - float(module.x), a.z - float(module.z)).rotated(angle)
		return Vector3(float(module.x) + offset.x, lerpf(a.y, b.y, progress), float(module.z) + offset.y)
	return a.lerp(b, progress)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
