extends SceneTree
const World = preload("res://core/garden_world.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Props = preload("res://presentation/native/mechanism_props.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	var directions: Array[Vector3] = [Vector3.LEFT,Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK]
	for turn in range(4):
		var world := World.new("3-4")
		world.state.turns.light = turn
		world.state.items.mirror.tile = "f:8:0"
		world.state.items.mirror.angle = 0
		var original: Dictionary = world.snapshot().duplicate(true)
		var tiles: Array = world.tiles().duplicate(true)
		stage.set_world(world)
		var lamp: Node3D = stage._props_nodes["guardian:emitter"]
		var mouth: MeshInstance3D = lamp.get_node("TurningLamp/LampMouth")
		var lens: MeshInstance3D = lamp.get_node("TurningLamp/LampLens")
		_check(mouth.global_position.is_equal_approx(Vector3(8,1.67,4)),"light aperture is on exact domain source at turn "+str(turn))
		_check(mouth.global_basis.y.normalized().is_equal_approx(directions[turn]),"physical lamp mouth faces independently expected cardinal direction")
		_check(lamp.get_meta("emitter_direction").is_equal_approx(directions[turn]),"lamp metadata agrees with physical direction")
		_check((lens.material_override as StandardMaterial3D).emission_enabled,"source glass is luminous in every rotation")
		var ray: Array = world.rays()
		_check(ray.size()>1,"every source rotation has physical emitted light")
		if ray.size()>1:
			var direction := Vector3(float(ray[1].x-ray[0].x),0,float(ray[1].z-ray[0].z))
			_check(direction.is_equal_approx(directions[turn]),"light logic and independently expected emitter normal agree")
		var core: Node3D = stage._props_nodes["mark:core"]
		var receiver: Node3D = core.get_node("GuardianReceivingShoot")
		_check(receiver.get_node("ReceivingFlower").global_position.is_equal_approx(Vector3(-4,1.67,0)),"receiver is rooted on unchanged real optical destination")
		_check(bool(receiver.get_meta("receiver_powered"))==(turn==1),"flower receives only the actual reflected north-source ray")
		_check(lamp.find_children("*","CollisionObject3D",true,false).is_empty() and receiver.find_children("*","CollisionObject3D",true,false).is_empty(),"optical dressing does not add walking surfaces or new hard obstacles")
		_check(lamp.find_children("*","Label3D",true,false).is_empty() and receiver.find_children("*","Label3D",true,false).is_empty(),"source and receiver are physical forms without text plaques")
		_check(world.snapshot()==original and world.tiles()==tiles,"optical construction preserves state and support topology")
	var before := World.new("3-4")
	var after := World.new("3-4")
	before.state.items.mirror.tile="f:8:0"
	after.state.items.mirror.tile="f:8:0"
	after.state.turns.light=1
	stage.set_world(after)
	var receiver: Node3D = stage._props_nodes["mark:core"].get_node("GuardianReceivingShoot")
	for progress: float in [0,.5,.999,1,.5,0]:
		Props.update_motion(stage,before,after,progress)
		var lamp: Node3D = stage._props_nodes["guardian:emitter"]
		_check(lamp.get_node("TurningLamp/LampMouth").global_position.is_equal_approx(Vector3(8,1.67,4)),"controller offset does not pull lamp mouth off optical centre")
		_check(bool(receiver.get_meta("receiver_powered"))==(progress>=1),"receiver never lights before the physical lamp docks")
	stage.set_world(World.new("2-2"))
	_check(not stage._props_nodes.has("guardian:emitter"),"pond source is unchanged")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"guardian-optics-props","checks":checks,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
