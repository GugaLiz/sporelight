extends "res://tests/native_route_test.gd"
## Inclusive CPU timings of the real 1-4 command/motor/presentation chain.
## This does not measure GPU compilation, browser frames or file persistence.
var measurements: Array[Dictionary] = []
const Sanctuary = preload("res://presentation/native/original_sanctuary_dressing.gd")
const Obstacles = preload("res://presentation/native/native_prop_obstacles.gd")

class TimedStage:
	extends "res://presentation/native/native_garden_stage.gd"
	var timings: Dictionary = {}
	func _record(key: String, started: int) -> void:
		var row: Dictionary = timings.get(key, {"calls":0, "usec":0})
		row.calls += 1
		row.usec += Time.get_ticks_usec() - started
		timings[key] = row
	func refresh_world(value: RefCounted, preserve_pose: bool = true, cached_tiles: Array = []) -> void:
		var started := Time.get_ticks_usec()
		super.refresh_world(value, preserve_pose, cached_tiles)
		_record("refresh", started)
	func _update_props() -> void:
		var started := Time.get_ticks_usec()
		super._update_props()
		_record("props", started)
	func _update_terrain() -> void:
		var started := Time.get_ticks_usec()
		super._update_terrain()
		_record("terrain", started)
	func _add_sanctuary() -> void:
		var started := Time.get_ticks_usec()
		super._add_sanctuary()
		_record("sanctuary", started)
	func _add_mole() -> void:
		var started := Time.get_ticks_usec()
		super._add_mole()
		_record("mole", started)
	func support_height(at: Vector3, support_id: String, who: String = "") -> float:
		var started := Time.get_ticks_usec()
		var result: float = super.support_height(at, support_id, who)
		_record("supportHeight", started)
		return result

func _initialize() -> void:
	create_timer(35).timeout.connect(func() -> void: push_error("hold profile timed out"); quit(2))
	_run.call_deferred()

func _timings() -> Dictionary:
	var result := {}
	for key: String in app.view.timings:
		var row: Dictionary = app.view.timings[key]
		result[key] = {"calls":row.calls, "inclusiveMs":float(row.usec)/1000.0}
	return result

func _measure_command(command: String, held: bool) -> void:
	app.view.timings.clear()
	var nodes_before: Array[int] = []
	for node: Node in app.view._props.get_children(): nodes_before.append(node.get_instance_id())
	var obstacles_before: int = app.view.prop_obstacle_revision
	var started := Time.get_ticks_usec()
	app._on_command(command)
	var call_usec := Time.get_ticks_usec() - started
	var frames := 0
	var total_usec := call_usec
	var maximum_usec := call_usec
	while (not app.motion.is_empty() or app.native_movement.is_moving() or app._approaching_heavy_lever) and frames < 180:
		await physics_frame
		started = Time.get_ticks_usec()
		app._process(1.0/60.0)
		app._physics_process(1.0/60.0)
		var elapsed := Time.get_ticks_usec() - started
		total_usec += elapsed
		maximum_usec = maxi(maximum_usec, elapsed)
		frames += 1
	_check(frames < 180, command + " settles through the actual application")
	_check(app.session.world.lever_held() == held, command + " keeps the expected hold state")
	var nodes_after: Array[int] = []
	for node: Node in app.view._props.get_children(): nodes_after.append(node.get_instance_id())
	_check(nodes_before == nodes_after, command + " reuses every static prop node")
	_check(app.view.prop_obstacle_revision == obstacles_before, command + " keeps the existing obstacle and route cache revision")
	measurements.append({"phase":command, "commandMs":call_usec/1000.0, "synchronousTotalMs":total_usec/1000.0, "maximumSynchronousSliceMs":maximum_usec/1000.0, "simulationFrames":frames, "propNodesReused":nodes_before == nodes_after, "obstacleRevisionUnchanged":app.view.prop_obstacle_revision == obstacles_before, "inclusiveTimings":_timings()})

