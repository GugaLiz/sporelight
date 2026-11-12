extends SceneTree
## Contracts 71/76 supersede 70's candidate widths and blanket no-collision
## policy. Source identity, true support and caches remain strict CPU checks.

const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Profiles = preload("res://presentation/native/level_presentation_profiles.gd")
const Terrace = preload("res://presentation/native/terrace_materials.gd")
const SceneryScale = preload("res://presentation/native/scenery_scale.gd")
const Original = preload("res://presentation/native/original_garden_dressing.gd")
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
const INITIAL_COUNTS := {"1-3":14,"1-4":19,"2-1":12,"2-2":7,"2-3":4,"2-4":1,"3-1":11,"3-2":5,"3-3":12,"3-4":8}
const HARD_ART := ["stone-lantern","wood-lantern","river-rock","light-tower","violet-crystal","lotus-pool","arch"]
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
	stage.set_process(false)
	_check_material_cache(stage)
	_check_scenery_sources(stage)
	_check_second_dressing(stage)
	var palettes := {}
	var counts := {}
	for id: String in Profiles.CHAPTER_LEVELS:
		var world: RefCounted = Cloud.new(id) if id.begins_with("cloud-") else World.new(id)
		var before: Dictionary = world.snapshot().duplicate(true)
		stage.set_world(world)
		await process_frame
		var geometry := _geometry(stage)
		_check_chapter_materials(stage,id)
		var count := 0
		for node: Node in stage._props.get_children():
			if not node.has_meta("original_scenery_index"): continue
			count+=1
			_check_original_scenery(stage,node,id)
		if INITIAL_COUNTS.has(id): _check(count==INITIAL_COUNTS[id],id+" complete original initial inventory, including hidden cave instances")
		counts[id]=count
		if id.begins_with("cloud-"):
			_check_cloud_goal(stage,id)
		else:
			var anchor: Node3D = stage._props_nodes.get("mark:core")
			if anchor!=null:
				_check_core(stage,anchor,id)
				var sprite: Sprite3D = anchor.find_children("*","Sprite3D",false,false)[0]
				palettes[str(world.level.chapter)]=sprite.material_override.get_shader_parameter("stone_tint")
		var builds: int = stage._build_count
		stage.refresh_world(world)
		_check(_geometry(stage)==geometry and stage._build_count==builds,id+" unchanged refresh preserves real tread geometry and collision without rebuilding")
		_check(world.snapshot()==before,id+" presentation preserves rule state and save identity")
	_check(palettes.get("valley")!=palettes.get("pond") and palettes.get("pond")!=palettes.get("cave"),"mainline original flowerbed palettes remain distinct")
	stage.set_world(World.new("1-1"))
	var first: Sprite3D = stage._props_nodes["mark:core"].find_children("*","Sprite3D",false,false)[0]
	_check(is_equal_approx(first.pixel_size*first.texture.get_width(),1.16),"first garden retains approved core width")
	var first_tint: Variant = first.material_override.get_shader_parameter("stone_tint")
	_check(first_tint==null or first_tint==Vector3(1.12,1.04,.77),"first shader defaults survive chapter changes")
	_check(stage.has_presentation_feature("physical_stair_steps"),"first garden geometry policy restored")
	_check(Profiles.for_level("unknown").is_empty(),"unregistered levels retain fallback")
	_check(stage.asset_errors().is_empty(),"all artwork resources load")
	print(JSON.stringify({"suite":"chapter-presentation","checks":checks,"passed":failures.is_empty(),"failures":failures,"dressingCounts":counts,"gpuPixelsVerified":false}))
	stage.free()
	quit(0 if failures.is_empty() else 1)

