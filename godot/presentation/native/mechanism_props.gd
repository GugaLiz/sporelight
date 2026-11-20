extends RefCounted
const Props = preload("res://elements/prop_definitions.gd")
## Read-only mechanism dressing. Every cue describes the current mechanism,
## never a required answer, a new path, or a completion prerequisite.

const LEAF_COLORS := {"turn": Color("d9d6a5"), "rise": Color("b4d6c4"), "rest": Color("c4cbe1")}
const SYMBOL_FONT = preload("res://assets/fonts/NotoSansSC-Variable.ttf")
const LEAF_SYMBOLS := {"turn": "转", "rise": "↑", "rest": "–"}
const FACE_RIGHT := Vector3(0.70710678, 0, -0.70710678)
const FACE_UP := Vector3(-0.35355339, 0.8660254, -0.35355339)
const FACE_NORMAL := Vector3(0.61237244, 0.5, 0.61237244)
const FERRY_CONTROLLER_OFFSET := Vector3(0.60, 0, -0.60)
const CONTROLLER_OFFSET := Vector3(0.28, 0, 0)
const LEVER_REST := Vector3(-0.370920469,0.928664636,0)
# Keep the original .47m arm and hinge; pulling diagonally towards the
# operator brings its knob down to the standing artwork's hand, not neck.
const LEVER_HELD := Vector3(.33,.303,.14)
const OriginalRatios = preload("res://presentation/native/original_prop_ratios.gd")
static var _pond_leaf_resource: ArrayMesh
static var _pond_profile_resources: Dictionary = {}

static func standing_offset(world: RefCounted, tile_id: String, who: String) -> Vector3:
	if str(world.level.id)=="2-1" and tile_id=="m:float:0:0":
		return Vector3(-.40,0,.40) if who=="luvie" else Vector3(.24,0,-.40)
	if str(world.level.id)=="2-4" and tile_id=="m:boat:0:0":
		return Vector3(-.40,0,.40) if who=="luvie" else Vector3(.24,0,-.24)
	if (str(world.level.id)=="2-4" and tile_id=="f:-4:0") or (str(world.level.id)=="3-3" and tile_id=="f:1:-4"):
		return Vector3(.30,0,-.30) if who=="luvie" else Vector3(-.30,0,.30)
	if str(world.level.id)=="2-3" and tile_id=="m:stage:0:0":
		# Canonical resting poses separate along the camera's horizontal axis.
		# Actual passengers still ride the original rigid mechanism transform.
		return Vector3(-.30,0,.24) if who=="luvie" else Vector3(.30,0,-.24)
	if str(world.level.id) == "1-4" and tile_id == "f:-3:0":
		return Vector3(.38,0,-.08) if who == "luvie" else Vector3(-.32,0,.26)
	if str(world.level.id) == "1-4" and tile_id == "f:-3:5":
		# Approach the latch beside its complete arch, rather than standing
		# in its doorway or between the arch and the adjacent bell.
		return Vector3(-.44,0,.44) if who == "luvie" else Vector3(.44,0,.44)
	if str(world.level.id) == "1-4" and tile_id == "f:-4:0":
		return Vector3(.38,0,.08) if who == "luvie" else Vector3(-.30,0,.38)
	# Keep the cloud operator on its original fixed terrace but outside the
	# pink doorway's silhouette. This also identifies it as an instrument
	# stance so explicit saved poses retain priority during restoration.
	if str(world.level.id) == "cloud-3" and tile_id == "floor:8:5":
		return Vector3(.30,0,-.30) if who == "luvie" else Vector3(.48,0,-.05)
	if str(world.level.id) in ["1-1", "1-2", "2-4"] or str(world.level.id).begins_with("cloud-"):
		return Vector3.ZERO
	for mark: Dictionary in world.level.get("marks", []):
		if str(mark.get("tile", "")) == tile_id and str(mark.get("kind", "")) in ["turn", "valve", "lift"] and str(mark.id) != "mirrorA":
			# Separate the wheel and travellers along the camera's horizontal
			# axis as well as on the floor; same-axis clearance hid the entire rod.
			var offset := Vector3(-.40, 0, 0) if who == "luvie" else Vector3(-.37, 0, -.48)
			if who == "buddy" and (str(world.level.id) in ["1-3","2-1","3-2"] or (str(world.level.id) == "3-4" and str(mark.id) == "water")): offset.z = .48
			if str(world.level.id) == "3-3" and str(mark.id) == "turn":
				offset = Vector3(.30,0,-.24) if who == "luvie" else Vector3(.30,0,.30)
			# The authored 3x3 lift may meet a west shore/stair at another
			# height. Keep the hero inside its tested central flat support.
			if str(world.level.id) == "3-3" and str(mark.id) == "lift": offset.x = -.30
			if str(world.level.id) in ["3-3","3-4"] and str(mark.id) == "lift" and who == "buddy": offset = Vector3(-.30,0,.30)
			# The last light arm can cease being a rule neighbour on departure;
			# keep this passenger inside the centre without weakening the guard.
			if str(world.level.id) == "3-4" and str(mark.id) == "light": offset.x = -.30
			if str(world.level.id) == "3-4" and str(mark.id) == "light" and who == "buddy": offset = Vector3(.25,0,.36)
			var module := _rotating_module(world,tile_id)
			return offset.rotated(Vector3.UP,-float(world.state.turns.get(module,0))*PI/2) if not module.is_empty() else offset
	return Vector3.ZERO

