extends SceneTree
## Cross-level binding and physics invariance, not a visual beauty assertion.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Props = preload("res://elements/prop_definitions.gd")
const Assets = preload("res://elements/element_assets.gd")
const Natural = preload("res://presentation/native/symbiosis_dressing.gd")
const Shadow = preload("res://presentation/native/shadow_dressing.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _core(stage: Node) -> Sprite3D:
	if not stage._props_nodes.has("mark:core"): return null
	for child: Node in stage._props_nodes["mark:core"].get_children():
		if child is Sprite3D and child.has_meta("core_planter"): return child
	return null

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	stage.set_process(false)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var revealed := {}
	for entry: Dictionary in reference.cases:
		if str(entry.name).begins_with("authored/") and not entry.steps.is_empty():
			revealed[str(entry.name).trim_prefix("authored/")] = entry.steps.back().snapshot
	var states := {}
	var geometry := {}
	for chapter in range(1, 4):
		for index in range(1, 5):
			var id := "%d-%d" % [chapter,index]
			# Hidden sanctuaries use existing solved fixture geometry. Selecting
			# the empty visual here is a render fixture, not traversal evidence.
			var world := World.new(id, revealed.get(id, {}))
			world.state.completed = false
			stage.set_world(world)
			var art := _core(stage)
			_check(art != null, id + " has terminal planter")
			if art == null: continue
			states[id] = world.snapshot().duplicate(true)
			geometry[id] = {"at":art.position,"size":art.pixel_size,"span":art.get_meta("ground_footprint_span"),"center":art.get_meta("ground_footprint_center")}
			_check(art.texture == Assets.texture("flower"), id + " binds shared empty slot")
			_check(art.offset == Vector2(0,102), id + " preserves painted foot")
			_check(Props.semantic_for_mark(id, {"id":"core","kind":"core"}) == "planter-terminal", id + " semantic core")
	var before_revision := Assets.revision()
	var natural_before := Natural.asset_texture("wheel")
	var shadow_before := Shadow.icon_texture(0)
	var result := Assets.apply_theme({"schema_version":1,"resource_overrides":{"flower":Assets.resource_path("bloom"),"symbiosis-wheel":Assets.resource_path("symbiosis-lift")}})
	_check(bool(result.ok), "same-canvas shared replacement accepted")
	_check(Assets.revision() > before_revision, "replacement advances cache revision")
	_check(Natural.asset_texture("wheel") != natural_before and Natural.asset_texture("wheel").atlas == Assets.texture("symbiosis-wheel"), "natural atlas refreshes through shared resource provider")
	_check(Shadow.icon_texture(0) != shadow_before and Shadow.icon_texture(0).atlas == Assets.texture("shadow-sun-stone"), "shadow atlas refreshes through shared resource provider")
	for id: String in states:
		var world := World.new(id, states[id])
		var snapshot := world.snapshot().duplicate(true)
		stage.set_world(world)
		var art := _core(stage)
		_check(art.texture == Assets.texture("bloom"), id + " receives global replacement")
		_check(art.position == geometry[id].at and art.pixel_size == geometry[id].size, id + " replacement keeps registration and scale")
		_check(art.get_meta("ground_footprint_span") == geometry[id].span and art.get_meta("ground_footprint_center") == geometry[id].center, id + " replacement keeps collision footprint")
		_check(world.snapshot() == snapshot, id + " appearance change cannot write gameplay state")
	for key: String in Props.section("semantic_overrides"):
		var parts := key.split("/")
		_check(Props.semantic_for_mark(parts[0], {"id":parts[1],"kind":"flower"}) != "planter-task", key + " does not become a generic planter")
	Assets.reset_theme()
	var old_revision := Props.revision()
	var previous_bounds := Props.rectangles("scale", "body_bounds")
	var invalid := Props.definitions()
	invalid.planters.terminal.ground_span = [-1, .8]
	_check(not Props.validate_definition(invalid) and Props.revision() == old_revision, "negative footprint is rejected without publishing a revision")
	invalid = Props.definitions()
	invalid.natural_assets.symbiosis.wheel.atlasAlpha8 = [0,0,99999,10]
	_check(not Props.validate_definition(invalid), "out-of-canvas natural crop is rejected")
	invalid = Props.definitions()
	invalid.renderer_adapters.scenery.erase("entry")
	_check(not Props.validate_definition(invalid), "missing renderer entry is rejected")
	_check(Props.reload_definitions() and Props.revision() == old_revision + 1, "explicit definition reload advances revision")
	_check(is_same(previous_bounds, Props.rectangles("scale", "body_bounds")), "reload preserves existing renderer table references")
	_check(previous_bounds.flower == Rect2(16,50,224,182), "reload preserves reviewed flower body bounds")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-prop-library","passed":failures.is_empty(),"checks":checks,"failures":failures,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
