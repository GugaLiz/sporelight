extends RefCounted
## The existing lift rides hanging guides attached to the fixed high shore.
## No walkable surface, collision, or new connection is added.
const TRAVEL := 1.30

static func build(stage: Node, root: Node3D) -> void:
	var frame := Node3D.new()
	frame.name = "GuardianLiftFrame"
	frame.set_meta("visual_only", true)
	root.add_child(frame)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			var corner := Node3D.new()
			corner.name = "CornerBinding" + str(frame.get_child_count())
			corner.position = Vector3(x * 1.39, 0, z * 1.39)
			frame.add_child(corner)
			_binding(stage, corner, Vector3(.62, .022, .075), Vector3(-x * .25, .009, 0))
			_binding(stage, corner, Vector3(.075, .022, .62), Vector3(0, .009, -z * .25))
			var rivet: MeshInstance3D = stage._sphere(corner, .035, Vector3(0, .02, 0), Color("d4b77c"))
			rivet.scale.y = .35
			rivet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The permanent high shore starts at x=6.5 and spans z=-1.5..1.5.
	# Cantilever brackets bite into its side wall; the central x=6,z=0
	# boarding cell remains open. Hanging rods need no invented floating feet.
	for side: float in [-1.0, 1.0]:
		var guide := Node3D.new()
		guide.name = "LiftGuideAssembly" + str(frame.get_child_count())
		guide.position = Vector3(1.51, 0, side * 1.28)
		frame.add_child(guide)
		var fixed := Node3D.new()
		fixed.name = "ShoreAnchoredGuide"
		fixed.set_meta("anchor_tile", "f:7:-1" if side < 0 else "f:7:1")
		guide.add_child(fixed)
		var rod: MeshInstance3D = stage._cylinder(fixed, .058, 1.65, Vector3(0, .375, 0), Color("c3b48b"))
		rod.name = "HangingRail"
		var bracket: MeshInstance3D = stage._box(fixed, Vector3(1.16, .12, .12), Vector3(.58, 1.12, 0), Color("9b8863"))
		bracket.name = "ShoreBracket"
		var anchor: MeshInstance3D = stage._box(fixed, Vector3(.10, .40, .28), Vector3(1.06, .96, 0), Color("7e8069"))
		anchor.name = "StoneWallAnchor"
		var a := Vector3(1.09, .77, 0)
		var b := Vector3(.03, 1.12, 0)
		var brace: MeshInstance3D = stage._cylinder(fixed, .036, a.distance_to(b), a.lerp(b,.5), Color("8d7b58"))
		brace.name = "BracketBrace"
		brace.quaternion = Quaternion(Vector3.UP, (b-a).normalized())
		var end: MeshInstance3D = stage._sphere(fixed, .075, Vector3(0, -.45, 0), Color("8c7956"))
		end.name = "RailEndCap"
		var collar: MeshInstance3D = stage._cylinder(guide, .115, .20, Vector3(0, -.20, 0), Color("768e83"))
		collar.name = "MovingCollar"
		stage._box(guide, Vector3(.23, .13, .15), Vector3(-.08, -.20, 0), Color("8c7956"))
	# A shallow brass conduit ties the control foot to the moving platform.
	_binding(stage, frame, Vector3(1.04, .012, .055), Vector3(.96, .008, 0))
	set_height(root, float(int(stage.world.state.turns.get("lift", 0)) % 2))
	set_return_state(root, false)

static func _binding(stage: Node, root: Node3D, size: Vector3, at: Vector3) -> void:
	var mesh: MeshInstance3D = stage._box(root, size, at, Color("ad986a"))
	mesh.name = "BrassBinding" + str(root.get_child_count())
	mesh.set_meta("lift_binding", true)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func set_height(root: Node3D, step: float) -> void:
	var frame: Node3D = root.get_node_or_null("GuardianLiftFrame")
	if frame == null: return
	var travel := clampf(step, 0, 1) * TRAVEL
	frame.set_meta("height_step", clampf(step, 0, 1))
	for child: Node in frame.get_children():
		if not child.has_node("ShoreAnchoredGuide"): continue
		# The collars ride the platform. Rails and brackets stay attached to
		# the real high-bank wall through ascent, descent and undo.
		child.get_node("ShoreAnchoredGuide").position.y = -travel

static func set_return_state(root: Node3D, pending: bool) -> void:
	var frame: Node3D = root.get_node_or_null("GuardianLiftFrame")
	if frame == null: return
	if frame.has_meta("return_pending") and bool(frame.get_meta("return_pending")) == pending: return
	frame.set_meta("return_pending", pending)
	for mesh: Node in frame.find_children("*", "MeshInstance3D", true, false):
		if not mesh.has_meta("lift_binding"): continue
		var material: StandardMaterial3D = mesh.material_override
		material.albedo_color = Color("d3b879") if pending else Color("ad986a")
		material.emission_enabled = pending
		material.emission = Color("bda264") * .12 if pending else Color.BLACK
