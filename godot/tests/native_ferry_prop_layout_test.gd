extends SceneTree
## Geometry/projection checks only. Matching GPU captures remain required.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var stage: Node
var checks := 0
var failures: Array[String] = []
var alpha_bounds := {}
var min_flower_gap := INF
var min_insect_gap := INF

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var entry: Dictionary = {}
	for candidate: Dictionary in fixture.cases:
		if str(candidate.name) == "authored/2-4": entry = candidate
	var states: Array = [entry.initial.snapshot]
	var before_slide: Dictionary = {}
	var after_slide: Dictionary = {}
	for step: Dictionary in entry.steps:
		if str(step.command.value) == "turn:boat":
			before_slide = states.back()
			after_slide = step.snapshot
		states.append(step.snapshot)
	# JSON fixtures contain floating-point numerals; compare the canonical
	# saved-world representation after the same strict loader used in play.
	before_slide = World.new("2-4", before_slide).snapshot()
	after_slide = World.new("2-4", after_slide).snapshot()
	for dimensions in [Vector2i(1280, 720), Vector2i(844, 390)]:
		stage._viewport.size = dimensions
		stage.set_layout(Rect2(16, 80, dimensions.x - 32, dimensions.y - 180))
		for index in range(states.size()):
			stage.clear_motion(false)
			var world := World.new("2-4", states[index])
			var snapshot: Dictionary = world.snapshot().duplicate(true)
			stage.set_world(world)
			_layout(str(dimensions) + "/state" + str(index))
			check(world.snapshot() == snapshot, "static layout leaves gameplay/save state unchanged")
		var world := World.new("2-4", before_slide)
		check(world.act("turn:boat").ok, "real boat action succeeds")
		check(world.snapshot() == after_slide, "real boat action retains its authored result")
		stage.set_world(World.new("2-4", before_slide))
		for progress in [0.0, 0.25, 0.5, 0.75, 1.0]:
			stage.set_motion(before_slide, after_slide, progress, "turn:boat")
			_layout(str(dimensions) + "/travel" + str(progress))
		stage.clear_motion(false)
		world.undo()
		check(world.snapshot() == before_slide, "undo returns boat and occupants to original shore")
		stage.set_world(world)
		_layout(str(dimensions) + "/undo")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-ferry-prop-layout", "checks": checks, "passed": failures.is_empty(), "failures": failures, "minimumFlowerGapWorld": min_flower_gap, "minimumInsectGapWorld": min_insect_gap, "gpuPixelsVerified": false}))
	quit(0 if failures.is_empty() else 1)

func _layout(label: String) -> void:
	var controller: Node3D = stage._props_nodes["mark:slide"]
	var flower: Node3D = stage._props_nodes["mark:plant"]
	var invitation: Node3D = stage._props_nodes["mark:invite"]
	var surface: Node3D = stage._surfaces["m:boat:0:0"]
	check(controller.global_position.is_equal_approx(surface.global_position) and controller.position == flower.position and controller.position == invitation.position, label + " all three logical interactions stay at the same deck centre")
	check(controller.get_meta("tile_id") == "m:boat:0:0" and not controller.find_children("*", "CollisionObject3D", true, false).size(), label + " control keeps rule identity without new collision")
	var base: MeshInstance3D = controller.get_node("InstrumentBase")
	var wheel: MeshInstance3D = controller.get_node("InstrumentWheel")
	var control_rect := _mesh_rect(base).merge(_mesh_rect(controller.get_node("InstrumentStem"))).merge(_mesh_rect(wheel))
	var plant: Sprite3D = flower.get_child(0)
	var plant_rect := _sprite_rect(plant)
	var ppu: float = stage.world_to_screen(controller.global_position + Vector3(0.70710678, 0, -0.70710678)).distance_to(stage.world_to_screen(controller.global_position))
	var gap := (control_rect.position.x - plant_rect.end.x) / ppu
	min_flower_gap = minf(min_flower_gap, gap)
	check(gap > 0.05, label + " full control footprint projects clear of complete flower silhouette")
	# Source mechanism flower is 55px against a 70px whole-tile diamond.
	# Keep the support-relative foot rule while restoring that authored width.
	check(not plant.no_depth_test and is_equal_approx(plant.pixel_size * 256, 55.0 / 70.0 * sqrt(2.0)) and is_equal_approx(plant.position.y, 0.012 * (55.0 / 70.0 * sqrt(2.0)) / 1.16), label + " flower retains source width, normal depth and grounded height")
	var bug_root: Node3D = stage._props_nodes.get("item:bug")
	if bug_root != null and str(bug_root.get_meta("tile_id")) == "m:boat:0:0":
		var bug: Sprite3D = bug_root.get_child(0)
		var bug_gap := (control_rect.position.x - _sprite_rect(bug).end.x) / ppu
		min_insect_gap = minf(min_insect_gap, bug_gap)
		check(bug_gap > 0.05 and is_equal_approx(bug.position.y, 0.28) and not bug.no_depth_test, label + " insect remains unobstructed without raising or depth bypass")
	for dx in [-0.19, 0.0, 0.19]:
		for dz in [-0.19, 0.0, 0.19]:
			var foot := base.global_position + Vector3(dx, -0.06, dz)
			var supported := false
			for id: String in stage._surfaces:
				if not id.begins_with("m:boat:"): continue
				var support: Node3D = stage._surfaces[id]
				var local: Vector3 = support.to_local(foot)
				if absf(local.x) <= 0.5 and absf(local.z) <= 0.5 and absf(support.sample_height(foot) - foot.y) < 0.0001: supported = true
			check(supported, label + " complete controller base stays on the same moving boat")

func _mesh_rect(mesh: MeshInstance3D) -> Rect2:
	var points: Array[Vector3] = []
	for index in range(8): points.append(mesh.to_global(mesh.get_aabb().get_endpoint(index)))
	return _screen_rect(points)

func _sprite_rect(sprite: Sprite3D) -> Rect2:
	var path := sprite.texture.resource_path
	if not alpha_bounds.has(path):
		var picture := Image.load_from_file(ProjectSettings.globalize_path(path))
		var low := Vector2(picture.get_width(), picture.get_height())
		var high := Vector2.ZERO
		for y in range(picture.get_height()):
			for x in range(picture.get_width()):
				if picture.get_pixel(x, y).a >= 128.0 / 255.0:
					low = low.min(Vector2(x, y))
					high = high.max(Vector2(x + 1, y + 1))
		alpha_bounds[path] = Rect2(low, high - low)
	var rect: Rect2 = alpha_bounds[path]
	var points: Array[Vector3] = []
	for x in [rect.position.x, rect.end.x]:
		for y in [rect.position.y, rect.end.y]:
			var local := Vector3(x - sprite.texture.get_width() * 0.5 + sprite.offset.x, sprite.texture.get_height() * 0.5 - y + sprite.offset.y, 0) * sprite.pixel_size
			points.append(sprite.to_global(local) if sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED else sprite.global_position + stage._camera.global_basis * local)
	return _screen_rect(points)

func _screen_rect(points: Array[Vector3]) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in points:
		var projected: Vector2 = stage.world_to_screen(point)
		low = low.min(projected)
		high = high.max(projected)
	return Rect2(low, high - low)
