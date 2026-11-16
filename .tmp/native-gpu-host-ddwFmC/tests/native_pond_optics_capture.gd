extends "res://tests/native_route_test.gd"
## Native Windows/OpenGL evidence through actual application transactions.
## The original 21 intentions are replayed unchanged; extra demonstrations are
## legally undone before continuing. No fixture snapshot is installed in play.
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
var output := ""
var source_sha := ""
var outer: SubViewport
var dimensions := Vector2i(1280, 720)
var phase := "setup"
var images: Array = []
var events: Array = []
var command_timings: Array = []
var source_start: Dictionary = {}
var logger := ErrorLogger.new()
var rendered_count := 0
var midpoint_saved := false
var capturing := false
var finished := false

func _initialize() -> void:
	OS.add_logger(logger)
	ProjectSettings.set_setting("rendering/shader_compiler/shader_cache/enabled", false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--source-sha="): source_sha = argument.trim_prefix("--source-sha=")
	RenderingServer.frame_post_draw.connect(func() -> void: rendered_count += 1)
	create_timer(420).timeout.connect(func() -> void:
		if not finished:
			push_error("Pond optics real-input capture timed out")
			quit(2))
	_run.call_deferred()

func _tick() -> void:
	await super._tick()
	if phase == "demo-turn-b" and not midpoint_saved and not app.motion.is_empty() and str(app.motion.kind) == "angle:mirrorB":
		var progress: float = float(app.motion.elapsed) / float(app.motion.duration)
		if progress >= 0.45 and progress < 0.85:
			midpoint_saved = true
			_check(progress < 1.0, "B midpoint comes from an unfinished actual app motion")
			_check_incident_prefix()
			await _capture("b-turn-mid")

func _dispatch(id: String) -> int:
	# Complete the first real draw before any snapshot, layout, readback or PNG
	# work. The reported command timing excludes all later capture preparation.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var revision: int = app.session.revision
	var started := Time.get_ticks_usec()
	app._on_command(id)
	var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	command_timings.append({"phase": phase, "command": id, "viewport": [dimensions.x, dimensions.y], "synchronousMs": sync_ms, "dispatchToFirstDrawMs": float(Time.get_ticks_usec() - started) / 1000.0, "firstDrawBeforeCapturePreparation": true})
	return revision

func _act(id: String, label: String) -> bool:
	phase = label
	var revision := await _dispatch(id)
	var settled := await _drain(600)
	if not _check(settled, label + " actual action, passengers and drop approach settle"):
		print("OPTICS ACTION STALL ", JSON.stringify({"motion": app.motion, "status": app.status_message, "movement": app.native_movement.qa_state()}))
		return false
	return _check(app.session.revision > revision or bool(app.session.world.state.completed), label + " accepted through application transaction: " + app.status_message)

func _run_size(fixture: Dictionary) -> void:
	outer = SubViewport.new()
	outer.size = dimensions
	outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(outer)
	_setup()
	app.reparent(outer)
	app.view.set_settings(app.settings)
	app.hud.apply_settings(app.settings)
	app.repository.data = Repository.empty_store()
	_check(app.repository.data.mainline.runs.is_empty(), "cold optics entry has an empty memory repository")
	phase = "cold"
	var started := Time.get_ticks_usec()
	app._enter_level("2-2")
	var synchronous := float(Time.get_ticks_usec() - started) / 1000.0
	await _tick()
	await _tick()
	for unused in range(8): await RenderingServer.frame_post_draw
	command_timings.append({"phase": phase, "command": "_enter_level(empty repository)", "viewport": [dimensions.x, dimensions.y], "synchronousMs": synchronous, "readyAfterEightDrawsMs": float(Time.get_ticks_usec() - started) / 1000.0, "includesPng": false})
	_check(int(app.session.world.state.items.mirrorA.angle) == 0 and int(app.session.world.state.items.mirrorB.angle) == 0 and not app.session.world.beam_hits(4, 0), "cold entry preserves both initial angles and an unlit receiver")
	_source_contract()
	await _capture("cold")
	# Reproduce the user's A-turned/B-unmoved view with real walking and input.
	if not await _walk_to("f:1:2", "user view approach A") or not await _walk_to("f:1:1", "user view reaches A"):
		await _dispose()
		return
	var user_baseline: Dictionary = app.session.world.snapshot()
	var user_baseline_ray: Array = app.session.world.rays().duplicate(true)
	if not await _act("angle:mirrorA", "user-a-turn"):
		await _dispose()
		return
	_check(str(app.session.world.state.items.mirrorB.tile) == "f:4:3" and int(app.session.world.state.items.mirrorA.angle) == 1, "user view keeps B at its untouched initial support")
	# Reproduce the user's clear view from the starting shore. Standing on
	# the interaction cell would put both actors in front of the glass.
	if not await _walk_to("f:0:2","user view clears the real A mirror"):
		await _dispose()
		return
	await _capture("a-turned-b-initial")
	if not await _undo_until(user_baseline, user_baseline_ray, "user-a-turn-undo"):
		await _dispose()
		return
	_check(int(app.session.world.state.items.mirrorA.angle) == 0, "real undo restores A before replaying authored intentions")
	var expected: Dictionary = fixture.initial.snapshot
	var executed := 0
	var success := true
	for index: int in range(fixture.steps.size()):
		var step: Dictionary = fixture.steps[index]
		var command: Dictionary = step.command
		phase = "authored-%02d" % index
		if str(command.kind) == "move":
			success = await _walk_to(str(command.value), "pond optics original/%d" % index)
		elif str(command.kind) == "act":
			var actor: String = app.session.world.actor()
			var intended := str(expected.actors[actor])
			if intended != str(app.session.world.state.actors[actor]):
				success = await _walk_to(intended, "pond optics original approach/%d" % index)
			if success: success = await _act(str(command.value), "authored-%02d" % index)
		else:
			success = _check(false, "authored optics intention is supported")
		if not success: break
		executed += 1
		expected = step.snapshot
		if index == 4:
			# The original walk collects the optional glow at B. Step back through
			# real movement so neither that glow nor the actor hides the new rim.
			var pickup_stance: Dictionary = app.session.world.snapshot()
			var pickup_ray: Array = app.session.world.rays().duplicate(true)
			var previous_stance := str(fixture.steps[3].snapshot.actors[app.session.world.actor()])
			if not await _walk_to(previous_stance, "B initial mirror unobstructed side view"):
				success = false
				break
			await _capture("b-initial-side-close")
			if not await _undo_until(pickup_stance, pickup_ray, "B-side-view-restore"):
				success = false
				break
		_check(bool(app.session.world.normalize_saved(app.session.world.snapshot()).get("ok", false)), "original optics step %d produces a valid native save" % index)
		if index == 5:
			_check(str(app.session.world.state.items.mirrorB.get("holder", "")) == "luvie", "first authored pickup really puts B in the hero's leaf pouch")
			events.append(_state("authored-first-b-held"))
		if index == 12:
			_check(str(app.session.world.state.items.mirrorB.tile) == "f:1:0" and int(app.session.world.state.items.mirrorB.angle) == 0, "authored B drop reaches the unrotated slot")
			await _capture("b-dropped-unrotated")
			if not await _demonstrate_b():
				success = false
				break
		if index == 15:
			_check(app.session.world.beam_hits(4, 0), "original A turn restores real receiver light before final walk")
			events.append(_state("authored-receiver-aligned"))
	var completed := bool(app.session.world.state.completed)
	_check(success and executed == 21 and completed, "all original 21 pond intentions complete with actual bodies")
	routes.append({"level": "2-2", "viewport": [dimensions.x, dimensions.y], "success": success, "completed": completed, "steps": executed, "expectedSteps": fixture.steps.size(), "extraCommandsLegallyUndone": true})
	if completed:
		var stayed:=false
		for button: Node in app.hud.find_children("*","Button",true,false):
			if button.text=="留下看看":
				button.pressed.emit()
				stayed=true
				break
		_check(stayed and app.strolling,"real stay button dismisses completion overlay without clearing completed state")
		await _capture("completed")
	await _dispose()

func _demonstrate_b() -> bool:
	var baseline: Dictionary = app.session.world.snapshot()
	var baseline_ray: Array = app.session.world.rays().duplicate(true)
	# A is adjacent to the B slot. Both rotations are genuine offered actions;
	# all actors/items remain on the existing fixed supports before darkening.
	if not await _act("angle:mirrorA", "demo-turn-a"): return false
	midpoint_saved = false
	if not await _act("angle:mirrorB", "demo-turn-b"): return false
	_check(midpoint_saved, "actual B rotation supplied a rendered midpoint")
	_check(app.session.world.beam_hits(4, 0) and not bool(app.session.world.state.completed), "aligned demonstration lights receiver without completing the garden")
	await _capture("receiver-aligned")
	var aligned: Dictionary = app.session.world.snapshot()
	var aligned_ray: Array = app.session.world.rays().duplicate(true)
	# Reproduce both placed/aligned mirrors with the travellers clear of the
	# glass, as in the user's latest view. Return through normal undo commands.
	if not await _walk_to("f:0:2", "aligned view clears both real mirrors"): return false
	await _capture("receiver-aligned-clear")
	if not await _undo_until(aligned, aligned_ray, "aligned-clear-view-undo"): return false
	if not _darkening_clear(): return false
	if not await _act("take:mirrorB", "demo-take-b"): return false
	_check(not app.session.world.beam_hits(4, 0) and str(app.session.world.state.items.mirrorB.get("holder", "")) == "luvie", "real held B stops receiver light and retracts the light-dependent road")
	await _capture("b-held-receiver-dark")
	if not await _undo_until(aligned, aligned_ray, "demo-take-b-undo"): return false
	_check(app.session.world.beam_hits(4, 0) and app.session.world.rays() == aligned_ray and str(app.session.world.state.items.mirrorB.tile) == "f:1:0", "real undo restores B, its angle and the exact receiver ray")
	await _capture("undo-receiver-restored")
	if not _darkening_clear(): return false
	if not await _undo_until(baseline, baseline_ray, "demo-restore-authored-drop"): return false
	var restored: Dictionary = app.session.world.snapshot()
	_check(restored.items == baseline.items and restored.actors == baseline.actors and restored.flags == baseline.flags, "bounded actual undos restore the authored mirror and logical stance state before continuing")
	events.append(_state("demo-restored-authored-drop"))
	return true

func _undo_until(target: Dictionary, target_ray: Array, label: String, limit: int = 32) -> bool:
	# Walking/following can add legal checkpoints after a mechanism commits.
	# Observe every immediate undo before ticking follow again; settling after
	# each intermediate checkpoint could recreate that same walking history.
	# These are normal app commands. The history and snapshots are never edited.
	var steps: Array = []
	for index: int in range(limit):
		if _matches_undo_target(target, target_ray): break
		if not app.session.world.can_undo(): break
		phase = "%s-%02d" % [label, index]
		var before: Dictionary = app.session.world.snapshot()
		var revision: int = await _dispatch("undo")
		_check(app.motion.is_empty(), label + " undo is an immediate application transaction")
		var after: Dictionary = app.session.world.snapshot()
		steps.append({"step": index + 1, "revisionBefore": revision, "revisionAfter": app.session.revision, "sameStateCheckpoint": before == after, "items": after.items.duplicate(true), "actors": after.actors.duplicate(true), "ray": app.session.world.rays(), "targetReached": _matches_undo_target(target, target_ray)})
	var reached := _matches_undo_target(target, target_ray)
	events.append({"label": label, "viewport": [dimensions.x, dimensions.y], "undoCommands": steps.size(), "limit": limit, "steps": steps, "targetReachedBeforePhysicalSettle": reached, "historyEdited": false, "snapshotInjected": false})
	if not _check(reached, label + " reaches the requested mirror state, logical supports and ray within its undo bound"): return false
	if not _check(await _drain(600), label + " real restored bodies and follow settle"): return false
	return _check(_matches_undo_target(target, target_ray), label + " retains the requested mechanism and logical stance after physical settling")

func _matches_undo_target(target: Dictionary, target_ray: Array) -> bool:
	var state: Dictionary = app.session.world.state
	return state.items == target.items and state.actors == target.actors and state.flags == target.flags and state.active == target.active and bool(state.completed) == bool(target.completed) and app.session.world.rays() == target_ray

func _darkening_clear() -> bool:
	var occupied: Array = []
	for who: String in app.session.world.state.actors:
		var point: Dictionary = app.session.world.point_for(str(app.session.world.state.actors[who]))
		if float(point.get("z", INF)) == 0.0 and float(point.get("x", -INF)) >= 3.0: occupied.append("actor:" + who)
	for item_id: String in app.session.world.state.items:
		var item: Dictionary = app.session.world.state.items[item_id]
		if not str(item.get("holder", "")).is_empty() or str(item.get("tile", "")).is_empty(): continue
		var point: Dictionary = app.session.world.point_for(str(item.tile))
		if float(point.get("z", INF)) == 0.0 and float(point.get("x", -INF)) >= 3.0: occupied.append("item:" + item_id)
	events.append({"label": "darkening-preflight", "viewport": [dimensions.x, dimensions.y], "occupiedDependentSupports": occupied, "ruleOverride": false})
	return _check(occupied.is_empty(), "loss-of-light demonstration leaves dependent supports unoccupied; no rule protection is bypassed")

func _source_contract() -> void:
	var actions: Array = []
	for command: Dictionary in app.session.world.commands(): actions.append(str(command.id))
	for forbidden: String in ["take:source", "angle:source", "take:lamp", "angle:lamp"]:
		_check(not forbidden in actions, "fixed source never offers " + forbidden)
	var source: Node3D = app.view._props_nodes.get("mark:source")
	var stone_lamp := false
	if source != null:
		for child: Node in source.get_children():
			if child is Sprite3D and child.texture != null and child.texture.resource_path.ends_with("stone-lantern.png"): stone_lamp = true
	_check(stone_lamp, "fixed source retains its established stone lantern artwork")
	_check(source != null and source.find_children("ReflectionFace", "MeshInstance3D", true, false).is_empty(), "fixed source has no reflective mirror face")
	for item_id: String in ["mirrorA", "mirrorB"]:
		var mirror: Node3D = app.view._props_nodes.get("item:" + item_id)
		if mirror == null: continue
		var item: Dictionary = app.view.world.state.items[item_id]
		var support: Vector3 = app.view.tile_position(app.view._tile_map[str(item.tile)])
		_check(Vector2(mirror.position.x, mirror.position.z).distance_to(Vector2(support.x, support.z)) < 0.0001, item_id + " stays centred on its real authored support")
		var face: MeshInstance3D = mirror.get_node("ReflectionFace")
		for beam: Node3D in app.view._effects.get_children():
			if str(beam.get_meta("rule_contact_item", "")) == item_id:
				_check(is_equal_approx(beam.global_position.y, face.global_position.y), item_id + " real reflected contact stays at glass centre height")

func _check_incident_prefix() -> void:
	var count := 0
	for beam: Node3D in app.view._effects.get_children():
		if not beam.has_meta("rule_ray"): continue
		var expected := int(beam.get_meta("rule_segment_index", 99)) < 2 if beam.has_meta("rule_segment_index") else int(beam.get_meta("rule_point_index", 99)) <= 2
		_check(beam.visible == expected, "actual B midpoint retains only source-A-B incidence and real contacts")
		if beam.visible: count += 1
	_check(count > 0 and not app.session.world.beam_hits(4, 0), "midpoint has visible incidence while committed receiver remains unlit")

func _capture(label: String) -> void:
	capturing = true
	_source_contract()
	app._update_layout()
	app.view._fit_camera(true)
	var first_draw := rendered_count
	var wait_started := Time.get_ticks_usec()
	for unused in range(8): await RenderingServer.frame_post_draw
	var wait_ms := float(Time.get_ticks_usec() - wait_started) / 1000.0
	var state := _state(label)
	var read_started := Time.get_ticks_usec()
	var pixels := outer.get_texture().get_image()
	var read_ms := float(Time.get_ticks_usec() - read_started) / 1000.0
	var filename := "%s-%dx%d.png" % [label, dimensions.x, dimensions.y]
	_check(pixels != null and not pixels.is_empty() and pixels.get_size() == dimensions, "actual GPU framebuffer " + filename)
	var encode_started := Time.get_ticks_usec()
	if pixels != null and not pixels.is_empty(): _check(pixels.save_png(output.path_join(filename)) == OK, "save " + filename)
	state["file"] = filename
	state["captureTiming"] = {"actualDrawsBeforeReadback": rendered_count - first_draw, "eightDrawWaitMs": wait_ms, "readbackMs": read_ms, "pngMs": float(Time.get_ticks_usec() - encode_started) / 1000.0, "includedInCommandTiming": false}
	images.append(state)
	print("CAPTURE " + filename)
	capturing = false

func _state(label: String) -> Dictionary:
	var world: RefCounted = app.session.world
	var actors := {}
	for who: String in ["luvie", "buddy"]:
		var body: CharacterBody3D = app.view.get_actor_body(who)
		var carry: Sprite3D = body.get_node("Visual/Carry")
		actors[who] = {"support": str(world.state.actors[who]), "body": _v(body.position), "clearOfHardProps": app.view.prop_physical_point_clear(body.position, who), "carryVisible": carry.visible, "carryId": str(carry.get_meta("original_carry_id", "")), "carrySemantics": str(carry.get_meta("original_carry_semantics", ""))}
	var mirrors := {}
	for id: String in ["mirrorA", "mirrorB"]:
		var item: Dictionary = world.state.items[id]
		var row := {"state": item.duplicate(true), "actualNormal": null, "renderedYaw": null}
		var item_root: Node3D = app.view._props_nodes.get("item:" + id)
		var face: MeshInstance3D = item_root.get_node_or_null("ReflectionFace") as MeshInstance3D if item_root != null else null
		if face != null:
			row["actualNormal"] = _v(face.global_basis.z.normalized())
			row["renderedYaw"] = face.rotation.y
			row["facePosition"] = _v(face.global_position)
		mirrors[id] = row
	var source := {"actions": [], "art": []}
	for command: Dictionary in world.commands():
		if "source" in str(command.id) or "lamp" in str(command.id): source.actions.append(str(command.id))
	var source_root: Node3D = app.view._props_nodes.get("mark:source")
	if source_root != null:
		for child: Node in source_root.get_children():
			if child is Sprite3D: source.art.append({"name": str(child.name), "texture": child.texture.resource_path if child.texture != null else "", "depthTest": not child.no_depth_test, "position": _v(child.global_position)})
	var beams: Array = []
	for node: Node3D in app.view._effects.get_children():
		if node.has_meta("rule_ray"):
			var beam_row := {"part": str(node.get_meta("rule_ray_part", "")), "segment": node.get_meta("rule_segment_index", -1), "point": node.get_meta("rule_point_index", -1), "contact": node.get_meta("rule_contact_item", ""), "visible": node.visible, "position": _v(node.position)}
			if node.mesh is QuadMesh: beam_row["width"] = node.mesh.size.x
			elif node.mesh is CylinderMesh: beam_row["diameter"] = node.mesh.top_radius * 2.0
			if node.material_override is ShaderMaterial:
				var tint: Color = node.material_override.get_shader_parameter("tint")
				beam_row["alpha"] = tint.a
			beams.append(beam_row)
	return {"label": label, "viewport": [dimensions.x, dimensions.y], "snapshot": world.snapshot(), "committedRay": world.rays(), "presentationRay": app.view.world.rays(), "receiverLit": world.beam_hits(4, 0), "presentationReceiverLit": app.view.world.beam_hits(4, 0), "completed": bool(world.state.completed), "actors": actors, "mirrors": mirrors, "source": source, "beams": beams, "motion": {} if app.motion.is_empty() else {"kind": str(app.motion.kind), "elapsed": float(app.motion.elapsed), "duration": float(app.motion.duration), "progress": float(app.motion.elapsed) / float(app.motion.duration)}, "cameraSize": app.view._camera.size, "overview": app.view.overview, "status": app.status_message, "render": app.view.render_statistics()}

func _dispose() -> void:
	app.queue_free()
	app = null
	outer.queue_free()
	await process_frame

func _run() -> void:
	if output.is_empty() or OS.get_name() != "Windows" or DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Explicit output and actual native Windows/OpenGL rendering are required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	source_start = _hashes()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture: Dictionary = {}
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/2-2": fixture = entry
	if not _check(not fixture.is_empty() and fixture.steps.size() == 21, "original 2-2 fixture contains its 21 authored intentions"):
		quit(2)
		return
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		dimensions = size
		await _run_size(fixture)
	var source_end := _hashes()
	_check(source_start == source_end, "production, fixture and capture sources remain stable during the batch")
	_check(images.size() == 20, "both native viewport sizes have ten representative original frames including initial B side view")
	failures.append_array(logger.captured_errors())
	var report := {"suite": "native-pond-optics-real-app-gpu", "sourceSha256": source_sha, "captureScriptSha256": FileAccess.get_sha256("res://tests/native_pond_optics_capture.gd"), "baseRouteTestSha256": FileAccess.get_sha256("res://tests/native_route_test.gd"), "display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "initialSources": source_start, "finalSources": source_end, "sourceFilesStable": source_start == source_end, "shaderCacheEnabled": false, "images": images, "events": events, "originalRoutes": routes, "commandTimings": command_timings, "checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Actual empty MemoryRepository entry, native body walking, original 21 fixture intentions and extra legally undone demonstrations at two sizes. No play snapshot injection. Midpoint comes from actual app motion elapsed time, then manual app ticks wait while eight real draw events prepare its frame; the same motion subsequently settles normally. PNG readback and encoding are separate from command-to-first-draw timing. Native OpenGL pixels are not Web performance or browser-input evidence."}
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	finished = true
	print(JSON.stringify({"suite": report.suite, "images": images.size(), "checks": checks, "passed": report.passed, "failures": failures}))
	quit(0 if report.passed else 1)

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["tests/native_pond_optics_capture.gd", "tests/native_route_test.gd", "tests/fixtures/reference.json", "application/main.gd", "application/native_movement.gd", "application/native_action_policy.gd", "application/game_session.gd", "services/save_repository.gd", "services/snapshot_normalizer.gd", "core/garden_world.gd", "presentation/native/native_garden_stage.gd", "presentation/native/rule_ray_presentation.gd", "presentation/native/garden_beam_column.gdshader", "presentation/native/garden_beam_column.gdshader.uid", "presentation/native/garden_ray.gdshader", "presentation/native/garden_mirror.gdshader", "presentation/native/garden_mirror.gdshader.uid", "presentation/native/original_carry_art.gd", "presentation/native/native_prop_obstacles.gd", "presentation/native/mechanism_props.gd", "content/levels.json"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result

func _v(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