func _cache_contract() -> void:
	var fountain: Node3D = app.view._props.get_node("SanctuaryFountain")
	var desired: Vector3 = fountain.get_meta("original_sanctuary_desired")
	var before: Dictionary = Sanctuary.fountain_candidate(app.view, desired, .54)
	var searches := Sanctuary.fountain_searches
	Sanctuary.fountain_candidate(app.view, desired, .54)
	_check(Sanctuary.fountain_searches == searches, "unchanged local support reuses the validated full basin")
	var prior: Dictionary = app.view._tile_map["f:-9:-2"]
	var blocked: Dictionary = prior.duplicate(true)
	blocked.small = true
	app.view._tile_map["f:-9:-2"] = blocked
	_check(Sanctuary.fountain_candidate(app.view, desired, .54).is_empty(), "changed local small-support flag invalidates the old placement")
	_check(Sanctuary.fountain_searches == searches+1, "changed local support performs a real complete validation")
	app.view._tile_map["f:-9:-2"] = prior
	_check(Sanctuary.fountain_candidate(app.view, desired, .54) == before, "restored support retrieves the exact original centre")
	var support: Node3D = app.view._surfaces["f:-9:-2"]
	var transform := support.transform
	support.position.y += .04
	_check(Sanctuary.fountain_candidate(app.view, desired, .54).is_empty(), "changed physical support height invalidates the cached floor")
	support.transform = transform
	_check(Sanctuary.fountain_candidate(app.view, desired, .54) == before, "restored physical floor reuses its exact placement")
	var core: Node3D = app.view._props_nodes["mark:core"]
	for child: Node in core.get_children():
		if not child.has_meta("core_planter"): continue
		var center: Vector3 = child.get_meta("ground_footprint_center")
		searches = Sanctuary.fountain_searches
		child.set_meta("ground_footprint_center",center+Vector3(.025,0,0))
		Sanctuary.fountain_candidate(app.view, desired, .54)
		_check(Sanctuary.fountain_searches == searches+1, "changed actual core footprint invalidates the layout cache")
		child.set_meta("ground_footprint_center",center)
	_check((fountain.get_meta("original_sanctuary_ground_outline") as PackedVector2Array).size() == 128, "all original basin perimeter samples remain")
	var shape: ConvexPolygonShape3D = fountain.get_node("FountainBasinFoot/BasinVolume").shape
	_check(shape.points.size() == 256, "all original upper and lower convex vertices remain")

func _props_invalidation_contract() -> void:
	# Only the temporary hold dependency is removed. Other actual content
	# changes must still recreate their presentation and obstacle inventory.
	for change: String in ["latch","home","plate","item","collected","discovered","observations"]:
		var world: RefCounted = app.session.world.fork(app.session.world.snapshot())
		app.view.set_world(world)
		var revision: int = app.view.prop_obstacle_revision
		match change:
			"latch", "home": world.state.flags.append(change)
			"plate": world.state.actors.buddy = "f:3:5"
			"item": world.state.items.bell.tile = "f:-3:5"
			"collected": world.state.collected.append("spore-1")
			"discovered": world.state.discovered.append("f:-4:0")
			"observations": world.state.observations.append("rest")
		app.view.refresh_world(world)
		_check(app.view.prop_obstacle_revision == revision+1, change + " still invalidates the complete prop inventory")
	app.view.set_world(app.session.world)
	var revision: int = app.view.prop_obstacle_revision
	app.view._props_signature = 0
	app.view.refresh_world(app.session.world)
	_check(app.view.prop_obstacle_revision == revision+1, "an explicit forced prop rebuild remains effective")

func _run() -> void:
	_setup()
	var prior: Node = app.view
	app.remove_child(prior)
	prior.free()
	app.view = TimedStage.new()
	app.add_child(app.view)
	app.view.timings.clear()
	var started := Time.get_ticks_usec()
	app._enter_level("1-4")
	_check(app.native_movement != null, "application creates its actual native motor before profiling")
	if app.native_movement == null:
		quit(1)
		return
	measurements.append({"phase":"cold-enter", "commandMs":(Time.get_ticks_usec()-started)/1000.0, "inclusiveTimings":_timings()})
	var cold_searches := Sanctuary.fountain_searches
	var cold_shapes := Obstacles.basin_shape_builds
	var cold_shape: Shape3D = app.view._props.get_node("SanctuaryFountain/FountainBasinFoot/BasinVolume").shape
	await _measure_command("use:hold", true)
	await _measure_command("release:hold", false)
	await _measure_command("use:hold", true)
	await _measure_command("undo", false)
	_check(measurements.size() == 5, "all five performance phases completed")
	_check(Sanctuary.fountain_searches == cold_searches, "hold release and undo never repeat the remote fountain search")
	_check(Obstacles.basin_shape_builds == cold_shapes, "hold release and undo never rebuild an identical convex hull")
	_check(app.view._props.get_node("SanctuaryFountain/FountainBasinFoot/BasinVolume").shape == cold_shape, "rebuilt prop nodes retain the exact shared collision resource")
	_cache_contract()
	_props_invalidation_contract()
	print(JSON.stringify({"suite":"native-hold-performance", "passed":failures.is_empty(), "checks":checks, "failures":failures, "measurements":measurements, "cacheCounters":{"fountainSearches":Sanctuary.fountain_searches,"fountainHits":Sanctuary.fountain_cache_hits,"moleHits":Sanctuary.placement_cache_hits,"convexBuilds":Obstacles.basin_shape_builds,"convexHits":Obstacles.basin_shape_cache_hits}, "timingsInclusive":true, "gpuPixelsVerified":false, "scope":"Native CPU only, memory repository; real commands and continuous motor. Nested timings overlap."}))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
