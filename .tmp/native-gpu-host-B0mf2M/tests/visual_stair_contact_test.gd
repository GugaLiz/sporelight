extends SceneTree
## This replaces the rejected 8a7186fd pilot test. Expectations below are the
## declared route/geometry budgets, not values imported from the implementation.
## A passing headless run proves path/contact contracts, never visual quality.

const Session := preload("res://application/game_session.gd")
const Command := preload("res://contracts/game_command.gd")
const World := preload("res://core/garden_world.gd")
const Snapshot := preload("res://contracts/snapshot_data.gd")
const View := preload("res://presentation/world/garden_view.gd")
const Surface := preload("res://presentation/world/stair_surface.gd")
const Iso := preload("res://presentation/world/iso_projection.gd")
const ErrorLogger := preload("res://tests/visual_error_logger.gd")
const LOOP := ["f:0:0", "g:root:1:0", "f:2:0", "f:2:-1", "f:3:-1", "f:4:-1", "f:4:0", "f:3:0", "f:2:0", "g:root:1:0", "f:0:0"]
const WALK_SECONDS := 0.205
const MAX_CLEARANCE := 6.0 / 48.0

var _checks := 0
var _failures: Array[String] = []
var _captures: Array = []
var _samples: Array = []
var _regressions: Array = []
var _plant_samples: Array = []
var _heading_samples: Array = []
var _common_times: Dictionary = {}
var _logger := ErrorLogger.new()
var _output := ""
var _size := Vector2i(1280, 720)
var _viewport: SubViewport
var _view: Node2D
var _probe_view: Node2D
var _finished := false

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
			push_error("Complete depth-route verification timed out")
			quit(1))
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 60:
		_failures.append(label)

func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_view = View.new()
	_viewport.add_child(_view)
	_probe_view = View.new()
	_probe_view.visible = false
	_viewport.add_child(_probe_view)
	_view.set_settings({"particles": false, "dynamicLight": true, "lowMotion": false})
	_view.set_layout(Rect2())
	_probe_view.set_settings({"particles": false, "dynamicLight": true, "lowMotion": false})
	_probe_view.set_layout(Rect2())
	await process_frame
	_geometry_budget()
	_heading_contract()
	for fps in [30, 60]:
		await _complete_route(fps)
	await _other_actions()
	await _soft_plant_boundaries()
	_puzzle_contract()
	_other_level_gate()
	_check(_view.asset_errors().is_empty(), "the original picture assets load")
	_viewport.queue_free()
	await process_frame
	_failures.append_array(_logger.captured_errors())
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		var report := FileAccess.open(_output.path_join("checks.json"), FileAccess.WRITE)
		_check(report != null, "route report can be written")
		if report != null:
			report.store_string(JSON.stringify({"passed": _failures.is_empty(), "checks": _checks,
				"failures": _failures, "size": [_size.x, _size.y], "display": DisplayServer.get_name(),
				"captures": _captures, "routeSamples": _samples, "regressions": _regressions,
				"plantOpacitySamples": _plant_samples, "headingSamples": _heading_samples, "sourceHashes": _source_hashes(),
				"budgets": {"rootVisualRun": [0.1, 0.9], "rootRail": [0.0, 0.8], "treadCount": 8,
					"rearRampRail": [0.2, 0.8], "rightRearVisualRun": [0.275, 0.875], "maxClearanceDesignPixels": 6,
					"heroWorldOffset": [-0.02, -0.18], "buddyWorldOffset": [-0.18, 0.18], "walkSeconds": WALK_SECONDS},
				"scope": "Complete high-island loop and reversed loop through legal rule actions at 30/60Hz exact elapsed samples. Original camera, xz trajectory, speed, heading, support and commit/reload continuity are asserted. GPU output records a small set of normal-scene route frames with a progressing animation clock. No draw-order test is used as a substitute for native depth testing.",
				"visualReviewRequired": true,
				"limitations": ["Numeric success does not certify natural appearance, actual sprite alpha pixels or correct native GPU occlusion. Root performs native-stage projection/depth and normal-scene review separately.", "These deterministic elapsed samples do not simulate OS input delivery or controller scheduling; real keyboard release/turning is a separate Web test.", "Run the unchanged visual_topology_transition_test independently; this suite never weakens its pixel-equality contract."]}, "\t") + "\n")
	_finished = true
	if _failures.is_empty():
		print("PASS complete stair/depth route: %d checks / %d time samples / %d selected normal frames (%s)" % [_checks, _samples.size(), _captures.size(), DisplayServer.get_name()])
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)

