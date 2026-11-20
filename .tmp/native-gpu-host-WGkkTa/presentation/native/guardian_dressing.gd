extends RefCounted
## Final-garden controls reuse painted wood/stone, with actual mechanical parts.
## Logical marks, existing hard bases and passenger stances remain unchanged.
const Natural = preload("res://presentation/native/symbiosis_dressing.gd")
const LiftFrame = preload("res://presentation/native/guardian_lift_frame.gd")
const Flow = preload("res://application/guardian_flow_guidance.gd")
const ART_SCALE := .62 / .9
const BASE_RADIUS := .19
const BASE_HEIGHT := .025
const Optics = preload("res://presentation/native/guardian_optics.gd")

static func build_core(stage: Node, root: Node3D) -> void:
	if str(stage.world.level.id) == "3-4": Optics.build_core(stage, root)

static func build_mark(stage: Node, root: Node3D, mark: Dictionary) -> bool:
	if str(stage.world.level.id) != "3-4": return false
	var id := str(mark.id)
	if id == "highslot":
		_slot(stage, root)
		return true
	if id not in ["inner", "water", "lift", "light"]: return false
	var local_offset := Vector3(.28,0,-.04 if id == "light" else 0.0)
	var offset := local_offset
	if id != "lift":
		offset = offset.rotated(Vector3.UP,-float(stage.world.state.turns.get(id,0))*PI/2)
		root.set_meta("instrument_local_offset",local_offset)
		root.set_meta("instrument_module",id)
		root.set_meta("instrument_offset",offset)
	# The painted pedestal owns the visible stone foot. Keep only a low
	# physical seat, with the same radius/floor used by the existing obstacle.
	var base: MeshInstance3D = stage._cylinder(root,BASE_RADIUS,BASE_HEIGHT,offset+Vector3(0,BASE_HEIGHT*.5,0),Color("79816a"))
	base.name = "InstrumentBase"
	var asset := "lift" if id == "lift" else "wheel"
	var sprite: Sprite3D = Natural._art(stage,root,asset,offset+Vector3(0,BASE_HEIGHT,0),"NaturalLift" if id == "lift" else "NaturalWheel")
	sprite.pixel_size *= ART_SCALE
	sprite.set_meta("visible_body_size",Vector2(Natural.asset_spec(asset).visibleWorldSize[0],Natural.asset_spec(asset).visibleWorldSize[1])*ART_SCALE)
	root.set_meta("guardian_role",id)
	root.set_meta("motion_kind","lift" if id == "lift" else "rotate")
	match id:
		"inner": _drive(stage,root,offset)
		"water": _water_outlet(stage,root,offset)
		"light": Optics.build_emitter(stage,root)
		"lift":
			LiftFrame.build(stage, root)
			var float_node: MeshInstance3D = stage._sphere(root,.025*ART_SCALE,Vector3.ZERO,Color("e5b764"))
			float_node.name = "GuardianLiftFloat"
			float_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.set_meta("guardian_lift_anchor",offset+Vector3(0,BASE_HEIGHT,0))
			_set_float(root,float(int(stage.world.state.turns.get("lift",0))%2))
	if id != "lift":
		_set_attachment_turn(root,-float(stage.world.state.turns.get(id,0))*PI/2)
	return true

static func _drive(stage: Node, root: Node3D, offset: Vector3) -> void:
	var drive := Node3D.new()
	drive.name = "GardenDriveGear"
	drive.set_meta("guardian_rotating_attachment",true)
	drive.position = offset
	root.add_child(drive)
	var axle: MeshInstance3D = stage._cylinder(drive,.027,.28,Vector3(0,.075,0),Color("92744d"))
	axle.rotation.z = PI/2
	for index in range(8):
		var angle := float(index)*TAU/8
		var tooth: MeshInstance3D = stage._box(drive,Vector3(.045,.025,.035),Vector3(cos(angle)*.13,.035,sin(angle)*.13),Color("8d7854"))
		tooth.rotation.y = -angle

