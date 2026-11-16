extends SceneTree
## Exact-progress evidence for the root-board topology transition. Preparations
## use real rules, while both renderers consume an uncommitted session preview.

const World := preload("res://core/garden_world.gd")
const Session := preload("res://application/game_session.gd")
const Command := preload("res://contracts/game_command.gd")
const Snapshot := preload("res://contracts/snapshot_data.gd")
const View := preload("res://presentation/world/garden_view.gd")
const Landscape := preload("res://presentation/world/garden_landscape.gd")
const Terrain := preload("res://presentation/world/terrain_presentation.gd")
const ErrorLogger := preload("res://tests/visual_error_logger.gd")
const PROGRESS := [0.0, 0.000001, 0.25, 0.5, 0.75, 1.0]
const TIME := 1200.0
const RETAINED_STAIRS := "f:4:-1|f:4:0"

## Keep the production draw path and its real textures. Only unrelated objects
## and overlays are omitted so terrain endpoint/ROI pixel equality is meaningful.
class TerrainView:
	extends "res://presentation/world/garden_view.gd"
	var draw_trace: Array = []
	func _draw() -> void:
		draw_trace = []
		super._draw()
		# A cached mesh is not re-issued through _draw_object every frame. Audit
		# the exact object/opacity snapshot committed with the resident mesh,
		# rather than treating an empty recorder as a missing rendered stair.
		if world != null and str(world.level.id) == "1-1":
			draw_trace = []
			for object: Dictionary in _depth_static_snapshot:
				if object.kind == "floor":
					draw_trace.append({"kind": "floor", "id": str(object.tile.id), "alpha": float(object.tile.get("alpha", 1.0))})
				elif object.kind in ["steps", "ramp"]:
					var ids: Array = [str(object.pair[0].id), str(object.pair[1].id)]
					ids.sort()
					draw_trace.append({"kind": object.kind, "id": "|".join(ids), "alpha": float(object.get("alpha", 1.0))})
	func _draw_object(p: GardenPaint, object: Dictionary, painted: Array, time: float) -> void:
		if object.kind not in ["floor", "steps", "ramp"]:
			return
		var entry: Dictionary = {"kind": object.kind}
		if object.kind == "floor":
			entry["id"] = str(object.tile.id)
			entry["alpha"] = float(object.tile.get("alpha", 1.0))
		else:
			var ids: Array = [str(object.pair[0].id), str(object.pair[1].id)]
			ids.sort()
			entry["id"] = "|".join(ids)
			entry["alpha"] = float(object.get("alpha", 1.0))
		draw_trace.append(entry)
		super._draw_object(p, object, painted, time)
	func _draw_interaction_light(_p: GardenPaint, _time: float) -> void:
		pass
	func _draw_spatial_guides(_p: GardenPaint, _time: float) -> void:
		pass
	func _draw_growth_targets(_p: GardenPaint) -> void:
		pass
	func _draw_mole_dialogue() -> void:
		pass

var _logger := ErrorLogger.new()
var _checks := 0
var _failures: Array[String] = []
var _captures: Array = []
var _pixel_comparisons: Array = []
var _output := ""
var _size := Vector2i(1280, 720)
var _finished := false
var _viewport: SubViewport
var _scene: Node2D
var _terrain: Node2D

func _initialize() -> void:
	OS.add_logger(_logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size() == 2:
				_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	create_timer(120).timeout.connect(func() -> void:
		if not _finished:
			push_error("Topology transition sampling timed out")
			quit(1))
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _run() -> void:
	_check(_size.x > 0 and _size.y > 0, "capture dimensions are positive")
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_scene = View.new()
	_terrain = TerrainView.new()
	_viewport.add_child(_scene)
	_viewport.add_child(_terrain)
	for view: Node2D in [_scene, _terrain]:
		view.set_settings({"particles": false, "dynamicLight": false, "lowMotion": false})
		view.set_layout(Rect2())
		view.set_visual_time(TIME)
	await process_frame
	for direction: String in ["down", "right"]:
		await _case(direction, false)
		await _case(direction, true)
	_test_other_level_gate()
	_check(_scene.asset_errors().is_empty() and _terrain.asset_errors().is_empty(), "all source textures loaded")
	_viewport.queue_free()
	await process_frame
	_failures.append_array(_logger.captured_errors())
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		var report := FileAccess.open(_output.path_join("checks.json"), FileAccess.WRITE)
		_check(report != null, "capture report opens")
		if report != null:
			report.store_string(JSON.stringify({"passed": _failures.is_empty(), "checks": _checks,
				"failures": _failures, "size": [_size.x, _size.y], "display": DisplayServer.get_name(),
				"engine": Engine.get_version_info().string, "captures": _captures,
				"pixelComparisons": _pixel_comparisons, "sourceHashes": _source_hashes(),
				"scope": "Four legal grow/retract actions; frozen time. Full scene evidence plus terrain-only actual production draws. Pixel assertions require a GPU run; headless verifies rule/camera/geometry/opacity contracts. Undo is immediate; no redo exists, so legal action replay is tested.",
				"terrainIsolation": "Production floor/steps rendering and background, with actor/prop/mark/runoff/guide overlays excluded only in the test subclass."}, "\t") + "\n")
	_finished = true
	if _failures.is_empty():
		print("PASS topology transitions: %d checks / %d samples (%s, %dx%d)" % [_checks, _captures.size(), DisplayServer.get_name(), _size.x, _size.y])
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)