static func _rotating_module(world: RefCounted,tile_id: String) -> String:
	for module: Dictionary in world.level.get("modules",[]):
		if str(module.get("kind","")) == "rotate" and tile_id == "m:%s:0:0" % str(module.id): return str(module.id)
	return ""

static func state_signature(world: RefCounted) -> Array:
	# Ordinary walking must not invalidate props. These are the only additional
	# dependencies not already present in the stage's item/flag/turn signature.
	if str(world.level.id) == "2-3":
		return [world.state.get("song", []), world.state.get("beat", 0), world.state.get("playing", false)]
	return []

static func update_motion(stage: Node, before: RefCounted, after: RefCounted, progress: float) -> void:
	_update_mirror_motion(stage,before,after,progress)
	preload("res://presentation/native/symbiosis_dressing.gd").update_motion(stage,before,after,progress)
	preload("res://presentation/native/guardian_dressing.gd").update_motion(stage,before,after,progress)
	if str(before.level.id) == "1-4" and stage._props_nodes.has("mark:hold"):
		var lever: Node3D = stage._props_nodes["mark:hold"]
		if lever.has_node("LeverArm"):
			var start := Basis(Quaternion(Vector3.UP,(LEVER_HELD if before.lever_held() else LEVER_REST).normalized()))
			var end := Basis(Quaternion(Vector3.UP,(LEVER_HELD if after.lever_held() else LEVER_REST).normalized()))
			_set_lever_basis(lever,start.slerp(end,clampf(progress,0,1)))
	# The domain previews a destination before the platform reaches it. Move
	# the physical gauge with the platform, reusing its existing mesh.
	for node: Node3D in stage._props_nodes.values():
		if node.has_node("SongPassengerMark"):
			var start := int(before.state.turns.get("stage", 0))
			var delta := posmod(int(after.state.turns.get("stage", 0)) - start, 4)
			var turn := float(start) + float(delta if delta <= 2 else delta - 4) * clampf(progress, 0, 1)
			(node.get_node("SongPassengerMark") as Node3D).rotation.y = -turn * PI / 2
		if node.has_meta("instrument_module"):
			var module := str(node.get_meta("instrument_module"))
			var start := int(before.state.turns.get(module,0))
			var delta := posmod(int(after.state.turns.get(module,0))-start,4)
			var turn := float(start)+float(delta if delta<=2 else delta-4)*clampf(progress,0,1)
			var local_offset: Vector3 = node.get_meta("instrument_local_offset")
			var offset := local_offset.rotated(Vector3.UP,-turn*PI/2)
			var previous: Vector3 = node.get_meta("instrument_offset")
			for child: Node3D in node.get_children(): child.position += offset-previous
			node.set_meta("instrument_offset",offset)
		if not node.has_meta("height_module"): continue
		var module := str(node.get_meta("height_module"))
		var start := _height_step(before, module)
		var finish := _height_step(after, module)
		var value := lerpf(start, finish, clampf(progress, 0.0, 1.0))
		var pointer: Node3D = node.get_node("HeightPointer")
		if node.has_meta("natural_height_origin"):
			pointer.position = preload("res://presentation/native/symbiosis_dressing.gd").lift_gauge_point(node.get_meta("natural_height_origin"), value / 2.0)
		else:
			pointer.position.y = 0.15 + value * 0.11
		node.set_meta("height_step", value)

static func mirror_yaw(angle: float) -> float:
	# A slash/backslash mirror's real normal must reflect the same cardinal
	# directions as GardenWorld.rays(), including its two-sided surface.
	return -PI/4+angle*PI/2

static func _update_mirror_motion(stage: Node, before: RefCounted, after: RefCounted, progress: float) -> void:
	for id: String in after.state.get("items",{}):
		if not id.begins_with("mirror"):continue
		var first: Dictionary=before.state.get("items",{}).get(id,{})
		var last: Dictionary=after.state.items[id]
		if first.is_empty() or not str(first.get("holder","")).is_empty() or not str(last.get("holder","")).is_empty():continue
		if str(first.get("tile",""))!=str(last.get("tile","")):continue
		var root: Node3D=stage._props_nodes.get("item:"+id)
		if root==null or not root.has_node("ReflectionFace"):continue
		var turn_from:=int(first.get("angle",0))
		var delta:=posmod(int(last.get("angle",0))-turn_from,4)
		var turn:=float(turn_from)+float(delta if delta<=2 else delta-4)*clampf(progress,0,1)
		root.get_node("ReflectionFace").rotation.y=mirror_yaw(turn)
		var leaf_back := root.get_node_or_null("ReflectionLeafBack") as Node3D
		if leaf_back != null: leaf_back.rotation.y=mirror_yaw(turn)+PI

