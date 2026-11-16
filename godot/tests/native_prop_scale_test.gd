extends SceneTree
## Source-pixel bounds and real action/undo/restore integration, not GPU QA.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Factory = preload("res://core/world_factory.gd")
const CarryArt = preload("res://presentation/native/original_carry_art.gd")
const ShadowArt = preload("res://presentation/native/shadow_dressing.gd")
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
	_root_basin()
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
	_mirror_states()
	for item: String in ["mirrorA", "mirrorB"]:
		_mirror_motion("2-2", item)
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
	check(not last.no_depth_test, level + " flower retains normal depth")
	# The complete stone planter is a hard base under the current scene
	# contract. Growth may replace its artwork, but must retain that obstacle.
	var mark_root: Node3D = stage._props_nodes["mark:" + mark]
	var stone: StaticBody3D = last.get_node_or_null("FlowerStoneFoot") as StaticBody3D
	check(bool(last.get_meta("hard_planter", false)) and stone != null, level + " flower retains its declared hard base")
	if stone != null:
		check(stone.collision_layer == 8 and stone.collision_mask == 0 and bool(stone.get_meta("not_walkable_support", false)), level + " stone blocks entry without creating walkable support")
		var volume: CollisionShape3D = stone.get_node_or_null("BaseVolume") as CollisionShape3D
		check(volume != null and volume.shape is BoxShape3D, level + " stone has a complete collision volume")
		if volume != null and volume.shape is BoxShape3D:
			var span: Vector2 = last.get_meta("ground_footprint_span")
			var center: Vector3 = mark_root.to_global(last.get_meta("ground_footprint_center"))
			var box: BoxShape3D = volume.shape as BoxShape3D
			check(is_equal_approx(box.size.x, span.x) and is_equal_approx(box.size.z, span.y), level + " stone covers the declared complete footprint")
			check(Vector2(volume.global_position.x, volume.global_position.z).distance_to(Vector2(center.x, center.z)) < 0.00001 and absf(volume.global_position.y - box.size.y * .5 - center.y) < 0.00001, level + " stone collision stays on the declared support anchor")
	stage.set_world(World.new(level, committed))
	check(stage._props_nodes["mark:" + mark].get_child(0).name == "bloom", level + " restored state retains the correct flower")
	world.undo()
	stage.set_world(world)
	check(world.snapshot() == before and stage._props_nodes["mark:" + mark].get_child(0).name == "flower", level + " undo restores original state and bud")
	measured.append({"level": level, "kind": "mechanism flower", "beforeBody": [first_size.x, first_size.y], "afterBody": [last_size.x, last_size.y]})

