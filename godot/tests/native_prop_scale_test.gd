extends SceneTree
## Source-pixel bounds and real action/undo/restore integration, not GPU QA.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Factory = preload("res://core/world_factory.gd")
const CarryArt = preload("res://presentation/native/original_carry_art.gd")
const IDS := ["1-1", "1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4", "cloud-1", "cloud-2", "cloud-3"]
const GROUNDED := ["fern", "pink-flowers", "blue-flowers", "yellow-flowers", "red-mushroom", "blue-mushroom", "stone-lantern", "wood-lantern", "flowers", "crystal", "dew-plant", "dew-parcel"]
var stage: Node
var checks := 0
var failures: Array[String] = []
var measured: Array = []
var bounds_cache := {}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func bounds(texture: Texture2D) -> Rect2:
	var path := texture.resource_path
	var key := path if not path.is_empty() else "instance:"+str(texture.get_instance_id())
	if bounds_cache.has(key): return bounds_cache[key]
	var picture := Image.load_from_file(ProjectSettings.globalize_path(path)) if not path.is_empty() else texture.get_image()
	var low := Vector2(picture.get_width(), picture.get_height())
	var high := Vector2(-1, -1)
	for y in range(picture.get_height()):
		for x in range(picture.get_width()):
			if picture.get_pixel(x, y).a < 128.0 / 255.0: continue
			low = low.min(Vector2(x, y))
			high = high.max(Vector2(x + 1, y + 1))
	var result := Rect2(low, high - low)
	bounds_cache[key] = result
	return result

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	for id: String in IDS:
		var world: RefCounted = Factory.create(id)
		var original: Dictionary = world.snapshot().duplicate(true)
		stage.set_world(world)
		check(world.snapshot() == original, id + " scale setup preserves rule snapshot")
		check(is_equal_approx(stage.get_actor_body("luvie").get_node("Visual/Art").pixel_size, 0.00625), id + " keeps accepted standing actor scale")
		check(is_equal_approx(stage.get_actor_body("buddy").get_node("Visual/Art").pixel_size, 0.0062), id + " keeps accepted companion scale")
	_ground_pixels()
	_flowers("2-4", "use:plant", "plant")
	_flowers("3-3", "use:care", "care")
	for entry: Array in [["1-4","bell"],["2-1", "dew"], ["3-3", "dew"], ["3-1", "lamp"], ["3-2", "sunPost"], ["3-2", "moonPost"], ["2-2", "mirrorB"], ["3-4", "mirror"]]:
		_carry(str(entry[0]), str(entry[1]))
	for entry: Array in [["2-2", "mirrorB", "f:1:0"], ["3-2", "sunPost", "f:0:0"], ["3-2", "moonPost", "f:3:-1"], ["3-4", "mirror", "f:8:0"]]:
		_drop(str(entry[0]), str(entry[1]), str(entry[2]))
	var cloud := Cloud.new("cloud-1")
	stage.set_world(cloud)
	# Cloud uses its original vector star and disc, distinct from the carried
	# spore packet. A removed generic node must not invalidate the suite.
	var seed: Sprite3D = stage._props_nodes["mark:seed"].get_node("Original_seed")
	check(is_equal_approx(seed.pixel_size*2, sqrt(2.0)/58.0) and not seed.no_depth_test, "cloud ground seed retains original vector pixel ratio and depth")
	cloud.state.cloudSeed = true
	var seed_state: Dictionary = cloud.snapshot().duplicate(true)
	stage.set_world(cloud)
	_measure_carry("luvie", 0.30, "cloud seed packet retains dedicated carried body")
	check(stage._props_nodes["mark:seed"].get_child_count() == 0, "cloud original star disappears after pickup")
	check(cloud.snapshot() == seed_state, "seed appearance does not change cloud progress")
	stage.set_world(World.new("2-4"))
	var bug: Sprite3D = stage._props_nodes["item:bug"].get_child(0)
	var bug_box := bounds(bug.texture)
	check(is_equal_approx(bug.texture.get_width()*bug.pixel_size,40.0*sqrt(2.0)/70.0), "insect preserves original 40px canvas against 70px tile")
	check(bug.position.y - bug_box.size.y * bug.pixel_size * 0.5 > 0.12, "insect remains hovering instead of planted")
	measured.append({"alias": "bug", "alpha": 128, "bounds": [bug_box.position.x, bug_box.position.y, bug_box.size.x, bug_box.size.y], "bodyWidth": bug_box.size.x * bug.pixel_size})
	stage.set_world(World.new("2-2"))
	_measure_ground("mirrorA","fixed mirrorA source leaf and unchanged panel")
	for level: String in ["1-1","2-1","3-4"]:
		stage.set_world(World.new(level))
		for entry: Dictionary in stage._garden_effects.collectibles.values():
			var sprite: Sprite3D = entry.sprite
			check(is_equal_approx(sprite.texture.get_width()*sprite.pixel_size,35.0*sqrt(2.0)/70.0),level+" collectible retains original35px canvas")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-prop-scale", "checks": checks, "passed": failures.is_empty(), "failures": failures, "measurements": measured, "gpuPixelsVerified": false}))
	quit(0 if failures.is_empty() else 1)

