extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var original: Dictionary
	for entry: Dictionary in data.cases:
		if entry.name == "authored/3-4": original = entry
	var high := World.new("3-4", original.steps[54].snapshot)
	var low := World.new("3-4", original.steps[55].snapshot)
	for pair: Array in [[low, high], [high, low]]:
		stage.set_world(pair[0])
		var before: Dictionary = pair[0].snapshot()
		var after: Dictionary = pair[1].snapshot()
		var surfaces: Array = pair[1].tiles()
		for p: float in [0.0, .25, .5, .999, 1.0]:
			stage.set_motion(before, after, p, "valve:lift")
			var lift: Node3D = stage._props_nodes["mark:lift"]
			var frame: Node3D = lift.get_node("GuardianLiftFrame")
			_check(frame.find_children("*", "CollisionObject3D", true, false).is_empty(), "lift dressing adds no collision or walkable support")
			_check(frame.find_children("*", "Label3D", true, false).is_empty(), "lift expresses mechanism without text plaques")
			for guide: Node in frame.get_children():
				if not guide.has_node("ShoreAnchoredGuide"): continue
				var fixed: Node3D = guide.get_node("ShoreAnchoredGuide")
				var anchor: MeshInstance3D = fixed.get_node("StoneWallAnchor")
				_check(is_equal_approx(anchor.global_position.y, .96), "guide anchor stays fixed through ascent/descent")
				var shore: Dictionary = stage._tile_map[str(fixed.get_meta("anchor_tile"))]
				var bank: Vector3 = stage.tile_position(shore)
				_check(anchor.global_position.x > bank.x-.5 and absf(anchor.global_position.z-bank.z)<.5 and anchor.global_position.y<bank.y and anchor.global_position.y>bank.y-.65, "guide anchor actually enters the permanent high-bank wall")
				_check(is_equal_approx(fixed.get_node("HangingRail").global_position.y,.375), "guide rail remains attached to shore, not rotating neighboring garden")
				_check(is_equal_approx(guide.get_node("MovingCollar").global_position.y,lift.global_position.y-.20), "collar stays attached to actual moving slab")
			_check(stage.world.tiles() == surfaces, "decorative lift structure preserves destination support topology")
		stage.clear_motion()
		_check(pair[0].snapshot() == before and pair[1].snapshot() == after, "motion presentation never changes saved state")
	var ready := World.new("3-4", original.steps[94].snapshot)
	stage.set_world(ready)
	var core: Dictionary = stage._tile_map["f:-4:0"]
	var hero: Vector3 = stage.actor_rest_position(core,"luvie")
	var buddy: Vector3 = stage.actor_rest_position(core,"buddy")
	_check(stage.prop_point_clear(hero,"luvie") and stage.prop_point_clear(buddy,"buddy"), "both reunion stances are clear of the planter hard base")
	var screen_axis := Vector3(1,0,-1).normalized()
	_check(absf((hero-buddy).dot(screen_axis)) > .45, "actual resting poses separate along camera horizontal axis")
	var initial := World.new("3-4")
	stage.set_world(initial)
	var revision: int = stage.prop_obstacle_revision
	var props: int = stage._props_nodes["mark:lift"].get_instance_id()
	initial.state.active = "buddy"
	stage.refresh_world(initial)
	_check(stage.prop_obstacle_revision == revision and stage._props_nodes["mark:lift"].get_instance_id() == props, "flow sync does not rebuild props when actor selection changes")
	stage.set_world(World.new("3-3"))
	_check(not stage._props_nodes["mark:lift"].has_node("GuardianLiftFrame"), "accepted other-level lift remains unchanged")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-guardian-lift-frame","checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