static func _height_step(world: RefCounted, module: String) -> float:
	return float(world.state.get("water", 0)) if str(world.level.id) == "2-1" else float(int(world.state.turns.get(module, 0)) % 2)

static func build_mark(stage: Node, root: Node3D, mark: Dictionary) -> bool:
	if preload("res://presentation/native/guardian_dressing.gd").build_mark(stage,root,mark): return true
	var world: RefCounted = stage.world
	var level := str(world.level.id)
	if level in ["1-1", "1-2"]:
		return false
	var kind := str(mark.get("kind", ""))
	var id := str(mark.get("id", ""))
	if kind in ["rest", "observe"]:
		# Source uses the small loose bouquet, not a blue scenery flower.
		stage._sprite(root, "flowers", OriginalRatios.canvas_width(kind,level), Vector3.ZERO, true)
		return true
	if kind == "lever":
		_lever(stage, root, bool(world.lever_held()) if id == "hold" else bool(world.flag(id)) or (id == "latch" and bool(world.state.get("cloudLatch", false))))
		return true
	if kind == "latch":
		_latch(stage, root, bool(world.flag(id)))
		return true
	if kind == "song":
		_song(stage, root, world.state)
		return true
	if level == "3-3" and id == "care":
		# Giving dew stabilizes the root; this garden has no 'care' flag.
		var settled := bool(world.flag("root"))
		flower(stage, root, settled)
		root.set_meta("mechanism_state", "rooted" if settled else "awaiting_dew")
		return true
	if level == "2-4" and id == "invite":
		# Invite and plant share one nectar flower. Keep this interaction anchor,
		# but do not paint a second unchanging flower directly over the first.
		root.set_meta("shared_visual", "mark:plant")
		return true
	if level == "2-4" and id == "plant":
		var planted := bool(world.flag("plant"))
		flower(stage, root, planted)
		root.set_meta("mechanism_state", "planted" if planted else "unplanted")
		return true
	if level == "3-2" and id == "freeze":
		_memory(stage, root, world.state)
		return true
	if kind in ["turn", "valve", "lift"]:
		# A fixed mirror already has a real leaf and frame from the item model.
		# A second full wheel in the same cell obscures that reflection surface.
		if id == "mirrorA":
			_symbol(root, "FixedMirror", "Ⅰ", Vector3(0.28, 0.22, 0.10), Color("eee2b7"), 0.004)
			return true
		_instrument(stage, root, mark)
		return true
	return false

static func flower(stage: Node, root: Node3D, active: bool) -> void:
	if str(stage.world.level.id)=="1-4" and str(root.name)=="Mark_home":
		# Returning the bell belongs to the mole's home, not another planter.
		# Keep the interaction anchor; create neither stone art nor a hard base.
		root.set_meta("mechanism_state","bell_returned" if active else "awaiting_bell")
		return
	if str(stage.world.level.id)=="2-3" and str(root.name)=="Mark_stage":
		# This mark names the passenger deck, not a second planting task.
		# Its paint follows the real platform without adding a shore obstacle.
		root.set_meta("mechanism_state","passenger_deck")
		_song_passenger_mark(stage, root)
		return
	# Both states share the complete authored planter and its painted foot.
	# The old loose bouquet -> cropped bloom halved the visible height and
	# put a cut through the planter at the ground. Its stone is a real local
	# obstruction; leaves above it must not turn the entire masonry transparent.
	var alias := Props.planter_alias(active)
	var width := OriginalRatios.canvas_width("flower",str(stage.world.level.id))
	var anchor := Props.planter_anchor(width)
	var center := Props.vector3(Props.section("planters").task.ground_center)
	var offset := anchor+center-Props.planter_center()
	var sprite: Sprite3D = stage._sprite(root, alias, width, offset, false)
	sprite.texture = stage._texture(alias)
	sprite.pixel_size = width / sprite.texture.get_width()
	sprite.offset = Props.vector2(Props.planter_spec().painted_foot)
	stage._integrate_prop(sprite, 0)
	sprite.set_meta("hard_planter",true)
	sprite.set_meta("canvas_world_width",width)
	sprite.set_meta("planter_anchor",anchor)
	sprite.set_meta("ground_footprint_span",Props.planter_span(width))
	sprite.set_meta("ground_footprint_center",offset-anchor+Props.planter_center())