func _root_basin() -> void:
	var world := _before_action("3-3", "use:care")
	stage.set_world(world)
	var before: Dictionary = world.snapshot().duplicate(true)
	var first: Sprite3D = stage._props_nodes["mark:care"].get_node("NaturalRootBasin")
	var size := bounds(first.texture).size * first.pixel_size
	var position := first.position
	var pixel_size := first.pixel_size
	var center: Vector3 = first.get_meta("ground_footprint_center")
	var span: Vector2 = first.get_meta("ground_footprint_span")
	check(absf(size.x - .9) < .00001 and absf(size.y - .51759941) < .00001, "3-3 natural root basin has its measured local silhouette")
	check(world.act("use:care").ok, "3-3 original dew delivery succeeds")
	stage.refresh_world(world)
	var last: Sprite3D = stage._props_nodes["mark:care"].get_node("NaturalRootBasin")
	var active_size := bounds(last.texture).size * last.pixel_size
	check(absf(active_size.x - size.x) < .003 and absf(active_size.y - size.y) < .005 and last.position == position and is_equal_approx(last.pixel_size, pixel_size), "3-3 filled bowl preserves uniform scale and position with small measured sprout-edge difference")
	check(last.texture.atlas.resource_path.ends_with("root-basin-settled-v1.png") and last.has_node("FlowerStoneFoot"), "3-3 stability selects painted water while retaining real bowl collision")
	check(last.get_meta("ground_footprint_center") == center and last.get_meta("ground_footprint_span") == span, "3-3 water state never moves or resizes the hard bowl footprint")
	stage.set_world(World.new("3-3", world.snapshot()))
	check(stage._props_nodes["mark:care"].get_node("NaturalRootBasin").texture.atlas.resource_path.ends_with("root-basin-settled-v1.png"), "3-3 reload retains actual stored water")
	world.undo()
	stage.set_world(world)
	check(world.snapshot() == before and stage._props_nodes["mark:care"].get_node("NaturalRootBasin").texture.atlas.resource_path.ends_with("root-basin-v1.png"), "3-3 undo restores empty bowl and original progress")
	measured.append({"level":"3-3","kind":"natural root basin","beforeBody":[size.x,size.y],"afterBody":[active_size.x,active_size.y]})

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
	if str(stage.world.level.id) == "3-2" and item in ["sunPost", "moonPost"]:
		# The user's natural-stone redesign is a local exception to the old
		# crystal canvas. Measure opaque mineral pixels, not transparent PNG size.
		var mode := 0 if item == "sunPost" else 1
		var body := bounds(sprite.texture)
		var width := body.size.x * sprite.pixel_size
		var height := body.size.y * sprite.pixel_size
		check(sprite.texture is AtlasTexture and sprite.texture == ShadowArt.icon_texture(mode), label + " actual natural-stone resource with cached alpha crop")
		check(not node.has_node("PostEmblem") and not node.has_node("PostEmblemBorder"), label + " mineral identity has no attached badges")
		check(absf(width - (.5330525653 if mode == 0 else .5462225130)) < .00001 and absf(height - .8430182145) < .00001, label + " measured natural-stone opaque body matches local approved dimensions")
		check(width <= .72731 and height <= .84302 and sprite.scale.is_equal_approx(Vector3.ONE), label + " uniformly fitted mineral remains inside original stone envelope")
		var foot_x := (body.get_center().x - .5 - sprite.texture.get_width() * .5 + sprite.offset.x) * sprite.pixel_size
		var foot_y := (sprite.texture.get_height() * .5 - (body.end.y - .5) + sprite.offset.y) * sprite.pixel_size
		check(absf(foot_x) < .00001 and absf(foot_y) < .00001 and not sprite.no_depth_test, label + " natural opaque bottom pixel retains physical foot anchor and depth")
		measured.append({"label": label, "naturalStone": true, "alpha": 128, "bodyWidth": width, "bodyHeight": height, "footPixelError": [foot_x, foot_y]})
		return
	# Independent literal source sizes from render.ts, not production constants.
	var source_width := 52.0 if item.begins_with("mirror") else (34.0 if bool(data.get("picked",false)) else 49.0) if item == "dew" else 36.0
	if str(stage.world.level.id) == "3-3" and item == "dew" and not bool(data.get("picked", false)):
		source_width *= .72 # Local unpicked plant redesign; parcels and other levels retain the original ratio.
	check(is_equal_approx(sprite.texture.get_width()*sprite.pixel_size,source_width*sqrt(2.0)/70.0),label+" source canvas/tile ratio")
	check(not sprite.no_depth_test,label+" ground keeps depth")
	if item.begins_with("mirror"):
		var face: MeshInstance3D = node.get_node("ReflectionFace")
		check(face.mesh.size.is_equal_approx(Vector3(.53,.42,.025)),label+" unchanged real ground reflection plane")
		if str(stage.world.level.id) in ["2-2", "3-4"]:
			# 3-4 now shares the recognizable silver mirror. Its seedbed mount
			# keeps the previously approved northward physical clearance offset.
			var support_offset := Vector3(0,0,-.20) if str(stage.world.level.id) == "3-4" and str(data.tile) == "f:1:-4" else Vector3.ZERO
			var spindle: MeshInstance3D = node.get_node("ReflectionSpindle")
			var rim: MeshInstance3D = face.get_node("SilverBeveledRim")
			var mount: MeshInstance3D = node.get_node("FixedMirrorGimbal")
			var bottom: MeshInstance3D = node.get_node("BottomGimbalBearing")
			var top: MeshInstance3D = node.get_node("TopGimbalBearing")
			var rim_bounds: AABB = rim.mesh.get_aabb()
			check(is_equal_approx(face.position.y,.37) and Vector3(node.get_meta("physical_item_offset",Vector3.ZERO)).is_equal_approx(support_offset),label + " silver optical centre and existing physical placement offset are preserved")
			check(rim_bounds.size.z >= 0.07 and rim_bounds.size.x < 0.54 and rim_bounds.size.y < 0.47, label + " oval silver rim has visible physical thickness inside the original scale")
			check(not node.has_node("ReflectionLeafBack") and face.material_override.shader.code.contains("cull_disabled"), label + " both real glass faces remain visible without a leaf covering the back")
			check(is_equal_approx(spindle.position.y - spindle.mesh.height * 0.5, 0.09) and spindle.position.y + spindle.mesh.height * 0.5 > bottom.position.y - bottom.mesh.height * 0.5, label + " real spindle overlaps the fixed mount bearing above the original seat")
			check(is_equal_approx(bottom.position.y + bottom.mesh.height * 0.5, face.position.y + rim_bounds.position.y) and is_equal_approx(top.position.y - top.mesh.height * 0.5, face.position.y + rim_bounds.end.y), label + " vertical bearings physically meet both ends of the rotating frame")
			check(mount.get_parent() == node and mount.material_override is StandardMaterial3D and mount.position == face.position, label + " stationary metal surround shares the real optical centre without becoming a fake mirror")
			check(Vector2(face.position.x,face.position.z).is_equal_approx(Vector2(support_offset.x,support_offset.z)) and Vector2(spindle.position.x,spindle.position.z).is_equal_approx(Vector2(support_offset.x,support_offset.z)), label + " glass and spindle share the existing physical support centre")
			var clear_bounds := true
			for corner in range(8):
				var at: Vector3 = face.position + face.basis * rim_bounds.get_endpoint(corner) - support_offset
				if absf(at.x) > 0.2051 or absf(at.z) > 0.2051: clear_bounds = false
			check(clear_bounds, label + " settled thick frame remains within the original hard-base footprint")
			var mount_bounds: AABB = mount.mesh.get_aabb()
			for corner in range(8):
				var at: Vector3 = mount.position + mount.basis * mount_bounds.get_endpoint(corner) - support_offset
				if absf(at.x) > 0.2051 or absf(at.z) > 0.2051: clear_bounds = false
			check(clear_bounds, label + " fixed surround also stays within the existing hard-base footprint")
		else:
			check(is_equal_approx(face.position.y, 0.32) and not node.has_node("ReflectionSpindle") and face.get_child_count() == 4 and node.has_node("ReflectionLeafBack"), label + " other chapter mirror keeps original height and construction")
		_check_mirror_reflection(face, int(data.get("angle", 0)), label)
	var opaque := bounds(sprite.texture)
	measured.append({"label":label,"sourceCanvasPixels":source_width,"worldCanvas":sprite.texture.get_width()*sprite.pixel_size,"visibleBody":opaque.size.x*sprite.pixel_size})

