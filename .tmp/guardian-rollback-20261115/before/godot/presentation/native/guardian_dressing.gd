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
	if id=="root":
		_root_shoot(stage,root)
		return true
	if id == "highslot":
		_slot(stage, root)
		return true
	if id in ["liftcall_low", "liftcall_high"]:
		LiftFrame.build_call(stage,root,id=="liftcall_high")
		return true
	if id == "inner": return true
	if id not in ["water", "lift", "light"]: return false
	var offset := Vector3(.04,0,.26) if id=="light" else Vector3(.28,0,0)
	var base: MeshInstance3D = stage._cylinder(root,BASE_RADIUS,BASE_HEIGHT,offset+Vector3(0,BASE_HEIGHT*.5,0),Color("79816a"))
	base.name = "InstrumentBase"
	root.set_meta("guardian_role",id)
	if id=="water":
		# Waterworks owns the actual sluice and moving gate. This existing
		# low foot supplies its shared physical/planner obstacle, once only.
		return true
	if id=="light":
		Optics.build_emitter(stage,root)
		return true
	var sprite: Sprite3D = Natural._art(stage,root,"lift",offset+Vector3(0,BASE_HEIGHT,0),"NaturalLift")
	sprite.pixel_size *= ART_SCALE
	sprite.set_meta("visible_body_size",Vector2(Natural.asset_spec("lift").visibleWorldSize[0],Natural.asset_spec("lift").visibleWorldSize[1])*ART_SCALE)
	root.set_meta("motion_kind","lift")
	LiftFrame.build(stage, root)
	var float_node: MeshInstance3D = stage._sphere(root,.025*ART_SCALE,Vector3.ZERO,Color("e5b764"))
	float_node.name = "GuardianLiftFloat"
	float_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("guardian_lift_anchor",offset+Vector3(0,BASE_HEIGHT,0))
	_set_float(root,float(int(stage.world.state.turns.get("lift",0))%2))
	return true

static func _root_shoot(stage: Node, root: Node3D) -> void:
	root.set_meta("guardian_role","root_shoot")
	root.set_meta("soft_foliage",true)
	var shoot := Node3D.new()
	shoot.name = "RootFrontierShoot"
	shoot.position = Vector3(.16,.012,.16)
	root.add_child(shoot)
	# A low living root with leaves, not a second planter. Its roots point
	# east toward the existing seedbed exit and the three real gap sockets.
	for side: float in [-1,0,1]:
		var a := Vector3(-.12,.018,side*.07)
		var b := Vector3(.10,.022,side*.09)
		var c := Vector3(.30,.012,side*.11)
		Optics._link(stage,shoot,"RootBack"+str(side),a,b,.018,Color("9a8b64"))
		Optics._link(stage,shoot,"RootTip"+str(side),b,c,.012,Color("b5a37b"))
	Optics._link(stage,shoot,"LivingStem",Vector3(0,.02,0),Vector3(.035,.21,0),.019,Color("78945d"))
	for side: float in [-1,1]:
		var leaf: MeshInstance3D = stage._sphere(shoot,.10,Vector3(side*.07,.15,0),Color("93ab72"))
		leaf.name = "PairedLeaf"+str(side)
		leaf.scale = Vector3(1.0,.36,.55)
		leaf.rotation.z=side*.50
		leaf.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
	var step := lerpf(float(int(before.state.turns.get("lift",0))%2),float(int(after.state.turns.get("lift",0))%2),clampf(progress,0,1))
	for id: String in ["liftcall_low","liftcall_high"]:
		var call_root: Node3D = stage._props_nodes.get("mark:"+id)
		if call_root != null: LiftFrame.set_call_height(call_root,step)
	var root: Node3D = stage._props_nodes.get("mark:lift")
	if root == null or not root.has_node("GuardianLiftFloat"): return
	_set_float(root,lerpf(float(int(before.state.turns.get("lift",0))%2),float(int(after.state.turns.get("lift",0))%2),clampf(progress,0,1)))
	LiftFrame.set_return_state(root, bool(root.get_meta("return_requested",false)) and (before.rays()==after.rays() or progress>=1.0))

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