func _case(direction: String, retract: bool) -> void:
	var name := direction + ("-retract" if retract else "-grow")
	var session := Session.new("1-1")
	if retract:
		_check(session.apply(Command.interact("grow:root:" + direction)).accepted, name + " legal preparation")
	var command := Command.interact("retract:root" if retract else "grow:root:" + direction)
	var before: Dictionary = session.world.snapshot()
	var board_before: Array = session.world.tiles()
	var revision_before: int = session.revision
	var prepared = session.prepare(command)
	_check(prepared.accepted and prepared.changed, name + " has a real legal uncommitted preview")
	var after: Dictionary = prepared.after.duplicate(true)
	var fork: RefCounted = session.world.fork(after)
	var board_after: Array = fork.tiles()
	var walls_before := _walls(session.world.level, board_before)
	_check(walls_before == _walls(session.world.level, board_after), name + " fixed masonry depths and texture UV descriptors remain stable across topology endpoints")
	var baseline: Dictionary = await _sample(session.world, name, "before", -1.0)
	var expected_camera: Dictionary = baseline.camera
	var previous_opacity := 1.0 if retract else 0.0
	for progress: float in PROGRESS:
		for view: Node2D in [_scene, _terrain]:
			view.set_motion(before, after, progress, command.value)
		var sample := await _sample(session.world, name, _progress_name(progress), progress, false)
		_check(sample.camera == expected_camera, name + " camera cannot move at p=" + str(progress))
		_check(session.world.snapshot() == before and session.world.tiles() == board_before and session.revision == revision_before, name + " preview cannot mutate the real session")
		_check(fork.snapshot() == after and fork.tiles() == board_after, name + " preview cannot mutate its endpoint fork")
		_check(prepared.before == before and prepared.after == after, name + " preview inputs remain detached")
		var painted := _painted(board_before, board_after, progress)
		_check(walls_before == _walls(session.world.level, painted), name + " every authored wall depth and UV descriptor remains fixed during preview")
		var steps: Array = _terrain.call("_step_entries", painted)
		var opacity := _root_opacity(painted)
		_check(absf(opacity - (1.0 - _ease(progress) if retract else _ease(progress))) < 0.000001, name + " changed road follows its eased opacity")
		_check(opacity <= previous_opacity if retract else opacity >= previous_opacity, name + " changed road opacity is monotonic")
		previous_opacity = opacity
		_validate_steps(name, direction, retract, steps, progress)
		if not baseline.image.is_empty() and not sample.image.is_empty():
			_compare_roi(baseline.image, sample.image, _wall_roi(_terrain), name + "/" + _progress_name(progress) + "/fixed-wall")
			_compare_roi(baseline.image, sample.image, _stairs_roi(_terrain), name + "/" + _progress_name(progress) + "/unrelated-right-stairs")
		if progress == 0.0:
			_compare_images(baseline.image, sample.image, name + "/before-to-p0")
		if progress == 0.000001:
			_compare_images(baseline.image, sample.image, name + "/before-to-epsilon")
		if progress == 1.0:
			baseline["endpoint_image"] = sample.image
	_check(session.commit(prepared).accepted and session.revision == revision_before + 1 and session.world.snapshot() == after, name + " real commit occurs once and matches the legal preview")
	for view: Node2D in [_scene, _terrain]:
		view.clear_motion(false)
	var committed := await _sample(session.world, name, "commit", -1.0)
	_check(committed.camera == expected_camera, name + " commit retains camera scale and origin")
	_compare_images(baseline.get("endpoint_image", PackedByteArray()), committed.image, name + "/p1-to-commit")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.world.snapshot()))
	var reloaded := World.new("1-1", saved)
	_check(Snapshot.equivalent(reloaded.snapshot(), after) and not reloaded.can_undo(), name + " JSON reload restores the exact static endpoint without fabricating history")
	var restored := await _sample(reloaded, name, "reload", -1.0)
	_compare_images(committed.image, restored.image, name + "/commit-to-reload")
	var undone = session.apply(Command.undo_action())
	_check(undone.accepted and session.world.snapshot() == before, name + " real undo restores the prior topology")
	for view: Node2D in [_scene, _terrain]:
		view.clear_motion(false)
	var undo_frame := await _sample(session.world, name, "undo", -1.0)
	_compare_images(baseline.image, undo_frame.image, name + "/before-to-undo")
	_check(_terrain._motion_from.is_empty() and _terrain._motion_to.is_empty(), name + " undo leaves no stale visual transition")
	var replay = session.apply(command)
	_check(replay.accepted and session.world.snapshot() == after, name + " the same legal action can be replayed after undo; no redo capability is invented")

