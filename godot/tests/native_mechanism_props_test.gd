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
	print(JSON.stringify({"suite": "native-mechanism-props", "passed": failures.is_empty(), "checks": checks, "failures": failures, "gpuPixelsVerified": false, "scope": "Current-state cues, actual actions and undo, refresh invalidation, collision-free props and unchanged domain snapshots."}))
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
	_check(node.get_node("ActionSymbol_0").text == "转", "song initially shows the actual turn leaf")
	_check(node.get_node("ActionSymbol_1").text == "↑", "song initially shows the actual rise leaf")
	var node_id := node.get_instance_id()
	stage.refresh_world(world)
	_check(node_id == _mark("song").get_instance_id(), "unchanged state reuses props")
	_check(world.act("swap:0").ok, "real action can exchange leaves before rehearsal")
	stage.refresh_world(world)
	_check(_mark("song").get_node("ActionSymbol_0").text == "↑", "exchange invalidates props and changes the first visible action")
	_check(_mark("song").get_node("ActionSymbol_1").text == "转", "exchange moves the turn symbol with its leaf")
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
	_check(world.act("resetSong").ok, "real reset restores trial state")
	stage.refresh_world(world)
	_check(int(_mark("song").get_meta("beat")) == 0, "reset releases all played leaves")
	_check(_mark("song").get_node("ActionSymbol_0").text == "↑", "reset preserves the chosen phrase instead of a hardcoded answer")
	var snapshot: Dictionary = world.snapshot()
	stage.refresh_world(world)
	_check(world.snapshot() == snapshot, "song dressing never mutates the trial snapshot")
	stage.set_world(World.new("1-3"))
	stage.set_world(World.new("2-3", original))
	_check(_mark("song").get_node("ActionSymbol_0").text == "转", "cross-level restore does not retain another phrase")

func _test_latch(level: String) -> void:
	var world := _before_action(level, "use:latch")
	stage.set_world(world)
	_check(_mark("latch").get_meta("mechanism_state") == "unfixed", level + " latch starts visibly unfixed")
	_check_latch_contact(_mark("latch"), level + " open")
	var before_angle: float = _mark("latch").get_node("LatchBolt").rotation.z
	_check(world.act("use:latch").ok, level + " actual latch action succeeds")
	stage.refresh_world(world)
	_check(_mark("latch").get_meta("mechanism_state") == "fixed", level + " fixed latch reflects real flag")
	_check_latch_contact(_mark("latch"), level + " locked")
	_check(absf(_mark("latch").get_node("LatchBolt").rotation.z - before_angle) > 1.0, level + " bolt visibly changes orientation")
	var snapshot: Dictionary = world.snapshot()
	_check(not _contains_collision(_mark("latch")), level + " decorative latch introduces no physical gate")
	_check(world.snapshot() == snapshot, level + " rendering leaves logic unchanged")
	world.undo()
	stage.refresh_world(world)
	_check(_mark("latch").get_meta("mechanism_state") == "unfixed", level + " undo restores latch appearance")

