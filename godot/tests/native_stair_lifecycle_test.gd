extends SceneTree
## Logical board membership and final geometry survive cancellation and undo.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Factory = preload("res://core/world_factory.gd")
var checks := 0
var failures: Array[String] = []
var transitions := 0
var stage: Node2D

func _initialize() -> void: call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if not str(entry.name).begins_with("authored/"): continue
		var previous: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if previous.get("growth", {}) != step.snapshot.get("growth", {}):
				var first: RefCounted = Factory.create(str(entry.levelId), previous)
				var last: RefCounted = Factory.create(str(entry.levelId), step.snapshot)
				_transition(first, last, str(step.command.get("value", "undo")))
				_transition(last, first, "undo")
			previous = step.snapshot
	_check(transitions > 4, "multiple authored growth/retraction and undo transitions covered")
	print(JSON.stringify({"suite": "native-stair-lifecycle", "passed": failures.is_empty(), "checks": checks, "transitions": transitions, "failures": failures, "gpuPixelsVerified": false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _transition(first: RefCounted, last: RefCounted, command: String) -> void:
	transitions += 1
	var label := str(first.level.id) + "/" + command + "/" + str(transitions)
	var before: Dictionary = first.snapshot()
	var after: Dictionary = last.snapshot()
	stage.clear_motion(false)
	stage.set_world(first)
	var source := _settled(first, label + "/source")
	stage.set_world(last)
	var destination := _settled(last, label + "/destination")
	stage.set_world(first)
	var added: Array[String] = []
	var removed: Array[String] = []
	for id: String in destination:
		if not source.has(id): added.append(id)
	for id: String in source:
		if not destination.has(id): removed.append(id)
	var identities := {}
	for progress: float in [0.0, 0.25, 0.5, 0.75]:
		stage.set_motion(before, after, progress, command)
		for id: String in removed:
			_check(not stage._surfaces.has(id), label + "/" + id + " retraction removes the entire stair immediately")
		for id: String in added:
			_check(stage._surfaces.has(id), label + "/" + id + " growth has its full-size reveal surface")
			if not stage._surfaces.has(id): continue
			var surface: Node3D = stage._surfaces[id]
			_check(surface.scale.is_equal_approx(stage._surface_scale(surface)), label + " growth never compresses a stair")
			var identity: Array = [surface.geometry_rebuilds, surface._body.get_child(0).shape.get_rid()]
			var parts := 0
			for part: MeshInstance3D in [surface._top, surface._sides, surface._ramps, surface._treads, surface._risers]:
				if part.mesh == null: continue
				identity.append(part.mesh.get_rid())
				parts += 1
				_check(part.material_override is ShaderMaterial, label + " each visible stair face has reveal material")
				if part.material_override is ShaderMaterial:
					_check(is_equal_approx(float(part.material_override.get_shader_parameter("growth_progress")), progress * progress * (3.0 - 2.0 * progress)), label + " all faces share exact reveal progress")
			_check(parts >= 2, label + " reveal covers top and structural sides")
			if progress == 0.0: identities[id] = identity
			else: _check(identity == identities[id], label + " advancing reveal never rebuilds mesh or collision")
	for progress: float in [0.0, 0.25, 0.5, 0.75]:
		stage.clear_motion(false)
		stage.set_world(first)
		stage.set_motion(before, after, progress, command)
		stage.clear_motion(false)
		stage.set_world(first)
		_check(_settled(first, label + "/cancel") == source, label + " cancellation restores exact source geometry")
	stage.set_motion(before, after, 1.0, command)
	stage.clear_motion(false)
	stage.set_world(last)
	_check(_settled(last, label + "/commit") == destination, label + " completed transition restores destination")
	stage.set_world(first)
	_check(_settled(first, label + "/undo") == source, label + " undo restores exact source")
	stage.set_world(last)
	_check(_settled(last, label + "/reenter") == destination, label + " reentry has no stale hidden faces")
	_check(first.snapshot() == before and last.snapshot() == after, label + " presentation never mutates logical snapshots")

func _settled(world: RefCounted, label: String) -> Dictionary:
	var ids: Array[String] = []
	var result := {}
	for tile: Dictionary in world.tiles():
		var id := str(tile.id)
		ids.append(id)
		_check(stage._surfaces.has(id), label + "/" + id + " authored support exists")
		if not stage._surfaces.has(id): continue
		var surface: Node3D = stage._surfaces[id]
		_check(surface.visible == world.visible(tile), label + "/" + id + " visibility obeys world")
		_check(surface._growth_overrides.is_empty(), label + "/" + id + " no reveal override after settling")
		var faces: Array = [surface._body.get_child(0).shape.get_faces()]
		for part: MeshInstance3D in [surface._top, surface._sides, surface._ramps, surface._treads, surface._risers]:
			faces.append(part.mesh.surface_get_arrays(0) if part.mesh != null else [])
		result[id] = var_to_bytes(faces).hex_encode().sha256_text()
	_check(stage._surfaces.size() == ids.size(), label + " no ghost supports after removal")
	return result
