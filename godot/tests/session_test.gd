extends SceneTree

const Session = preload("res://application/game_session.gd")
const Command = preload("res://contracts/game_command.gd")
const Router = preload("res://application/input_router.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _run() -> void:
	var session := Session.new("1-1")
	var initial: Dictionary = session.world.snapshot()
	var moved = session.apply(Command.move_to("f:-1:0"))
	_check(moved.accepted and moved.changed and session.revision == 1, "legal movement commits once")
	_check(initial.actors.luvie == "f:0:0" and moved.after.actors.luvie == "f:-1:0", "before snapshot is detached")
	var invalid = session.apply(Command.move_to("missing-tile"))
	_check(not invalid.accepted and not invalid.changed and session.revision == 1, "illegal movement does not advance revision")
	var restored = session.apply(Command.undo_action())
	_check(restored.accepted and session.world.snapshot() == initial, "session undo restores original state")
	var reloaded := Session.new("1-1", session.world.snapshot())
	_check(not reloaded.apply(Command.undo_action()).accepted, "reload does not fabricate undo history")
	var song := Session.new("2-3")
	for tile in song.world.path_to("m:stage:0:0"):
		_check(song.apply(Command.move_to(str(tile))).accepted, "stage passenger route")
	_check(song.apply(Command.interact("switch")).accepted, "switch to piano player")
	_check(song.apply(Command.interact("play")).accepted, "start automatic song")
	var beat: int = int(song.world.state.beat)
	var played = song.apply(Command.interact("beat"))
	_check(played.accepted and int(song.world.state.beat) != beat, "automatic song uses internal beat permission")
	var input := Router.new()
	var down := InputEventKey.new()
	down.physical_keycode = KEY_LEFT
	down.pressed = true
	_check(input.handle_key(down) == "left", "first physical direction is accepted")
	down.echo = true
	_check(input.handle_key(down).is_empty(), "reference mode filters key echo")
	input.continuous = true
	input.buffer("left")
	_check(input.take_next() == "left" and input.buffered_direction.is_empty(), "single direction buffer is consumed")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_LEFT
	up.pressed = false
	input.handle_key(up)
	_check(input.take_next().is_empty(), "release clears continued movement")
	input.clear()
	_check(input.held.is_empty(), "focus clear releases all input")
	if failures.is_empty():
		print("PASS session/input: %d checks" % checks)
		quit(0)
	else:
		for label in failures:
			push_error(label)
		quit(1)

