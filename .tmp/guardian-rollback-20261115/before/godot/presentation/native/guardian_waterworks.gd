extends RefCounted
## Fixed spring -> short stone channel -> waterwheel -> existing lift guide.
## Visual only: never adds support, rotates the bank or mutates game state.
const WATER_SHADER = preload("res://presentation/native/guardian_channel_water.gdshader")
const STONE := Color("aaa491")
const DARK_STONE := Color("777b6e")
const WOOD := Color("887052")
const IRON := Color("656d64")

static func build(stage: Node) -> void:
	if str(stage.world.level.id) != "3-4": return
	var root := Node3D.new()
	root.name = "GuardianWaterworks"
	root.set_meta("visual_only", true)
	root.set_meta("water_design", 2)
	root.set_meta("water_materials", [])
	stage._effects.add_child(root)
	_basin(stage, root, "SpringPool", Vector3(4.02,0,3.78), Vector2(.68,.54), true)
	var points: Array[Vector3] = [Vector3(4.10,.034,3.55),Vector3(4.20,.030,3.30),Vector3(4.28,.026,3.00),Vector3(4.43,.023,2.78),Vector3(4.64,.020,2.50),Vector3(4.70,.018,2.27)]
	_channel(stage,root,points)
	_sluice(stage,root)
	_basin(stage, root, "WheelBasin", Vector3(4.72,0,2.08), Vector2(.62,.70), false)
	var fall := MeshInstance3D.new()
	fall.name = "SluiceFall"
	var sheet := QuadMesh.new()
	sheet.size = Vector2(.12,.065)
	fall.mesh = sheet
	fall.position = Vector3(4.70,.017,2.29)
	fall.rotation.x = -.22
	fall.material_override = _water_material(root,1.0)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fall)
	_wheel(stage,root)
	root.set_meta("bank_bounds",Rect2(Vector2(2.5,1.5),Vector2(3,3)))
	update(stage,stage.world,stage.world,1.0)

static func _stone(stage: Node, parent: Node3D, at: Vector3, size: Vector3, index: int) -> MeshInstance3D:
	var mesh: MeshInstance3D=stage._sphere(parent,1.0,at,STONE.lerp(DARK_STONE,float(index%4)*.095))
	mesh.name="BankStone"+str(parent.get_child_count())
	mesh.scale=size
	mesh.rotation.y=float(index)*1.41
	var material: StandardMaterial3D=mesh.material_override
	material.roughness=.94
	if index%4==0:
		var moss: MeshInstance3D=stage._sphere(parent,1.0,at+Vector3(0,size.y*.78,0),Color("84916e"))
		moss.name="SoftMoss"+str(index)
		moss.scale=Vector3(size.x*.61,size.y*.19,size.z*.59)
		moss.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

static func _basin(stage: Node,parent: Node3D,label: String,at: Vector3,size: Vector2,source: bool) -> void:
	var basin:=Node3D.new()
	basin.name=label
	basin.position=at
	basin.set_meta("inset_footprint",size)
	parent.add_child(basin)
	var bottom: MeshInstance3D=stage._sphere(basin,1.0,Vector3(0,-.040,0),Color("656f65"))
	bottom.name="RecessedBed"
	bottom.scale=Vector3(size.x*.45,.050,size.y*.43)
	for index in range(12):
		# A real opening joins the spring/channel and channel/receiving pool.
		if (source and index==10) or (not source and index==3): continue
		var angle:=float(index)*TAU/12+.065*sin(index*2.7)
		var rough:=1.0+.045*sin(float(index)*2.3)
		var point:=Vector3(cos(angle)*size.x*.42*rough,.015,sin(angle)*size.y*.40*rough)
		var stone:=_stone(stage,basin,point,Vector3(.043+.006*sin(index*1.7),.028+.005*cos(index*2.1),.085+.014*sin(index*1.3)),index)
		stone.rotation.y=-angle+.12*sin(index*1.9)
	var water:=MeshInstance3D.new()
	water.name="StoredWater"
	water.mesh=_water_disc()
	water.position.y=.019
	water.scale=Vector3(size.x*.76,1,size.y*.71)
	water.material_override=_water_material(parent,0.0,true)
	water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	basin.add_child(water)
	if source:
		_stone(stage,basin,Vector3(-.12,.08,.10),Vector3(.13,.12,.10),19)
		_stone(stage,basin,Vector3(-.02,.045,.17),Vector3(.095,.075,.065),20)