func _test_care() -> void:
	var world := _before_action("3-3", "use:care")
	stage.set_world(world)
	_check(_mark("care").get_meta("mechanism_state") == "awaiting_dew", "root care initially waits for actual dew")
	_check(world.act("use:care").ok, "real dew delivery succeeds")
	stage.refresh_world(world)
	_check(world.flag("root") and not world.flag("care"), "care regression uses this level's real root flag")
	_check(_mark("care").get_meta("mechanism_state") == "rooted", "stable roots now have a visible flowering result")
	_check(_mark("care").has_node("bloom"), "root care uses the authored bloom image")
	world.undo()
	stage.refresh_world(world)
	_check(_mark("care").get_meta("mechanism_state") == "awaiting_dew", "undo returns to pre-dew appearance")

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
	for entry: Array in [["1-3", "turn", "rotate", "转"], ["2-1", "water", "lift", "↕"], ["2-4", "slide", "slide", "↔"], ["3-2", "mode", "daylight", "日"], ["3-3", "turn", "rotate", "转"], ["3-3", "lift", "lift", "↕"], ["3-4", "water", "rotate", "转"], ["3-4", "light", "rotate", "转"], ["cloud-1", "turn", "rotate", "转"], ["cloud-2", "dock", "recall", "↓"], ["cloud-2", "valve", "lift", "↕"], ["cloud-3", "turn", "rotate", "转"]]:
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
			_check(not _contains_collision(node) and snapshot == world.snapshot(),str(entry[0])+" original mechanism does not alter collision or rules")
			_test_cloud_action(str(entry[0]),"lift" if str(entry[0]) == "cloud-2" else "rotate")
			continue
		_check(str(node.get_meta("motion_kind")) == str(entry[2]), str(entry[0]) + " instrument uses actual module kind")
		var label: Label3D = node.get_node("MotionKind")
		var base: MeshInstance3D = node.get_node("InstrumentBase")
		var stem: MeshInstance3D = node.get_node("InstrumentStem")
		var wheel: MeshInstance3D = node.get_node("InstrumentWheel")
		# Source55px flower restoration requires the already tested wider side
		# placement; logical mark centres and the full deck support stay fixed.
		var axis := Vector2(0.60, -0.60) if str(entry[0]) == "2-4" else Vector2(.28,0)
		if str(entry[0]) == "3-3" and str(entry[1]) == "turn": axis = Vector2(-.30,0)
		if str(entry[0]) == "3-4" and str(entry[1]) == "light": axis = Vector2(.28,-.04)
		_check(Vector2(base.position.x, base.position.z) == axis and Vector2(stem.position.x, stem.position.z) == axis and Vector2(wheel.position.x, wheel.position.z) == axis, str(entry[0]) + " instrument shares its reviewed display axis")
		_check(is_zero_approx(base.position.y - (base.mesh as CylinderMesh).height * 0.5), str(entry[0]) + " base contacts its support without floating")
		_check(label.billboard == BaseMaterial3D.BILLBOARD_DISABLED and absf(wheel.basis.y.dot(label.basis.z)) > 0.9999, str(entry[0]) + " wheel and symbol share one physical face plane")
		_check(stage.world_to_screen(wheel.global_position).distance_to(stage.world_to_screen(label.global_position)) < 0.01, str(entry[0]) + " glyph projects at the wheel centre")
		var label_offset := label.position - wheel.position
		_check(is_zero_approx(label_offset.dot(label.basis.x)) and is_zero_approx(label_offset.dot(label.basis.y)) and label_offset.dot(label.basis.z) > 0, str(entry[0]) + " symbol is only offset toward the viewer to avoid overlap")
		_check(label.text == str(entry[3]) and not label.no_depth_test, str(entry[0]) + " motion glyph respects scene depth")
		_check(label.font == Props.SYMBOL_FONT and label.font.has_char(label.text.unicode_at(0)), str(entry[0]) + " motion symbol has an embedded supported glyph")
		_check(not _contains_collision(node), str(entry[0]) + " instrument adds no invisible collider")
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
		_check(not _contains_collision(node) and world.snapshot() == snapshot, "lever alignment changes neither collisions nor domain state")

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

func _contains_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D: return true
	for child: Node in node.get_children():
		if _contains_collision(child): return true
	return false

func _check_song_contact(node: Node3D) -> void:
	var base: MeshInstance3D = node.get_node("SongBase")
	var box: BoxMesh = base.mesh
	_check(is_zero_approx(base.position.y - box.size.y * 0.5), "song base rests on the support plane")
	var top := base.position.y + box.size.y * 0.5
	for index in range(3):
		var leaf: MeshInstance3D = node.get_node("ActionLeaf_" + str(index))
		var leaf_box: BoxMesh = leaf.mesh
		var label: Label3D = node.get_node("ActionSymbol_" + str(index))
		_check(leaf.position.y - leaf_box.size.y * 0.5 >= top, "song leaf never penetrates the instrument base")
		_check(label.billboard == BaseMaterial3D.BILLBOARD_DISABLED and label.basis.z.is_equal_approx(Vector3.UP), "song glyph lies in its leaf plane")
		_check(Vector2(label.position.x, label.position.z) == Vector2(leaf.position.x, leaf.position.z) and is_equal_approx(label.position.y - leaf.position.y - leaf_box.size.y * 0.5, 0.003), "song glyph stays centred just above the current leaf surface")

func _check_latch_contact(node: Node3D, label: String) -> void:
	var post: MeshInstance3D = node.get_node("LatchPost")
	var box: BoxMesh = post.mesh
	_check(is_zero_approx(post.position.y - box.size.y * 0.5), label + " post rests on the support plane")
	var bolt: MeshInstance3D = node.get_node("LatchBolt")
	var bolt_box: BoxMesh = bolt.mesh
	var hinge := bolt.position + bolt.basis * Vector3(bolt_box.size.x * 0.5, 0, 0)
	_check(hinge.is_equal_approx(Vector3(0.27, 0.26, 0.16)), label + " bolt endpoint stays attached to the same hinge")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