static func _lever(stage: Node, root: Node3D, held: bool) -> void:
	var base: MeshInstance3D = stage._box(root, Vector3(0.38, 0.1, 0.3), Vector3(0, 0.05, 0), Color("b3b18c"))
	base.name = "LeverBase"
	var hinge := Vector3(0, 0.1, 0)
	var arm_basis := Basis(Quaternion(Vector3.UP,(LEVER_HELD if held else LEVER_REST).normalized()))
	var arm: MeshInstance3D = stage._box(root, Vector3(0.045, 0.47, 0.045), hinge + arm_basis * Vector3(0, 0.235, 0), Color("c7b179"))
	arm.name = "LeverArm"
	arm.basis = arm_basis
	var handle: MeshInstance3D = stage._sphere(root, 0.09, hinge + arm_basis * Vector3(0, 0.47, 0), Color("cf9870"))
	handle.name = "LeverHandle"
	root.set_meta("mechanism_state","latched" if str(stage.world.level.id)=="1-4" and stage.world.flag("latch") else "held" if held else "released")

static func sync_hold(stage: Node) -> void:
	if str(stage.world.level.id)!="1-4" or not stage._props_nodes.has("mark:hold"):return
	var root: Node3D=stage._props_nodes["mark:hold"]
	var held: bool=stage.world.lever_held()
	_set_lever_basis(root,Basis(Quaternion(Vector3.UP,(LEVER_HELD if held else LEVER_REST).normalized())))
	root.set_meta("mechanism_state","latched" if stage.world.flag("latch") else "held" if held else "released")

static func _set_lever_basis(root: Node3D, basis: Basis) -> void:
	var arm: MeshInstance3D = root.get_node("LeverArm")
	arm.basis = basis
	arm.position = Vector3(0,.1,0)+basis*Vector3(0,.235,0)
	root.get_node("LeverHandle").position = Vector3(0,.1,0)+basis*Vector3(0,.47,0)

static func _latch(stage: Node, root: Node3D, locked: bool) -> void:
	var arch_at := Vector3(-.45, 0, -.1) if str(stage.world.level.id) == "2-3" else Vector3(0, 0, -.1)
	var arch: Sprite3D = stage._sprite(root, "arch", OriginalRatios.canvas_width("latch"), arch_at)
	arch.offset = Vector2(0,104)
	if str(stage.world.level.id)=="1-4":
		_arch_latch(stage,root,locked)
		return
	# Other gardens keep their original small latch.
	# Separate the pond latch from the flower and the ordinary operator pose;
	# keep its whole foot on the same authored shore and keep the arch still.
	var offset := Vector3(-.67,0,.18) if str(stage.world.level.id)=="2-3" else Vector3.ZERO
	var post: MeshInstance3D=stage._box(root,Vector3(.08,.37,.08),Vector3(.27,.185,.12)+offset,Color("b3b18c"))
	post.name="LatchPost"
	var hinge:=Vector3(.27,.26,.16)+offset
	root.set_meta("latch_hinge",hinge)
	var angle:=0.0 if locked else -PI/2
	var bolt: MeshInstance3D=stage._box(root,Vector3(.27,.045,.055),hinge+Vector3(-.135,0,0).rotated(Vector3.BACK,angle),Color("d7c28a") if locked else Color("b8bba6"))
	bolt.name="LatchBolt"
	bolt.rotation.z=angle
	var gem: MeshInstance3D=stage._sphere(root,.045,Vector3(.27,.37,.12)+offset,Color("c4e3ac") if locked else Color("8d9c8c"))
	gem.name="LatchState"
	root.set_meta("mechanism_state","fixed" if locked else "unfixed")

static func _arch_latch(stage: Node, root: Node3D, locked: bool) -> void:
	# The outer right column leaves a separate silhouette beside the doorway.
	# Grounded timber carries the brass pin; the normal depth test stays on.
	var post: MeshInstance3D=stage._box(root,Vector3(.14,.52,.14),Vector3(.30,.26,-.473),Color("806848"))
	post.name="LatchPost"
	var face:=Basis(FACE_RIGHT,FACE_UP,FACE_NORMAL).orthonormalized()
	var hinge:=Vector3(.30,.48,-.473)+face.z*.045
	root.set_meta("latch_hinge",hinge)
	var length:=.38
	var angle:=0.0 if locked else PI/2
	var basis:=face*Basis(Vector3.BACK,angle)
	var plate: MeshInstance3D=stage._box(root,Vector3(.26,.22,.065),hinge-face.z*.025,Color("554d3b"))
	plate.name="LatchMount"
	plate.basis=face
	var bolt: MeshInstance3D=stage._box(root,Vector3(length,.075,.085),hinge+basis*Vector3(length*.5,0,0),Color("d3ad61"))
	bolt.name="LatchBolt"
	bolt.basis=basis
	var pivot: MeshInstance3D=stage._box(root,Vector3(.10,.12,.10),hinge,Color("a57d43"))
	pivot.name="LatchHinge"
	pivot.basis=face
	# The keeper clips the shaft near its hinge and is fixed to the same
	# mount, rather than floating in the air at the free end of the pin.
	var socket: MeshInstance3D=stage._box(root,Vector3(.10,.14,.12),hinge+face.x*.13,Color("65553c"))
	socket.name="LatchSocket"
	socket.basis=face
	var loop:=TorusMesh.new()
	loop.inner_radius=.045
	loop.outer_radius=.075
	var grip: MeshInstance3D=stage._mesh_instance(root,loop,Color("e0bd76"),hinge+basis*Vector3(length,0,0)+face.z*.075)
	grip.name="LatchTab"
	grip.basis=face*Basis(Vector3.RIGHT,PI/2)
	root.set_meta("mechanism_state","fixed" if locked else "unfixed")