static func _channel(stage: Node,root: Node3D,points: Array[Vector3]) -> void:
	var channel:=Node3D.new()
	channel.name="StoneChannel"
	root.add_child(channel)
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var uvs:=PackedVector2Array()
	var distance:=0.0
	for segment in range(points.size()-1):
		var a: Vector3=points[segment]
		var b: Vector3=points[segment+1]
		var direction: Vector3=(b-a).normalized()
		var side:=Vector3(-direction.z,0,direction.x).normalized()*.074
		var length:=a.distance_to(b)
		var face: Array[Vector3]=[a-side,b-side,b+side,a-side,b+side,a+side]
		vertices.append_array(PackedVector3Array(face))
		for unused in range(6): normals.append(Vector3.UP)
		uvs.append_array(PackedVector2Array([Vector2(0,distance),Vector2(0,distance+length),Vector2(1,distance+length),Vector2(0,distance),Vector2(1,distance+length),Vector2(1,distance)]))
		var bed: MeshInstance3D=stage._box(channel,Vector3(.17,.025,length+.035),a.lerp(b,.5)-Vector3(0,.021,0),Color("6f796b"))
		bed.rotation.y=atan2(direction.x,direction.z)
		bed.name="SunkenChannelBed"+str(segment)
		var count:=maxi(2,ceili(length/.17))
		for part in range(count):
			for edge in [-1.0,1.0]:
				var id:=segment*count+part+(19 if edge>0 else 0)
				var fraction: float=clampf((float(part)+.5+.15*sin(id*2.1))/count,0,1)
				var center:=a.lerp(b,fraction)
				var offset: Vector3=side.normalized()*(.108+.004*sin(id*2.0))*edge
				var stone:=_stone(stage,channel,center+offset,Vector3(.032+.004*sin(id*1.7),.022+.004*cos(id*2.2),.074+.012*sin(id*1.3)),id)
				stone.rotation.y=atan2(direction.x,direction.z)+.13*sin(id*2.6)
		distance+=length
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var water:=MeshInstance3D.new()
	water.name="RunningWater"
	water.mesh=mesh
	water.material_override=_water_material(root,.22)
	water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	channel.add_child(water)

static func _sluice(stage: Node,root: Node3D) -> void:
	var sluice:=Node3D.new()
	sluice.name="SluiceGate"
	sluice.position=Vector3(4.28,0,3.00)
	sluice.set_meta("hard_footprint",Vector2(.34,.22))
	root.add_child(sluice)
	for side in [-1.0,1.0]:
		_stone(stage,sluice,Vector3(side*.13,.026,0),Vector3(.040,.045,.040),3)
		stage._box(sluice,Vector3(.035,.26,.040),Vector3(side*.13,.15,0),WOOD)
	var gate: MeshInstance3D=stage._box(sluice,Vector3(.22,.11,.032),Vector3(0,.075,0),Color("978362"))
	gate.name="GateBoard"
	var stem: MeshInstance3D=stage._cylinder(sluice,.014,.17,Vector3(0,.22,0),IRON)
	stem.name="GateStem"
	var handle: MeshInstance3D=stage._box(sluice,Vector3(.15,.024,.030),Vector3(0,.31,0),Color("ae9772"))
	handle.name="GateHandle"

static func _link(stage: Node,root: Node3D,label: String,a: Vector3,b: Vector3,radius: float,color: Color) -> MeshInstance3D:
	var link: MeshInstance3D=stage._cylinder(root,radius,a.distance_to(b),a.lerp(b,.5),color)
	link.name=label
	link.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	return link

