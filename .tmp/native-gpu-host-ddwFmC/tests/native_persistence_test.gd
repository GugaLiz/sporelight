extends SceneTree
## Uses the real FileAccess/temporary/backup repository. Memory stubs cannot
## detect JSON precision or persistence verification failures.
const Repository = preload("res://services/save_repository.gd")
const Factory = preload("res://core/world_factory.gd")
const Session = preload("res://application/game_session.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Movement = preload("res://application/native_movement.gd")
const Router = preload("res://application/input_router.gd")
const Command = preload("res://contracts/game_command.gd")
var checks := 0
var failures: Array[String] = []
var repository: RefCounted
var stage: Node2D
var session: RefCounted
var movement: RefCounted
var router: RefCounted
var store_path := ""
var commits := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _validate(snapshot: Dictionary) -> Dictionary:
	return Factory.create(str(snapshot.get("levelId", ""))).normalize_saved(snapshot)

func _difference(left: Variant, right: Variant, path: String = "$") -> Dictionary:
	if left is int or left is float:
		return {} if (right is int or right is float) and float(left) == float(right) else {"path": path, "before": left, "after": right}
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key):
				return {"path": path + "." + str(key), "missing": true}
			var found := _difference(left[key], right[key], path + "." + str(key))
			if not found.is_empty():
				return found
		return {}
	if left is Array and right is Array:
		if left.size() != right.size():
			return {"path": path, "length": true}
		for index in range(left.size()):
			var found := _difference(left[index], right[index], path + "[%d]" % index)
			if not found.is_empty():
				return found
		return {}
	return {} if left == right else {"path": path, "before": left, "after": right}

func _quantized_pose(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for pose: Dictionary in result.get("runtime", {}).get("poses", {}).values():
		for axis: int in range(3):
			pose.offset[axis] = roundi(float(pose.offset[axis]) * 10000.0)
	return result

func _commit_and_reload(label: String) -> bool:
	var snapshot: Dictionary = session.world.snapshot()
	var outcome: Dictionary = repository.commit_run(snapshot)
	commits += 1
	if not bool(outcome.get("ok", false)):
		var short_json := JSON.stringify(repository.data, "\t")
		var precision_loss := _difference(repository.data, JSON.parse_string(short_json))
		print("REAL PERSISTENCE ERROR ", JSON.stringify({"label": label, "error": outcome, "shortJsonDifference": precision_loss}, "", true, true))
		_check(false, label + " real repository commit: " + str(outcome.get("error", "")))
		return false
	var reload := Repository.new(store_path)
	reload.configure_levels(JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels)
	reload.snapshot_validator = _validate
	var loaded: Dictionary = reload.load_store()
	_check(loaded.ok, label + " file reload succeeds")
	var restored: Dictionary = reload.data.mainline.runs.get("1-1", {})
	_check(Repository.json_equivalent(_quantized_pose(snapshot), _quantized_pose(restored)), label + " file preserves exact rules and 1e-4 continuous pose")
	return true

func _tick() -> void:
	await physics_frame
	movement.tick(1.0 / 60.0)

func _walk(to: String) -> void:
	movement.request_path(session.world.path_to(to))
	for index in range(240):
		await _tick()
		if not movement.is_moving():
			break
	_check(session.world.state.actors.luvie == to, "real motor reaches " + to)
	_commit_and_reload("arrival/" + to)

func _run() -> void:
	store_path = "user://qa-native-runtime-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_msec()]
	repository = Repository.new(store_path)
	repository.configure_levels(JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels)
	repository.snapshot_validator = _validate
	session = Session.new("1-1")
	# Deliberately retain the same snapped binary float used by the motor.
	# Exact file verification must succeed without replacing it by an epsilon.
	var pose_x := snappedf(float(Vector3(0.0531, 0, 0).x), 0.0001)
	session.world.state.runtime = {"version": 1, "poses": {"luvie": {"support": "f:0:0", "offset": [pose_x, 0.0002, 0], "facing": "front"}}}
	var precision_saved := _commit_and_reload("fractional-runtime-pose")
	if precision_saved:
		stage = Stage.new()
		root.add_child(stage)
		stage.set_world(session.world)
		router = Router.new()
		movement = Movement.new()
		movement.setup(session, stage, router)
		await physics_frame
		var grown: RefCounted = session.apply(Command.interact("grow:root:down"))
		_check(grown.accepted, "plant lower route")
		stage.refresh_world(session.world, true)
		movement.capture()
		_commit_and_reload("planted-root")
		movement.support_changed.connect(func(_who: String, _result: RefCounted) -> void:
			stage.refresh_world(session.world, true)
			_commit_and_reload("crossing")
		)
		await _walk("g:root:0:1")
		await _walk("f:0:0")
		var before_return: Dictionary = session.world.snapshot()
		movement.stop()
		movement.restore()
		_commit_and_reload("return-home-stable")
		_check(session.world.state.actors == before_return.actors, "home stabilization cannot reset committed location")
		stage.queue_free()
		await process_frame
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(store_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(store_path + suffix))
	print(JSON.stringify({"suite": "native-real-persistence", "passed": failures.is_empty(), "checks": checks, "commits": commits, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
