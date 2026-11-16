extends SceneTree
## Prepared art/footprint states. Full physical routes and GPU pixels are separate.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Props = preload("res://presentation/native/mechanism_props.gd")
const Guardian = preload("res://presentation/native/guardian_dressing.gd")
const Natural = preload("res://presentation/native/symbiosis_dressing.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Array = []
var stage: Node

func _initialize() -> void: _run.call_deferred()
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func _inspect(world: RefCounted) -> void:
	var snapshot: Dictionary = world.snapshot().duplicate(true)
	var tiles: Array = world.tiles().duplicate(true)
	stage.set_world(world)
	_check(stage._props.find_children("*","Label3D",true,false).is_empty(),"3-4 scene has no text plaques")
	for id: String in ["inner","water","lift","light"]:
		var root: Node3D = stage._props_nodes["mark:"+id]
		var base: MeshInstance3D = root.get_node("InstrumentBase")
		var cylinder := base.mesh as CylinderMesh
		_check(is_equal_approx(cylinder.top_radius,.19) and is_equal_approx(cylinder.bottom_radius,.1995) and is_equal_approx(cylinder.height,.025),id+" original tapered radii retained with low seat below painted stone foot")
		var offset := Vector3(.28,0,-.04 if id=="light" else 0.0)
		if id!="lift": offset=offset.rotated(Vector3.UP,-float(world.state.turns[id])*PI/2)
		_check(base.position.is_equal_approx(offset+Vector3(0,.0125,0)),id+" original module-local placement and ground floor retained")
		var entries: Array = stage._prop_obstacles.filter(func(e: Dictionary) -> bool: return str(e.id)=="mark:"+id+"/InstrumentBase")
		_check(entries.size()==1,id+" has one existing hard base")
		if entries.size()==1:
			_check(entries[0].rect.size.is_equal_approx(Vector2(.399,.399)),id+" original tapered-base navigation footprint unchanged")
			_check(is_equal_approx(float(entries[0].floor),root.global_position.y) and is_equal_approx(float(entries[0].top),root.global_position.y+.41),id+" original hard collision floor and top unchanged")
		var asset := "lift" if id=="lift" else "wheel"
		var sprite: Sprite3D = root.get_node("NaturalLift" if id=="lift" else "NaturalWheel")
		var spec: Dictionary = Natural.asset_spec(asset)
		var crop: Array = spec.atlasAlpha8
		var foot: Array = spec.footPixel
		var body := Vector2(float(spec.opaqueAlpha128[2]),float(spec.opaqueAlpha128[3]))*sprite.pixel_size
		_check(is_equal_approx(body.y,.62) and body.x<=.38,id+" painted body fits old controller envelope")
		_check(sprite.visible == (id != "light"),id+" light replaces unrelated wheel with a real source while other controls remain visible")
		var error := Vector2(float(foot[0])-float(crop[0])-sprite.texture.get_width()*.5+sprite.offset.x,sprite.texture.get_height()*.5-(float(foot[1])-float(crop[1]))+sprite.offset.y)*sprite.pixel_size
		_check(error.length()<.00001 and not sprite.no_depth_test,id+" natural asset retains registered foot and real depth")
		measurements.append({"id":id,"turn":world.state.turns.get(id,0),"body":[body.x,body.y],"baseSpan":[.399,.399],"visibleSeatHeight":.025,"hardHeight":.41})
	_check(stage._props_nodes["mark:inner"].has_node("GardenDriveGear"),"inner has attached drive axle and teeth")
	_check(stage._props_nodes["mark:water"].has_node("WaterOutletTrough"),"water has actual recessed outlet")
	_check(stage._props_nodes.has("guardian:emitter") and stage._props_nodes["guardian:emitter"].has_node("TurningLamp/LampMouth"),"light has a real glowing aperture at the source")
	_check(stage._props_nodes["mark:lift"].has_node("GuardianLiftFloat"),"lift has physical floating marker")
	var slot: Node3D = stage._props_nodes["mark:highslot"]
	_check(slot.has_node("MirrorSocketRecess") and slot.has_node("MirrorSocketClampLeft") and slot.has_node("MirrorSocketClampRight"),"slot is a shallow socket with attached clamps")
	for child: Node in slot.get_children():
		if not child is MeshInstance3D: continue
		var bounds: AABB = child.mesh.get_aabb()
		for corner in range(8):
			var point: Vector3 = child.transform*bounds.get_endpoint(corner)
			_check(absf(point.x)<=.26001 and absf(point.z)<=.26001 and point.y>=-.00001 and point.y<=.04001,"slot geometry remains within old .52m/.04m envelope")
	_check(not stage._prop_obstacles.any(func(e: Dictionary) -> bool: return str(e.id).begins_with("mark:highslot")),"visual socket adds no hard obstacle or walk restriction")
	_check(world.snapshot()==snapshot and world.tiles()==tiles,"art does not mutate rules or support topology")
	_check(is_equal_approx(stage.get_actor_body("luvie").get_node("Visual/Art").pixel_size,.00625) and is_equal_approx(stage.get_actor_body("buddy").get_node("Visual/Art").pixel_size,.0062),"both actor sizes unchanged")

func _motion() -> void:
	var before := World.new("3-4")
	var after := before.fork(before.snapshot())
	for id: String in ["inner","water","light","lift"]: after.state.turns[id]=1
	stage.set_world(after)
	var values: Array[Vector3] = []
	for progress: float in [0.0,.5,1.0,.5,0.0]:
		Props.update_motion(stage,before,after,progress)
		var lift: Node3D = stage._props_nodes["mark:lift"]
		values.append(lift.get_node("GuardianLiftFloat").position)
		_check(is_equal_approx(float(lift.get_meta("height_step")),progress),"lift float follows actual interpolated height")
		for pair: Array in [["inner","GardenDriveGear"],["water","WaterOutletTrough"]]:
			var root: Node3D=stage._props_nodes["mark:"+str(pair[0])]
			var offset:=Vector3(.28,0,-.04 if pair[0]=="light" else 0.0).rotated(Vector3.UP,-progress*PI/2)
			_check(root.get_node("InstrumentBase").position.is_equal_approx(offset+Vector3(0,.0125,0)),str(pair[0])+" base follows same rotating module offset")
			_check(root.get_node(str(pair[1])).position.is_equal_approx(offset) and is_equal_approx(root.get_node(str(pair[1])).rotation.y,-progress*PI/2),str(pair[0])+" attached mechanism translates and rotates with module")
		var lamp: Node3D = stage._props_nodes["guardian:emitter"]
		_check(is_equal_approx(lamp.get_node("TurningLamp").rotation.y,-progress*PI/2),"source lamp turns with its actual module")
		_check(lamp.get_node("TurningLamp/LampMouth").global_position.is_equal_approx(Vector3(8,1.67,4)),"source aperture stays at real optical centre during motion")
	_check(values[0].is_equal_approx(values[4]) and values[1].is_equal_approx(values[3]) and values[2].y>values[1].y and values[1].y>values[0].y,"lift motion is reversible without accumulated drift")

func _run() -> void:
	stage=Stage.new()
	root.add_child(stage)
	await process_frame
	for turn in range(4):
		var world := World.new("3-4")
		for id: String in ["inner","water","light"]: world.state.turns[id]=turn
		world.state.turns.lift=turn%2
		if turn%2==1: world.state.items.mirror.tile="f:8:0"
		_inspect(world)
		_check(str(stage._props_nodes["mark:highslot"].get_meta("mechanism_state"))==("occupied" if turn%2 else "empty"),"socket identity follows actual mirror placement")
	_motion()
	stage.set_world(World.new("1-3"))
	_check(stage._props_nodes["mark:turn"].has_node("MotionKind"),"other garden controller remains unchanged")
	stage.set_world(World.new("3-3"))
	_check(is_equal_approx(stage._props_nodes["mark:turn"].get_node("NaturalWheel").pixel_size,float(Natural.asset_spec("wheel").pixelSize)),"3-3 accepted natural size remains unchanged")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-guardian-props","checks":checks,"failures":failures,"measurements":measurements,"passed":failures.is_empty(),"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
