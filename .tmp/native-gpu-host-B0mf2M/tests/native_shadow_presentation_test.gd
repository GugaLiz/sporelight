extends SceneTree
## Structural and real-domain-action checks. GPU captures separately establish
## readable artwork; prepared snapshots here are not physical route playback.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Art = preload("res://presentation/native/shadow_dressing.gd")
const Carry = preload("res://presentation/native/original_carry_art.gd")
var checks := 0
var failures: Array[String] = []
var stage: Node2D
var fixture: Dictionary = {}
var post_colors: Dictionary = {}
var stone_specs: Array = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _mark(id: String) -> Node3D: return stage._props_nodes.get("mark:" + id)

func _contains(mesh: ArrayMesh, point: Vector2) -> bool:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index: int in range(0, vertices.size(), 3):
		var triangle := PackedVector2Array()
		for offset: int in range(3): triangle.append(Vector2(vertices[index + offset].x, vertices[index + offset].y))
		if Geometry2D.is_point_in_polygon(point, triangle): return true
	return false

func _shape(node: MeshInstance3D, mode: int, label: String) -> void:
	_check(node != null and node.mesh is ArrayMesh, label + " has real relief geometry")
	if node == null or not node.mesh is ArrayMesh: return
	_check(int(node.get_meta("celestial_mode", -1)) == mode, label + " matches its actual day/night identity")
	_check(node.mesh.get_surface_count() == 1 and node.mesh.surface_get_array_len(0) >= 12, label + " contains triangulated silhouette geometry")
	_check(_contains(node.mesh, Vector2.ZERO) == (mode == 0), label + " sun has a filled centre while moon has a genuine cut-out")
	_check(_contains(node.mesh, Vector2(-.8, 0)), label + " retains its visible outer silhouette")
	if mode == 0:
		_check(_contains(node.mesh, Vector2(.5, 0)) and not _contains(node.mesh, Vector2(.64, 0)), label + " sunlight has a round disc separated from its short rays")
	_check(not (node.material_override as StandardMaterial3D).no_depth_test, label + " uses real scene depth")
	_check(node.find_children("*", "CollisionObject3D", true, false).is_empty(), label + " relief adds no collision")

func _soft_only(node: Node3D, label: String) -> void:
	_check(bool(node.get_meta("not_walkable_support", false)), label + " explicitly provides no walking support")
	_check(node.find_children("*", "CollisionObject3D", true, false).is_empty() and node.find_children("*", "CollisionShape3D", true, false).is_empty(), label + " has no decorative collision")

func _alpha_bounds(pixels: Image, threshold: int) -> Rect2i:
	var low := Vector2i(pixels.get_width(), pixels.get_height())
	var high := Vector2i(-1, -1)
	for y: int in range(pixels.get_height()):
		for x: int in range(pixels.get_width()):
			if roundi(pixels.get_pixel(x, y).a * 255.0) < threshold: continue
			low = low.min(Vector2i(x, y))
			high = high.max(Vector2i(x + 1, y + 1))
	return Rect2i(low, high - low)

func _test_stone_assets() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/images/shadow-stones/manifest.json"))
	stone_specs = manifest.assets
	_check(stone_specs.size() == 2, "natural day and night stones have separately measured source assets")
	for mode: int in range(stone_specs.size()):
		var spec: Dictionary = stone_specs[mode]
		var path := "res://assets/images/shadow-stones/" + str(spec.file)
		var pixels := Image.load_from_file(path)
		_check(pixels != null and not pixels.is_empty(), "natural stone PNG exists: " + str(spec.kind))
		if pixels == null or pixels.is_empty(): continue
		_check(FileAccess.get_sha256(path) == str(spec.sha256), "natural stone source matches recorded generated asset hash")
		_check(pixels.get_width() == int(spec.canvas[0]) and pixels.get_height() == int(spec.canvas[1]), "natural stone canvas matches offline source measurement")
		for entry: Array in [[8, "atlasAlpha8"], [128, "bodyAlpha128"]]:
			var bounds := _alpha_bounds(pixels, int(entry[0]))
			var expected: Array = spec[str(entry[1])]
			_check(bounds == Rect2i(int(expected[0]), int(expected[1]), int(expected[2]), int(expected[3])), "natural stone alpha " + str(entry[0]) + " validates offline crop/body bounds")
		var body: Array = spec.bodyAlpha128
		var measured := Vector2(float(body[2]), float(body[3])) * float(spec.pixelSize)
		_check(absf(measured.x - (.5330525653 if mode == 0 else .5462225130)) < .00001 and absf(measured.y - .8430182145) < .00001, "natural stone actual opaque width and height match approved local redesign")
		_check(measured.x <= .72731 and measured.y <= .84302, "natural stone stays uniformly inside original stone envelope")
		_check(Vector2(float(spec.footPixel[0]), float(spec.footPixel[1])).is_equal_approx(Vector2(float(body[0]) + float(body[2]) * .5 - .5, float(body[1]) + float(body[3]) - .5)), "natural stone foot uses actual opaque bottom pixel centre")