func _grown(direction := "right") -> RefCounted:
	var session := Session.new("1-1")
	_check(session.apply(Command.interact("grow:root:" + direction)).accepted, "preparation grows only a real chosen root")
	return session

func _definition(low: Dictionary, high: Dictionary) -> Dictionary:
	var ids := [str(low.id), str(high.id)]
	if "g:root:1:0" in ids and "f:2:0" in ids:
		return {"style": "steps", "visual_start": 0.1, "visual_end": 0.9, "rail_start": 0.0, "rail_end": 0.8}
	if str(low.id) in ["f:2:0", "f:3:0"] and is_equal_approx(float(low.x), float(high.x)):
		return {"style": "ramp", "visual_start": 0.2, "visual_end": 0.8, "rail_start": 0.2, "rail_end": 0.8}
	return {"style": "steps", "visual_start": 0.275, "visual_end": 0.875, "rail_start": 0.2, "rail_end": 0.8}

func _geometry_budget() -> void:
	var session: RefCounted = _grown()
	for endpoints: Array in [["g:root:1:0", "f:2:0"], ["f:2:0", "f:2:-1"], ["f:3:0", "f:3:-1"], ["f:4:0", "f:4:-1"]]:
		var low: Dictionary = session.world.point_for(endpoints[0])
		var high: Dictionary = session.world.point_for(endpoints[1])
		var expected := _definition(low, high)
		var surface: Dictionary = Surface.connection(session.world.level, [low, high])
		_check(not surface.is_empty(), "each actual height edge has a connection: " + str(endpoints))
		if surface.is_empty():
			continue
		_check(surface == Surface.connection(session.world.level, [high, low]), "both directions normalize to the same physical connection")
		_check(str(surface.style) == expected.style, "the two removed stair visuals stay ramps; other connections stay stairs")
		_check(absf(float(surface.run_start) - float(expected.visual_start)) < 0.000001 and absf(float(surface.run_end) - float(expected.visual_end)) < 0.000001, "visible run follows the independently declared full-length art budget")
		_check(absf(float(surface.rail_start) - float(expected.rail_start)) < 0.000001 and absf(float(surface.rail_end) - float(expected.rail_end)) < 0.000001, "contact rail follows the declared budget")
		if expected.style == "steps":
			_check(int(surface.treads) == 8, "there are eight six-design-pixel risers, not the rejected compressed four")
			var direction := Vector2(float(high.x) - float(low.x), float(high.z) - float(low.z))
			for index in range(8):
				var corners: Array = Surface.corners(surface, index)
				_check(corners.size() == 4, "each rendered tread exposes its four real corners")
				if corners.size() != 4:
					continue
				for vertex in range(4):
					var u := float(expected.visual_start) + (index + (1 if vertex >= 2 else 0)) * (float(expected.visual_end) - float(expected.visual_start)) / 8.0
					var v := -0.29 if vertex in [0, 3] else 0.29
					var expected_xz := Vector2(low.x, low.z) + direction * u + Vector2(-direction.y, direction.x) * v
					_check(Vector2(corners[vertex].x, corners[vertex].z).distance_to(expected_xz) < 0.000001 and absf(float(corners[vertex].h) - float(low.h) - (index + 1.0) / 8.0) < 0.000001, "actual tread corners preserve declared run/width/rise independent of contact()")
		for sample in range(101):
			var u := sample / 100.0
			var actual: Dictionary = Surface.contact(surface, u)
			var expected_h := _rail_height(low, high, expected, u)
			_check(absf(float(actual.h) - expected_h) < 0.000001, "rail values match the independent continuous support equation")
			var ground := _support_height(low, high, expected, u)
			_check(expected_h >= ground - 0.000001 and expected_h - ground <= MAX_CLEARANCE + 0.000001, "real stair clearance stays within one declared six-pixel riser")