func _ground_pixels() -> void:
	for level in ["1-1", "1-2", "2-2", "3-3", "cloud-1"]:
		stage.set_world(Factory.create(level))
		for alias: String in GROUNDED:
			var sprite: Sprite3D = stage._sprite(stage._props, alias, 0.4, Vector3.ZERO)
			var body := bounds(sprite.texture)
			if level == "1-1":
				check(sprite.offset == Vector2(0, sprite.texture.get_height() * 0.4), alias + " first garden keeps its approved anchor")
			else:
				var bottom := (sprite.texture.get_height() * 0.5 - (body.end.y - 0.5) + sprite.offset.y) * sprite.pixel_size
				check(absf(bottom) < 0.00001, level + "/" + alias + " last opaque pixel rests on the support plane")
				check(not sprite.no_depth_test, alias + " retains depth")
			if level == "1-2": measured.append({"alias": alias, "alpha": 128, "bounds": [body.position.x, body.position.y, body.size.x, body.size.y], "footPixelY": body.end.y - 0.5})
		for alias: String in ["vine", "trailing-vine", "spore", "lilypad"]:
			var sprite: Sprite3D = stage._sprite(stage._props, alias, 0.4, Vector3.ZERO)
			check(sprite.offset == Vector2(0, sprite.texture.get_height() * 0.4), level + "/" + alias + " keeps its dedicated caller anchor")
		var goal: Node3D = stage._props_nodes.get("mark:core", stage._props_nodes.get("mark:finish"))
		if goal != null:
			var plant: Sprite3D = goal.get_child(0)
			if str(level).begins_with("cloud-"):
				check(plant.name == "Original_finish" and float(plant.get_meta("source_foot")) == 8.0 and not plant.no_depth_test, level + " keeps original finish disk and star with grounded source anchor")
			else:
				check(plant.offset == Vector2(0, 102) and plant.texture.get_width() == 256, level + " keeps complete core planter and foot")

func _flowers(level: String, action: String, mark: String) -> void:
	var world := _before_action(level, action)
	stage.set_world(world)
	var before: Dictionary = world.snapshot().duplicate(true)
	var first: Sprite3D = stage._props_nodes["mark:" + mark].get_child(0)
	var first_size := bounds(first.texture).size * first.pixel_size
	var first_at := first.position
	var first_offset := first.offset
	check(first.texture.get_width() == 256, level + " dormant flower uses complete artwork")
	check(world.act(action).ok, level + " real flower action succeeds")
	var committed: Dictionary = world.snapshot().duplicate(true)
	stage.refresh_world(world)
	check(world.snapshot() == committed, level + " flower appearance does not mutate committed progress")
	var last: Sprite3D = stage._props_nodes["mark:" + mark].get_child(0)
	var last_size := bounds(last.texture).size * last.pixel_size
	check(last.texture.get_width() == 256 and last.name == "bloom", level + " active flower uses complete bloom")
	check(absf(last_size.x - first_size.x) < 0.00001 and last_size.y / first_size.y > 0.9 and last_size.y / first_size.y < 1.1, level + " growth keeps coherent body width and height")
	check(last.position == first_at and last.offset == first_offset, level + " flower growth keeps contact anchor")
	check(stage._props_nodes["mark:" + mark].get_child_count() == 1, level + " shared mechanism tile has one visual")
	check(not last.no_depth_test and stage._props_nodes["mark:" + mark].find_children("*", "CollisionObject3D", true, false).is_empty(), level + " flower adds no occlusion bypass or collision")
	stage.set_world(World.new(level, committed))
	check(stage._props_nodes["mark:" + mark].get_child(0).name == "bloom", level + " restored state retains the correct flower")
	world.undo()
	stage.set_world(world)
	check(world.snapshot() == before and stage._props_nodes["mark:" + mark].get_child(0).name == "flower", level + " undo restores original state and bud")
	measured.append({"level": level, "kind": "mechanism flower", "beforeBody": [first_size.x, first_size.y], "afterBody": [last_size.x, last_size.y]})