func _check_chapter_materials(stage: Node,id: String) -> void:
	var paint: Dictionary = stage._terrain_materials()
	if id.begins_with("cloud-"):
		_check(paint.top is StandardMaterial3D and paint.side is StandardMaterial3D and paint.ramp is StandardMaterial3D and paint.riser==paint.side,id+" original cream stone uses standard materials")
		if not paint.top is StandardMaterial3D or not paint.side is StandardMaterial3D or not paint.ramp is StandardMaterial3D:return
		_check(paint.top.albedo_color==Color.WHITE and paint.side.albedo_color==Color("d4d3bf") and paint.ramp.albedo_color==Color("efe6d3"),id+" original cloud colours independent of valley paint")
		var image: Image = paint.top.albedo_texture.get_image()
		_check(image.get_pixel(64,64).is_equal_approx(Color("faf5e9")) and image.get_pixel(0,0).is_equal_approx(Color("fffdf6")),id+" cream inset and original fine edge")
		_check(paint.top.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and paint.side.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,id+" source cloud colours remain unshaded")
		return
	_check(paint.ramp is ShaderMaterial and paint.riser is ShaderMaterial and paint.side is ShaderMaterial,id+" mainline painted materials use shaders")
	if not paint.ramp is ShaderMaterial or not paint.riser is ShaderMaterial or not paint.side is ShaderMaterial:return
	_check(paint.ramp.shader==Terrace.StairShader and paint.ramp.get_shader_parameter("original_stone")==paint.top.albedo_texture,id+" true treads retain chapter paving")
	_check(paint.riser.shader==Terrace.StairShader and paint.riser.get_shader_parameter("riser")==true and paint.riser.get_shader_parameter("original_stone")==paint.top.albedo_texture,id+" risers retain their own face mapping")
	var chapter := str(stage.world.level.chapter)
	var masonry := "masonry-pond" if chapter=="pond" else "wall-left" if chapter=="cave" else "masonry-valley"
	_check(paint.side.shader==Terrace.IslandStoneShader and paint.side.get_shader_parameter("wall_art")==stage._texture(masonry),id+" complete source chapter masonry")
	_check(paint.side.get_shader_parameter("wall_art_right")==stage._texture("wall-right" if chapter=="cave" else masonry),id+" original right wall artwork")
	_check(paint.side.get_shader_parameter("wall_art")!=paint.top.albedo_texture,id+" walls independent of overhead paving")
	var density: Vector2 = paint.side.get_shader_parameter("wall_pixels_per_unit")
	_check(is_equal_approx(density.x,70.0) and absf(density.y*.65-48.0)<.0001,id+" original horizontal and vertical pixel density")

func _check_hard_feet(node: Node,required: bool,label: String) -> void:
	var bodies: Array[Node] = node.find_children("*","CollisionObject3D",true,false)
	_check((not bodies.is_empty())==required,label+" visible hard feet obstruct; soft crowns do not")
	for body: CollisionObject3D in bodies:
		_check(body is StaticBody3D and body.collision_layer==8 and body.collision_mask==0 and bool(body.get_meta("not_walkable_support",false)),label+" anti-entry body is not walkable terrain")
		_check(body.has_meta("prop_obstacle_id"),label+" base participates in path identity")
		for shape: CollisionShape3D in body.find_children("*","CollisionShape3D",true,false):
			_check(shape.shape is BoxShape3D and shape.shape.size.x>0 and shape.shape.size.z>0,label+" explicit local base volume")

func _check_original_scenery(stage: Node,node: Sprite3D,id: String) -> void:
	var alias := str(node.get_meta("original_scenery_alias"))
	var support := str(node.get_meta("original_scenery_support"))
	_check(stage._tile_map.has(support) and stage._surfaces.has(support),id+" real support/"+alias)
	if not stage._tile_map.has(support) or not stage._surfaces.has(support):return
	var tile: Dictionary = stage._tile_map[support]
	var pixels := float(node.get_meta("original_scenery_pixels"))
	_check(is_equal_approx(node.pixel_size*node.texture.get_width(),pixels*sqrt(2.0)/70),id+" original canvas ratio/"+alias)
	_check(Original.flat_footprint(stage,node.position,support,float(node.get_meta("original_scenery_foot_radius"))),id+" full base on real same-height ground/"+alias)
	_check(absf(node.position.y-stage.support_height(node.position,support)-.008)<.0001,id+" exact original foot contact/"+alias)
	_check(not node.no_depth_test and node.visible==stage.world.visible(tile,stage._tiles),id+" true depth and discovery visibility/"+alias)
	_check(str(tile.get("kind","fixed")) not in ["module","root","shadow","bridge","lift"] and not bool(tile.get("small",false)),id+" no moving or narrow support/"+alias)
	_check(node.texture==stage._texture(alias),id+" source art identity/"+alias)
	_check_hard_feet(node,node.visible and alias in HARD_ART,id+"/"+alias)