func _check_mirror_reflection(face: MeshInstance3D, angle: int, label: String) -> void:
	# Probe the actual rendered thin face, independently of its authored yaw.
	# These incoming/outgoing pairs are the two-sided optical contract, not a
	# second copy of the production angle-to-rotation formula.
	var incoming: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var outgoing: Array[Vector3] = [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]
	if posmod(angle, 2) != 0:
		outgoing = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	var normal := face.global_basis.z.normalized()
	check(absf(normal.y) < 0.00001, label + " reflection face stays vertical")
	for index in range(incoming.size()):
		var reflected := incoming[index] - 2.0 * incoming[index].dot(normal) * normal
		check(reflected.distance_to(outgoing[index]) < 0.00001, label + " real face reflects cardinal incident " + str(index) + " to the rule direction")

func _mirror_states() -> void:
	# All four A/B angle combinations retain their original support and size.
	# Only A=1/B=1 may illuminate the real receiver from the authored slot.
	for a in range(2):
		for b in range(2):
			var world := World.new("2-2")
			var snapshot: Dictionary = world.snapshot()
			snapshot.items.mirrorA.angle = a
			snapshot.items.mirrorB = {"tile": "f:1:0", "angle": b}
			world = World.new("2-2", snapshot)
			stage.set_world(world)
			var label := "2-2 A=" + str(a) + "/B=" + str(b)
			_measure_ground("mirrorA", label + " fixed mirror")
			_measure_ground("mirrorB", label + " placed mirror")
			check(world.beam_hits(4, 0) == (a == 1 and b == 1), label + " current ray alone controls receiver")
			check(world.snapshot() == snapshot, label + " optical presentation preserves the saved puzzle")
	var high := _before_action("3-4", "drop:mirror:f:8:0")
	check(high.act("drop:mirror:f:8:0").ok, "3-4 optical probe uses actual high-slot placement")
	for angle in range(2):
		var snapshot: Dictionary = high.snapshot()
		snapshot.items.mirror.angle = angle
		var restored := World.new("3-4", snapshot)
		stage.set_world(restored)
		_measure_ground("mirror", "3-4 high-slot angle=" + str(angle))
		check(restored.snapshot() == snapshot, "3-4 optical presentation preserves restored high-slot state")

