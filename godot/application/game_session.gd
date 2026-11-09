class_name GardenSession
extends RefCounted

const World = preload("res://core/garden_world.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")

var world: RefCounted
var revision: int = 0

func _init(level_id: String = "1-1", saved: Dictionary = {}) -> void:
	var factory: Script = load("res://core/world_factory.gd")
	world = factory.create(level_id, saved) if factory != null else World.new(level_id, saved)

func apply(command: GardenCommand) -> GardenCommandResult:
	if command.kind == GardenCommand.Kind.UNDO:
		return _undo(command)
	return commit(prepare(command))

func prepare(command: GardenCommand) -> GardenCommandResult:
	var result := GardenCommandResult.new()
	result.command = command
	result.before = world.snapshot()
	result.revision = revision
	if command.kind == GardenCommand.Kind.UNDO:
		result.message = "撤销需要当前会话历史。"
		return result
	var preview: RefCounted = world.fork(result.before)
	var outcome: Dictionary = {}
	match command.kind:
		GardenCommand.Kind.MOVE:
			outcome = preview.move(command.value)
		GardenCommand.Kind.ACTOR_MOVE:
			outcome = preview.move_actor(command.actor_id, command.value, false)
		GardenCommand.Kind.INTERACT:
			outcome = preview.act(command.value, command.value == "beat" and bool(preview.state.get("playing", false)))
	result.accepted = bool(outcome.get("ok", false))
	result.message = str(outcome.get("message", ""))
	result.after = preview.snapshot()
	result.changed = not Snapshot.equivalent(result.before, result.after)
	return result

func commit(prepared: GardenCommandResult) -> GardenCommandResult:
	if not prepared.accepted or not prepared.changed:
		return prepared
	if prepared.revision != revision or not Snapshot.equivalent(world.snapshot(), prepared.before):
		prepared.accepted = false
		prepared.changed = false
		prepared.message = "花园状态已改变，请重新操作。"
		return prepared
	var outcome: Dictionary
	if prepared.command.kind == GardenCommand.Kind.ACTOR_MOVE:
		outcome = world.move_actor(prepared.command.actor_id, prepared.command.value, false)
	elif prepared.command.kind == GardenCommand.Kind.MOVE:
		outcome = world.move(prepared.command.value)
	else:
		outcome = world.act(prepared.command.value, prepared.command.value == "beat" and bool(world.state.get("playing", false)))
	prepared.accepted = bool(outcome.get("ok", false))
	prepared.message = str(outcome.get("message", ""))
	prepared.after = world.snapshot()
	prepared.changed = not Snapshot.equivalent(prepared.before, prepared.after)
	if prepared.accepted and prepared.changed:
		revision += 1
	prepared.revision = revision
	return prepared

func commit_actor_move(who: String, tile_id: String) -> GardenCommandResult:
	return commit(prepare(GardenCommand.move_actor(who, tile_id)))

func _undo(command: GardenCommand) -> GardenCommandResult:
	var result := GardenCommandResult.new()
	result.command = command
	result.before = world.snapshot()
	result.revision = revision
	if bool(world.state.completed):
		result.message = "已经修复的花园可以留下走走。"
		result.after = result.before.duplicate(true)
		return result
	result.accepted = world.undo()
	if result.accepted:
		world.state.playing = false
	result.message = "回到刚才的稳定时刻。" if result.accepted else "还没有可以退回的步骤。"
	result.after = world.snapshot()
	result.changed = not Snapshot.equivalent(result.before, result.after)
	if result.accepted and result.changed:
		revision += 1
	result.revision = revision
	return result
