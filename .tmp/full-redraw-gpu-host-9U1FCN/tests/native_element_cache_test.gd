extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Assets = preload("res://elements/element_assets.gd")
const Props = preload("res://elements/prop_definitions.gd")
const Placement = preload("res://presentation/native/original_scenery_placement.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func replacement_path(source: Texture2D) -> String:
	for alias: String in Assets.paths():
		var image := Assets.texture(alias)
		if image != null and image != source and image.get_size() == source.get_size():
			return Assets.resource_path(alias)
	return ""

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	stage.set_process(false)
	var pond := World.new("2-1")
	stage.set_world(pond)
	var snapshot := pond.snapshot().duplicate(true)
	var tiles := pond.tiles().duplicate(true)
	var environment: Node = stage._original_pond
	var original: Texture2D = environment.water_material.get_shader_parameter("pigment")
	var replacement := replacement_path(original)
	var grass_replacement := replacement_path(Assets.texture("paving-grass"))
	check(not replacement.is_empty(), "existing same-canvas replacement fixture available")
	check(not grass_replacement.is_empty() and not grass_replacement.ends_with("paving-grass.jpg"), "grass replacement has a different filename")
	var builds: int = environment.builds
	var shoreline: PackedVector2Array = environment.shoreline.duplicate()
	var result: Dictionary = stage.apply_element_theme({"schema_version":1,"resource_overrides":{"water-pigment":replacement,"paving-grass":grass_replacement}})
	check(bool(result.ok), "water appearance transaction accepted")
	check(environment.builds == builds + 1, "unchanged pond geometry refreshes its resource bindings exactly once")
	check(environment.water_material.get_shader_parameter("pigment") == Assets.texture("water-pigment") and environment.water_material.get_shader_parameter("pigment") != original, "existing pond shader receives replacement texture")
	var grasses := environment.find_children("MossPocket_*", "MeshInstance3D", true, false)
	check(not grasses.is_empty(), "existing ecological moss fixture exists")
	for patch: MeshInstance3D in grasses:
		var material := patch.material_override
		check(material is ShaderMaterial and material.shader.resource_path.ends_with("original_pond_bank.gdshader"), "grass shader selected by semantic slot after filename change")
		if material is ShaderMaterial: check(material.get_shader_parameter("grass") == Assets.texture("paving-grass"), "ecological grass shader binds new shared texture")
	check(environment.shoreline == shoreline and pond.tiles() == tiles and pond.snapshot() == snapshot, "theme preserves shoreline and complete puzzle state")
	stage.refresh_world(pond,true)
	check(environment.builds == builds + 1, "ordinary refresh reuses refreshed environment")
	Assets.reset_theme()
	stage.reload_element_visuals()
	check(environment.water_material.get_shader_parameter("pigment") == original, "pond restoration updates existing scene")
	var world := World.new("1-3")
	stage.set_world(world)
	var context := Placement.prepare(stage)
	var attempted: int = Placement.searches + Placement.authored_hits
	var before := world.snapshot().duplicate(true)
	check(Props.reload_definitions(), "measured prop definitions reload")
	stage.refresh_world(world,true)
	var next_context := Placement.prepare(stage)
	check(context.cache_key != next_context.cache_key, "footprint revision invalidates scenery placement context")
	check(Placement.searches + Placement.authored_hits > attempted, "existing scenery positions revalidate after footprint reload")
	check(world.snapshot() == before, "placement refresh does not change game rules")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"element-cache","checks":checks,"failures":failures,"passed":failures.is_empty(),"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