static func _song(stage: Node, root: Node3D, state: Dictionary) -> void:
	if str(stage.world.level.id) == "2-3":
		_pond_song(stage, root, state)
		return
	var base: MeshInstance3D = stage._box(root, Vector3(0.72, 0.15, 0.38), Vector3(0, 0.075, 0), Color("b4b993"))
	base.name = "SongBase"
	var sequence: Array = state.get("song", ["turn", "rise", "rest"])
	var beat := clampi(int(state.get("beat", 0)), 0, 3)
	var playing := bool(state.get("playing", false))
	for index in range(3):
		var note := str(sequence[index])
		var x := -0.23 + index * 0.23
		var y := 0.18 if index < beat else 0.22
		var color: Color = LEAF_COLORS.get(note, Color.WHITE)
		var leaf: MeshInstance3D = stage._box(root, Vector3(0.19, 0.035, 0.27), Vector3(x, y, 0), color)
		leaf.name = "ActionLeaf_" + str(index)
		var symbol := _symbol(root, "ActionSymbol_" + str(index), str(LEAF_SYMBOLS.get(note, "·")), Vector3(x, y + 0.0205, 0), Color("f4edd4"), 0.0045)
		symbol.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		symbol.rotation.x = -PI / 2
		symbol.outline_size = 1
		var progress_color := Color("7a8b83") if index < beat else Color("f1d28d") if index == beat and playing else Color("c5ceba")
		var dot: MeshInstance3D = stage._sphere(root, 0.026, Vector3(x, 0.195, 0.17), progress_color)
		dot.name = "Beat_" + str(index)
	root.set_meta("song", sequence.duplicate())
	root.set_meta("beat", beat)
	root.set_meta("playing", playing)

static func _pond_song(stage: Node, root: Node3D, state: Dictionary) -> void:
	# The complete original base stays on the existing fixed three-by-three
	# shore. The eastern landing and the original shore planter remain clear.
	# NativePropObstacles reads this exact SongBase transform for its collider
	# and route planner; no independent display-only offset is involved.
	var offset := Vector3(-0.66, 0, 0.10)
	var right := FACE_RIGHT
	var front := Vector3(0.70710678, 0, 0.70710678)
	var table_basis := Basis(right, Vector3.UP, front)
	var cradle := PackedVector2Array([Vector2(-.315,-.19),Vector2(.315,-.19),Vector2(.36,-.145),Vector2(.36,.145),Vector2(.315,.19),Vector2(-.315,.19),Vector2(-.36,.145),Vector2(-.36,-.145)])
	var base: MeshInstance3D = stage._mesh_instance(root, _pond_profile_mesh("cradle", cradle, .15), Color("98764e"), offset + Vector3.UP * .075)
	base.name = "SongBase"
	base.basis = table_basis
	var soundboard := PackedVector2Array([Vector2(-.29,-.16),Vector2(.29,-.16),Vector2(.33,-.12),Vector2(.33,.12),Vector2(.29,.16),Vector2(-.29,.16),Vector2(-.33,.12),Vector2(-.33,-.12)])
	var inset: MeshInstance3D = stage._mesh_instance(root, _pond_profile_mesh("soundboard", soundboard, .012), Color("496354"), offset + Vector3.UP * .153)
	inset.name = "SongSoundboard"
	inset.basis = table_basis
	var sequence: Array = state.get("song", ["turn", "rise", "rest"])
	var beat := clampi(int(state.get("beat", 0)), 0, 3)
	var key_basis := Basis(right, Vector3.UP * 0.8660254 + front * 0.5, front * 0.8660254 - Vector3.UP * 0.5)
	var colors := {"turn": Color("c9d296"), "rise": Color("a9c99e"), "rest": Color("b8c8ad")}
	for index in range(3):
		var note := str(sequence[index])
		var done := index < beat
		var next := index == beat
		# Even the lowered key's complete tilted underside clears the inset.
		var center := offset + right * (-0.23 + index * 0.23) + Vector3.UP * (0.240 if done else 0.277)
		var mesh := _pond_action_leaf_mesh()
		var color: Color = colors.get(note, Color("c7cbe0"))
		var leaf: MeshInstance3D = stage._mesh_instance(root, mesh, color.darkened(0.17) if done else color, center)
		leaf.name = "ActionLeaf_" + str(index)
		leaf.basis = key_basis
		_pond_leaf_veins(stage, leaf)
		_pond_action_relief(stage, root, note, index, center + key_basis.y * .0205, key_basis)
		# The leaf rests on a short wooden tongue instead of floating like a
		# label. Its compression follows the same existing pressed-key state.
		var contact := center + key_basis * Vector3(0,-.0175,.10)
		var support_height := contact.y - .159
		var stem: MeshInstance3D = stage._cylinder(root, .012, support_height, Vector3(contact.x, .159 + support_height * .5, contact.z), Color("aa8b5e"))
		stem.name = "LeafTongue_" + str(index)
		var dot: MeshInstance3D = stage._sphere(root, 0.032 if next else 0.024, offset + right * (-0.23 + index * 0.23) + front * 0.17 + Vector3.UP * 0.178, Color("e9bf75") if next else Color("628474") if done else Color("a4b6a4"))
		dot.name = "Beat_" + str(index)
		dot.set_meta("next", next)
	root.set_meta("song", sequence.duplicate())
	root.set_meta("beat", beat)
	root.set_meta("playing", bool(state.get("playing", false)))
	root.set_meta("song_instrument_offset", offset)
	root.set_meta("song_next_action", str(sequence[beat]) if beat < 3 else "")