func _complete_route(fps: int) -> void:
	var session: RefCounted = _grown()
	_view.clear_motion(false)
	_view.set_world(session.world)
	var timeline := 1200.0
	var path: Array = LOOP.duplicate()
	var reverse: Array = LOOP.duplicate()
	reverse.reverse()
	path.append_array(reverse.slice(1))
	for segment in range(1, path.size()):
		var target := str(path[segment])
		var prepared = session.prepare(Command.move_to(target))
		_check(prepared.accepted and prepared.changed, "complete loop follows a real one-cell edge: " + target)
		var before: Dictionary = prepared.before.duplicate(true)
		var after: Dictionary = prepared.after.duplicate(true)
		var source_tile: Dictionary = session.world.point_for(str(before.actors.luvie))
		var target_tile: Dictionary = session.world.point_for(target)
		_view.set_visual_time(timeline)
		_probe_view.clear_motion(false)
		_probe_view.set_world(session.world)
		_probe_view.set_visual_time(timeline)
		var static_before := _feet(_probe_view)
		var previous: Dictionary = {}
		var elapsed := 0.0
		var frames := int(ceil(WALK_SECONDS * fps))
		var endpoint: Dictionary = {}
		for frame in range(frames + 1):
			elapsed = minf(frame / float(fps), WALK_SECONDS)
			var progress := elapsed / WALK_SECONDS
			_view.set_visual_time(timeline + elapsed * 1000.0)
			_view.set_motion(before, after, progress, "move")
			var sample := _validate_frame(source_tile, target_tile, progress, "move", "%dHz/edge%d/frame%d" % [fps, segment, frame])
			_check(absf(float(sample.walkStarted) - 1200.0) < 0.000001, "the complete continuous route never restarts its gait clock at a grid boundary")
			sample.merge({"fps": fps, "segment": segment, "elapsed": elapsed, "timelineMs": timeline + elapsed * 1000.0, "from": source_tile.id, "to": target_tile.id}, true)
			_check(session.world.snapshot() == before and prepared.before == before and prepared.after == after, "route preview cannot change real rule state or detached inputs")
			if frame == 0:
				_same_feet(static_before, sample, "static-to-p0 on every edge of the island")
			if not previous.is_empty():
				var delta_t := elapsed - float(previous.elapsed)
				for actor: String in ["luvie", "buddy"]:
					var a: Dictionary = previous.actors[actor].ground
					var b: Dictionary = sample.actors[actor].ground
					var travelled := Vector2(float(b.x) - float(a.x), float(b.z) - float(a.z))
					var desired := Vector2(float(target_tile.x) - float(source_tile.x), float(target_tile.z) - float(source_tile.z)) * delta_t / WALK_SECONDS
					_check(travelled.distance_to(desired) < 0.000001, "a directional command has zero lateral drift and constant xz speed, including after disembarking")
			previous = sample
			endpoint = sample
			_samples.append(sample)
			var key := str(segment) + "/" + str(roundi(elapsed * 1000000.0))
			if fps == 30:
				_common_times[key] = sample
			elif _common_times.has(key):
				_same_feet(_common_times[key], sample, "30/60Hz agree at the same actual elapsed time")
				_check(_common_times[key].facing == sample.facing, "30/60Hz keep the same heading at common elapsed times")
			if fps == 60 and (frame == 6 or frame == frames):
				await _capture("route/edge%02d-%s" % [segment, "middle" if frame == 6 else "arrival"], sample)
		_check(session.commit(prepared).accepted and Snapshot.equivalent(session.world.snapshot(), after), "each loop edge commits once to its intended tile")
		# Keep the visible route's motion linked across segments. Exercise actual
		# clear/reload in the hidden probe so those checks do not reset its gait.
		_probe_view.set_world(session.world)
		_probe_view.set_visual_time(timeline + WALK_SECONDS * 1000.0)
		_probe_view.set_motion(before, after, 1.0, "move")
		_same_feet(endpoint, _feet(_probe_view), "both route and clear probe use the same p1 stance")
		_probe_view.clear_motion(false)
		var committed := _feet(_probe_view)
		_same_feet(endpoint, committed, "p1-to-clear on every edge of the island")
		if str(source_tile.id) == "f:2:0" and target == "f:3:0":
			for actor: String in ["luvie", "buddy"]:
				var difference := absf(float(endpoint.actors[actor].depth) - float(committed.actors[actor].depth))
				_check(difference < 0.000001, "old f2-to-f3 regression: p1 and clear keep the same actual world anchor and depth plane")
				_regressions.append({"name": "f2-to-f3-p1-clear", "fps": fps, "actor": actor, "p1": endpoint.actors[actor], "clear": committed.actors[actor], "depthDifference": difference})
		var saved: Dictionary = JSON.parse_string(JSON.stringify(after))
		var restored := World.new("1-1", saved)
		_check(Snapshot.equivalent(restored.snapshot(), after) and not restored.can_undo(), "every landing survives JSON reload without invented history")
		_probe_view.set_world(restored)
		_same_feet(endpoint, _feet(_probe_view), "all island landings keep their actual feet after reload")
		timeline += WALK_SECONDS * 1000.0
	_check(str(session.world.state.actors.luvie) == "f:0:0" and str(session.world.state.actors.buddy) == "f:0:0", "full loop and reversed loop return both travellers to the root island")

