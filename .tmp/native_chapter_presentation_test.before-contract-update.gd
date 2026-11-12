extends SceneTree

const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Profiles = preload("res://presentation/native/level_presentation_profiles.gd")
const Terrace = preload("res://presentation/native/terrace_materials.gd")
const SceneryScale = preload("res://presentation/native/scenery_scale.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _geometry(stage: Node) -> Dictionary:
	var result := {}
	for id: String in stage._surfaces:
		var surface: Node3D = stage._surfaces[id]
		var shape: ConcavePolygonShape3D = surface.get_node("SupportCollision/SharedSurfaceShape").shape
		result[id] = {"faces": shape.get_faces(), "transform": surface.transform, "rises": surface.rises.duplicate()}
	return result

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	_check_material_cache(stage)
	_check_scenery_sources(stage)
	_check_second_dressing(stage)
	_check_second_dressing(stage, true)
	var palettes := {}
	var dressing_counts := {}
	for id: String in Profiles.CHAPTER_LEVELS:
		var world: RefCounted = Cloud.new(id) if id.begins_with("cloud-") else World.new(id)
		var before: Dictionary = world.snapshot().duplicate(true)
		stage.set_world(world)
		await process_frame
		_check(world.snapshot() == before, id + " presentation leaves rule state and save identity unchanged")
		var geometry := _geometry(stage)
		var paint: Dictionary = stage._terrain_materials()
		_check(paint.ramp is ShaderMaterial and paint.ramp.shader == Terrace.StairShader and paint.ramp.get_shader_parameter("original_stone") == paint.top.albedo_texture, id + " real treads reuse the first garden shader with original chapter paint")
		_check(paint.riser.shader == Terrace.StairShader and paint.riser.get_shader_parameter("riser") == true and paint.riser.get_shader_parameter("original_stone") == paint.top.albedo_texture, id + " real risers have their own face mapping and chapter paint")
		var chapter_name := str(world.level.get("chapter", "valley"))
		var masonry := "masonry-pond" if chapter_name == "pond" else "wall-left" if chapter_name == "cave" else "masonry-valley"
		var right_wall := "wall-right" if chapter_name == "cave" else masonry
		_check(paint.side.shader == Terrace.IslandStoneShader and paint.side.get_shader_parameter("wall_art") == stage._texture(masonry), id + " walls preserve the complete original chapter masonry")
		_check(paint.side.get_shader_parameter("wall_art_right") == stage._texture(right_wall), id + " cave retains its separately painted right wall")
		_check(paint.side.get_shader_parameter("wall_art") != paint.top.albedo_texture, id + " wall painting is independent of overhead paving")
		var density: Vector2 = paint.side.get_shader_parameter("wall_pixels_per_unit")
		_check(is_equal_approx(density.x, 70.0) and absf(density.y * 0.65 - 48.0) < 0.0001, id + " wall artwork retains original horizontal and vertical source-pixel density")
		var lanterns := 0
		var vines := 0
		for node in stage._props.get_children():
			if not node.has_meta("dressing_support"): continue
			var alias := str(node.get_meta("dressing_alias", ""))
			lanterns += int(alias in ["stone-lantern", "wood-lantern"])
			vines += int(alias == "trailing-vine")
			var support := str(node.get_meta("dressing_support"))
			var tile: Dictionary = stage._tile_map[support]
			_check(is_equal_approx(node.pixel_size * SceneryScale.SOURCES[alias].body.size.x, float(SceneryScale.SOURCES[alias].width)), id + " visible scenery width follows semantic source measurement/" + alias)
			if alias != "trailing-vine":
				_check(SceneryScale.flat_footprint(stage, node.position, support, alias), id + " complete scenery base stays on flat safe support/" + alias)
			if id == "3-3" and alias == "stone-lantern":
				_check_cave_lantern_sightline(stage, node)
			_check(world.visible(tile), id + " edge planting never reveals an undiscovered support")
			_check(str(tile.get("kind", "fixed")) not in ["module", "root", "shadow", "bridge", "lift"] and not bool(tile.get("small", false)), id + " edge planting never occupies a moving or narrow support")
			_check(absf(node.position.y - stage.support_height(node.position, support) - 0.015) < 0.0001, id + " planted artwork rests on real support")
			_check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), id + " decorative planting adds no collision or shortcut")
			_check(node.texture != stage._texture("crystal"), id + " decoration does not imitate movable sun/moon puzzle posts")
			_check(str(tile.id) not in [str(world.level.get("start", "")), str(world.level.get("buddy", ""))], id + " chapter dressing leaves actor spawn clear")
			for root_patch: Dictionary in world.level.get("roots", []):
				for socket: Array in root_patch.get("sockets", []):
					_check(Vector2(float(socket[0]) - float(tile.x), float(socket[1]) - float(tile.z)).length() > 1.01, id + " chapter dressing avoids every future root socket")
		_check(lanterns <= 1 and vines <= 2, id + " restrained chapter dressing budget")
		dressing_counts[id] = {"lanterns": lanterns, "vines": vines}
		for mark: Dictionary in world.level.get("marks", []):
			if str(mark.kind) != "core": continue
			var anchor: Node3D = stage._props_nodes.get("mark:" + str(mark.id))
			if anchor == null: continue # Undiscovered goals must stay hidden.
			var sprites: Array[Node] = anchor.find_children("*", "Sprite3D", false, false)
			_check(sprites.size() == 1, id + " goal retains one complete original flowerbed")
			_check(anchor.get_node_or_null("ContactPatch") != null, id + " goal has a ground contact patch")
			_check(anchor.find_children("*", "CollisionObject3D", true, false).is_empty(), id + " flowerbed adds no support or movement obstacle")
			if sprites.is_empty(): continue
			var sprite: Sprite3D = sprites[0]
			_check(is_equal_approx(sprite.pixel_size * sprite.texture.get_width(), 0.90), id + " goal footprint fits unchanged single-tile landing")
			_check(sprite.offset == Vector2(0, 102) and not sprite.no_depth_test, id + " original foot anchor and actual occlusion retained")
			var chapter := str(world.level.get("chapter", "valley"))
			palettes[chapter] = sprite.material_override.get_shader_parameter("stone_tint")
			_check(absf(anchor.get_node("ContactPatch").global_position.y - stage.support_height(anchor.global_position, str(mark.tile)) - 0.008) < 0.0001, id + " contact patch is on its actual landing")
		# Repeated presentation updates keep the already built real stair mesh;
		# geometry correctness itself is checked by the independent ray suite.
		var builds: int = stage._build_count
		stage.refresh_world(world)
		_check(_geometry(stage) == geometry and stage._build_count == builds, id + " unchanged state preserves real treads, risers and collision without rebuilding")
		_check(world.snapshot() == before, id + " comparison cannot write to the domain")
	_check(palettes.get("valley") != palettes.get("pond") and palettes.get("pond") != palettes.get("cave") and palettes.get("cave") != palettes.get("cloud"), "chapters retain distinct stone palettes")
	stage.set_world(World.new("1-1"))
	var core_id := ""
	for mark: Dictionary in stage.world.level.marks:
		if str(mark.kind) == "core": core_id = str(mark.id)
	var first: Node3D = stage._props_nodes["mark:" + core_id]
	var art: Sprite3D = first.find_children("*", "Sprite3D", false, false)[0]
	var first_tint: Variant = art.material_override.get_shader_parameter("stone_tint")
	_check(first_tint == null or first_tint == Vector3(1.12, 1.04, 0.77), "first garden retains original shader defaults after chapter changes")
	_check(stage.has_presentation_feature("physical_stair_steps"), "returning to first garden restores its original geometry policy")
	_check(Profiles.for_level("unknown").is_empty(), "unregistered levels keep existing fallback")
	_check(stage.asset_errors().is_empty(), "all chapter artwork resources load")
	print(JSON.stringify({"suite": "chapter-presentation", "checks": checks, "passed": failures.is_empty(), "failures": failures, "dressingCounts": dressing_counts, "gpuPixelsVerified": false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_cave_lantern_sightline(stage: Node, lantern: Sprite3D) -> void:
	# The entrance lantern was grounded correctly but mostly hidden by the
	# near wall of the taller foreground terrace. Check the foot sightline
	# against that actual surface, not just the lantern's own support height.
	var terrace: Node3D = stage._surfaces["f:-1:3"]
	var ray: Vector3 = Stage.CAMERA_RAY
	var start: Vector3 = lantern.global_position + Vector3.UP * 0.03
	var distance: float = (terrace.global_position.z - 0.5 - start.z) / ray.z
	var crossing := start + ray * distance
	_check(crossing.y > terrace.sample_height(crossing) + 0.02, "3-3 lantern foot sightline clears the actual elevated foreground terrace")
	var radius := SceneryScale.footprint_radius("stone-lantern")
	for x: float in [-radius, radius]:
		for z: float in [-radius, radius]:
			var foot := start + Vector3(x, 0, z)
			var foot_crossing := foot + ray * ((terrace.global_position.z - 0.5 - foot.z) / ray.z)
			_check(foot_crossing.y > terrace.sample_height(foot_crossing) + 0.02, "3-3 enlarged lantern full base clears foreground cliff")
	var old_start := start + Vector3(0, 0, 0.54)
	var old_crossing := old_start + ray * ((terrace.global_position.z - 0.5 - old_start.z) / ray.z)
	_check(old_crossing.y < terrace.sample_height(old_crossing), "3-3 regression fixture detects the old buried-lantern sightline")
	_check(not lantern.no_depth_test and lantern.material_override == null and is_equal_approx(lantern.pixel_size * lantern.texture.get_width(), SceneryScale.nominal_width("stone-lantern")), "3-3 lantern keeps real depth, original artwork and first-garden-sized stone body")


func _check_second_dressing(stage: Node, without_redundant_tiles := false) -> void:
	var world := World.new("1-2")
	if without_redundant_tiles:
		# Exercise the authored four-segment landing with no duplicate fixed
		# endpoint or south bypass tile. Missing decoration anchors must fail.
		world.level = world.level.duplicate(true)
		world.level.tiles = world.level.tiles.filter(func(tile: Dictionary) -> bool: return str(tile.id) not in ["f:3:1", "f:4:2"])
	var before: Dictionary = world.snapshot().duplicate(true)
	stage.set_world(world)
	var aliases := {}
	for node: Node in stage._props.get_children():
		if not node.has_meta("dressing_support"): continue
		var support := str(node.get_meta("dressing_support"))
		_check(stage._tile_map.has(support), "second garden decoration anchor exists/" + support)
		var alias := str(node.get_meta("dressing_alias"))
		_check(is_equal_approx(node.pixel_size * SceneryScale.SOURCES[alias].body.size.x, float(SceneryScale.SOURCES[alias].width)), "second garden visible scenery width follows semantic role/" + alias)
		if alias != "trailing-vine":
			_check(SceneryScale.flat_footprint(stage, node.position, support, alias), "second garden full decorative base avoids rear steps and stays inside support/" + alias)
		aliases[alias] = int(aliases.get(alias, 0)) + 1
		var offset: Vector2 = node.get_meta("dressing_offset")
		var anchor: Vector3 = stage.tile_position(stage._tile_map[support])
		_check(Vector2(node.position.x - anchor.x, node.position.z - anchor.z).distance_to(offset) < 0.0001, "second garden scenery follows physical support mapping/" + alias)
		_check(absf(node.position.y - stage.support_height(node.position, support) - 0.015) < 0.0001, "second garden scenery uses real stair height/" + alias)
		_check(node is Sprite3D and not node.no_depth_test and node.find_children("*", "CollisionObject3D", true, false).is_empty(), "second garden scenery keeps depth and adds no collision/" + alias)
		_check(support not in ["f:1:1", "f:3:1", "f:4:1", "f:4:2"], "second garden scenery leaves seedbed, docking, flowerbed and removed corner clear/" + alias)
	_check(aliases.get("stone-lantern", 0) == 1 and aliases.get("red-mushroom", 0) == 2 and aliases.get("trailing-vine", 0) == 2, "second garden restores original lantern, red mushrooms and cliff vines")
	_check(aliases.values().reduce(func(total: int, count: int) -> int: return total + count, 0) == 9, "all nine authored decorations render without silently skipping absent supports")
	var fern: Node3D = stage._props.get_node("SecondGarden_fern_f_5_1")
	var flowers: Node3D = stage._props.get_node("SecondGarden_yellow_flowers_f_5_1")
	var projected_separation := absf((fern.position - flowers.position).dot(Vector3(1, 0, -1).normalized()))
	_check(projected_separation > (SceneryScale.nominal_width("fern") + SceneryScale.nominal_width("yellow-flowers")) * 0.5 + 0.04, "second-garden side-rim plants retain a projected gap after resizing")
	_check(world.snapshot() == before, "second garden decoration cannot change progress or path state")


func _check_scenery_sources(stage: Node) -> void:
	for alias: String in SceneryScale.SOURCES:
		var source: Dictionary = SceneryScale.SOURCES[alias]
		var texture: Texture2D = stage._texture(alias)
		var image := Image.load_from_file(ProjectSettings.globalize_path(texture.resource_path))
		_check(not image.is_empty() and image.get_size() == source.size, "scenery measurement uses current source dimensions/" + alias)
		var minimum: Vector2i = source.size
		var maximum := Vector2i.ZERO
		var foot := Vector2i(source.size.x, 0)
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a < 64.0 / 255.0: continue
				minimum = Vector2i(mini(minimum.x, x), mini(minimum.y, y))
				maximum = Vector2i(maxi(maximum.x, x + 1), maxi(maximum.y, y + 1))
				if y >= int(image.get_height() * 0.8): foot = Vector2i(mini(foot.x, x), maxi(foot.y, x + 1))
		_check(Rect2i(minimum, maximum - minimum) == source.body and foot == source.base_x, "scenery alpha64 body and full lower silhouette match recorded measurement/" + alias)
	stage.set_world(World.new("1-1"))
	var first_widths := {}
	for child: Node in stage._props.get_children():
		if not child is Sprite3D: continue
		for alias: String in ["stone-lantern", "red-mushroom"]:
			if child.texture != stage._texture(alias): continue
			if not first_widths.has(alias): first_widths[alias] = []
			first_widths[alias].append(snappedf(child.pixel_size * child.texture.get_width(), 0.01))
	_check(first_widths.get("stone-lantern", []) == [0.43] and first_widths.get("red-mushroom", []) == [0.26, 0.28], "approved first-garden lantern and mushroom scale remains untouched")


func _check_material_cache(stage: Node) -> void:
	stage.set_world(World.new("1-1"))
	var original: Dictionary = stage._terrain_materials()
	stage.set_world(World.new("1-3"))
	var painted: Dictionary = stage._terrain_materials()
	_check(original.ramp is StandardMaterial3D and painted.ramp is ShaderMaterial, "first-to-third garden switch cannot reuse the old plain ramp cache")
	var connector: Dictionary = stage._terrain_materials(true)
	_check(connector.ramp != painted.ramp and connector.ramp.get_shader_parameter("connector") == true and painted.ramp.get_shader_parameter("connector") == false, "thin-connector material cannot contaminate fixed-island cache")
	_check(connector.side.get_shader_parameter("stair_side") == true, "thin stair sides use the approved physical-depth stone edge")
	var unknown := World.new("1-3")
	unknown.level = unknown.level.duplicate(true)
	unknown.level.id = "unregistered-presentation"
	stage.set_world(unknown)
	_check(stage._terrain_materials().ramp == original.ramp, "unknown levels keep original materials after visiting a painted chapter")
	stage.set_world(World.new("2-1"))
	var pond: Dictionary = stage._terrain_materials()
	_check(pond.ramp.get_shader_parameter("original_stone") != painted.ramp.get_shader_parameter("original_stone"), "chapter transition cannot reuse another chapter's path artwork")