static func _pond_action_relief(stage: Node, root: Node3D, note: String, index: int, at: Vector3, face: Basis) -> void:
	var relief := Node3D.new()
	relief.name = "ActionSymbol_" + str(index)
	relief.position = at
	relief.basis = face.scaled_local(Vector3(.75,1,.75))
	relief.set_meta("action", note)
	root.add_child(relief)
	var shapes: Array = []
	if note == "turn":
		var arc := PackedVector2Array()
		for step in range(25):
			var angle := float(step) * PI * 1.5 / 24.0
			arc.append(Vector2(cos(angle),sin(angle)) * .058)
		for step in range(24,-1,-1):
			var angle := float(step) * PI * 1.5 / 24.0
			arc.append(Vector2(cos(angle),sin(angle)) * .036)
		shapes = [arc, PackedVector2Array([Vector2(-.008,-.083),Vector2(.046,-.058),Vector2(-.008,-.030)])]
	elif note == "rise":
		shapes = [PackedVector2Array([Vector2(0,-.072),Vector2(.061,-.007),Vector2(.019,-.007),Vector2(.019,.066),Vector2(-.019,.066),Vector2(-.019,-.007),Vector2(-.061,-.007)])]
	else:
		for side in [-1,1]:
			var x: float = side * .026
			shapes.append(PackedVector2Array([Vector2(x-.011,-.050),Vector2(x+.011,-.050),Vector2(x+.011,.050),Vector2(x-.011,.050)]))
	for part in shapes.size():
		var mesh: MeshInstance3D = stage._mesh_instance(relief, _pond_profile_mesh(note + str(part), shapes[part], .003), Color("4f755b"), Vector3.ZERO, false)
		mesh.name = "Carving_" + str(part)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _pond_leaf_veins(stage: Node, leaf: MeshInstance3D) -> void:
	var veins := [
		PackedVector2Array([Vector2(.009,-.110),Vector2(.015,-.110),Vector2(.008,-.058),Vector2(.003,-.058)]),
		PackedVector2Array([Vector2(-.010,.060),Vector2(-.005,.060),Vector2(-.010,.108),Vector2(-.016,.108)])
	]
	for index in veins.size():
		var vein: MeshInstance3D = stage._mesh_instance(leaf, _pond_profile_mesh("vein" + str(index), veins[index], .0015), Color("78936b"), Vector3(0,.0205,0), false)
		vein.name = "LeafVein_" + str(index)
		vein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _pond_profile_mesh(key: String, outline: PackedVector2Array, height: float) -> ArrayMesh:
	if _pond_profile_resources.has(key): return _pond_profile_resources[key]
	var contour := outline.duplicate()
	var signed_area := 0.0
	for index in contour.size(): signed_area += contour[index].cross(contour[(index+1)%contour.size()])
	if signed_area < 0: contour.reverse()
	var triangles := Geometry2D.triangulate_polygon(contour)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in range(0,triangles.size(),3):
		var a := contour[triangles[index]]
		var b := contour[triangles[index+1]]
		var c := contour[triangles[index+2]]
		if (b-a).cross(c-a) < 0:
			var swap := b
			b = c
			c = swap
		for point: Vector2 in [a,b,c]:
			vertices.append(Vector3(point.x,height*.5,point.y))
			normals.append(Vector3.UP)
		for point: Vector2 in [c,b,a]:
			vertices.append(Vector3(point.x,-height*.5,point.y))
			normals.append(Vector3.DOWN)
	for index in contour.size():
		var a := contour[index]
		var b := contour[(index+1)%contour.size()]
		var normal := Vector3(b.y-a.y,0,a.x-b.x).normalized()
		for point: Vector3 in [Vector3(a.x,height*.5,a.y),Vector3(a.x,-height*.5,a.y),Vector3(b.x,-height*.5,b.y),Vector3(a.x,height*.5,a.y),Vector3(b.x,-height*.5,b.y),Vector3(b.x,height*.5,b.y)]:
			vertices.append(point)
			normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_pond_profile_resources[key] = mesh
	return mesh

