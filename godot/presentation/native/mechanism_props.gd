extends RefCounted
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
		return Vector3(-.38,0,.38) if who == "luvie" else Vector3(-.32,0,-.32)
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
	if str(before.level.id) == "1-4" and stage._props_nodes.has("mark:hold"):
		var lever: Node3D = stage._props_nodes["mark:hold"]
		if lever.has_node("LeverArm"):
			var start := Basis(Quaternion(Vector3.UP,(LEVER_HELD if before.lever_held() else LEVER_REST).normalized()))
			var end := Basis(Quaternion(Vector3.UP,(LEVER_HELD if after.lever_held() else LEVER_REST).normalized()))
			_set_lever_basis(lever,start.slerp(end,clampf(progress,0,1)))
	# The domain previews a destination before the platform reaches it. Move
	# the physical gauge with the platform, reusing its existing mesh.
	for node: Node3D in stage._props_nodes.values():
		if node.has_meta("flower_fixed_center"):
			_update_fixed_flower(node)
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
		pointer.position.y = 0.15 + value * 0.11
		node.set_meta("height_step", value)

static func _height_step(world: RefCounted, module: String) -> float:
	return float(world.state.get("water", 0)) if str(world.level.id) == "2-1" else float(int(world.state.turns.get(module, 0)) % 2)

static func build_mark(stage: Node, root: Node3D, mark: Dictionary) -> bool:
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
	# Both states share the complete authored planter and its painted foot.
	# The old loose bouquet -> cropped bloom halved the visible height and
	# put a cut through the planter at the ground. Its stone is a real local
	# obstruction; leaves above it must not turn the entire masonry transparent.
	var alias := "bloom" if active else "flower"
	var width := OriginalRatios.canvas_width("flower",str(stage.world.level.id))
	var anchor := Vector3(0.27, 0.012, 0.34) * (width / 1.16)
	var center := Vector3(-.55,0,-.38)
	if str(stage.world.level.id)=="2-3" and str(root.name)=="Mark_stage":
		# Both one-cell arms are real routes and can become a boarding edge.
		# Keep the whole source planter on the existing fixed starting shore;
		# the stage's logical mark and interaction ring stay at its centre.
		root.set_meta("flower_fixed_center",Vector3(-3.5,0,-.65))
		center=Vector3(-3.5,0,-.65)-root.global_position
		# An always-visible, walkable stamp identifies the original boarding
		# centre after the stone artwork moves ashore. It is not new support.
		var ring := TorusMesh.new()
		ring.inner_radius=.235
		ring.outer_radius=.25
		var centre_ring: MeshInstance3D=stage._mesh_instance(root,ring,Color("b8c4a1"),Vector3(0,.012,0))
		centre_ring.name="FlowerPlatformRing"
		var symbol := _symbol(root,"FlowerPlatformSymbol","花",Vector3(0,.026,0),Color("87997a"),.005)
		symbol.billboard=BaseMaterial3D.BILLBOARD_DISABLED
		symbol.rotation.x=-PI/2
		symbol.outline_size=1
	if str(stage.world.level.id)=="1-4" and str(root.name)=="Mark_home": center=Vector3(0,0,-.65)
	var offset := anchor+center-Vector3(0,0,.07)
	var sprite: Sprite3D = stage._sprite(root, alias, width, offset, false)
	sprite.texture = stage._texture(alias)
	sprite.pixel_size = width / sprite.texture.get_width()
	sprite.offset = Vector2(0, 102)
	stage._integrate_prop(sprite, 0)
	sprite.set_meta("hard_planter",true)
	sprite.set_meta("canvas_world_width",width)
	sprite.set_meta("planter_anchor",anchor)
	sprite.set_meta("ground_footprint_span",Vector2(.80,.80)*(width/1.16))
	sprite.set_meta("ground_footprint_center",offset-anchor+Vector3(0,0,.07))

static func _update_fixed_flower(root: Node3D) -> void:
	var center: Vector3=Vector3(root.get_meta("flower_fixed_center"))-root.global_position
	for child: Node in root.get_children():
		if not child is Sprite3D or not child.has_meta("hard_planter"): continue
		child.position=Vector3(child.get_meta("planter_anchor"))+center-Vector3(0,0,.07)
		child.set_meta("ground_footprint_center",center)

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
	root.set_meta("mechanism_state","held" if held else "released")

static func _set_lever_basis(root: Node3D, basis: Basis) -> void:
	var arm: MeshInstance3D = root.get_node("LeverArm")
	arm.basis = basis
	arm.position = Vector3(0,.1,0)+basis*Vector3(0,.235,0)
	root.get_node("LeverHandle").position = Vector3(0,.1,0)+basis*Vector3(0,.47,0)

static func _latch(stage: Node, root: Node3D, locked: bool) -> void:
	var arch: Sprite3D = stage._sprite(root, "arch", OriginalRatios.canvas_width("latch"), Vector3(0, 0, -0.1))
	arch.offset = Vector2(0,104)
	# A small visible latch belongs to the arch, not the crossing itself.
	# It has no collision and does not imply that any extra tiles exist.
	var post: MeshInstance3D = stage._box(root, Vector3(0.08, 0.37, 0.08), Vector3(0.27, 0.185, 0.12), Color("b3b18c"))
	post.name = "LatchPost"
	var hinge := Vector3(0.27, 0.26, 0.16)
	var angle := 0.0 if locked else -PI / 2
	# Both poses share a physical hinge on the post. Rotating around the
	# bar's own centre previously detached the open bolt from that post.
	var bolt_center := hinge + Vector3(-0.135, 0, 0).rotated(Vector3.BACK, angle)
	var bolt: MeshInstance3D = stage._box(root, Vector3(0.27, 0.045, 0.055), bolt_center, Color("d7c28a") if locked else Color("b8bba6"))
	bolt.name = "LatchBolt"
	bolt.rotation.z = angle
	var gem: MeshInstance3D = stage._sphere(root, 0.045, Vector3(0.27, 0.37, 0.12), Color("c4e3ac") if locked else Color("8d9c8c"))
	gem.name = "LatchState"
	root.set_meta("mechanism_state", "fixed" if locked else "unfixed")

static func _song(stage: Node, root: Node3D, state: Dictionary) -> void:
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