func _inspect_stone(post: Node3D, mode: int, label: String) -> void:
	_check(not post.has_node("PostEmblem") and not post.has_node("PostEmblemBorder"), label + " natural mineral has no attached badge or badge border")
	var stone: Sprite3D = post.get_node("crystal")
	_check(stone.texture is AtlasTexture and stone.texture == Art.icon_texture(mode), label + " ground uses the actual cached natural-stone atlas")
	if not stone.texture is AtlasTexture: return
	var atlas := stone.texture as AtlasTexture
	var spec: Dictionary = stone_specs[mode]
	var crop: Array = spec.atlasAlpha8
	_check(atlas.atlas.resource_path.ends_with("/shadow-stones/" + str(spec.file)) and atlas.region == Rect2(float(crop[0]), float(crop[1]), float(crop[2]), float(crop[3])), label + " atlas retains generated PNG and measured transparent-margin crop")
	_check(is_equal_approx(stone.pixel_size, float(spec.pixelSize)) and stone.scale.is_equal_approx(Vector3.ONE), label + " stone uses a uniform measured body scale")
	var foot := Vector2(float(spec.footPixel[0]) - float(crop[0]), float(spec.footPixel[1]) - float(crop[1]))
	var anchor := Vector2(foot.x - stone.texture.get_width() * .5 + stone.offset.x, stone.texture.get_height() * .5 - foot.y + stone.offset.y) * stone.pixel_size
	_check(anchor.length() < .00001 and not stone.no_depth_test, label + " actual opaque foot meets anchor with normal depth")
	var physical_offset := Vector3(0, 0, -.20) if mode == 0 and str(stage.world.state.items.sunPost.tile) == "f:0:0" else Vector3.ZERO
	_check(stone.position.is_equal_approx(physical_offset), label + " retains original physical slot offset")
	var id := "item:sunPost" if mode == 0 else "item:moonPost"
	var entries: Array = stage._prop_obstacles.filter(func(entry: Dictionary) -> bool: return str(entry.id) == id)
	_check(entries.size() == 1, label + " retains one conservative original hard-foot footprint")
	if entries.size() == 1:
		var rect: Rect2 = entries[0].rect
		var center: Vector3 = post.global_position + physical_offset
		_check(rect.size.is_equal_approx(Vector2.ONE * (36.0 / 70.0)) and rect.get_center().is_equal_approx(Vector2(center.x, center.z)), label + " original hard-foot rectangle and center are unchanged")
	post_colors[str(mode) + ":" + str(stage.world.state.mode)] = stone.modulate

