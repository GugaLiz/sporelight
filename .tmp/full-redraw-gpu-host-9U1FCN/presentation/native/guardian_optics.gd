extends RefCounted
## Physical source and receiving flower for the guardian's real straight rays.
## Both optical centres stay on the domain axis; the planter is not enlarged.
const SOURCE_HEIGHT := .37
const RECEIVER_HEIGHT := 1.67

static func build_core(stage: Node, root: Node3D) -> void:
	var receiver := Node3D.new()
	receiver.name = "GuardianReceivingShoot"
	receiver.set_meta("soft_foliage", true)
	receiver.set_meta("receiver_rule_point", Vector3(-4, 2, 0))
	receiver.set_meta("stem_root", Vector3(-.10,.23,0))
	root.add_child(receiver)
	var stem: Array[Vector3] = [Vector3(-.10,.23,0), Vector3(-.15,.72,.02), Vector3(-.10,1.20,.015), Vector3(0,RECEIVER_HEIGHT,0)]
	for index in range(stem.size()-1):
		_link(stage, receiver, "ReceivingStem"+str(index), stem[index], stem[index+1], .025, Color("7a925a"))
	var flower := Node3D.new()
	flower.name = "ReceivingFlower"
	flower.position = Vector3(0,RECEIVER_HEIGHT,0)
	flower.set_meta("open_span", .70)
	receiver.add_child(flower)
	for index in range(8):
		var petal := Node3D.new()
		petal.name = "Petal"+str(index)
		petal.rotation.x = index * TAU/8
		flower.add_child(petal)
		var surface: MeshInstance3D = stage._mesh_instance(petal,_petal(),Color("a8b48a"),Vector3.ZERO)
		surface.name = "Fold"
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(surface.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var heart: MeshInstance3D = stage._sphere(receiver,.11,Vector3(.015,RECEIVER_HEIGHT,0),Color("b5bd87"))
	heart.name = "ReceivingHeart"
	heart.scale.x = .45
	heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The paired lower leaves show that the receiver grows from the flowerbed.
	for index in range(2):
		var leaf: MeshInstance3D = stage._mesh_instance(receiver,_petal(),Color("78975d"),stem[index+1])
		leaf.name = "StemLeaf"+str(index)
		leaf.scale = Vector3(.7,.7,.8)
		leaf.rotation.x = -1.0 if index==0 else 1.0
		(leaf.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	set_receiver(root, stage.world.beam_hits(-4,0), bool(stage.world.state.completed))

static func _petal() -> ArrayMesh:
	# Concave pointed petals in the YZ plane face the incoming beam (+X).
	var outline: Array[Vector3] = [Vector3(0,.075,-.025),Vector3(.01,.18,-.095),Vector3(.025,.29,-.065),Vector3(.03,.35,0),Vector3(.025,.29,.065),Vector3(.01,.18,.095),Vector3(0,.075,.025)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in range(outline.size()):
		var a := Vector3(-.018,.20,0)
		var b: Vector3 = outline[index]
		var c: Vector3 = outline[(index+1)%outline.size()]
		vertices.append_array(PackedVector3Array([a,b,c]))
		var normal := (b-a).cross(c-a).normalized()
		normals.append_array(PackedVector3Array([normal,normal,normal]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func _link(stage: Node, parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var mesh: MeshInstance3D = stage._cylinder(parent,radius,a.distance_to(b),a.lerp(b,.5),color)
	mesh.name = label
	mesh.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func set_receiver(root: Node3D, powered: bool, complete: bool) -> void:
	var receiver: Node3D = root.get_node_or_null("GuardianReceivingShoot")
	if receiver == null: return
	var key := str(powered)+":"+str(complete)
	if str(receiver.get_meta("appearance_key","")) == key: return
	receiver.set_meta("appearance_key",key)
	receiver.set_meta("receiver_powered",powered)
	receiver.set_meta("receiver_bloom",complete)
	var heart: MeshInstance3D = receiver.get_node("ReceivingHeart")
	var material: StandardMaterial3D = heart.material_override
	material.albedo_color = Color("f0d88e") if powered else Color("a2af7b")
	material.emission_enabled = powered
	material.emission = Color("ecd8a0")*.23 if powered else Color.BLACK
	for petal: Node3D in receiver.get_node("ReceivingFlower").get_children():
		var surface: MeshInstance3D = petal.get_node("Fold")
		surface.rotation.z = -.04 if complete else -.24 if powered else -.66
		var paint: StandardMaterial3D = surface.material_override
		paint.albedo_color = Color("eedaa8") if complete else Color("d6c68d") if powered else Color("9bab82")
		paint.emission_enabled = powered
		paint.emission = Color("d7bc7d")*.045 if powered else Color.BLACK

static func build_emitter(stage: Node, control: Node3D) -> void:
	# A separate registered module root avoids the control's offset animation.
	var lamp := Node3D.new()
	lamp.name = "GuardianLamp"
	lamp.position = control.position
	lamp.set_meta("tile_id","m:light:0:0")
	stage._props.add_child(lamp)
	stage._props_nodes["guardian:emitter"] = lamp
	var head := Node3D.new()
	head.name = "TurningLamp"
	lamp.add_child(head)
	var stand: MeshInstance3D = stage._cylinder(head,.085,.21,Vector3(.26,.13,-.04),Color("8d977e"))
	stand.name = "LampStem"
	var barrel := CylinderMesh.new()
	barrel.top_radius = .20
	barrel.bottom_radius = .125
	barrel.height = .32
	barrel.radial_segments = 24
	barrel.cap_top = false
	var housing: MeshInstance3D = stage._mesh_instance(head,barrel,Color("8f8263"),Vector3(.16,SOURCE_HEIGHT,0))
	housing.name = "LampHousing"
	housing.rotation.z = PI/2
	var rim := TorusMesh.new()
	rim.inner_radius = .17
	rim.outer_radius = .215
	var lip: MeshInstance3D = stage._mesh_instance(head,rim,Color("d0b27a"),Vector3(0,SOURCE_HEIGHT,0))
	lip.name = "LampMouth"
	lip.rotation.z = PI/2
	var glass := CylinderMesh.new()
	glass.top_radius = .167
	glass.bottom_radius = .167
	glass.height = .012
	glass.radial_segments = 32
	var lens: MeshInstance3D = stage._mesh_instance(head,glass,Color("f5dc9b"),Vector3(.006,SOURCE_HEIGHT,0))
	lens.name = "LampLens"
	lens.rotation.z = PI/2
	var material: StandardMaterial3D = lens.material_override
	material.emission_enabled = true
	material.emission = Color("f5dc9b")*.28
	# The tiny crank belongs to the lamp body, not a second unrelated wheel.
	_link(stage,head,"CrankAxle",Vector3(.25,.30,.07),Vector3(.25,.30,.17),.023,Color("b69b66"))
	var crank := TorusMesh.new()
	crank.inner_radius = .045
	crank.outer_radius = .066
	var wheel: MeshInstance3D = stage._mesh_instance(head,crank,Color("bd9a60"),Vector3(.25,.30,.17))
	wheel.rotation.x = PI/2
	set_emitter_turn(stage,float(stage.world.state.turns.get("light",0)))
	control.get_node("NaturalWheel").visible = false

static func set_emitter_turn(stage: Node, turn: float) -> void:
	var lamp: Node3D = stage._props_nodes.get("guardian:emitter")
	if lamp == null: return
	lamp.get_node("TurningLamp").rotation.y = -turn*PI/2
	lamp.set_meta("emitter_turn",turn)
	lamp.set_meta("emitter_direction",Vector3.LEFT.rotated(Vector3.UP,-turn*PI/2))

static func update(stage: Node, before: RefCounted, after: RefCounted, progress: float) -> void:
	if str(after.level.id) != "3-4": return
	var core: Node3D = stage._props_nodes.get("mark:core")
	if core != null:
		set_receiver(core,after.beam_hits(-4,0) and (before.rays()==after.rays() or progress>=1.0),bool(after.state.completed))
	var start := int(before.state.turns.get("light",0))
	var delta := posmod(int(after.state.turns.get("light",0))-start,4)
	set_emitter_turn(stage,float(start)+float(delta if delta<=2 else delta-4)*clampf(progress,0,1))
