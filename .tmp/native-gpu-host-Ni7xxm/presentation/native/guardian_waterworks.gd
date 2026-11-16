extends RefCounted
## One visible hydraulic chain for 3-4. A rotating, open trough docks with
## the permanent west bank; closed pipes follow real banks to the lift.
## These are low inset channels / sidewall pipes, never walking supports.
const CHANNEL := Color("7f998b")
const WATER := Color("91c9ca")
const PIPE := Color("829481")

static func build(stage: Node) -> void:
	if str(stage.world.level.id) != "3-4": return
	var root := Node3D.new()
	root.name = "GuardianWaterworks"
	root.set_meta("visual_only", true)
	stage._effects.add_child(root)
	var rotor := Node3D.new()
	rotor.name = "RotatingTrough"
	rotor.position = stage.tile_position(stage.world.module_point("water", [0,0]))
	root.add_child(rotor)
	# The two original L arms now visibly carry water. The sole outlet lies
	# at local +Z; only turn 1 brings it to the permanent west-bank inlet.
	_bowl(stage, rotor, "SourceBowl", Vector3(-1.85,0,-.15))
	_trough(stage, rotor, "SourceNeck", Vector3(-1.85,0,-.15), Vector3(-1.85,0,0), .14)
	_trough(stage, rotor, "InletArm", Vector3(-1.85,0,0), Vector3(0,0,0), .16)
	_trough(stage, rotor, "OutletArm", Vector3(0,0,0), Vector3(0,0,2.43), .16)
	var spout: MeshInstance3D = stage._box(rotor, Vector3(.20,.025,.13), Vector3(0,.017,2.405), Color("b0b397"))
	spout.name = "DockingSpout"
	root.set_meta("local_outlet",Vector3(0,.04,2.43))
	root.set_meta("fixed_inlet",Vector3(-2.60,.025,8))
	# This receiver is recessed into an existing permanent small shore tile.
	# It never blocks the companion's west/east approach through the tile.
	var reservoir := _reservoir(stage, root, "WestReservoir", Vector3(-3.05,0,8.12), Vector2(.52,.34))
	reservoir.set_meta("support_id","f:-3:8")
	_trough(stage, root, "FixedInlet", Vector3(-2.60,0,8), Vector3(-2.94,0,8.12), .16)
	# Water only crosses the actual short spout/inlet gap, not the void to
	# a remote lift. Closed narrow pipes are mounted below the bank edges.
	var transfer := Node3D.new()
	transfer.name = "DockedWater"
	root.add_child(transfer)
	_pipe(stage,transfer,"ShortFlow",Vector3(-2.43,.04,8),Vector3(-2.60,.025,8),.035,WATER)
	var bank_pipe := Node3D.new()
	bank_pipe.name = "PermanentBankPipe"
	root.add_child(bank_pipe)
	_polyline(stage,bank_pipe,[Vector3(-3.05,-.035,8.12),Vector3(-3.05,-.10,8.48),Vector3(-4.48,-.10,8.48),Vector3(-4.48,-.10,.10)])
	var root_pipe := Node3D.new()
	root_pipe.name = "RootBankPipe"
	root.add_child(root_pipe)
	# These banks only exist once the root bridge has really connected.
	_polyline(stage,root_pipe,[Vector3(-4.48,-.10,.10),Vector3(-4.48,-.10,-4.48),Vector3(4.48,-.10,-4.48),Vector3(4.48,-.10,-1.53)])
	var lift := Node3D.new()
	lift.name = "LiftReservoirAssembly"
	lift.position = stage.tile_position(stage.world.module_point("lift",[0,0]))
	root.add_child(lift)
	var lift_reservoir := _reservoir(stage,lift,"LiftReservoir",Vector3(.70,0,-1.20),Vector2(.40,.34))
	lift_reservoir.set_meta("support_id","m:lift:1:-1")
	var feed := Node3D.new()
	feed.name = "FlexibleDockFeed"
	root.add_child(feed)
	for index in range(3):
		var part: MeshInstance3D = stage._cylinder(feed,.038,1.0,Vector3.ZERO,PIPE)
		part.name = "Hose"+str(index)
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("lift_low",stage.tile_position({"x":4,"z":0,"h":0}))
	root.set_meta("lift_high",stage.tile_position({"x":4,"z":0,"h":2}))
	update(stage,stage.world,stage.world,1.0)