func _inspect(world: RefCounted, label: String) -> void:
	var before: Dictionary = world.snapshot()
	var tiles: Array = world.tiles()
	stage.set_world(world)
	stage.refresh_world(world, false)
	_check(world.snapshot() == before and world.tiles() == tiles, label + " dressing preserves puzzle state and exact walkable tiles")
	for node: Node in stage._props.find_children("*", "Node3D", true, false):
		if node.has_meta("shadow_role"):
			_check(node.find_children("*", "Label3D", true, false).is_empty(), label + " celestial mechanisms have no floating words")
	for mode: int in range(2):
		var id := "sunPost" if mode == 0 else "moonPost"
		var item: Dictionary = world.state.items[id]
		var post: Node3D = stage._props_nodes.get("item:" + id)
		if str(item.get("holder", "")).is_empty():
			_check(post != null and int(post.get_meta("shadow_mode", -1)) == mode, label + " ground post retains identity " + id)
			if post != null:
				_inspect_stone(post, mode, label + " " + id)
				_check(bool(post.get_meta("shadow_active", false)) == (mode == int(world.state.mode)), label + " post activity follows current light, not frozen memory")
		else:
			_inspect_carry(str(item.holder), id, mode, label)
		var slot := _mark("sunSlot" if mode == 0 else "moonSlot")
		_check(slot != null and int(slot.get_meta("shadow_mode", -1)) == mode, label + " suggested slot matches the post identity")
		if slot != null:
			_shape(slot.get_node("SlotImprint"), mode, label + " slot " + str(mode))
			_soft_only(slot, label + " suggested slot")
	var control := _mark("mode")
	var selected := int(world.state.mode)
	_check(int(control.get_meta("shadow_mode", -1)) == selected, label + " control follows actual current light")
	var sun: MeshInstance3D = control.get_node("CurrentSun")
	var moon: MeshInstance3D = control.get_node("CurrentMoon")
	_shape(sun, 0, label + " control sun")
	_shape(moon, 1, label + " control moon")
	_check((sun.basis.x.length() > moon.basis.x.length()) == (selected == 0), label + " selected mode is physically prominent")
	_check(control.has_node("CurrentModeNotch"), label + " active light has an inset marker")
	var memory := _mark("freeze")
	var frozen: Variant = world.state.get("frozen")
	_check(int(memory.get_meta("shadow_mode", -2)) == (-1 if frozen == null else int(frozen)), label + " memory follows retained mode, independently of current light")
	_check(memory.get_meta("shadow_memory_points", []) == world.state.get("shadowMemory", []), label + " memory records the exact retained coordinates")
	_check(memory.has_node("RetainedImprint") == (frozen != null) and memory.has_node("RetainedContour") == (frozen != null), label + " only an actual retained impression has the closed contour")
	_soft_only(memory, label + " memory leaf")
	if frozen != null: _shape(memory.get_node("RetainedImprint"), int(frozen), label + " retained impression")
	var expected: Dictionary = {}
	for tile: Dictionary in tiles:
		if str(tile.get("kind", "")) == "shadow" and world.visible(tile, tiles): expected[str(tile.id)] = tile
	var seen: Dictionary = {}
	for node: Node in stage._props.get_children():
		if str(node.get_meta("shadow_role", "")) != "road": continue
		var tile_id := str(node.get_meta("tile_id", ""))
		_check(expected.has(tile_id) and not seen.has(tile_id), label + " road relief belongs to one real shadow tile")
		if not expected.has(tile_id): continue
		seen[tile_id] = true
		var mode := 0 if tile_id.begins_with("shadow:sun") else 1
		var retained: bool = frozen != null and int(frozen) == mode
		_shape(node.get_node("RoadImprint"), mode, label + " road " + tile_id)
		_check(bool(node.get_meta("shadow_retained")) == retained and node.has_node("RetainedContour") == retained, label + " road contour distinguishes retained from current projection")
		var surface: Node3D = stage._surface_for_support(tile_id)
		_check(surface != null and surface.has_method("sample_height"), label + " road relief has actual physical support")
		if surface != null and surface.has_method("sample_height"):
			var at: Vector3 = (node as Node3D).global_position
			var ground_height: float = surface.sample_height(at)
			var expected_center: Vector3 = stage._props.to_global(stage.tile_position(expected[tile_id]))
			_check(Vector2(at.x, at.z).is_equal_approx(Vector2(expected_center.x, expected_center.z)) and absf(at.y - ground_height - .008) < .001, label + " road relief is inset just above the actual physical surface")
		_soft_only(node, label + " road relief")
	_check(seen.size() == expected.size(), label + " no actual shadow road is missing its identity")
	_check(world.snapshot() == before, label + " all inspection leaves rules unchanged")

func _inspect_carry(who: String, id: String, mode: int, label: String) -> void:
	var body: CharacterBody3D = stage.get_actor_body(who)
	var sprite: Sprite3D = body.get_node("Visual/Carry")
	var model: Node3D = body.get_node("Visual/CarryModel")
	_check(sprite.visible and not model.visible and str(sprite.get_meta("original_carry_id", "")) == id, label + " carried post keeps its identity in the original pouch")
	_check(sprite.position == Vector3(.17, .46, .06) and sprite.offset == Vector2(4, -8), label + " pouch keeps approved hand anchor")
	_check(is_equal_approx(sprite.pixel_size * 4, 1.6 / 115.0 * (.66 if who == "buddy" else 1.0)), label + " pouch keeps accepted actor-relative scale")
	_check(is_equal_approx(float(sprite.get_meta("original_carry_pouch_scale")), .65) and float(sprite.get_meta("original_carry_source_pixels")) == 18, label + " original thumbnail size is preserved")
	var icon := Art.icon_texture(mode)
	_check(icon is AtlasTexture and icon == Art.icon_texture(mode) and icon != Art.icon_texture(1 - mode), label + " sun and moon use distinct cached natural-stone resources")
	_check(sprite.get_meta("original_carry_with_cord") == Carry.texture(id, icon, true) and sprite.get_meta("original_carry_no_cord") == Carry.texture(id, icon, false), label + " both carried poses use the same natural stone as the ground prop")
	_check(sprite.modulate.is_equal_approx(Color.WHITE), label + " natural mineral colours are not retinted along with the pouch")
	var builds := Carry.rasterizations
	var current := sprite.texture
	stage.refresh_world(stage.world, true)
	_check(Carry.rasterizations == builds and sprite.texture == current, label + " ordinary refresh reuses the same carried artwork")