func _mirror_motion(level: String, item: String) -> void:
	var action := "angle:" + item
	var world := _before_action(level, action)
	var before: Dictionary = world.snapshot()
	stage.set_world(world)
	var first: MeshInstance3D = stage._props_nodes["item:" + item].get_node("ReflectionFace")
	var start_normal := first.global_basis.z.normalized()
	check(world.act(action).ok, level + "/" + item + " real turn is offered")
	var after: Dictionary = world.snapshot()
	stage.set_world(world)
	var last: MeshInstance3D = stage._props_nodes["item:" + item].get_node("ReflectionFace")
	var finish_normal := last.global_basis.z.normalized()
	var turn := start_normal.signed_angle_to(finish_normal, Vector3.UP)
	check(is_equal_approx(absf(turn), PI / 2), level + "/" + item + " aligned states differ by the shortest quarter turn")
	for reverse: bool in [false, true]:
		var from: Dictionary = after if reverse else before
		var to: Dictionary = before if reverse else after
		var normal := finish_normal if reverse else start_normal
		stage.set_world(World.new(level, from))
		for phase: float in [0.0, 0.5, 1.0]:
			stage.set_motion(from, to, phase, "undo" if reverse else action)
			var face: MeshInstance3D = stage._props_nodes["item:" + item].get_node("ReflectionFace")
			var expected := normal.rotated(Vector3.UP, (-turn if reverse else turn) * phase)
			var label := level + "/" + item + (" undo" if reverse else " turn") + " phase=" + str(phase)
			check(face.global_basis.z.normalized().distance_to(expected) < 0.00001, label + " real mirror rotates continuously along the shortest arc")
			check(face.mesh.size.is_equal_approx(Vector3(.53,.42,.025)), label + " rotation does not resize the mirror")
			if level in ["2-2", "3-4"]:
				var surround: Node3D = stage._props_nodes["item:" + item].get_node("FixedMirrorGimbal")
				check(surround.global_basis.z.normalized().distance_to(Vector3(1, 0, 1).normalized()) < 0.00001, label + " physical outer mount stays fixed while only the inner optical face turns")
			check(stage.world.snapshot() == to, label + " interpolation never changes committed rule state")
		stage.clear_motion(false)
	check(world.snapshot() == after, level + "/" + item + " motion and reverse presentation preserve the original model")

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
	if str(stage.world.level.id) == "3-2" and item in ["sunPost", "moonPost"]:
		var stone := ShadowArt.icon_texture(0 if item == "sunPost" else 1)
		check(stone is AtlasTexture and sprite.modulate.is_equal_approx(Color.WHITE), label + " natural mineral colours remain untinted in the original pouch")
		check(sprite.get_meta("original_carry_with_cord") == CarryArt.texture(item, stone, true) and no_cord == CarryArt.texture(item, stone, false), label + " both carry poses use the same natural stone as its ground prop")
	elif item in ["sunPost", "moonPost"]:
		check(sprite.modulate.is_equal_approx(Color("ffe5a2") if item == "sunPost" else Color("bfd7ff")), label + " other chapter day/night tint remains unchanged")
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