func _carry(level: String, item: String) -> void:
	var world := _before_action(level, "take:" + item)
	stage.set_world(world)
	var before: Dictionary = world.snapshot().duplicate(true)
	_measure_ground(item,level+" before pickup")
	check(world.act("take:" + item).ok, level + " actual pickup " + item)
	var after: Dictionary = world.snapshot().duplicate(true)
	# The picked dew parcel is a different asset from the unpicked plant.
	# Compare the actual parcel's ground representation, not the donor plant.
	var grounded := after.duplicate(true)
	grounded.items[item].holder = ""
	grounded.items[item].tile = before.items[item].tile
	stage.set_world(World.new(level, grounded))
	_measure_ground(item,level+" picked ground representation")
	stage.set_world(world)
	stage.refresh_world(world)
	check(world.snapshot() == after, level + " carry appearance leaves item ownership unchanged")
	var who := str(world.state.items[item].holder)
	_measure_pouch(who,item,level+"/"+item)
	if item.begins_with("mirror") or item == "lamp":
		var held: Sprite3D = stage.get_actor_body(who).get_node("Visual/Carry")
		var original_angle := int(world.state.items[item].get("angle",0))
		var original_texture := held.texture
		check(world.act("angle:" + item).ok, level + " actual held orientation action")
		stage.refresh_world(world)
		check(int(world.state.items[item].angle) != original_angle and int(held.get_meta("original_carry_angle")) == int(world.state.items[item].angle),level+" pouch retains actual orientation identity without a full ground panel")
		check(held.texture == original_texture,level+" original pouch thumbnail remains cached across orientation action")
		world.undo()
		stage.refresh_world(world)
		check(world.snapshot() == after and int(held.get_meta("original_carry_angle")) == original_angle, level + " orientation undo restores original item and pouch metadata")
	var drop_action := ""
	for command: Dictionary in world.commands():
		if str(command.id).begins_with("drop:"+item+":"): drop_action = str(command.id); break
	check(not drop_action.is_empty() and world.act(drop_action).ok,level+" offered real drop succeeds for "+item)
	stage.refresh_world(world)
	check(not _carrying(who),level+" real drop hides pouch")
	_measure_ground(item,level+" actual drop")
	world.undo()
	stage.refresh_world(world)
	check(world.snapshot() == after,level+" drop undo restores held state")
	_measure_pouch(who,item,level+" drop undone")
	stage.set_world(World.new(level, after))
	_measure_pouch(who,item,level+" restored")
	world.undo()
	stage.set_world(world)
	check(world.snapshot() == before and not _carrying(who), level + " undo returns item to its original support")

func _carrying(who: String) -> bool:
	return stage.get_actor_body(who).get_node("Visual/Carry").visible or stage.get_actor_body(who).get_node("Visual/CarryModel").has_node("ReflectionFace")

func _measure_ground(item: String,label: String) -> void:
	var node: Node3D = stage._props_nodes.get("item:"+item)
	check(node != null,label+" has a ground representation")
	if node == null: return
	var data: Dictionary = stage.world.state.items[item]
	if item == "bell":
		var model: Node3D = node.get_node("OriginalBell")
		var body: MeshInstance3D = model.get_child(0)
		check(is_equal_approx(body.mesh.bottom_radius*2*model.scale.x,28.0*sqrt(2.0)/70.0),label+" source bell28px width")
		return
	var sprite: Sprite3D = node.get_node("lilypad") if item.begins_with("mirror") else node.get_child(0)
	# Independent literal source sizes from render.ts, not production constants.
	var source_width := 52.0 if item.begins_with("mirror") else (34.0 if bool(data.get("picked",false)) else 49.0) if item == "dew" else 36.0
	check(is_equal_approx(sprite.texture.get_width()*sprite.pixel_size,source_width*sqrt(2.0)/70.0),label+" source canvas/tile ratio")
	check(not sprite.no_depth_test,label+" ground keeps depth")
	if item.begins_with("mirror"):
		var face: MeshInstance3D = node.get_node("ReflectionFace")
		check(face.mesh.size.is_equal_approx(Vector3(.53,.42,.025)) and face.get_child_count() == 4,label+" unchanged real ground mirror and frame")
		check(is_equal_approx(face.rotation.y,PI/4+int(data.get("angle",0))*PI/2),label+" placed mirror follows actual rule angle")
	var opaque := bounds(sprite.texture)
	measured.append({"label":label,"sourceCanvasPixels":source_width,"worldCanvas":sprite.texture.get_width()*sprite.pixel_size,"visibleBody":opaque.size.x*sprite.pixel_size})