func _memory_positions() -> Dictionary:
	var result := {}
	for node: Node in stage._props.get_children():
		if str(node.get_meta("shadow_role", "")) == "road" and bool(node.get_meta("shadow_retained", false)):
			result[str(node.get_meta("tile_id"))] = (node as Node3D).global_position
	return result

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	await process_frame
	_test_stone_assets()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/3-2": fixture = entry
	_check(not fixture.is_empty(), "original 3-2 route fixture exists")
	if fixture.is_empty(): quit(1); return
	_inspect(World.new("3-2"), "initial")
	for index: int in [2, 5, 9, 17, 24, 26, 35]:
		_inspect(World.new("3-2", fixture.steps[index].snapshot), "original step " + str(index))
	var world := World.new("3-2", fixture.steps[24].snapshot)
	_inspect(world, "sun memory before post movement")
	var retained: Array = world.state.shadowMemory.duplicate(true)
	var positions := _memory_positions()
	_check(world.move("f:-1:0").ok and world.move("f:0:0").ok and world.act("take:sunPost").ok, "original legal actions pick up the post after freezing")
	_inspect(world, "sun post carried after freezing")
	_check(world.state.shadowMemory == retained and _memory_positions() == positions, "retained road geometry does not follow the lifted post")
	# One cell west is still near the suggested sun slot, so the original
	# command offers that slot instead of the actor's floor. Leave its range
	# before asking for a floor drop; never bypass the offered action set.
	_check(world.move("f:-1:0").ok and world.move("f:-2:0").ok, "post carrier returns to original fixed floor beyond slot range")
	_check(world.commands().any(func(command: Dictionary) -> bool: return str(command.id) == "drop:sunPost:f:-2:0"), "relocation uses the actual offered floor-drop command")
	_check(world.act("drop:sunPost:f:-2:0").ok, "original post can be moved after freezing")
	_check(str(world.state.items.sunPost.tile) == "f:-2:0", "post relocation actually changed its grounded tile")
	_inspect(world, "sun post relocated after freezing")
	_check(world.state.shadowMemory == retained and _memory_positions() == positions, "retained road geometry stays fixed after post relocation")
	world = World.new("3-2", fixture.steps[26].snapshot)
	_check(world.act("freeze").ok, "original current moon projection may replace sun memory")
	_inspect(world, "moon memory")
	_check(int(world.state.frozen) == 1 and int(_mark("freeze").get_meta("shadow_mode")) == 1, "memory symbol changes to the actually frozen moon")
	world.undo()
	_inspect(world, "undo moon memory")
	_check(int(world.state.frozen) == 0, "undo restores original sun memory")
	for mode: int in range(2):
		var active_key := str(mode) + ":" + str(mode)
		var inactive_key := str(mode) + ":" + str(1 - mode)
		_check(post_colors.has(active_key) and post_colors.has(inactive_key), "both actual post-lighting states were inspected")
		if post_colors.has(active_key) and post_colors.has(inactive_key):
			var active: Color = post_colors[active_key]
			var inactive: Color = post_colors[inactive_key]
			_check(active.is_equal_approx(Color.WHITE) and active.get_luminance() > inactive.get_luminance() + .1, "current light naturally brightens its matching stone")
	stage.set_world(World.new("3-1"))
	_check(stage._props.find_children("*", "Node3D", true, false).all(func(node: Node) -> bool: return not node.has_meta("shadow_role")), "celestial dressing does not leak into another level")
	print(JSON.stringify({"suite": "native-shadow-presentation", "passed": failures.is_empty(), "checks": checks, "failures": failures, "gpuPixelsVerified": false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