static func _pond_action_leaf_mesh() -> ArrayMesh:
	if _pond_leaf_resource != null: return _pond_leaf_resource
	# A closed leaf-shaped key, with the same envelope as the former box.
	# Its outline identifies an action leaf without adding another sign.
	var contour := PackedVector2Array([
		Vector2(.018,-.125), Vector2(.052,-.090), Vector2(.083,-.040),
		Vector2(.095,.010), Vector2(.060,.066), Vector2(.018,.105),
		Vector2(-.015,.125), Vector2(-.040,.084), Vector2(-.073,.038),
		Vector2(-.095,-.012), Vector2(-.068,-.070), Vector2(-.025,-.110)
	])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in contour.size():
		var a := contour[index]
		var b := contour[(index + 1) % contour.size()]
		var top_a := Vector3(a.x, .0175, a.y)
		var top_b := Vector3(b.x, .0175, b.y)
		var bottom_a := Vector3(a.x, -.0175, a.y)
		var bottom_b := Vector3(b.x, -.0175, b.y)
		var outward := Vector3(b.y - a.y, 0, a.x - b.x).normalized()
		var faces := [[Vector3(0, .0175, 0), top_a, top_b], [Vector3(0, -.0175, 0), bottom_b, bottom_a], [top_a, bottom_a, bottom_b], [top_a, bottom_b, top_b]]
		for face_index in faces.size():
			for vertex: Vector3 in faces[face_index]:
				vertices.append(vertex)
				normals.append(Vector3.UP if face_index == 0 else Vector3.DOWN if face_index == 1 else outward)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	_pond_leaf_resource = ArrayMesh.new()
	_pond_leaf_resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _pond_leaf_resource

static func _song_passenger_mark(stage: Node, root: Node3D) -> void:
	var mark := Node3D.new()
	mark.name = "SongPassengerMark"
	mark.rotation.y = -float(stage.world.state.turns.get("stage", 0)) * PI / 2
	mark.set_meta("not_walkable_support", true)
	root.add_child(mark)
	# A pale paint inset separates the legend from busy paving. It is only a
	# two-millimetre visual layer; the real native deck remains its sole support.
	var inset := CylinderMesh.new()
	inset.top_radius = 0.297
	inset.bottom_radius = 0.297
	inset.height = 0.002
	inset.radial_segments = 40
	var paint: MeshInstance3D = stage._mesh_instance(mark, inset, Color("e3ddbb"), Vector3(0, 0.017, 0))
	paint.name = "PassengerDeckPaint"
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paint.set_meta("not_walkable_support", true)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.305
	ring.outer_radius = 0.325
	var edge: MeshInstance3D = stage._mesh_instance(mark, ring, Color("5c8579"), Vector3(0, 0.021, 0))
	edge.name = "PassengerDeckOutline"
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Large painted footsteps survive the low viewing angle better than tiny
	# floor text. These are visual paint only, never collision or new support.
	for side in [-1, 1]:
		var sole: MeshInstance3D = stage._cylinder(mark, 0.052, 0.002, Vector3(side * 0.095, 0.021, 0.045), Color("456e60"))
		sole.name = "PassengerFoot_" + str(side)
		sole.scale.z = 1.45
		sole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var toe: MeshInstance3D = stage._cylinder(mark, 0.044, 0.002, Vector3(side * 0.095, 0.021, -0.07), Color("456e60"))
		toe.name = "PassengerToe_" + str(side)
		toe.scale.z = 0.72
		toe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _memory(stage: Node, root: Node3D, state: Dictionary) -> void:
	var frozen: Variant = state.get("frozen")
	var retained := frozen != null
	var leaf: Sprite3D = stage._sprite(root, "lilypad", 0.60, Vector3(0, 0.035, 0), true)
	leaf.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	leaf.rotation.x = -PI / 2
	leaf.offset = Vector2.ZERO
	leaf.modulate = Color("dbc98f") if retained and int(frozen) == 0 else Color("a9bfdf") if retained else Color("a5b9a0")
	_symbol(root, "MemoryMode", "日" if retained and int(frozen) == 0 else "月" if retained else "·", Vector3(0, 0.34, 0), Color("f3dea2") if retained and int(frozen) == 0 else Color("c3d7ee"), 0.005)
	root.set_meta("mechanism_state", "sun_memory" if retained and int(frozen) == 0 else "moon_memory" if retained else "empty_memory")

