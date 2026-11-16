extends SceneTree
## Production main/motor/HUD/save chain. Only audio is stubbed; file mode uses
## actual transactional persistence in an isolated temporary user directory.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Router = preload("res://application/input_router.gd")
const Repository = preload("res://services/save_repository.gd")
const Factory = preload("res://core/world_factory.gd")
const Normalizer = preload("res://services/snapshot_normalizer.gd")
var results: Array = []
var failures: Array[String] = []
var checks := 0
var app: Node

class CountedNormalizer:
	extends Normalizer
	var measured := false
	var uncached_times: Array = []
	func _normalize_uncached(id: String, snapshot: Dictionary) -> Dictionary:
		var start := Time.get_ticks_usec()
		var result: Dictionary = super._normalize_uncached(id, snapshot)
		if measured: uncached_times.append(Time.get_ticks_usec() - start)
		return result

class Harness:
	extends "res://application/main.gd"
	var measured := false
	var metrics: Dictionary = {}
	func _ready() -> void: pass
	func _record(key: String, start: int) -> void:
		if not measured: return
		if not metrics.has(key): metrics[key] = []
		metrics[key].append(Time.get_ticks_usec() - start)
	func _save() -> void:
		var start := Time.get_ticks_usec()
		super._save()
		_record("save", start)
	func _sync_hud() -> void:
		var start := Time.get_ticks_usec()
		super._sync_hud()
		_record("hud", start)
	func _command_states() -> Dictionary:
		var start := Time.get_ticks_usec()
		var result: Dictionary = super._command_states()
		_record("commandStates", start)
		return result
	func _on_native_support_changed(who: String, result: RefCounted) -> void:
		var start := Time.get_ticks_usec()
		super._on_native_support_changed(who, result)
		_record("supportChanged", start)

class TimedStage:
	extends Stage
	var measured := false
	var refresh_times: Array = []
	func refresh_world(value: RefCounted, preserve_pose: bool = true) -> void:
		var start := Time.get_ticks_usec()
		super.refresh_world(value, preserve_pose)
		if measured: refresh_times.append(Time.get_ticks_usec() - start)

class TimedRepository:
	extends Repository
	var measured := false
	var memory_only := false
	var metrics: Dictionary = {}
	func _record(key: String, start: int) -> void:
		if not measured: return
		if not metrics.has(key): metrics[key] = []
		metrics[key].append(Time.get_ticks_usec() - start)
	func persist(candidate: Dictionary = {}) -> Dictionary:
		var start := Time.get_ticks_usec()
		var result: Dictionary
		if memory_only:
			var next: Dictionary = data.duplicate(true) if candidate.is_empty() else candidate.duplicate(true)
			result = _validate_store(next)
			if result.ok: data = next
		else:
			result = super.persist(candidate)
		_record("persist", start)
		return result
	func _validate_store(value: Dictionary) -> Dictionary:
		var start := Time.get_ticks_usec()
		var result: Dictionary = super._validate_store(value)
		_record("storeValidation", start)
		return result
	func _validate_snapshot(value: Dictionary, expected_id: String = "") -> Dictionary:
		var start := Time.get_ticks_usec()
		var result: Dictionary = super._validate_snapshot(value, expected_id)
		_record("snapshotValidation", start)
		return result

class AudioStub:
	extends Node
	func start() -> void: pass
	func play(_kind: String) -> void: pass
	func configure(_settings: Dictionary) -> void: pass
	func pause(_value: bool) -> void: pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for level_id: String in ["1-3", "3-4"]:
		for memory_only: bool in [true, false]:
			for populated: bool in [false, true]:
				await _sample(level_id, memory_only, populated)
	print(JSON.stringify({"suite": "native-application-walk-performance", "passed": failures.is_empty(), "checks": checks, "failures": failures, "results": results, "timingsInclusive": true, "memoryPersist": "One full store validation; production commit_run/stage_run normalization retained. File mode executes all canonicalization, backup and read-back validations."}))
	quit(0 if failures.is_empty() else 1)

func _sample(level_id: String, memory_only: bool, populated: bool) -> void:
	app = Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_input(false)
	app.set_physics_process(false)
	app.levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	app.levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	app.input_router = Router.new()
	var filename := "user://performance-walk-%d/%s-%s-%s.json" % [OS.get_process_id(), level_id, memory_only, populated]
	app.repository = TimedRepository.new(filename)
	app.repository.memory_only = memory_only
	app.repository.configure_levels(app.levels)
	app.repository.snapshot_validator = app._normalize_snapshot
	if populated:
		for level: Dictionary in app.levels:
			app.repository.data.mainline.runs[str(level.id)] = Factory.create(str(level.id)).snapshot()
	app.audio = AudioStub.new()
	app.add_child(app.audio)
	app.settings = Repository.default_settings()
	app.view = TimedStage.new()
	app.add_child(app.view)
	app.hud = HUD.new()
	app.add_child(app.hud)
	app.hud.command_requested.connect(app._on_command)
	app.hud.set_repository(app.repository)
	app.native_enabled = true
	app._snapshot_normalizer = CountedNormalizer.new()
	app._enter_level(level_id)
	for unused: int in range(5):
		await physics_frame
		app._physics_process(1.0 / 60.0)
	var target := ""
	var length := 0
	for tile: Dictionary in app.session.world.tiles():
		var route: Array = app.session.world.path_to(str(tile.id))
		if route.size() > length and route.size() <= 3:
			target = str(tile.id)
			length = route.size()
	app._go(target)
	app.measured = true
	app.repository.measured = true
	app.view.measured = true
	app._snapshot_normalizer.measured = true
	var ticks: Array = []
	var crossings: Array = []
	var steady: Array = []
	for unused: int in range(100):
		await physics_frame
		var revision: int = app.session.revision
		var start := Time.get_ticks_usec()
		app._physics_process(1.0 / 60.0)
		var elapsed := Time.get_ticks_usec() - start
		ticks.append(elapsed)
		if revision != app.session.revision: crossings.append(elapsed)
		else: steady.append(elapsed)
	_check(str(app.session.world.state.actors.luvie) == target and app.native_movement.click_path.is_empty(), "real full application route settles: " + level_id)
	_check(app.storage_ready, "real commit_run and persistence remain valid")
	_check(app.repository.data.mainline.runs[level_id].actors.luvie == target, "final persisted support matches physical actor")
	var metrics := {"tick": _stats(ticks), "crossingTick": _stats(crossings), "steadyTick": _stats(steady), "refresh": _stats(app.view.refresh_times), "uncachedDomainNormalization": _stats(app._snapshot_normalizer.uncached_times)}
	for key: String in app.metrics: metrics[key] = _stats(app.metrics[key])
	for key: String in app.repository.metrics: metrics[key] = _stats(app.repository.metrics[key])
	results.append({"level": level_id, "mode": "memory" if memory_only else "file", "storedRuns": app.repository.data.mainline.runs.size(), "populated": populated, "metrics": metrics})
	print("APPLICATION WALK SAMPLE " + JSON.stringify(results.back()))
	app.queue_free()
	await process_frame
	# Only this sample's exact temporary files are removed; user saves are never opened.
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(filename + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(filename + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(filename.get_base_dir()))

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count": 0, "totalMs": 0.0}
	values.sort()
	var sum := 0
	for value: int in values: sum += value
	return {"count": values.size(), "totalMs": sum / 1000.0, "medianMs": float(values[values.size() / 2]) / 1000.0, "p95Ms": float(values[mini(values.size() - 1, int(values.size() * 0.95))]) / 1000.0, "maxMs": float(values.back()) / 1000.0}

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