func _validate_frame(source: Dictionary, target: Dictionary, progress: float, kind: String, label: String) -> Dictionary:
	var factor := progress if kind in ["move", "roll"] else _ease(progress)
	var logical := Iso.interpolate(source, target, factor)
	_view._camera(_view._tiles(), logical)
	var expected_origin: Vector2 = _view.origin
	var expected_scale: float = _view.scale_factor
	var sample := _feet()
	sample["facing"] = str(_view.character_presentation().get("facing", ""))
	sample["walkStarted"] = float(_view.character_presentation().get("walk_started", -1.0))
	sample["poseKey"] = str(_view.character_presentation().get("key", ""))
	var expected_facing := _xz_heading(source, target)
	_check(sample.facing == expected_facing, label + " heading matches the requested logical direction")
	_check(absf(_view.scale_factor - expected_scale) < 0.000001 and _view.origin.distance_to(expected_origin) < 0.002, label + " the camera remains on the original logical path")
	for actor: String in ["luvie", "buddy"]:
		var foot: Dictionary = sample.actors[actor].ground
		var desired_xz := Vector2(float(logical.x) + (-0.02 if actor == "luvie" else -0.18), float(logical.z) + (-0.18 if actor == "luvie" else 0.18))
		_check(Vector2(foot.x, foot.z).distance_to(desired_xz) < 0.000001, label + "/" + actor + " uses one constant island-wide stance, including flat ground")
		var expected_h := float(logical.h)
		if not is_equal_approx(float(source.h), float(target.h)):
			var low: Dictionary = source if float(source.h) < float(target.h) else target
			var high: Dictionary = target if float(source.h) < float(target.h) else source
			var direction := Vector2(float(high.x) - float(low.x), float(high.z) - float(low.z))
			var u := (Vector2(foot.x, foot.z) - Vector2(low.x, low.z)).dot(direction)
			var declared := _definition(low, high)
			expected_h = _rail_height(low, high, declared, u)
			var support_h := _support_height(low, high, declared, u)
			_check(float(foot.h) >= support_h - 0.000001 and float(foot.h) - support_h <= MAX_CLEARANCE + 0.000001, label + "/" + actor + " actual foot stays above real support with at most six pixels clearance")
		_check(absf(float(foot.h) - expected_h) < 0.000001, label + "/" + actor + " actual height follows the independently declared rail or flat landing")
		var ground_screen: Vector2 = _view.project(foot)
		_check(ground_screen.distance_to(Vector2(sample.actors[actor].screen[0], sample.actors[actor].screen[1])) < 0.002, label + "/" + actor + " ground foot projection adds no invisible world/pixel displacement")
	return sample