static func _water_outlet(stage: Node, root: Node3D, offset: Vector3) -> void:
	var outlet := Node3D.new()
	outlet.name = "WaterOutletTrough"
	outlet.set_meta("guardian_rotating_attachment",true)
	outlet.position = offset
	root.add_child(outlet)
	# A real shallow U-channel attaches to the foot, not a water-symbol plaque.
	stage._box(outlet,Vector3(.18,.018,.09),Vector3(-.055,.035,0),Color("756950"))
	for side in [-1,1]:
		stage._box(outlet,Vector3(.18,.04,.018),Vector3(-.055,.048,side*.047),Color("a29470"))
	stage._box(outlet,Vector3(.165,.005,.065),Vector3(-.055,.047,0),Color("94c9c2"))
	var collar: MeshInstance3D = stage._cylinder(outlet,.035,.05,Vector3(.055,.075,0),Color("9a8057"))
	collar.rotation.z = PI/2

static func _set_float(root: Node3D, step: float) -> void:
	var pixel := Vector2(397,lerpf(1000,480,clampf(step,0,1)))
	var art_point := Natural._pixel_point("lift",Vector3.ZERO,pixel)*ART_SCALE
	root.get_node("GuardianLiftFloat").position = Vector3(root.get_meta("guardian_lift_anchor"))+art_point
	root.set_meta("height_step",step)
	LiftFrame.set_height(root, step)

static func sync_current(stage: Node) -> void:
	if str(stage.world.level.id) != "3-4": return
	# Called on state refresh, never by a per-frame board scan or prop rebuild.
	var flow: Dictionary = Flow.describe(stage.world, stage._tiles)
	var lift: Node3D = stage._props_nodes.get("mark:lift")
	if lift != null:
		var returning := str(flow.target) == "lift" and bool(flow.light_current)
		lift.set_meta("return_requested", returning)
		LiftFrame.set_return_state(lift, returning)

static func update_motion(stage: Node, before: RefCounted, after: RefCounted, progress: float) -> void:
	if str(after.level.id) != "3-4": return
	Optics.update(stage,before,after,progress)
	for id: String in ["inner","water","light"]:
		var controller: Node3D = stage._props_nodes.get("mark:"+id)
		if controller == null: continue
		var start := int(before.state.turns.get(id,0))
		var delta := posmod(int(after.state.turns.get(id,0))-start,4)
		_set_attachment_turn(controller,-(float(start)+float(delta if delta<=2 else delta-4)*clampf(progress,0,1))*PI/2)
	var root: Node3D = stage._props_nodes.get("mark:lift")
	if root == null or not root.has_node("GuardianLiftFloat"): return
	_set_float(root,lerpf(float(int(before.state.turns.get("lift",0))%2),float(int(after.state.turns.get("lift",0))%2),clampf(progress,0,1)))
	LiftFrame.set_return_state(root, bool(root.get_meta("return_requested",false)) and (before.rays()==after.rays() or progress>=1.0))

static func _set_attachment_turn(root: Node3D, angle: float) -> void:
	for child: Node in root.get_children():
		if child is Node3D and child.has_meta("guardian_rotating_attachment"):
			child.rotation.y = angle

static func _slot(stage: Node, root: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = .21
	ring.outer_radius = .25
	var rim: MeshInstance3D = stage._mesh_instance(root,ring,Color("929a7b"),Vector3(0,.02,0))
	rim.name = "MirrorSocketRim"
	var recess: MeshInstance3D = stage._cylinder(root,.21,.008,Vector3(0,.004,0),Color("596d68"))
	recess.name = "MirrorSocketRecess"
	for side in [-1,1]:
		var clamp_node: MeshInstance3D = stage._box(root,Vector3(.035,.035,.13),Vector3(side*.222,.021,0),Color("b9a475"))
		clamp_node.name = "MirrorSocketClampLeft" if side < 0 else "MirrorSocketClampRight"
	var item: Dictionary = stage.world.state.items.get("mirror",{})
	root.set_meta("guardian_role","mirror_socket")
	root.set_meta("mechanism_state","occupied" if str(item.get("tile",""))=="f:8:0" and str(item.get("holder",""))=="" else "empty")
