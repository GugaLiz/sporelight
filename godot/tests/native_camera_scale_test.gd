extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Factory = preload("res://core/world_factory.gd")
const IDS = ["1-1", "1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4", "cloud-1", "cloud-2", "cloud-3"]
var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var rows: Array = []
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(844, 390), Vector2i(390, 844)]:
		stage._viewport.size = dimensions
		var safe := Rect2(22, minf(96, dimensions.y * 0.16), dimensions.x - 44, dimensions.y - minf(180, dimensions.y * 0.28))
		stage.set_layout(safe)
		stage.set_world(Factory.create("1-1"))
		stage.overview = false
		stage._fit_camera(true)
		var limit := 52.0 if dimensions.y < 430 else 68.0 if dimensions.x < 650 else 57.0
		var approved := dimensions.y / limit if dimensions.x < 650 or dimensions.y < 430 else minf(maxf(5.8, stage._framing_size), dimensions.y / limit)
		check(is_equal_approx(stage._camera.size, approved), str(dimensions) + " approved first camera unchanged")
		var size: float = stage._camera.size
		for id: String in IDS:
			stage.set_world(Factory.create(id))
			stage.overview = false
			stage._fit_camera(true)
			check(is_equal_approx(stage._camera.size, size), id + " same play scale " + str(dimensions))
			var normal: float = stage._camera.size
			var focus: Vector3 = stage._focus
			if stage._framing_size > normal * 1.02:
				var body: CharacterBody3D = stage.get_actor_body(str(stage.world.state.active))
				check(focus.is_equal_approx(body.position + Vector3(0, 0.45, 0)), id + " large garden follows actor")
			stage.overview = true
			stage._fit_camera(true)
			check(is_equal_approx(stage._camera.size, maxf(5.8, stage._overview_framing_size)), id + " overview fits authored extent")
			check(stage._focus.is_equal_approx(stage._overview_focus), id + " overview centres projected map")
			check_terrain_inside(stage, safe, id + str(dimensions))
			check_prop_art_inside(stage, safe, id + str(dimensions))
			stage.overview = false
			stage._fit_camera(true)
			check(is_equal_approx(stage._camera.size, normal), id + " returns to play scale")
			rows.append({"size": str(dimensions), "level": id, "pixelsPerUnit": dimensions.y / normal})
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-camera-scale", "checks": checks, "failures": failures, "rows": rows, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func check_terrain_inside(stage: Node2D, safe: Rect2, label: String) -> void:
	# Independent visual-mesh vertices, not the framing helper's AABB or
	# tile-centre approximation: the reported cloud-3 failure was a side edge.
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for surface: Node3D in stage._surfaces.values():
		for part: MeshInstance3D in [surface._top, surface._sides, surface._treads, surface._risers, surface._ramps]:
			if part.mesh == null: continue
			for index in range(part.mesh.get_surface_count()):
				var vertices: PackedVector3Array = part.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					var screen: Vector2 = stage.world_to_screen(part.global_transform * vertex)
					low = low.min(screen)
					high = high.max(screen)
	check(safe.grow(0.1).encloses(Rect2(low, high - low)), label + " every terrain edge fits overview safe area")

func check_prop_art_inside(stage: Node2D, safe: Rect2, label: String) -> void:
	# Independent source-canvas corners include nested fountain/gate art and
	# billboard projection; the old cloud-only shallow traversal omitted them.
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	var stack: Array = stage._props.get_children()
	var count := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is Sprite3D: continue
		var card := node as Sprite3D
		if not card.is_visible_in_tree() or card.texture == null: continue
		for pixel: Vector2 in [Vector2.ZERO,Vector2(card.texture.get_width(),0),Vector2(card.texture.get_width(),card.texture.get_height()),Vector2(0,card.texture.get_height())]:
			var local := Vector3(pixel.x-card.texture.get_width()*.5+card.offset.x,card.texture.get_height()*.5-pixel.y+card.offset.y,0)*card.pixel_size
			var point: Vector3 = card.to_global(local)
			if card.billboard == BaseMaterial3D.BILLBOARD_ENABLED:
				var size := card.global_basis.get_scale()
				point = card.global_position+stage._camera.global_basis.x*local.x*size.x+stage._camera.global_basis.y*local.y*size.y
			var screen: Vector2 = stage.world_to_screen(point)
			low = low.min(screen); high = high.max(screen)
		count += 1
	check(count>0 and safe.grow(.1).encloses(Rect2(low,high-low)),label+" full visible nested source artwork fits overview")