## First-garden heading is an authored four-way art choice. This oracle uses
## only the requested horizontal axis; it does not call the product selector
## or project elevation into a screen vector.
func _xz_heading(source: Dictionary, target: Dictionary) -> String:
	var dx := float(target.x) - float(source.x)
	var dz := float(target.z) - float(source.z)
	if absf(dx) > absf(dz):
		return "right" if dx > 0.0 else "left"
	return "front" if dz > 0.0 else "back"

func _legacy_heading(source: Dictionary, target: Dictionary) -> String:
	# Frozen pre-change screen-direction rule for the other eleven gardens.
	var dx := float(target.x) - float(source.x)
	var dz := float(target.z) - float(source.z)
	var dh := float(target.h) - float(source.h)
	var screen := Vector2((dx - dz) * 35.0, (dx + dz) * 17.5 - dh * 48.0)
	if absf(screen.y) > absf(screen.x) * 0.85:
		return "back" if screen.y < 0.0 else "front"
	return "right" if screen.x > 0.0 else "left"

func _heading_contract() -> void:
	var by_direction: Dictionary = {}
	var routes := {
		"right": ["f:-1:0", "f:0:0", "g:root:1:0", "f:2:0", "f:3:0", "f:2:0", "g:root:1:0", "f:0:0"],
		"down": ["f:0:-1", "f:0:0", "g:root:0:1", "f:0:2", "g:root:0:1", "f:0:0"]
	}
	for branch: String in routes:
		var session: RefCounted = _grown(branch)
		_probe_view.clear_motion(false)
		_probe_view.set_world(session.world)
		for destination: String in routes[branch]:
			var prepared = session.prepare(Command.move_to(destination))
			_check(prepared.accepted and prepared.changed, "heading comparison uses a legal route edge")
			if not prepared.accepted or not prepared.changed:
				continue
			var source: Dictionary = session.world.point_for(str(prepared.before.actors.luvie))
			var target: Dictionary = session.world.point_for(destination)
			var expected := _xz_heading(source, target)
			_probe_view.set_visual_time(21000.0)
			_probe_view.set_motion(prepared.before, prepared.after, 0.5, "move")
			var actual := str(_probe_view.character_presentation().get("facing", ""))
			_check(actual == expected, "1-1 horizontal direction stays " + expected + " at height difference " + str(float(target.h) - float(source.h)))
			if not by_direction.has(expected):
				by_direction[expected] = {}
			by_direction[expected][roundi(float(target.h) - float(source.h))] = actual
			_heading_samples.append({"level": "1-1", "source": source, "target": target, "expected": expected, "actual": actual, "policy": "horizontal-four-way"})
			_check(session.commit(prepared).accepted, "heading comparison commits the original rule move")
			_probe_view.clear_motion(false)
	for direction: String in ["left", "right", "front", "back"]:
		_check(by_direction.has(direction) and by_direction[direction].size() >= 2 and by_direction[direction].has(0), "same " + direction + " heading is exercised on both flat and sloped real edges")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var levels_seen: Dictionary = {}
	var legacy_disagreements := 0
	for entry: Dictionary in fixture.cases:
		var level_id := str(entry.levelId)
		if level_id == "1-1" or str(entry.name) != "authored/" + level_id:
			continue
		var previous: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			var after: Dictionary = step.snapshot
			if str(step.command.get("kind", "")) == "move" and step.result.get("ok", false) and str(previous.actors.luvie) != str(after.actors.luvie):
				var model := World.new(level_id, previous)
				var future := World.new(level_id, after)
				var source: Dictionary = model.point_for(str(previous.actors.luvie))
				var target: Dictionary = future.point_for(str(after.actors.luvie))
				_probe_view.clear_motion(false)
				_probe_view.set_world(model)
				_probe_view.set_motion(previous, after, 0.5, "move")
				var expected := _legacy_heading(source, target)
				var actual := str(_probe_view.character_presentation().get("facing", ""))
				_check(actual == expected, level_id + " retains its original projected direction policy")
				levels_seen[level_id] = true
				if expected != _xz_heading(source, target):
					legacy_disagreements += 1
				_heading_samples.append({"level": level_id, "source": source, "target": target, "expected": expected, "actual": actual, "policy": "unchanged-projected"})
			previous = after
	_check(levels_seen.size() == 11, "all other eleven gardens exercise their original heading branch")
	_check(legacy_disagreements > 0, "the other-garden checks include edges that would fail under the new first-garden heading policy")