static func _wheel(stage: Node,root: Node3D) -> void:
	var assembly:=Node3D.new()
	assembly.name="WaterwheelDrive"
	root.add_child(assembly)
	var center:=Vector3(4.72,.245,1.98)
	var rotor:=Node3D.new()
	rotor.name="PaddleWheel"
	rotor.position=center
	assembly.add_child(rotor)
	for side in [-1.0,1.0]:
		var ring:=TorusMesh.new()
		ring.inner_radius=.185
		ring.outer_radius=.220
		var rim: MeshInstance3D=stage._mesh_instance(rotor,ring,WOOD,Vector3(side*.075,0,0))
		rim.rotation.z=PI/2
	for index in range(10):
		var angle:=index*TAU/10
		var at:=Vector3(0,sin(angle)*.204,cos(angle)*.204)
		var paddle: MeshInstance3D=stage._box(rotor,Vector3(.18,.052,.075),at,Color("a58d65"))
		paddle.rotation.x=-angle
		_link(stage,rotor,"Spoke"+str(index),Vector3.ZERO,at*.91,.012,WOOD)
	_link(stage,assembly,"DrivenAxle",center-Vector3(.16,0,0),Vector3(5.27,.245,1.98),.025,IRON)
	for x in [4.55,5.22]:
		_stone(stage,assembly,Vector3(x,.03,1.98),Vector3(.09,.05,.11),5)
		stage._box(assembly,Vector3(.05,.21,.07),Vector3(x,.13,1.98),WOOD)
	var winch: MeshInstance3D=stage._cylinder(assembly,.095,.19,Vector3(5.14,.245,1.98),Color("8b7859"))
	winch.name="LiftWinch"
	winch.rotation.z=PI/2
	# Short bank-to-guide transmission, attached to actual fixed hardware;
	# no dangling cross-map cable, fake bank or walking surface.
	_link(stage,assembly,"GuideTransmission",Vector3(5.27,.245,1.98),Vector3(5.51,-.38,1.28),.037,IRON)
	assembly.set_meta("guide_connection",Vector3(5.51,-.38,1.28))

static func _water_disc() -> ArrayMesh:
	# Explicit radial UVs keep pool ripples concentric rather than using the
	# cylinder cap atlas, where most of the authored ripple was invisible.
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var uvs:=PackedVector2Array()
	for index in range(40):
		var a:=Vector3(cos(index*TAU/40)*.5,0,sin(index*TAU/40)*.5)
		var b:=Vector3(cos((index+1)*TAU/40)*.5,0,sin((index+1)*TAU/40)*.5)
		vertices.append_array(PackedVector3Array([Vector3.ZERO,b,a]))
		normals.append_array(PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP]))
		uvs.append_array(PackedVector2Array([Vector2(.5,.5),Vector2(b.x+.5,b.z+.5),Vector2(a.x+.5,a.z+.5)]))
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func _water_material(root: Node3D,flow: float,pool: bool=false) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=WATER_SHADER
	material.set_shader_parameter("flow_speed",flow)
	material.set_shader_parameter("pool_surface",pool)
	var materials: Array=root.get_meta("water_materials")
	materials.append(material)
	root.set_meta("water_materials",materials)
	return material

static func update(stage: Node,before: RefCounted,after: RefCounted,eased: float) -> void:
	if str(after.level.id)!="3-4": return
	var root: Node3D=stage._effects.get_node_or_null("GuardianWaterworks")
	if root==null: return
	var progress:=clampf(eased,0,1)
	var was_open:=int(before.state.turns.water)%2==1
	var is_open:=int(after.state.turns.water)%2==1
	var gate_step:=lerpf(float(was_open),float(is_open),progress)
	var flowing:=is_open and (was_open or progress>=1.0)
	var stored: bool=after.flag("rain") and (before.flag("rain") or progress>=1.0)
	root.set_meta("water_open",flowing)
	root.set_meta("water_stored",stored)
	root.get_node("StoneChannel/RunningWater").visible=flowing
	root.get_node("SluiceFall").visible=flowing
	root.get_node("WheelBasin/StoredWater").visible=stored
	root.get_node("SluiceGate/GateBoard").position.y=.075+.11*gate_step
	root.get_node("SluiceGate/GateStem").position.y=.22+.11*gate_step
	root.get_node("SluiceGate/GateHandle").position.y=.31+.11*gate_step
	var quiet: bool=stage.settings.get("lowMotion",false)
	var time: float=0.0 if quiet else stage.visual_time*.001
	# stage.visual_time is paused/manual-clock aware. Materials and meshes
	# are cached once; reduced motion fixes the water phase explicitly.
	for material: ShaderMaterial in root.get_meta("water_materials"):
		material.set_shader_parameter("effect_time",time)
	var wheel: Node3D=root.get_node("WaterwheelDrive/PaddleWheel")
	var previous_time: float=root.get_meta("last_visual_time",time)
	var elapsed:=clampf(time-previous_time,0,.05)
	root.set_meta("last_visual_time",time)
	if flowing and not quiet: wheel.rotation.x-=elapsed*.62
	var lift_motion:=lerpf(float(int(before.state.turns.lift)%2),float(int(after.state.turns.lift)%2),progress)
	root.get_node("WaterwheelDrive/LiftWinch").rotation.x=lift_motion*TAU*1.5
