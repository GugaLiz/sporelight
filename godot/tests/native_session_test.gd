extends SceneTree
const Session = preload("res://application/game_session.gd")
const World = preload("res://core/garden_world.gd")
const Router = preload("res://application/input_router.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var session := Session.new("1-1")
	var initial: Dictionary = session.world.snapshot()
	var buddy: String = str(initial.actors.buddy)
	session.world.record_checkpoint()
	var movement: RefCounted = session.commit_actor_move("luvie", "f:-1:0")
	_check(movement.accepted, "explicit actor movement accepted")
	_check(session.world.state.actors.buddy == buddy, "other actor never advances ahead of its physical body")
	_check(session.revision == 1, "crossing advances revision exactly once")
	_check(not session.commit_actor_move("buddy", "missing").accepted, "missing edge rejected")
	_check(not session.commit_actor_move("luvie", "f:2:-1").accepted, "height and unopened root cannot be bypassed")
	_check(not session.commit_actor_move("unknown", "f:0:0").accepted, "unknown actor rejected")
	var second: RefCounted = session.commit_actor_move("luvie", "f:-2:0")
	_check(second.accepted, "continuous group may cross another support")
	_check(session.world.undo(), "movement intent checkpoint is undoable")
	_check(Snapshot.equivalent(initial, session.world.snapshot()), "one undo restores the entire continuous movement intent")
	var lever := Session.new("1-4")
	lever.world.state.flags.append("hold")
	var path: Array = lever.world.path_to("f:-3:0")
	for tile: String in path:
		lever.commit_actor_move("luvie", tile)
	lever.world.state.flags.append("hold")
	var buddy_path: Array = lever.world.path_to(str(lever.world.state.actors.luvie), "buddy")
	if not buddy_path.is_empty():
		lever.commit_actor_move("buddy", str(buddy_path[0]))
		_check(lever.world.flag("hold"), "partner movement does not release the hero's lever")
	var runtime := World.new("1-1")
	runtime.state.runtime = {"version": 1, "poses": {"luvie": {"support": "f:0:0", "offset": [0.22, 0.02, -0.12], "facing": "right"}}}
	_check(runtime.normalize_saved(runtime.snapshot()).ok, "continuous local pose survives save validation")
	var invalid: Dictionary = runtime.snapshot()
	invalid.runtime.poses.luvie.offset = [99, 0, 0]
	_check(not runtime.normalize_saved(invalid).ok, "invalid local pose rejected")
	invalid = runtime.snapshot()
	invalid.runtime.poses.luvie.support = "f:2:-1"
	_check(not runtime.normalize_saved(invalid).ok, "cross-layer pose support mismatch rejected")
	var router := Router.new()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_RIGHT
	key.pressed = true
	router.handle_key(key)
	_check(router.movement_vector() == Vector2.RIGHT, "held key exposes continuous intent")
	key.pressed = false
	router.handle_key(key)
	_check(router.movement_vector() == Vector2.ZERO, "release immediately removes intent")
	if failures.is_empty():
		print("PASS native session: %d checks" % checks)
		quit(0)
	else:
		quit(1)
