extends SceneTree
## Independent source-ellipse checks: the painted front edge is not its centre.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Sanctuary = preload("res://presentation/native/original_sanctuary_dressing.gd")
const Obstacles = preload("res://presentation/native/native_prop_obstacles.gd")
var checks := 0
var failures: Array[String] = []
var samples := 0

func _initialize() -> void:
	create_timer(40).timeout.connect(func() -> void: push_error("fountain contact test timed out"); quit(2))
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var first_position := Vector3.INF
	for state: String in ["initial", "opened", "completed", "undo"]:
		var world := World.new("1-4")
		if state in ["opened", "completed"]: world.state.flags.append("home")
		world.state.completed = state == "completed"
		var snapshot: Dictionary = world.snapshot().duplicate(true)
		stage.set_world(world)
		await process_frame
		var fountain: Sprite3D = stage._props.get_node_or_null("SanctuaryFountain")
		_check(fountain != null, state + " has a supported fountain")
		if fountain == null:
			stage.queue_free()
			await process_frame
			quit(1)
			return
		_check(world.snapshot() == snapshot, state + " preserves rules and saves")
		_check(is_equal_approx(float(fountain.get_meta("original_fountain_ratio")), .84375), state + " keeps accepted basin size")
		_check(is_equal_approx(fountain.pixel_size, sqrt(2.0) / 70.0 * 92.0 / 90.0 / 4.0 * .84375), state + " keeps original raster scale")
		# SVG viewBox starts at (-52,-70); the lower basin centre is (0,2).
		var anchor := Vector2((fountain.texture.get_width() * .5 - fountain.offset.x) / 4.0 - 52.0, (fountain.texture.get_height() * .5 + fountain.offset.y) / 4.0 - 70.0)
		_check(anchor.is_equal_approx(Vector2(0, 22)), state + " preserves the lowest front rim as its rendering foot")
		var unit := fountain.pixel_size * 4.0
		var outline := PackedVector2Array()
		var unsupported := 0
		for ring: float in [0.0, .25, .5, .75, 1.0]:
			for index: int in range(128):
				var angle := TAU * index / 128.0
				var source := Vector2(cos(angle) * 43.0 * ring, 2.0 + sin(angle) * 20.0 * ring) - anchor
				var point: Vector3 = fountain.position + Vector3(1, 0, -1).normalized() * source.x * unit + Vector3(1, 0, 1).normalized() * source.y * unit * 2.0
				if ring == 1.0: outline.append(Vector2(point.x, point.z))
				var id := "f:%d:%d" % [roundi(point.x), roundi(point.z)]
				var tile: Dictionary = stage._tile_map.get(id, {})
				if tile.is_empty() or not stage._surfaces.has(id) or str(tile.get("kind", "fixed")) != "fixed" or absf(stage.support_height(point, id) - (fountain.position.y - .008)) > .012:
					unsupported += 1
				samples += 1
		_check(unsupported == 0, state + " every independent lower-basin sample has real same-height support (unsupported=" + str(unsupported) + ")")
		_check(Geometry2D.is_point_in_polygon(Vector2(-9, -2), outline), state + " visible basin still covers original solid-cell centre")
		var core: Node3D = stage._props_nodes["mark:core"]
		var layout: Dictionary=core.get_meta("original_core_layout")
		_check(not bool(layout.limited) and is_equal_approx(float(layout.width),float(layout.source_width)),state+" core keeps approved full source width")
		_check(Vector3(layout.shift).is_equal_approx(Vector3(.6,0,1.6)),state+" core uses the reviewed same-island front placement")
		var tile: Dictionary=stage._tile_map["f:-9:0"]
		var hero: Vector3=stage.actor_rest_position(tile,"luvie")
		var companion: Vector3=stage.actor_rest_position(tile,"buddy")
		_check(hero.distance_to(companion)>.31,state+" real repair stopping points separate the two capsules")
		var safe: Dictionary=stage.prop_waypoint(tile,"buddy",companion)
		_check(not safe.is_empty() and (safe.point as Vector3).distance_to(companion)<.001,state+" readable companion stance is genuinely supported and reachable")
		for child in core.get_children():
			if not child.has_meta("core_planter"): continue
			var center: Vector3 = core.to_global(child.get_meta("ground_footprint_center"))
			var span: Vector2 = child.get_meta("ground_footprint_span")
			var rect := Rect2(Vector2(center.x, center.z) - span * .5, span).grow(.02)
			var polygon := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			_check(Geometry2D.intersect_polygons(outline, polygon).is_empty(), state + " full basin clears actual core stone with 2cm margin")
		var source_point := Vector2(2, -42)
		var expected: Vector3 = fountain.position + stage._camera.global_basis.x * (source_point.x - anchor.x) * unit + stage._camera.global_basis.y * (anchor.y - source_point.y) * unit + stage._camera.global_basis.z * .002
		_check(Sanctuary.effect_position(fountain.position, stage._camera, source_point.x, source_point.y, .84375).distance_to(expected) < .00001, state + " water nozzle and painted basin use the same anchor")
		var atmosphere: Node = stage._garden_effects.atmosphere
		_check(atmosphere.fountain_at == fountain.position and is_equal_approx(atmosphere.fountain_ratio, .84375), state + " persistent effects follow the actual basin")
		var found: Array=stage._prop_obstacles.filter(func(entry: Dictionary)->bool:return str(entry.id)=="sanctuary:fountain")
		_check(found.size()==1,state+" basin has exactly one physical/navigation owner")
		var volume: CollisionShape3D=fountain.get_node("FountainBasinFoot/BasinVolume")
		_check(volume.shape is ConvexPolygonShape3D and not volume.disabled,state+" painted basin owns an enabled convex collider")
		if found.size()==1:
			var entry: Dictionary=found[0]
			var vertices: PackedVector3Array=volume.shape.points
			_check(vertices.size()==outline.size()*2,state+" convex volume uses both levels of the complete source outline")
			for index in range(outline.size()):
				var point: Vector3=volume.to_global(vertices[index*2])
				_check(Vector2(point.x,point.z).distance_to(outline[index])<.00001,state+" physical hull and independent painted footprint coincide")
			var center3: Vector3=fountain.get_meta("original_sanctuary_ground_center")
			var center:=Vector2(center3.x,center3.z)
			_check(not Obstacles.clear(center3,.16,[entry]),state+" navigation rejects entering basin centre")
			# Real manual contact can be inside the planner's extra 2cm margin.
			# Escape uses the ellipse normal, not its enclosing box's normal.
			var outward: Vector2=(outline[48]-center).normalized()
			var touching: Vector2=outline[48]+outward*.165
			var free: Vector2=outline[48]+outward*.35
			var start:=Vector3(touching.x,center3.y,touching.y)
			var finish:=Vector3(free.x,center3.y,free.y)
			_check(stage.prop_physical_point_clear(start,"luvie") and not stage.prop_point_clear(start,"luvie"),state+" case exercises real contact inside navigation margin")
			_check(stage.prop_segment_clear(start,finish,"luvie"),state+" click can escape a real curved basin contact")
			_check(not stage.prop_segment_clear(start,center3,"luvie"),state+" contact escape never permits moving into the basin")
			for index: int in [0,16,32,48,64,80,96,112]:
				var normal: Vector2=(outline[index]-center).normalized()
				var outside: Vector2=outline[index]+normal*.23
				var foot:=Vector3(outside.x,fountain.position.y,outside.y)
				_check(Obstacles.clear(foot,.16,[entry]),state+" valid space outside real ellipse is not blocked by its bounding box")
				_check(not Obstacles.segment_clear(foot,Vector3(center.x,foot.y,center.y),.16,[entry]),state+" continuous navigation cannot sweep through basin edge")
				var query:=PhysicsRayQueryParameters3D.create(foot+Vector3.UP*.2,Vector3(center.x,foot.y+.2,center.y),8)
				var hit: Dictionary=stage._scene.get_world_3d().direct_space_state.intersect_ray(query)
				_check(not hit.is_empty(),state+" actual basin edge physically blocks a horizontal ray")
		if first_position == Vector3.INF: first_position = fountain.position
		else: _check(fountain.position.is_equal_approx(first_position), state + " basin position stays stable across state changes")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-fountain-contact", "checks":checks, "passed":failures.is_empty(), "failures":failures, "sourceEllipseSamples":samples, "gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