func _feet(view: Node2D = null) -> Dictionary:
	var active: Node2D = _view if view == null else view
	var board: Array = active._tiles()
	active._camera(board, active._player_point(active._state(), board))
	var record: Dictionary = {"actors": {}, "camera": {"scale": active.scale_factor, "origin": [active.origin.x, active.origin.y]}}
	for mark: Dictionary in active.world.level.marks:
		if mark.kind == "core":
			var tile: Dictionary = active.world.point_for(str(mark.tile))
			record["coreOpacity"] = active.call("_soft_occluder_opacity", tile)
			break
	for actor: String in ["luvie", "buddy"]:
		var foot: Dictionary = active.actor_ground_point(actor)
		var screen: Vector2 = active.actor_screen_footpoint(actor, false)
		record.actors[actor] = {"ground": foot, "depth": float(foot.x) + float(foot.z), "screen": [screen.x, screen.y], "contact": active.actor_stair_contact(actor)}
	return record

func _same_feet(first: Dictionary, second: Dictionary, label: String) -> void:
	if first.has("coreOpacity") and second.has("coreOpacity"):
		_check(absf(float(first.coreOpacity) - float(second.coreOpacity)) < 0.000001, label + " the same actual foot position keeps the same soft-plant opacity")
	for actor: String in ["luvie", "buddy"]:
		var a: Dictionary = first.actors[actor].ground
		var b: Dictionary = second.actors[actor].ground
		_check(Vector3(a.x, a.h, a.z).distance_to(Vector3(b.x, b.h, b.z)) < 0.000001, label + "/" + actor + " world anchor is continuous")
		_check(Vector2(first.actors[actor].screen[0], first.actors[actor].screen[1]).distance_to(Vector2(second.actors[actor].screen[0], second.actors[actor].screen[1])) < 0.002, label + "/" + actor + " screen anchor is continuous")

func _other_actions() -> void:
	for direction: bool in [true, false]:
		for kind: String in ["roll", "hop"]:
			var session: RefCounted = _grown()
			var source := "g:root:1:0" if direction else "f:2:0"
			var target := "f:2:0" if direction else "g:root:1:0"
			for tile: String in session.world.path_to(source):
				_check(session.apply(Command.move_to(tile)).accepted, "additional action starts from a real reached tile")
			_view.clear_motion(false)
			_view.set_world(session.world)
			var prepared = session.prepare(Command.move_to(target))
			_check(prepared.accepted, "roll/hop cannot invent an illegal crossing")
			var first := _feet()
			var last: Dictionary = {}
			for progress: float in [0.0, 0.000001, 0.25, 0.5, 0.75, 0.999999, 1.0]:
				_view.set_visual_time(9000.0 + progress * (155.0 if kind == "roll" else 620.0))
				_view.set_motion(prepared.before, prepared.after, progress, kind)
				last = _validate_frame(session.world.point_for(source), session.world.point_for(target), progress, kind, kind + "/" + str(direction))
				if progress == 0.0:
					_same_feet(first, last, "roll/hop starts at the same static stance")
				if progress == 0.5:
					await _capture("actions/%s-%s-middle" % [kind, "up" if direction else "down"], last)
			_check(session.commit(prepared).accepted, "roll/hop commits the same rule movement")
			_view.clear_motion(false)
			_same_feet(last, _feet(), "roll/hop commits without changing the stance")