func _measure_pouch(who: String,item: String,label: String) -> void:
	var sprite: Sprite3D = stage.get_actor_body(who).get_node("Visual/Carry")
	var model: Node3D = stage.get_actor_body(who).get_node("Visual/CarryModel")
	check(sprite.visible and not model.visible and model.get_child_count() == 0,label+" small pouch replaces ground model")
	check(str(sprite.get_meta("original_carry_semantics","")) == "leaf-pouch-thumbnail" and str(sprite.get_meta("original_carry_id","")) == item,label+" original semantic identity")
	check(is_equal_approx(float(sprite.get_meta("original_carry_pouch_scale")),.65) and is_equal_approx(float(sprite.get_meta("original_carry_source_pixels")),25.0 if item == "dew" else 18.0),label+" original thumbnail and .65 pouch scale")
	check(is_equal_approx(sprite.pixel_size*4,1.6/115.0*(.66 if who == "buddy" else 1.0)),label+" accepted actor-relative pixel scale including buddy .66")
	check(sprite.position == Vector3(.17,.46,.06) and model.position == Vector3(.19,.35,.07),label+" existing native carry anchors unchanged")
	check(sprite.offset == Vector2(4,-8) and not sprite.no_depth_test,label+" source pouch centre anchor and normal depth")
	var no_cord: Texture2D = sprite.get_meta("original_carry_no_cord")
	var opaque := bounds(no_cord)
	# Source pouch body is24*.65=15.6px, dew wrapper25*.65=16.25px.
	# Leaves may extend beyond the bag; alpha measurement excludes empty canvas.
	var source_body_width := opaque.size.x/4
	check(absf(source_body_width-16.25) <= .75 if item == "dew" else source_body_width >= 15 and source_body_width <= 22,label+" rendered source pouch has original small visible silhouette")
	check(opaque.position.x > 0 and opaque.end.x < no_cord.get_width() and opaque.position.y > 0 and opaque.end.y < no_cord.get_height(),label+" source pouch raster is not clipped")
	if item in ["sunPost","moonPost"]: check(sprite.modulate.is_equal_approx(Color("ffe5a2") if item == "sunPost" else Color("bfd7ff")),label+" day/night identity retained")
	var identity := sprite.texture.get_instance_id()
	var builds := CarryArt.rasterizations
	stage.refresh_world(stage.world, true)
	check(sprite.texture.get_instance_id() == identity and CarryArt.rasterizations == builds,label+" ordinary refresh reuses both warmed pouch textures")
	CarryArt.pose(sprite,who,"idle-front")
	var front := sprite.texture
	CarryArt.pose(sprite,who,"idle-side")
	check(bool(sprite.get_meta("original_carry_cord_visible")) == (who == "buddy"),label+" source side-pose cord semantics")
	CarryArt.pose(sprite,who,"idle-front")
	check(sprite.texture == front and CarryArt.rasterizations == builds,label+" pose changes reuse cached variants")
	measured.append({"label":label,"holder":who,"sourcePouchVisiblePixels":source_body_width,"worldBodyWidth":opaque.size.x*sprite.pixel_size,"groundSameSizeRequired":false})

func _measure_carry(who: String, expected: float, label: String) -> void:
	var sprite: Sprite3D = stage.get_actor_body(who).get_node("Visual/Carry")
	var body := bounds(sprite.texture)
	check(sprite.visible and absf(body.size.x * sprite.pixel_size - expected) < 0.00001, label + " readable semantic carried body size")
	var centre := body.position + body.size * 0.5
	var offset := Vector2(centre.x - sprite.texture.get_width() * 0.5, sprite.texture.get_height() * 0.5 - centre.y) + sprite.offset
	check(offset.length() < 0.00001 and sprite.position == Vector3(0.17, 0.46, 0.06), label + " visible body is centred in the existing hand anchor")
	check(not sprite.no_depth_test, label + " carried body retains depth")
	measured.append({"label": label, "alpha": 128, "bounds": [body.position.x, body.position.y, body.size.x, body.size.y], "bodyWidth": body.size.x * sprite.pixel_size})

func _drop(level: String, item: String, tile: String) -> void:
	var action := "drop:" + item + ":" + tile
	var world := _before_action(level, action)
	stage.set_world(world)
	var before: Dictionary = world.snapshot().duplicate(true)
	var who := str(world.state.items[item].holder)
	check(world.act(action).ok, level + " actual item placement " + item)
	var placed: Dictionary = world.snapshot().duplicate(true)
	stage.refresh_world(world)
	check(world.snapshot() == placed, level + " placement visuals preserve destination and progress")
	check(not _carrying(who) and stage._props_nodes.has("item:" + item), level + " placed item has one ground representation")
	_measure_ground(item,level+" authored placement")
	world.undo()
	stage.refresh_world(world)
	check(world.snapshot() == before and _carrying(who), level + " undo placement restores carried item")

func _before_action(level: String, action: String) -> RefCounted:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) != "authored/" + level: continue
		var before: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act" and str(step.command.value) == action: return World.new(level, before)
			before = step.snapshot
	check(false, "fixture contains " + level + "/" + action)
	return World.new(level)
