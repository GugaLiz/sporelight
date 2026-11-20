extends SceneTree

const World = preload("res://core/garden_world.gd")
const Interaction = preload("res://application/native_interaction.gd")
const Profiles = preload("res://presentation/native/level_presentation_profiles.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _walk(world: RefCounted, destination: String) -> void:
	var path: Array = world.path_to(destination)
	_check(not path.is_empty(), "legal route to " + destination)
	for tile: String in path:
		_check(bool(world.move(tile).ok), "legal edge " + tile)

func _run() -> void:
	var world := World.new("1-1")
	_check(world.tiles().size() == 19, "expanded map contract")
	_check(bool(world.act("grow:root:right").ok), "east route grows")
	_check(not bool(world.act("grow:root:down").ok), "one seed cannot create both routes")
	_walk(world, "g:root:1:0")
	_check(not bool(world.act("retract:root").ok), "occupied bridge cannot retract")
	_walk(world, "f:3:-2")
	_check(world.state.collected.is_empty(), "direct route requires no optional collection")
	_check(bool(world.act("repair").ok) and world.state.completed, "upper flowerbed completes the main route")
	var restored := World.new("1-1", world.snapshot())
	_check(restored.state.completed and restored.state.actors.luvie == "f:3:-2", "completed save restores objective and position")
	world = World.new("1-1")
	_check(bool(world.act("grow:root:down").ok), "optional south route grows")
	_walk(world, "f:0:2")
	_check(not world.state.completed, "south exploration never completes the main objective")
	_walk(world, "f:0:0")
	# Companion may be one support behind; lead it to safe fixed ground first.
	_walk(world, "f:-1:0")
	_walk(world, "f:0:0")
	_check(bool(world.act("retract:root").ok), "safe return releases the seed")
	_check(world.undo() and world.state.growth.root == ["g:root:0:1"], "undo restores the retracted route")
	_check(bool(world.act("retract:root").ok) and bool(world.act("grow:root:right").ok), "optional route can switch to main route")
	var stage := Stage.new()
	root.add_child(stage)
	for id: String in ["1-1", "1-2", "1-3", "1-1"]:
		world = World.new(id)
		stage.set_world(world)
		_check(stage.has_presentation_feature("physical_stair_steps"), id + " registered garden uses physical stairs")
		if id != "1-1":
			_check(stage.physical_position(Vector3(3, 0, 0)) == Vector3(3, 0, 0), id + " retains original coordinates")
			for surface: Node3D in stage._surfaces.values():
				_check(surface.authored_terrace == (id == "1-2"), id + " uses its own terrain policy")
	var commands: Array = [{"id":"grow:root:right", "label":"original"}, {"id":"grow:root:down", "label":"original"}]
	var original := commands.duplicate(true)
	var context := Interaction.context(world, commands, {"grow:root:right":{"available":true}, "grow:root:down":{"available":false,"reason":"blocked"}}, Vector3.ZERO, stage.tile_position, Profiles.for_level("1-1"))
	_check(commands == original, "label customization never mutates domain commands")
	_check(not context.choices[0].disabled and context.choices[1].disabled and context.choices[1].reason == "blocked", "availability and denial reason remain domain-owned")
	_check(Interaction.context(world, commands, {}, Vector3(100,0,100), stage.tile_position).is_empty(), "out-of-range interactions remain hidden")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"first-garden-contract", "checks":checks, "passed":failures.is_empty(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