static func _instrument(stage: Node, root: Node3D, mark: Dictionary) -> void:
	var world: RefCounted = stage.world
	var level := str(world.level.id)
	var id := str(mark.id)
	var own: Dictionary = {}
	for module: Dictionary in world.level.get("modules", []):
		if str(mark.tile) == "m:%s:0:0" % str(module.id):
			own = module
	var motion := str(own.get("kind", "rotate"))
	if level == "cloud-2": motion = "recall" if id == "dock" else "lift"
	if level == "3-2" and id == "mode": motion = "daylight"
	# The ferry has flower/invite/slide on one logical cell. Spread only its
	# instrument artwork across the same 3x3 rigid deck, preserving the root
	# interaction identity and the flower/insect's original support and height.
	# This circular base remains inside a 1x1 deck even at 45 degrees:
	# length(offset) + radius < .5. Keep the mark/ring at the logical centre.
	var offset := FERRY_CONTROLLER_OFFSET if level == "2-4" and id == "slide" else CONTROLLER_OFFSET
	if level == "3-3" and id == "turn": offset = Vector3(-.30,0,-.30)
	# The light deck's approach clamps the companion's default z to .32.
	# Keep the full base clear there without moving a passenger onto the stair.
	if level == "3-4" and id == "light": offset.z = -.04
	var rotating := _rotating_module(world,str(mark.tile))
	if not rotating.is_empty():
		root.set_meta("instrument_local_offset",offset)
		offset = offset.rotated(Vector3.UP,-float(world.state.turns.get(rotating,0))*PI/2)
		root.set_meta("instrument_module",rotating)
		root.set_meta("instrument_offset",offset)
	if level == "2-1" and id == "water":
		preload("res://presentation/native/symbiosis_dressing.gd").build_water_control(stage, root, offset)
		return
	if (level == "1-3" and id == "turn") or (level == "2-4" and id == "slide"):
		var natural := preload("res://presentation/native/symbiosis_dressing.gd")
		var seat: MeshInstance3D = stage._cylinder(root,.19,.025,offset+Vector3(0,.0125,0),Color("707963"))
		seat.name = "InstrumentBase"
		natural._art(stage,root,"wheel",offset+Vector3(0,.025,0),"NaturalWheel")
		root.set_meta("motion_kind",motion)
		return
	var base: MeshInstance3D = stage._cylinder(root, 0.19, 0.12, Vector3(0, 0.06, 0) + offset, Color("aaad82"))
	base.name = "InstrumentBase"
	var stem: MeshInstance3D = stage._cylinder(root, 0.055, 0.37, Vector3(0, 0.28, 0) + offset, Color("b9a471"))
	stem.name = "InstrumentStem"
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.12
	wheel.outer_radius = 0.17
	var face := Basis(FACE_RIGHT, FACE_UP, FACE_NORMAL).orthonormalized()
	var wheel_node: MeshInstance3D = stage._mesh_instance(root, wheel, Color("e5cd8a"), Vector3(0, 0.48, 0) + offset)
	wheel_node.name = "InstrumentWheel"
	wheel_node.basis = face * Basis(Vector3.RIGHT, PI / 2)
	var symbol := "↔" if motion == "slide" else "↕" if motion == "lift" else "↓" if motion == "recall" else "转"
	var color := Color("f0dfb3")
	if motion == "daylight":
		symbol = "日" if int(world.state.get("mode", 0)) == 0 else "月"
		color = Color("f3dea2") if int(world.state.get("mode", 0)) == 0 else Color("c3d7ee")
	var label := _symbol(root, "MotionKind", symbol, wheel_node.position + face.z * 0.03, color, 0.0045)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.basis = face
	root.set_meta("motion_kind", motion)
	if motion in ["lift", "recall"]:
		var steps := 3 if level == "2-1" else 2
		var module := str(own.get("id", "lift"))
		var current := _height_step(world, module)
		for index in range(steps):
			var dot: MeshInstance3D = stage._sphere(root, 0.027, Vector3(-0.16, 0.15 + index * 0.11, 0.02) + offset, Color("728f8d"))
			dot.name = "Height_" + str(index)
		var pointer: MeshInstance3D = stage._sphere(root, 0.033, Vector3(-0.16, 0.15 + current * 0.11, 0.055) + offset, Color("c1e0df"))
		pointer.name = "HeightPointer"
		root.set_meta("height_module", module)
		root.set_meta("height_step", current)

static func _symbol(root: Node3D, node_name: String, text: String, at: Vector3, color: Color, size: float) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.position = at
	# The Web export has no OS font fallback. Use the shipped font and only
	# supported glyphs; symbols such as clockwise-arrow/crescent are absent.
	label.font = SYMBOL_FONT
	label.font_size = 40
	label.pixel_size = size
	label.modulate = color
	label.outline_modulate = Color("58685c")
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.fixed_size = false
	root.add_child(label)
	return label
