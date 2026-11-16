extends SceneTree
## Local 3-3 size exception. These prepared art states do not prove traversal.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
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
	var world := World.new("3-3")
	var previous: Dictionary = {}
	for completed: bool in [false, true, false]:
		world.state.completed = completed
		var before := world.snapshot().duplicate(true)
		var tiles := world.tiles().duplicate(true)
		stage.set_world(world)
		var core: Node3D = stage._props_nodes["mark:core"]
		var layout: Dictionary = core.get_meta("original_core_layout")
		var art: Sprite3D
		for child in core.get_children():
			if child is Sprite3D and child.has_meta("core_planter"): art = child
		_check(art != null, "core retains integrated planter artwork")
		if art == null: continue
		_check(is_equal_approx(float(layout.width), 1.65) and str(layout.reason) == "local_symbiosis_planter_scale", "3-3 uses explicit local size exception")
		_check(is_equal_approx(float(layout.source_width), 110.0 * sqrt(2.0) / 70.0), "source 110px size remains recorded independently")
		_check(layout.shift.is_equal_approx(Vector3(-.6, 0, -.6)), "rear placement remains stable on original high terrace")
		_check(Ratios._supported_footprint(stage, core, float(layout.width), layout.shift), "complete stone base stays on authored same-height fixed support")
		var span: Vector2 = art.get_meta("ground_footprint_span")
		var center: Vector3 = art.get_meta("ground_footprint_center")
		var obstacle: Dictionary = {}
		for entry: Dictionary in stage._prop_obstacles:
			if str(entry.id) == "mark:core": obstacle = entry
		_check(not obstacle.is_empty(), "smaller flowerbed retains real hard stone obstacle")
		if not obstacle.is_empty():
			_check(obstacle.rect.size.is_equal_approx(span), "hard base shrinks with visible planter geometry")
			var expected := core.to_global(center)
			_check(obstacle.rect.get_center().is_equal_approx(Vector2(expected.x, expected.z)), "hard base follows same registered physical centre")
		var state_data := {"width":art.texture.get_width()*art.pixel_size,"position":art.position,"offset":art.offset,"span":span,"center":center}
		if not previous.is_empty(): _check(previous == state_data, "bloom and restore do not rescale or shift the base/foot")
		previous = state_data
		_check(world.snapshot() == before and world.tiles() == tiles, "planter size does not change rules or topology")
		_check(is_equal_approx(stage.get_actor_body("luvie").get_node("Visual/Art").pixel_size, .00625), "main actor size remains unchanged")
		var bounds: Rect2 = Ratios.BODY_BOUNDS["bloom" if completed else "flower"]
		measurements.append({"completed":completed,"canvasWidth":state_data.width,"visibleBody":[bounds.size.x*art.pixel_size,bounds.size.y*art.pixel_size],"hardSpan":[span.x,span.y],"shift":[layout.shift.x,layout.shift.y,layout.shift.z]})
	# The named first garden remains its already accepted explicit exception.
	stage.set_world(World.new("1-1"))
	var first_width := 0.0
	for child in stage._props_nodes["mark:core"].get_children():
		if child is Sprite3D and child.has_meta("core_planter"): first_width = child.texture.get_width() * child.pixel_size
	_check(is_equal_approx(first_width, 1.16), "1-1 accepted planter size remains unchanged")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-symbiosis-planter","checks":checks,"failures":failures,"passed":failures.is_empty(),"measurements":measurements,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
