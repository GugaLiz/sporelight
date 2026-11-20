extends SceneTree
## Guardian-only size correction; prepared art states are not traversal evidence.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
const Guardian = preload("res://presentation/native/guardian_dressing.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Array = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var original: Dictionary = {}
	for entry: Dictionary in reference.cases:
		if str(entry.name)=="authored/3-4": original=entry
	_check(not original.is_empty(), "original guardian fixture remains available")
	var states: Array = [original.initial.snapshot, original.steps[46].snapshot, original.steps[94].snapshot, original.steps[95].snapshot, original.initial.snapshot]
	var previous: Dictionary = {}
	for index: int in states.size():
		var world := World.new("3-4",states[index])
		var before := world.snapshot().duplicate(true)
		var tiles := world.tiles().duplicate(true)
		var ray_before := world.rays().duplicate(true)
		stage.set_world(world)
		var core: Node3D = stage._props_nodes["mark:core"]
		var layout: Dictionary = core.get_meta("original_core_layout")
		var art: Sprite3D
		for child: Node in core.get_children():
			if child is Sprite3D and child.has_meta("core_planter"): art=child
		_check(art!=null,"guardian retains a single integrated flowerbed")
		if art==null: continue
		_check(is_equal_approx(float(layout.width),1.65) and str(layout.reason)=="local_guardian_planter_scale" and bool(layout.limited),"guardian alone declares compact width")
		_check(is_equal_approx(float(layout.source_width),150.0*sqrt(2.0)/70.0),"historic final canvas width retained as provenance")
		_check(layout.shift.is_equal_approx(Vector3(-.424,0,-.07)),"existing repair-island placement unchanged")
		_check(Ratios._supported_footprint(stage,core,float(layout.width),layout.shift),"complete resized stone base stays on original fixed ground")
		_check(not art.no_depth_test and art.offset==Vector2(0,102),"normal depth and original source foot registration")
		_check(art.texture==stage._texture("bloom" if world.state.completed else "flower"),"actual completion selects original flower state")
		var receiver: Node3D = core.get_node_or_null("GuardianReceivingShoot")
		_check(receiver!=null,"compact core has a physically rooted light receiving shoot")
		if receiver!=null:
			var flower: Node3D = receiver.get_node("ReceivingFlower")
			var heart: MeshInstance3D = receiver.get_node("ReceivingHeart")
			_check(flower.global_position.is_equal_approx(Vector3(-4,1.67,0)),"receiving flower meets unchanged horizontal rule light endpoint")
			_check(absf(heart.global_position.y-1.67)<.0001 and absf(heart.global_position.z)<.0001 and absf(heart.global_position.x+4)<.0495,"receiving heart intersects real light axis")
			_check(is_equal_approx(float(flower.get_meta("open_span")),.70) and flower.get_child_count()==8,"user-requested receiving flower has eight visible petals without enlarging planter")
			_check(receiver.find_children("*","CollisionObject3D",true,false).is_empty(),"soft shoot adds no collision wall or support")
			_check(receiver.find_children("*","Label3D",true,false).is_empty(),"receiver uses no scene text")
			_check(bool(receiver.get_meta("receiver_powered"))==world.beam_hits(-4,0),"current light controls receiver power rather than old star milestone")
		var span: Vector2 = art.get_meta("ground_footprint_span")
		var center: Vector3 = art.get_meta("ground_footprint_center")
		_check(span.is_equal_approx(Vector2.ONE*(.80*1.65/1.16)),"hard base matches independently expected smaller footprint")
		if receiver!=null:
			var stem_root: Vector3 = receiver.get_meta("stem_root")
			_check(absf(stem_root.x-center.x)<span.x*.5 and absf(stem_root.z-center.z)<span.y*.5 and stem_root.y>.0 and stem_root.y<.41,"slender shoot rooted within actual compact hard base")
		var obstacle: Dictionary = {}
		for entry: Dictionary in stage._prop_obstacles:
			if str(entry.id)=="mark:core": obstacle=entry
		_check(not obstacle.is_empty(),"smaller flowerbed retains its physical base")
		if not obstacle.is_empty():
			_check(obstacle.rect.size.is_equal_approx(span),"obstacle follows actual smaller stone span")
			var expected: Vector3 = core.to_global(center)
			_check(obstacle.rect.get_center().is_equal_approx(Vector2(expected.x,expected.z)),"collision and visible stone share registered centre")
		var actual := {"width":art.texture.get_width()*art.pixel_size,"position":art.position,"offset":art.offset,"span":span,"center":center,"corePosition":core.position}
		if not previous.is_empty(): _check(actual==previous,"lighting, return, bloom and reload do not move or resize the base")
		previous=actual
		_check(world.snapshot()==before and world.tiles()==tiles and world.rays()==ray_before,"art change leaves rule state, optical path and traversable topology intact")
		_check(is_equal_approx(stage.get_actor_body("luvie").get_node("Visual/Art").pixel_size,.00625),"hero size unchanged")
		var bounds: Rect2 = Ratios.BODY_BOUNDS["bloom" if world.state.completed else "flower"]
		measurements.append({"fixtureState":index,"completed":world.state.completed,"canvasWidth":actual.width,"visibleBody":[bounds.size.x*art.pixel_size,bounds.size.y*art.pixel_size],"hardSpan":[span.x,span.y],"shift":[layout.shift.x,layout.shift.y,layout.shift.z]})
	var lit := World.new("3-4",original.steps[46].snapshot)
	var dark := World.new("3-4",original.steps[46].snapshot)
	dark.state.turns.light=0
	stage.set_world(lit)
	var core: Node3D = stage._props_nodes["mark:core"]
	for progress: float in [0.0,.5,.9999,1.0]:
		Guardian.update_motion(stage,dark,lit,progress)
		_check(bool(core.get_node("GuardianReceivingShoot").get_meta("receiver_powered"))==(progress>=1.0),"receiving heart waits for actual aligned light during motion")
	Guardian.update_motion(stage,lit,dark,.5)
	_check(not bool(core.get_node("GuardianReceivingShoot").get_meta("receiver_powered")),"turning away extinguishes receiving heart despite retained star flag")
	for control: Array in [["1-1",1.16],["3-3",1.65],["3-2",110.0*sqrt(2.0)/70.0]]:
		stage.set_world(World.new(str(control[0])))
		var width := 0.0
		for child: Node in stage._props_nodes["mark:core"].get_children():
			if child is Sprite3D and child.has_meta("core_planter"): width=child.texture.get_width()*child.pixel_size
		_check(is_equal_approx(width,float(control[1])),str(control[0])+" existing accepted local size preserved")
		_check(not stage._props_nodes["mark:core"].has_node("GuardianReceivingShoot"),str(control[0])+" does not inherit guardian-only receiving shoot")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-guardian-planter","checks":checks,"failures":failures,"passed":failures.is_empty(),"measurements":measurements,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
