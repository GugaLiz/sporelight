extends SceneTree
## Actual native props and domain transactions; GPU appearance is reviewed
## separately from the matching browser export.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Props = preload("res://presentation/native/mechanism_props.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	await process_frame
	_test_song()
	_test_passenger_landmark()
	_test_latch("1-4")
	_test_latch("2-3")
	_test_care()
	_test_ferry()
	_test_memory()
	_test_symbol_font()
	_test_instruments()
	_test_lever_alignment()
	_test_moving_gauge("2-1", "valve:water", "water")
	_test_moving_gauge("3-3", "valve:lift", "lift")
	_test_baseline()
	print(JSON.stringify({"suite": "native-mechanism-props", "passed": failures.is_empty(), "checks": checks, "failures": failures, "gpuPixelsVerified": false, "scope": "Current-state cues, actual actions and undo, refresh invalidation, registered hard-base collisions matching visible mesh footprints, and unchanged domain snapshots."}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _mark(id: String) -> Node3D:
	return stage._props_nodes.get("mark:" + id)

func _test_song() -> void:
	var world := World.new("2-3")
	stage.set_world(world)
	var original: Dictionary = world.snapshot()
	var node := _mark("song")
	_check_song_contact(node)
	_check(node.get_node("ActionSymbol_0").get_meta("action") == "turn", "song relief follows the actual turn leaf")
	_check(node.get_node("ActionSymbol_1").get_meta("action") == "rise", "song relief follows the actual rise leaf")
	_check(node.get_node("ActionSymbol_2").get_meta("action") == "rest", "song pause relief follows the rest leaf")
	_check(node.find_children("*", "Label3D", true, false).is_empty(), "pond instrument uses physical relief rather than text signs")
	var node_id := node.get_instance_id()
	stage.refresh_world(world)
	_check(node_id == _mark("song").get_instance_id(), "unchanged state reuses props")
	_check(world.act("swap:0").ok, "real action can exchange leaves before rehearsal")
	stage.refresh_world(world)
	_check(_mark("song").get_node("ActionSymbol_0").get_meta("action") == "rise", "exchange invalidates props and changes the first visible action")
	_check(_mark("song").get_node("ActionSymbol_1").get_meta("action") == "turn", "exchange moves the turn relief with its leaf")
	_check(world.act("play").ok, "real rehearsal starts")
	stage.refresh_world(world)
	_check(bool(_mark("song").get_meta("playing")), "play state reaches the visible beat indicators")
	_check(world.act("beat", true).ok, "real beat advances the reordered phrase")
	stage.refresh_world(world)
	_check(int(_mark("song").get_meta("beat")) == 1, "first beat is marked played")
	_check(_mark("song").get_node("ActionLeaf_0").position.y < _mark("song").get_node("ActionLeaf_1").position.y, "played leaf is visually depressed")
	_check_song_contact(_mark("song"))
	_check(world.act("play").ok, "real rehearsal pauses")
	stage.refresh_world(world)
	_check(not bool(_mark("song").get_meta("playing")), "pause removes the active play indicator")
	_check(_mark("song").get_node("Beat_" + str(world.state.beat)).get_meta("next") and _mark("song").get_meta("song_next_action") == world.state.song[int(world.state.beat)], "paused instrument bead still identifies the actual queue position")
	_check(world.act("resetSong").ok, "real reset restores trial state")
	stage.refresh_world(world)
	_check(int(_mark("song").get_meta("beat")) == 0, "reset releases all played leaves")
	_check(_mark("song").get_node("ActionSymbol_0").get_meta("action") == "rise", "reset preserves the chosen phrase instead of a hardcoded answer")
	var snapshot: Dictionary = world.snapshot()
	stage.refresh_world(world)
	_check(world.snapshot() == snapshot, "song dressing never mutates the trial snapshot")
	stage.set_world(World.new("1-3"))
	stage.set_world(World.new("2-3", original))
	_check(_mark("song").get_node("ActionSymbol_0").get_meta("action") == "turn", "cross-level restore does not retain another phrase")

func _test_latch(level: String) -> void:
	var world := _before_action(level, "use:latch")
	stage.set_world(world)
	_check(_mark("latch").get_meta("mechanism_state") == "unfixed", level + " latch starts visibly unfixed")
	_check_latch_contact(_mark("latch"), level + " open")
	if level == "2-3": _rain_courtyard_clearance("before latch")
	var before_angle: float = _mark("latch").get_node("LatchBolt").rotation.z
	_check(world.act("use:latch").ok, level + " actual latch action succeeds")
	stage.refresh_world(world)
	_check(_mark("latch").get_meta("mechanism_state") == "fixed", level + " fixed latch reflects real flag")
	_check_latch_contact(_mark("latch"), level + " locked")
	_check(absf(_mark("latch").get_node("LatchBolt").rotation.z - before_angle) > 1.0, level + " bolt visibly changes orientation")
	var snapshot: Dictionary = world.snapshot()
	_check_hard_bases(_mark("latch"), 3, level + " latch post and separate arch pillars")
	_check(world.snapshot() == snapshot, level + " rendering leaves logic unchanged")
	if level == "2-3": _rain_courtyard_clearance("latched")
	world.undo()
	stage.refresh_world(world)
	_check(_mark("latch").get_meta("mechanism_state") == "unfixed", level + " undo restores latch appearance")
	if level == "2-3": _rain_courtyard_clearance("undo latch")

func _rain_courtyard_clearance(label: String) -> void:
	var core: Node3D = _mark("core")
	var plant: Sprite3D = core.get_child(0)
	var center: Vector3 = core.to_global(plant.get_meta("ground_footprint_center"))
	var span: Vector2 = plant.get_meta("ground_footprint_span")
	var stone := Rect2(Vector2(center.x, center.z) - span * .5, span)
	var arch: Sprite3D = _mark("latch").get_node("arch")
	var feet: Array[Rect2] = preload("res://presentation/native/native_arch_footprint.gd").card(arch)
	_check(is_equal_approx(plant.pixel_size * plant.texture.get_width(), 110.0 * sqrt(2.0) / 70.0), label + " rain flower keeps its source size")
	for foot: Rect2 in feet:
		_check(stone.position.x - foot.end.x > .15, label + " full arch pillar is west of planter with a visible ground gap")
		for x: float in [foot.position.x, foot.get_center().x, foot.end.x]:
			for z: float in [foot.position.y, foot.get_center().y, foot.end.y]:
				var supported := false
				for id: String in stage._surfaces:
					if not id.begins_with("f:"): continue
					var surface: Node3D = stage._surfaces[id]
					var point := Vector3(x, center.y, z)
					var local: Vector3 = surface.to_local(point)
					if absf(local.x) <= .5001 and absf(local.z) <= .5001 and absf(surface.sample_height(point) - center.y) < .025:
						supported = true
						break
				_check(supported, label + " complete pillar foot stays on the original high shore")
	for who: String in ["luvie", "buddy"]:
		for tile_id: String in ["f:0:-4", "f:1:-4"]:
			var tile: Dictionary = stage.world.point_for(tile_id)
			var at: Vector3 = stage.actor_rest_position(tile, who)
			# The standing hint can touch the existing independent latch post.
			# Walking/following uses this same-support safe endpoint, not the hint.
			var safe: Dictionary = stage.prop_waypoint(tile, who, at)
			_check(not safe.is_empty() and stage.prop_point_clear(safe.point, who), label + " " + who + " " + tile_id + " has a clear same-support latch/care endpoint")

func _test_passenger_landmark() -> void:
	var world := _before_action("2-3", "beat")
	for phase in range(3):
		stage.set_world(world)
		var before: Dictionary = world.snapshot()
		var deck := _mark("stage")
		_check(deck != null and deck.get_meta("mechanism_state") == "passenger_deck", "stage mark remains a passenger landmark in phase " + str(phase))
		_check(deck.has_node("SongPassengerMark/PassengerDeckPaint") and deck.get_node("SongPassengerMark").get_parent() == deck, "boarding paint belongs to the real moving platform")
		_check(deck.find_children("*", "Sprite3D", true, false).is_empty() and not deck.has_meta("flower_fixed_center"), "stage landmark does not masquerade as another flower bed on the shore")
		_check_hard_bases(deck, 0, "passenger paint adds no stone foot or obstacle")
		_check(not stage._prop_obstacles.any(func(entry: Dictionary) -> bool: return str(entry.id).begins_with("mark:stage/")), "boarding marker leaves no orphaned planter footprint in the route planner")
		_check(not world.commands().any(func(command: Dictionary) -> bool: return str(command.id) == "use:stage"), "removing the planter does not invent a planting action")
		_check(world.snapshot() == before, "passenger landmark leaves rule state unchanged")
		if phase < 2:
			_check(world.act("beat").ok, "original phrase still turns and raises the passenger deck")

func _test_care() -> void:
	var world := _before_action("3-3", "use:care")
	stage.set_world(world)
	_check(_mark("care").get_meta("mechanism_state") == "awaiting_dew", "root care initially waits for actual dew")
	_check(world.act("use:care").ok, "real dew delivery succeeds")
	stage.refresh_world(world)
	_check(world.flag("root") and not world.flag("care"), "care regression uses this level's real root flag")
	_check(_mark("care").get_meta("mechanism_state") == "rooted", "stable roots show their actual retained-water state")
	_check(_mark("care").has_node("NaturalRootBasin") and _mark("care").get_node("NaturalRootBasin").texture.atlas.resource_path.ends_with("root-basin-settled-v1.png") and not _mark("care").has_node("bloom"), "root care fills its natural bowl rather than a second flowerbed")
	world.undo()
	stage.refresh_world(world)
	_check(_mark("care").get_meta("mechanism_state") == "awaiting_dew", "undo returns to pre-dew appearance")
	_check(_mark("care").get_node("NaturalRootBasin").texture.atlas.resource_path.ends_with("root-basin-v1.png"), "undo restores the actual empty-root artwork")

func _test_ferry() -> void:
	var world := _before_action("2-4", "use:plant")
	stage.set_world(world)
	_check(_mark("invite").get_child_count() == 0, "invitation anchor does not duplicate the nectar flower")
	_check(_mark("plant").get_child_count() == 1, "ferry has one visible nectar flower")
	_check(_mark("invite").get_meta("shared_visual") == "mark:plant", "invitation keeps the original shared position")
	_check(world.act("use:plant").ok, "real nectar planting succeeds")
	stage.refresh_world(world)
	_check(_mark("plant").get_meta("mechanism_state") == "planted", "nectar flower visibly responds to planting")
	_check(world.commands().any(func(command: Dictionary) -> bool: return command.id == "use:invite"), "deduplicating art does not remove the invitation action")
	var before: Dictionary = world.snapshot()
	stage.refresh_world(world)
	_check(world.snapshot() == before and not world.flag("pollinated"), "flower visuals never auto-invite or pollinate")

func _test_memory() -> void:
	var world := _before_action("3-2", "freeze")
	stage.set_world(world)
	var leaf: Sprite3D = _mark("freeze").get_node("lilypad")
	_check(leaf.offset == Vector2.ZERO and Vector2(leaf.position.x, leaf.position.z) == Vector2.ZERO, "memory leaf is centred on its support anchor")
	_check(leaf.billboard == BaseMaterial3D.BILLBOARD_DISABLED and leaf.basis.z.is_equal_approx(Vector3.UP), "memory leaf remains laid on the support plane")
	_check(_mark("freeze").get_meta("mechanism_state") == "empty_memory", "no projection is shown as retained before freezing")
	_check(world.act("freeze").ok, "actual projection can be frozen")
	stage.refresh_world(world)
	var retained: Array = world.state.shadowMemory.duplicate(true)
	var frozen := int(world.state.frozen)
	var expected := "sun_memory" if frozen == 0 else "moon_memory"
	_check(_mark("freeze").get_meta("mechanism_state") == expected, "retained projection uses frozen mode rather than absent freeze flag")
	var after: Dictionary = world.snapshot()
	stage.set_world(World.new("1-3"))
	stage.set_world(World.new("3-2", after))
	_check(_mark("freeze").get_meta("mechanism_state") == expected, "saved memory restores the correct visual mode")
	_check(stage.world.state.shadowMemory == retained, "memory dressing preserves actual saved projection coordinates")

func _test_instruments() -> void:
	for entry: Array in [["1-3", "turn", "rotate", "转"], ["2-1", "water", "lift", "↕"], ["2-4", "slide", "slide", "↔"], ["3-2", "mode", "daylight", "日"], ["3-3", "turn", "rotate", "转"], ["3-3", "lift", "lift", "↕"], ["3-4", "inner", "rotate", ""], ["3-4", "water", "rotate", ""], ["3-4", "lift", "lift", ""], ["3-4", "light", "rotate", ""], ["cloud-1", "turn", "rotate", "转"], ["cloud-2", "dock", "recall", "↓"], ["cloud-2", "valve", "lift", "↕"], ["cloud-3", "turn", "rotate", "转"]]:
		var world: RefCounted = Cloud.new(str(entry[0])) if str(entry[0]).begins_with("cloud-") else World.new(str(entry[0]))
		var snapshot: Dictionary = world.snapshot()
		stage.set_world(world)
		var node := _mark(str(entry[1]))
		if str(entry[0]).begins_with("cloud-"):
			var original: Sprite3D = node.get_node_or_null("Original_"+str(entry[1]))
			_check(original != null,str(entry[0])+" retains dedicated original mechanism artwork")
			if original != null:
				_check(is_equal_approx(original.pixel_size*2,sqrt(2.0)/58.0) and not original.no_depth_test,str(entry[0])+" mechanism source ratio and real depth")
				_check(original.texture.get_image().get_used_rect().has_area(),str(entry[0])+" mechanism raster contains visible geometry")
			_check_hard_bases(node, 1, str(entry[0])+" original control stone base")
			_check(snapshot == world.snapshot(),str(entry[0])+" original mechanism preserves rules")
			_test_cloud_action(str(entry[0]),"lift" if str(entry[0]) == "cloud-2" else "rotate")
			continue
		_check(str(node.get_meta("motion_kind")) == str(entry[2]), str(entry[0]) + " instrument uses actual module kind")
		if str(entry[0]) == "3-3":
			_check(node.has_node("NaturalWheel" if str(entry[1]) == "turn" else "NaturalLift"), "3-3 retains a distinct natural mechanism silhouette")
			_check(node.find_children("*", "Label3D", true, false).is_empty(), "3-3 mechanisms no longer encode identity in text")
			_check_hard_bases(node, 1, "3-3 natural mechanism retains its real stone base")
			_check(snapshot == world.snapshot(), "3-3 natural mechanism preserves domain snapshot")
			continue
		if str(entry[0]) == "3-4":
			var role := str(entry[1])
			var label := "3-4 " + role
			var art: Sprite3D = node.get_node_or_null("NaturalLift" if role == "lift" else "NaturalWheel")
			_check(art != null and art.texture is AtlasTexture and not art.no_depth_test,label + " uses natural wood/stone art with real depth")
			_check(node.find_children("*", "Label3D", true, false).is_empty() and not node.has_node("InstrumentStem") and not node.has_node("InstrumentWheel"),label + " replaces the old text-post construction")
			var attachment := str({"inner":"GardenDriveGear","water":"WaterOutletTrough","lift":"GuardianLiftFloat","light":"LightBearingFork"}[role])
			_check(node.has_node(attachment) and str(node.get_meta("guardian_role", "")) == role,label + " retains its distinct physical mechanism")
			var natural_base: MeshInstance3D = node.get_node("InstrumentBase")
			var expected_axis := Vector2(.28,-.04 if role == "light" else 0.0)
			_check(Vector2(natural_base.position.x,natural_base.position.z).is_equal_approx(expected_axis) and is_zero_approx(natural_base.position.y-natural_base.mesh.height*.5),label + " existing grounded control axis is preserved")
			_check(is_equal_approx(natural_base.mesh.top_radius,.19) and is_equal_approx(natural_base.mesh.bottom_radius,.1995),label + " original stone top and flared hard-foot radii are preserved")
			_check_hard_bases(node,1,label + " natural mechanism retains one registered stone base")
			_check(snapshot == world.snapshot(),label + " natural mechanism preserves domain snapshot")
			continue
		var base: MeshInstance3D = node.get_node("InstrumentBase")
		var stem: MeshInstance3D = node.get_node("InstrumentStem")
		var wheel: MeshInstance3D = node.get_node("InstrumentWheel")
		# Source55px flower restoration requires the already tested wider side
		# placement; logical mark centres and the full deck support stay fixed.
		var axis := Vector2(0.60, -0.60) if str(entry[0]) == "2-4" else Vector2(.28,0)
		if str(entry[0]) == "3-3" and str(entry[1]) == "turn": axis = Vector2(-.30,-.30)
		if str(entry[0]) == "3-4" and str(entry[1]) == "light": axis = Vector2(.28,-.04)
		_check(Vector2(base.position.x, base.position.z).is_equal_approx(axis) and Vector2(stem.position.x, stem.position.z).is_equal_approx(axis) and Vector2(wheel.position.x, wheel.position.z).is_equal_approx(axis), str(entry[0]) + " instrument shares its reviewed display axis")
		_check(is_zero_approx(base.position.y - (base.mesh as CylinderMesh).height * 0.5), str(entry[0]) + " base contacts its support without floating")
		if str(entry[0]) == "3-2":
			_check(node.find_children("*", "Label3D", true, false).is_empty(), "3-2 uses physical sun/moon silhouettes instead of floating motion text")
			var sun: MeshInstance3D = node.get_node("CurrentSun")
			var moon: MeshInstance3D = node.get_node("CurrentMoon")
			_check(int(sun.get_meta("celestial_mode")) == 0 and int(moon.get_meta("celestial_mode")) == 1 and sun.mesh != moon.mesh, "3-2 control has distinct actual sun and moon shapes")
			for symbol: MeshInstance3D in [sun, moon]:
				_check(absf(wheel.basis.y.normalized().dot(symbol.basis.z.normalized())) > .9999, "3-2 wheel and celestial relief share one physical face plane")
				_check(not (symbol.material_override as StandardMaterial3D).no_depth_test, "3-2 celestial relief respects scene depth")
			_check(sun.basis.x.length() > moon.basis.x.length() and int(node.get_meta("shadow_mode")) == int(world.state.mode), "3-2 active relief prominence follows current sunlight")
			_check(node.has_node("CurrentModeNotch"), "3-2 selected mode also has a physical notch")
			_check_hard_bases(node, 1, "3-2 instrument retains its one stone base")
			_check(snapshot == world.snapshot(), "3-2 celestial control preserves domain snapshot")
			continue
		var label: Label3D = node.get_node("MotionKind")
		_check(label.billboard == BaseMaterial3D.BILLBOARD_DISABLED and absf(wheel.basis.y.dot(label.basis.z)) > 0.9999, str(entry[0]) + " wheel and symbol share one physical face plane")
		_check(stage.world_to_screen(wheel.global_position).distance_to(stage.world_to_screen(label.global_position)) < 0.01, str(entry[0]) + " glyph projects at the wheel centre")
		var label_offset := label.position - wheel.position
		_check(is_zero_approx(label_offset.dot(label.basis.x)) and is_zero_approx(label_offset.dot(label.basis.y)) and label_offset.dot(label.basis.z) > 0, str(entry[0]) + " symbol is only offset toward the viewer to avoid overlap")
		_check(label.text == str(entry[3]) and not label.no_depth_test, str(entry[0]) + " motion glyph respects scene depth")
		_check(label.font == Props.SYMBOL_FONT and label.font.has_char(label.text.unicode_at(0)), str(entry[0]) + " motion symbol has an embedded supported glyph")
		_check_hard_bases(node, 1, str(entry[0]) + " instrument stone base")
		_check(snapshot == world.snapshot(), str(entry[0]) + " dressing preserves domain snapshot")
	# The low-shore dew must be collected before flooding that shore. Use the
	# real pre-valve state rather than weakening this occupied-item safeguard.
	var pond := _before_action("2-1", "valve:water")
	stage.set_world(pond)
	_check(int(_mark("water").get_meta("height_step")) == 0 and _mark("water").has_node("Height_2"), "pond scale starts at low and preserves all three water levels")
	_check(pond.act("valve:water").ok, "actual water valve advances")
	stage.refresh_world(pond)
	_check(int(_mark("water").get_meta("height_step")) == 1, "water scale tracks current middle level")
	var identity := _mark("water").get_instance_id()
	stage.refresh_world(pond)
	_check(_mark("water").get_instance_id() == identity, "stationary state does not rebuild the instrument")

func _test_cloud_action(level: String,action: String) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for entry: Dictionary in reference.levels:
		if str(entry.id) != level: continue
		var previous: Dictionary = entry.initial
		for step: Dictionary in entry.steps:
			if str(step.command.value) == action:
				var world := Cloud.new(level,previous)
				var before: Dictionary = world.snapshot()
				stage.set_world(world)
				_check(world.act(action).ok,level+" original control still executes actual "+action)
				var after: Dictionary = world.snapshot()
				stage.refresh_world(world)
				_check(world.snapshot() == after and after != before,level+" rendering preserves committed mechanism change")
				world.undo()
				stage.refresh_world(world)
				_check(world.snapshot() == before,level+" original mechanism undo remains exact")
				return
			previous = step.snapshot
	_check(false,level+" reference contains "+action)

func _test_baseline() -> void:
	for id: String in ["1-1", "1-2"]:
		var world := World.new(id)
		stage.set_world(world)
		_check(Props.state_signature(world).is_empty(), id + " has no new cache dependency")
		_check(not _mark("root").has_meta("mechanism_state"), id + " approved root presentation remains untouched")

func _test_lever_alignment() -> void:
	var world := _before_action("1-4", "use:hold")
	for held: bool in [false, true]:
		if held: _check(world.act("use:hold").ok, "real lever action switches its state")
		var snapshot: Dictionary = world.snapshot()
		stage.set_world(world)
		stage.refresh_world(world)
		var node := _mark("hold")
		var base: MeshInstance3D = node.get_node("LeverBase")
		var arm: MeshInstance3D = node.get_node("LeverArm")
		var handle: MeshInstance3D = node.get_node("LeverHandle")
		var base_box: BoxMesh = base.mesh
		var arm_box: BoxMesh = arm.mesh
		var half_arm := Vector3(0, arm_box.size.y * 0.5, 0)
		_check(Vector2(base.position.x, base.position.z) == Vector2.ZERO and is_zero_approx(base.position.y - base_box.size.y * 0.5), "lever base is centred and seated in either state")
		_check((arm.position - arm.basis * half_arm).is_equal_approx(Vector3(0, 0.1, 0)), "lever rotates around its fixed base hinge")
		_check(handle.position.is_equal_approx(arm.position + arm.basis * half_arm), "lever handle stays attached to the moving arm tip")
		_check(is_equal_approx(handle.position.distance_to(Vector3(0,.1,0)),.47),"pulling changes direction without stretching the lever arm")
		_check(handle.position.x>0 and handle.position.z>.1 if held else handle.position.x<0 and is_zero_approx(handle.position.z),"held handle moves towards the standing operator, released handle returns to its old side")
		_check_hard_bases(node, 1, "lever stone base")
		_check(world.snapshot() == snapshot, "lever alignment preserves domain state")

func _test_symbol_font() -> void:
	for symbol: String in ["转", "↑", "–", "日", "月", "·", "↔", "↕", "↓", "Ⅰ"]:
		_check(Props.SYMBOL_FONT.has_char(symbol.unicode_at(0)), "embedded font supports mechanism glyph " + symbol)
	for id: String in ["2-3", "3-2"]:
		stage.set_world(World.new(id))
		var mark := _mark("song" if id == "2-3" else "mode")
		for child: Node in mark.get_children():
			if child is Label3D:
				_check(child.font == Props.SYMBOL_FONT, id + " 3D symbol does not depend on desktop fallback fonts")

func _test_moving_gauge(level: String, action: String, mark: String) -> void:
	# The natural 3-3 float has an art-relative trajectory, checked through
	# actual stage motion in native_symbiosis_presentation_test.
	if level == "3-3": return
	var world := _before_action(level, action)
	var before: Dictionary = world.snapshot()
	_check(world.act(action).ok, level + " real lift action prepares the gauge transition")
	var after: Dictionary = world.snapshot()
	stage.set_world(World.new(level, before))
	stage.set_motion(before, after, 0.0, action)
	var pointer: MeshInstance3D = _mark(mark).get_node("HeightPointer")
	var identities := [pointer.get_instance_id(), pointer.mesh.get_instance_id()]
	var body_transform: Transform3D = stage.get_actor_body("luvie").transform
	for phase: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		stage.set_motion(before, after, phase, action)
		# Settling installs destination terrain and refreshes its supported props.
		# Inspect the live pointer; the old queued node is no longer rendered.
		pointer = _mark(mark).get_node("HeightPointer")
		var eased := phase * phase * (3 - 2 * phase)
		_check(is_equal_approx(pointer.position.y, 0.15 + eased * 0.11), level + " gauge follows actual ascent phase " + str(phase))
		if phase < 1.0:
			_check(identities == [pointer.get_instance_id(), pointer.mesh.get_instance_id()], level + " moving gauge reuses node and mesh")
		else:
			_check(pointer.is_inside_tree() and not pointer.is_queued_for_deletion(), level + " settled gauge belongs to live destination geometry")
		_check(stage.get_actor_body("luvie").transform == body_transform, level + " gauge never moves the actor root")
	stage.set_motion(after, before, 0.0, "undo")
	pointer = _mark(mark).get_node("HeightPointer")
	for phase: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		stage.set_motion(after, before, phase, "undo")
		pointer = _mark(mark).get_node("HeightPointer")
		var eased := phase * phase * (3 - 2 * phase)
		_check(is_equal_approx(pointer.position.y, 0.15 + (1.0 - eased) * 0.11), level + " reverse gauge follows descent phase " + str(phase))
	stage.set_motion(after, before, 0.5, "undo")
	stage.clear_motion(false)
	_check(is_equal_approx(_mark(mark).get_node("HeightPointer").position.y, 0.15), level + " clearing motion resets the gauge to current world state")
	_check(world.snapshot() == after, level + " gauge sampling preserves the actual domain transaction")

func _before_action(level: String, action: String) -> RefCounted:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) != "authored/" + level: continue
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act" and str(step.command.value) == action:
				return World.new(level, before)
			before = step.snapshot
	_check(false, "authored action exists: " + level + "/" + action)
	return World.new(level)

func _check_hard_bases(root_node: Node3D, expected_count: int, label: String) -> void:
	# 76's hard feet are required. Audit the actual shapes and their independent
	# visible-mesh AABBs, rather than accepting arbitrary collision descendants.
	var bodies: Array[StaticBody3D] = []
	var pending: Array[Node] = [root_node]
	var shapes := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is CollisionObject3D:
			_check(node is StaticBody3D, label + " only declared static hard feet")
			if node is StaticBody3D: bodies.append(node)
		if node is CollisionShape3D: shapes += 1
	_check(bodies.size() == expected_count and shapes == expected_count, label + " exact local base count without an extra doorway wall")
	for body: StaticBody3D in bodies:
		_check(body.collision_layer == 8 and body.collision_mask == 0 and bool(body.get_meta("not_walkable_support", false)), label + " anti-entry layer never adds walkable terrain")
		var id := str(body.get_meta("prop_obstacle_id", ""))
		var matching: Array[Dictionary] = []
		for entry: Dictionary in stage._prop_obstacles:
			if str(entry.id) == id: matching.append(entry)
		_check(not id.is_empty() and matching.size() == 1, label + " one planner footprint per physical base")
		var volume: CollisionShape3D = body.get_node_or_null("BaseVolume") as CollisionShape3D
		_check(volume != null and volume.shape is BoxShape3D and not volume.disabled, label + " complete enabled hard-foot box")
		if volume == null or not volume.shape is BoxShape3D or matching.size() != 1: continue
		var box := volume.shape as BoxShape3D
		var entry := matching[0]
		var rect: Rect2 = entry.rect
		_check(volume.global_basis.is_equal_approx(Basis.IDENTITY), label + " planner and collider share world ground axes")
		_check(is_equal_approx(box.size.x, rect.size.x) and is_equal_approx(box.size.z, rect.size.y), label + " full declared footprint is physically blocked")
		_check(Vector2(volume.global_position.x, volume.global_position.z).is_equal_approx(rect.get_center()), label + " collider and planner footprint centres agree")
		_check(is_equal_approx(volume.global_position.y-box.size.y*.5, float(entry.floor)) and is_equal_approx(volume.global_position.y+box.size.y*.5, float(entry.top)), label + " physical volume matches the registered height band")
		_check(is_equal_approx(box.size.y,.41), label + " local stone has the established non-step-up clearance")
		var visual: Node3D = body.get_parent() as Node3D
		if visual is MeshInstance3D:
			_check(str(visual.name) in ["InstrumentBase","LeverBase","SongBase","LatchPost"], label + " collision belongs to a visible base mesh")
			var bounds: AABB = visual.mesh.get_aabb()
			var low := Vector3(INF,INF,INF)
			var high := Vector3(-INF,-INF,-INF)
			for index in range(8):
				var at: Vector3 = visual.to_global(bounds.get_endpoint(index))
				low = low.min(at)
				high = high.max(at)
			_check(rect.position.is_equal_approx(Vector2(low.x,low.z)) and rect.end.is_equal_approx(Vector2(high.x,high.z)), label + " footprint exactly covers actual visible mesh bounds")
			_check(is_equal_approx(float(entry.floor),low.y), label + " visible mesh and collider start on the same support")
		else:
			# The separate arch-pillar and cloud vector footprint contracts have
			# dedicated geometry tests; here reject a detached or unregistered box.
			_check(visual == root_node or (visual is Sprite3D and visual.get_parent() == root_node), label + " painted hard foot stays attached to its original art")
			_check(is_equal_approx(float(entry.floor),visual.global_position.y), label + " painted hard foot remains on its own support height")

func _check_song_contact(node: Node3D) -> void:
	var base: MeshInstance3D = node.get_node("SongBase")
	var base_bounds := base.mesh.get_aabb()
	_check(is_zero_approx(base.position.y + base_bounds.position.y), "song base rests on the support plane")
	_check_hard_bases(node, 1, "song wooden cradle")
	var top := base.position.y + base_bounds.end.y
	for index in range(3):
		var leaf: MeshInstance3D = node.get_node("ActionLeaf_" + str(index))
		var leaf_bounds := leaf.mesh.get_aabb()
		var relief: Node3D = node.get_node("ActionSymbol_" + str(index))
		var lowest := INF
		for corner in range(8):
			lowest = minf(lowest, (leaf.transform * leaf_bounds.get_endpoint(corner)).y)
		_check(lowest >= top, "song complete tilted key underside clears the physical instrument base")
		_check(relief.basis.y.is_equal_approx(leaf.basis.y) and relief.basis.x.normalized().is_equal_approx(leaf.basis.x) and relief.basis.z.normalized().is_equal_approx(leaf.basis.z), "song carving follows its actual tilted leaf instead of facing the camera")
		var local_glyph := leaf.basis.inverse() * (relief.position - leaf.position)
		var minimum_gap := INF
		for part: MeshInstance3D in relief.get_children():
			minimum_gap = minf(minimum_gap, local_glyph.y + part.mesh.get_aabb().position.y - leaf_bounds.end.y)
			_check(not part.material_override.no_depth_test and part.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "shallow relief keeps depth without a text shadow halo")
		_check(absf(local_glyph.x) < 0.00001 and absf(local_glyph.z) < 0.00001 and is_equal_approx(minimum_gap, .0015), "song relief underside clears the actual key face by 1.5mm")

func _check_latch_contact(node: Node3D, label: String) -> void:
	var post: MeshInstance3D = node.get_node("LatchPost")
	var box: BoxMesh = post.mesh
	_check(is_zero_approx(post.position.y - box.size.y * 0.5), label + " post rests on the support plane")
	var bolt: MeshInstance3D = node.get_node("LatchBolt")
	var bolt_box: BoxMesh = bolt.mesh
	var outer_latch: bool=str(stage.world.level.id)=="1-4"
	var hinge := bolt.position + bolt.basis * Vector3(bolt_box.size.x * (-0.5 if outer_latch else 0.5), 0, 0)
	var expected:=Vector3(.30,.48,-.473)+Props.FACE_NORMAL*.045 if outer_latch else Vector3(.27,.26,.16)
	if str(stage.world.level.id)=="2-3": expected+=Vector3(-.67,0,.18)
	_check(hinge.is_equal_approx(expected), label + " bolt endpoint stays attached to the same hinge")
	if str(stage.world.level.id)=="1-4":
		_check(is_equal_approx(box.size.y,.52) and is_equal_approx(box.size.x,.14),label+" outer latch bracket stays grounded at its actual size")
		_check(not node.has_node("LatchLabel") and not node.has_node("LatchPlaque"),label+" no action word masquerades as a state sign")
		var socket: Node3D=node.get_node("LatchSocket")
		var end:=bolt.position+bolt.basis*Vector3(bolt_box.size.x*.5,0,0)
		var nearest:=Geometry3D.get_closest_point_to_segment(socket.position,hinge,end)
		_check(nearest.distance_to(socket.position)<.001 if stage.world.flag("latch") else nearest.distance_to(socket.position)>.12,label+" pin passes through its attached keeper only after the actual latch flag")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