func _check_core(stage: Node,anchor: Node3D,id: String) -> void:
	var sprites: Array[Node] = anchor.find_children("*","Sprite3D",false,false)
	_check(sprites.size()==1 and anchor.has_meta("original_core_layout"),id+" one original bed with explicit ratio decision")
	if sprites.is_empty() or not anchor.has_meta("original_core_layout"):return
	var layout: Dictionary = anchor.get_meta("original_core_layout")
	var sprite: Sprite3D = sprites[0]
	var source_width := (150.0 if id=="3-4" else 110.0)*sqrt(2.0)/70
	_check(is_equal_approx(layout.source_width,source_width) and is_equal_approx(sprite.pixel_size*sprite.texture.get_width(),layout.width),id+" original source ratio and declared rendered width")
	_check(is_equal_approx(layout.width,source_width),id+" full source-width chapter core")
	_check(Ratios._supported_footprint(stage,anchor,layout.width,layout.shift),id+" complete core supported by genuine fixed ground")
	_check(sprite.offset==Vector2(0,102) and not sprite.no_depth_test,id+" original core anchor and depth")
	_check_hard_feet(anchor,true,id+"/core")
	var patch: Node3D = anchor.get_node_or_null("ContactPatch")
	_check(patch!=null,id+" core contact patch exists")
	if patch!=null:_check(absf(patch.global_position.y-anchor.global_position.y-.008)<.0001,id+" core patch lies on supported plane")

func _check_cloud_goal(stage: Node,id: String) -> void:
	var goal: Node3D = stage._props_nodes.get("mark:finish")
	_check(goal!=null,id+" cloud retains its own finish disc")
	if goal==null:return
	var sprite: Sprite3D = goal.get_node_or_null("Original_finish")
	_check(sprite!=null,id+" original cloud finish art")
	if sprite!=null:
		_check(is_equal_approx(sprite.pixel_size,sqrt(2.0)/58/2) and not sprite.no_depth_test,id+" independent 58px grid and normal depth")
		_check(is_equal_approx(sprite.scale.y,1/.8660254),id+" original cloud projection")
	_check_hard_feet(goal,false,id+"/flat finish disc")

func _check_second_dressing(stage: Node) -> void:
	var world := World.new("1-2")
	stage.set_world(world)
	var before: Dictionary = world.snapshot().duplicate(true)
	_check(not stage._tile_map.has("f:3:1") and not stage._tile_map.has("f:4:2"),"formal revision2 excludes duplicate endpoint and bypass")
	var aliases := {}
	for node: Node in stage._props.get_children():
		if not node.has_meta("dressing_support"):continue
		var alias := str(node.get_meta("dressing_alias"))
		var support := str(node.get_meta("dressing_support"))
		aliases[alias]=int(aliases.get(alias,0))+1
		if node.has_meta("original_scenery_index"):
			_check_original_scenery(stage,node,"1-2")
			_check(float(node.get_meta("original_scenery_pixels"))==30,"second original ground art stays 30px/"+alias)
		else:
			_check(alias=="trailing-vine" and not node.no_depth_test,"second wall vine identity and depth")
			_check(absf(node.position.y-stage.support_height(node.position,support)-.015)<.0001,"second hanging vine lip contact")
			_check_hard_feet(node,false,"second/vine")
		var offset: Vector2 = node.get_meta("dressing_offset")
		var at: Vector3 = stage.tile_position_id(support)
		_check(Vector2(node.position.x-at.x,node.position.z-at.z).distance_to(offset)<.0001,"second physical support mapping/"+alias)
		_check(support not in ["f:1:1","f:3:1","f:4:1","f:4:2"],"second seedbed, dock, goal and removed corner clear/"+alias)
	_check(aliases.get("stone-lantern",0)==1 and aliases.get("red-mushroom",0)==2 and aliases.get("trailing-vine",0)==2,"second original lamp, mushrooms and cliff vines")
	_check(aliases.values().reduce(func(total: int,count: int)->int:return total+count,0)==9,"all nine second-garden decorations retained")
	var fern: Node3D = stage._props.get_node("SecondGarden_fern_f_5_1")
	var flowers: Node3D = stage._props.get_node("SecondGarden_yellow_flowers_f_5_1")
	# Source-sized free crowns may overlap. Actual root clusters may not.
	var root_sum := float(fern.get_meta("original_scenery_foot_radius"))+float(flowers.get_meta("original_scenery_foot_radius"))
	_check(Vector2(fern.position.x,fern.position.z).distance_to(Vector2(flowers.position.x,flowers.position.z))>root_sum,"second actual fern and flower roots remain separated")
	_check(world.snapshot()==before,"second decoration preserves progress and paths")

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
	stage.set_world(Cloud.new("cloud-1"))
	var cloud: Dictionary = stage._terrain_materials()
	_check(cloud.ramp is StandardMaterial3D and cloud.ramp != original.ramp, "cloud cream does not reuse first-garden ramp cache")
	_check(stage._terrain_materials().top == cloud.top, "cloud repeated access reuses its source texture")
	stage.set_world(World.new("1-3"))
	_check(stage._terrain_materials().ramp == painted.ramp, "return from cloud restores painted cache instance")