func _sample(world: RefCounted, case_name: String, phase: String, progress: float, reset := true) -> Dictionary:
	if reset:
		for view: Node2D in [_scene, _terrain]:
			view.clear_motion(false)
			view.set_world(world)
	var record := {"case": case_name, "phase": phase, "progress": progress, "files": {}, "snapshot": world.snapshot()}
	var pixels := PackedByteArray()
	for isolation: bool in [false, true]:
		_scene.visible = not isolation
		_terrain.visible = isolation
		var active: Node2D = _terrain if isolation else _scene
		active.set_visual_time(TIME)
		active._camera(active._tiles(), active._player_point(active._state(), active._tiles()))
		await process_frame
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := _viewport.get_texture().get_image()
			_check(not image.is_empty(), case_name + "/" + phase + " has actual rendered pixels")
			image.convert(Image.FORMAT_RGBA8)
			if isolation:
				pixels = image.get_data()
			if not _output.is_empty():
				var file := case_name + "/" + phase + ("-terrain.png" if isolation else "-scene.png")
				var destination := _output.path_join(file)
				DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
				_check(image.save_png(destination) == OK, "save " + file)
				record.files["terrain" if isolation else "scene"] = file
		if isolation:
			record["camera"] = {"scale": active.scale_factor, "origin": [active.origin.x, active.origin.y]}
			record["drawTrace"] = _terrain.draw_trace.duplicate(true)
	_captures.append(record)
	return {"camera": record.camera, "image": pixels}

func _painted(before: Array, after: Array, progress: float) -> Array:
	var result: Array = []
	for tile: Dictionary in before:
		var next := _tile_by_id(after, str(tile.id))
		var painted := tile.duplicate(true)
		painted["alpha"] = 1.0 if not next.is_empty() else 1.0 - _ease(progress)
		result.append(painted)
	for tile: Dictionary in after:
		if _tile_by_id(before, str(tile.id)).is_empty():
			var painted := tile.duplicate(true)
			painted["alpha"] = _ease(progress)
			result.append(painted)
	return result

func _tile_by_id(board: Array, id: String) -> Dictionary:
	for tile: Dictionary in board:
		if str(tile.id) == id:
			return tile
	return {}

func _walls(level: Dictionary, board: Array) -> Array:
	var result: Array = []
	for tile: Dictionary in level.tiles:
		for side: String in ["left", "right"]:
			var adjacent := Landscape.tile_at(board, float(tile.x) + (1.0 if side == "right" else 0.0), float(tile.z) + (1.0 if side == "left" else 0.0), str(tile.id))
			var depth := Landscape.face_depth(tile, adjacent, 112.0, level)
			result.append({"id": tile.id, "side": side, "depth": depth,
				"u": (float(tile.x) if side == "left" else -float(tile.z)) * 70.0,
				"v": -float(tile.h) * 48.0, "texture": "masonry-valley"})
	return result

func _pair_key(pair: Array) -> String:
	var ids: Array = [str(pair[0].id), str(pair[1].id)]
	ids.sort()
	return "|".join(ids)

func _root_opacity(painted: Array) -> float:
	for tile: Dictionary in painted:
		if str(tile.id).begins_with("g:root:"):
			return float(tile.alpha)
	return -1.0

func _validate_steps(name: String, direction: String, retract: bool, steps: Array, progress: float) -> void:
	var retained := false
	var changed := false
	for entry: Dictionary in steps:
		var key := _pair_key(entry.pair)
		_check(key not in ["f:2:-1|f:2:0", "f:3:-1|f:3:0"], name + " the two explicitly removed rear stair visuals stay absent")
		if key == RETAINED_STAIRS:
			retained = true
			_check(is_equal_approx(float(entry.get("alpha", 1.0)), 1.0), name + " unrelated right stairs remain opaque")
		if "g:root:" in key:
			changed = true
			var expected := 1.0 - _ease(progress) if retract else _ease(progress)
			_check(absf(float(entry.get("alpha", 1.0)) - expected) < 0.000001, name + " added/removed connection stairs fade together with their road")
	_check(retained, name + " unrelated right stairs remain present during a sowing action")
	_check(changed, name + " the changed root landing connection is present in the transition union for " + direction)
	if DisplayServer.get_name() != "headless":
		var drawn: Dictionary = {}
		for entry: Dictionary in _terrain.draw_trace:
			if entry.kind == "steps":
				drawn[entry.id] = entry.alpha
		_check(drawn.size() == steps.size(), name + " actual GPU draw queue contains every intended stair connection")
		for entry: Dictionary in steps:
			var key := _pair_key(entry.pair)
			_check(drawn.has(key) and absf(float(drawn.get(key, -1.0)) - float(entry.get("alpha", 1.0))) < 0.000001, name + " actual GPU draw receives the intended stair opacity for " + key)