func _rail_height(low: Dictionary, high: Dictionary, declared: Dictionary, u: float) -> float:
	return float(low.h) + (float(high.h) - float(low.h)) * clampf((u - float(declared.rail_start)) / (float(declared.rail_end) - float(declared.rail_start)), 0.0, 1.0)

func _soft_plant_boundaries() -> void:
	var session := Session.new("1-1")
	_view.clear_motion(false)
	_view.set_world(session.world)
	_view.set_visual_time(15000.0)
	var core: Dictionary = session.world.point_for("f:3:0")
	_check(is_equal_approx(_plant_opacity(_view, core, "unplanted-root-island"), 1.0), "the unplanted start never reveals the distant flower or a route by fading it")
	await _capture("soft-plant/initial-root-island", _feet())
	_check(session.apply(Command.interact("grow:root:right")).accepted, "plant readibility setup grows the original right root")
	for tile: String in session.world.path_to("f:2:0"):
		_check(session.apply(Command.move_to(tile)).accepted, "plant readability setup reaches the flower approach by the real path")
	_view.clear_motion(false)
	var landing_alpha := _plant_opacity(_view, core, "f2-landing")
	_check(landing_alpha >= 0.38 - 0.000001 and landing_alpha < 1.0, "an actually nearby same-height traveller behind the flower receives bounded soft occlusion")
	await _capture("soft-plant/f2-landing", _feet())
	var prepared = session.prepare(Command.move_to("f:3:0"))
	_check(prepared.accepted, "the close flower step remains a legal rule move")
	_view.set_motion(prepared.before, prepared.after, 1.0, "move")
	var p1 := _plant_opacity(_view, core, "f3-p1")
	_check(session.commit(prepared).accepted, "the close flower step commits normally")
	_view.clear_motion(false)
	var committed := _plant_opacity(_view, core, "f3-clear")
	_check(absf(p1 - committed) < 0.000001, "same actual feet at p1 and clear cannot cause a plant-opacity pop")
	await _capture("soft-plant/f3-close", _feet())
	_check(session.apply(Command.move_to("f:4:0")).accepted, "a real same-height step reaches the flower foreground")
	_check(is_equal_approx(_plant_opacity(_view, core, "foreground-f4"), 1.0), "a traveller in front of the flower does not fade it")
	for tile: String in session.world.path_to("f:2:-1"):
		_check(session.apply(Command.move_to(tile)).accepted, "a real route reaches the higher rear platform")
	var high_alpha := _plant_opacity(_view, core, "higher-platform")
	_check(high_alpha > landing_alpha and high_alpha > 0.9, "the different-height rear platform restores almost full plant opacity")
	# Boundary probes move only the supplied plant query, not the rule state or
	# renderer. They assert opaque outer boundaries and bounds without copying
	# the smooth interpolation formula.
	var actor: Dictionary = _view.actor_ground_point("luvie")
	_check(is_equal_approx(_plant_opacity(_view, {"x": float(actor.x) + 1.7, "z": actor.z, "h": actor.h}, "outside-distance"), 1.0), "outside the declared distance boundary a soft plant is fully opaque")
	_check(is_equal_approx(_plant_opacity(_view, {"x": float(actor.x) + 0.3, "z": actor.z, "h": float(actor.h) + 1.2}, "outside-height"), 1.0), "outside the declared height boundary a soft plant is fully opaque")
	_check(is_equal_approx(_plant_opacity(_view, {"x": float(actor.x) - 0.3, "z": actor.z, "h": actor.h}, "outside-depth"), 1.0), "a plant behind the traveller does not fade")
	for id: String in ["1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4"]:
		var other := World.new(id)
		_probe_view.clear_motion(false)
		_probe_view.set_world(other)
		var point: Dictionary = _probe_view.actor_ground_point(str(other.state.active))
		_check(is_equal_approx(_plant_opacity(_probe_view, {"x": float(point.x) + 0.3, "z": point.z, "h": point.h}, id + "/policy-disabled"), 1.0), id + " does not enable the local soft-plant policy")