static func _bowl(stage: Node, root: Node3D, label: String, at: Vector3) -> void:
	var bowl := Node3D.new()
	bowl.name = label
	bowl.position = at
	root.add_child(bowl)
	var rim := TorusMesh.new()
	rim.inner_radius = .19
	rim.outer_radius = .23
	stage._mesh_instance(bowl,rim,Color("9aaa8b"),Vector3(0,.025,0))
	stage._cylinder(bowl,.19,.012,Vector3(0,.012,0),Color("617c74"))
	var water: MeshInstance3D = stage._cylinder(bowl,.18,.005,Vector3(0,.022,0),WATER)
	water.name = "StoredSourceWater"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _trough(stage: Node, parent: Node3D, label: String, a: Vector3, b: Vector3, width: float) -> void:
	var trough := Node3D.new()
	trough.name = label
	trough.position = a.lerp(b,.5)
	trough.rotation.y = atan2(b.x-a.x,b.z-a.z)
	parent.add_child(trough)
	var length := a.distance_to(b)
	stage._box(trough,Vector3(width,.012,length),Vector3(0,.009,0),Color("62796c"))
	for side: float in [-1.0,1.0]:
		stage._box(trough,Vector3(.025,.040,length),Vector3(side*(width-.025)*.5,.025,0),CHANNEL)
	var water: MeshInstance3D = stage._box(trough,Vector3(width-.055,.004,length),Vector3(0,.020,0),WATER)
	water.name = "WaterSurface"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _reservoir(stage: Node, parent: Node3D, label: String, at: Vector3, size: Vector2) -> Node3D:
	var reservoir := Node3D.new()
	reservoir.name=label
	reservoir.position=at
	reservoir.set_meta("inset_footprint",size)
	parent.add_child(reservoir)
	stage._box(reservoir,Vector3(size.x,.012,size.y),Vector3(0,.008,0),Color("617469"))
	for side: float in [-1.0,1.0]:
		stage._box(reservoir,Vector3(size.x,.04,.026),Vector3(0,.026,side*(size.y-.026)*.5),Color("a2ae91"))
		stage._box(reservoir,Vector3(.026,.04,size.y),Vector3(side*(size.x-.026)*.5,.026,0),Color("a2ae91"))
	var water: MeshInstance3D = stage._box(reservoir,Vector3(size.x-.06,.004,size.y-.06),Vector3(0,.026,0),WATER)
	water.name="StoredWater"
	water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return reservoir

static func _pipe(stage: Node, parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var pipe: MeshInstance3D=stage._cylinder(parent,radius,a.distance_to(b),a.lerp(b,.5),color)
	pipe.name=label
	pipe.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	pipe.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pipe

static func _polyline(stage: Node, parent: Node3D, points: Array[Vector3]) -> void:
	for index in range(points.size()-1):
		_pipe(stage,parent,"MountedPipe"+str(index),points[index],points[index+1],.038,PIPE)
		var joint: MeshInstance3D=stage._sphere(parent,.053,points[index],Color("a3af93"))
		joint.name="PipeJoint"+str(index)
		joint.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func update(stage: Node, before: RefCounted, after: RefCounted, eased: float) -> void:
	if str(after.level.id)!="3-4": return
	var root: Node3D=stage._effects.get_node_or_null("GuardianWaterworks")
	if root==null: return
	var progress:=clampf(eased,0,1)
	var start:=int(before.state.turns.water)
	var delta:=posmod(int(after.state.turns.water)-start,4)
	root.get_node("RotatingTrough").rotation.y=-(float(start)+float(delta if delta<=2 else delta-4)*progress)*PI/2
	var docked:=int(after.state.turns.water)==1 and (int(before.state.turns.water)==1 or progress>=1.0)
	root.get_node("DockedWater").visible=docked
	var filled: bool=after.flag("rain") and (before.flag("rain") or progress>=1.0)
	root.set_meta("water_docked",docked)
	root.set_meta("water_stored",filled)
	root.get_node("WestReservoir/StoredWater").visible=filled
	root.get_node("LiftReservoirAssembly/LiftReservoir/StoredWater").visible=filled
	root.get_node("FixedInlet/WaterSurface").visible=docked or filled
	var roots_exist: bool=after.flag("root") and (before.flag("root") or progress>=1.0)
	root.get_node("RootBankPipe").visible=roots_exist
	root.get_node("FlexibleDockFeed").visible=roots_exist
	var lift_step:=lerpf(float(int(before.state.turns.lift)%2),float(int(after.state.turns.lift)%2),progress)
	var lift_position:=Vector3(root.get_meta("lift_low")).lerp(Vector3(root.get_meta("lift_high")),lift_step)
	root.get_node("LiftReservoirAssembly").position=lift_position
	var points: Array[Vector3]=[Vector3(4.48,-.10,-1.53),Vector3(4.48,-.30,-1.53),Vector3(4.70,lift_position.y-.30,-1.30),Vector3(4.70,lift_position.y-.035,-1.20)]
	for index in range(3):
		var part: MeshInstance3D=root.get_node("FlexibleDockFeed/Hose"+str(index))
		var direction:=points[index+1]-points[index]
		part.position=points[index].lerp(points[index+1],.5)
		part.scale=Vector3(1,direction.length(),1)
		part.quaternion=Quaternion(Vector3.UP,direction.normalized())