func _wall_roi(view: Node2D) -> Rect2i:
	var point: Vector2 = view.project({"x": 4, "z": 0, "h": 1})
	var region := Rect2(point + Vector2(12, 45) * view.scale_factor, Vector2(11, 26) * view.scale_factor)
	return Rect2i(region).intersection(Rect2i(Vector2i.ZERO, _size))

func _stairs_roi(view: Node2D) -> Rect2i:
	var corners: Array[Vector2] = []
	for fraction: float in [0.1, 0.9]:
		for side: float in [-0.29, 0.29]:
			corners.append(view.project({"x": 4 + side, "z": -fraction, "h": lerpf(1.0, 2.0, fraction)}))
	var region := Rect2(corners[0], Vector2.ZERO)
	for point: Vector2 in corners:
		region = region.expand(point)
	region = region.grow(2.0 * view.scale_factor)
	return Rect2i(region).intersection(Rect2i(Vector2i.ZERO, _size))

func _test_other_level_gate() -> void:
	_check(Terrain.enabled(World.new("1-1").level), "the new terrain policy is enabled for 1-1")
	for id: String in ["1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4"]:
		var world := World.new(id)
		_check(not Terrain.enabled(world.level), id + " cannot enable the new topology policy")
		var tile: Dictionary = world.level.tiles[0]
		var base := 112.0 if world.level.chapter == "valley" else 42.0 if world.level.chapter == "pond" else 60.0
		for neighbor: Dictionary in [{}, {"id": "g:test:0:0", "x": tile.x, "z": tile.z, "h": tile.h, "kind": "root"}]:
			var legacy_depth := maxf(0.0, (float(tile.h) - float(neighbor.h)) * 48.0) if not neighbor.is_empty() else maxf(12.0, base + float(tile.h) * 48.0)
			_check(is_equal_approx(Landscape.face_depth(tile, neighbor, base, world.level), legacy_depth), id + " keeps the original structural wall-depth contract")
	var root_world := World.new("1-2")
	var before: Dictionary = root_world.snapshot()
	var probe: RefCounted = root_world.fork(before)
	_check(probe.act("grow:root:up").ok, "1-2 retains a real growth action for the old motion-gate check")
	_terrain.clear_motion(false)
	_terrain.set_world(root_world)
	_terrain.set_motion(before, probe.snapshot(), 0.5, "grow:root:up")
	_check(_terrain.call("_step_entries", _painted(root_world.tiles(), probe.tiles(), 0.5)).is_empty(), "1-2 keeps its original nonmovement stair drawing gate")
	_terrain.clear_motion(false)

func _compare_images(first: PackedByteArray, second: PackedByteArray, label: String) -> void:
	if first.is_empty() or second.is_empty():
		return
	_compare_roi(first, second, Rect2i(Vector2i.ZERO, _size), label)

func _compare_roi(first: PackedByteArray, second: PackedByteArray, region: Rect2i, label: String) -> void:
	if first.is_empty() or second.is_empty():
		return
	_check(region.has_area(), label + " compares a nonempty visible region")
	var changed := 0
	var max_delta := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var at := (y * _size.x + x) * 4
			var pixel_changed := false
			for channel in 4:
				var difference := absi(int(first[at + channel]) - int(second[at + channel]))
				max_delta = maxi(max_delta, difference)
				pixel_changed = pixel_changed or difference > 0
			if pixel_changed:
				changed += 1
	_check(changed == 0 and max_delta == 0, label + " actual terrain pixels remain exactly equal (changed=%d, max=%d)" % [changed, max_delta])
	_pixel_comparisons.append({"label": label, "rect": [region.position.x, region.position.y, region.size.x, region.size.y], "changedPixels": changed, "maxChannelDelta": max_delta})

func _progress_name(progress: float) -> String:
	return "epsilon" if progress > 0.0 and progress < 0.001 else "p%03d" % roundi(progress * 100)

func _ease(progress: float) -> float:
	return progress * progress * (3.0 - 2.0 * progress)

func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for file: String in ["res://core/garden_world.gd", "res://application/game_session.gd", "res://presentation/world/garden_view.gd", "res://presentation/world/garden_landscape.gd", "res://presentation/world/terrain_presentation.gd", "res://tests/visual_topology_transition_test.gd"]:
		result[file] = FileAccess.get_sha256(file)
	return result