func _plant_opacity(view: Node2D, point: Dictionary, label: String) -> float:
	var before: Dictionary = view.world.snapshot()
	var could_undo: bool = view.world.can_undo()
	var opacity: float = view.call("_soft_occluder_opacity", point)
	_check(view.world.snapshot() == before and view.world.can_undo() == could_undo, label + " soft-plant query cannot change puzzle state/history")
	_check(opacity >= 0.38 - 0.000001 and opacity <= 1.000001, label + " respects the declared material-only opacity range")
	_plant_samples.append({"name": label, "level": view.world.level.id, "point": point.duplicate(true), "opacity": opacity})
	return opacity

func _support_height(low: Dictionary, high: Dictionary, declared: Dictionary, u: float) -> float:
	if declared.style == "ramp":
		return _rail_height(low, high, declared, u)
	if u < float(declared.visual_start):
		return float(low.h)
	if u >= float(declared.visual_end):
		return float(high.h)
	var index := clampi(int(floor((u - float(declared.visual_start) + 0.00000001) * 8.0 / (float(declared.visual_end) - float(declared.visual_start)))), 0, 7)
	return float(low.h) + (float(high.h) - float(low.h)) * (index + 1.0) / 8.0

func _puzzle_contract() -> void:
	var unopened := Session.new("1-1")
	_check(not unopened.prepare(Command.move_to("g:root:1:0")).accepted, "a missing bridge stays unavailable")
	var branch: RefCounted = _grown("down")
	for target: String in ["g:root:0:1", "f:0:2", "g:root:0:1", "f:0:0"]:
		_check(branch.apply(Command.move_to(target)).accepted, "the optional low-island route remains legal")
	_check(branch.world.state.collected == ["spore-2"] and branch.world.budget() == 0, "optional exploration keeps its reward and one-root budget")
	_check(branch.apply(Command.interact("retract:root")).accepted and branch.apply(Command.interact("grow:root:right")).accepted, "return/reallocation remains a real player choice")
	for tile: String in branch.world.path_to("f:3:0"):
		_check(branch.apply(Command.move_to(tile)).accepted, "the branch run can reach the original flower")
	_check(branch.apply(Command.interact("repair")).accepted and branch.world.state.collected.size() == 1, "optional exploration never becomes full-collection gating")
	var direct: RefCounted = _grown()
	for tile: String in direct.world.path_to("f:3:0"):
		_check(direct.apply(Command.move_to(tile)).accepted, "direct zero-collection route remains legal")
	_check(direct.apply(Command.interact("repair")).accepted and direct.world.state.collected.is_empty(), "zero-collection completion stays valid")

func _other_level_gate() -> void:
	var sample: RefCounted = _grown()
	var pair := [sample.world.point_for("g:root:1:0"), sample.world.point_for("f:2:0")]
	for id: String in ["1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4"]:
		_check(Surface.connection(World.new(id).level, pair).is_empty(), id + " keeps the prior presentation")

func _capture(name: String, data: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var record: Dictionary = {"name": name, "state": _view.world.snapshot(), "sample": data, "visualTimeMs": _view.visual_time}
	if not _output.is_empty():
		var file := name + ".png"
		var destination := _output.path_join(file)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		_check(_viewport.get_texture().get_image().save_png(destination) == OK, "normal-scene evidence saves: " + name)
		record["file"] = file
	_captures.append(record)

func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)

func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for file: String in ["res://presentation/world/garden_view.gd", "res://presentation/world/stair_surface.gd", "res://presentation/world/depth_stage.gd", "res://presentation/world/depth_paint_target.gd", "res://tests/visual_stair_contact_test.gd"]:
		result[file] = FileAccess.get_sha256(file)
	return result
