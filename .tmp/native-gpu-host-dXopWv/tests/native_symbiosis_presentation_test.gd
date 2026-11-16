extends SceneTree
## Source measurements and original rules. GPU QA separately verifies appearance
## and actual travel; prepared boundary states here do not prove a physical route.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Array = []
var stage: Node2D
var fixture: Dictionary
var manifest: Dictionary

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _mark(id: String) -> Node3D: return stage._props_nodes.get("mark:" + id)

func _alpha(image: Image, threshold: float) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < threshold: continue
			low = low.min(Vector2i(x, y))
			high = high.max(Vector2i(x + 1, y + 1))
	return Rect2i(low, high - low)

func _assets() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/images/symbiosis/manifest.json"))
	for id: String in manifest.assets:
		var spec: Dictionary = manifest.assets[id]
		var path := "res://assets/images/symbiosis/" + str(spec.file)
		var image := Image.load_from_file(path)
		_check(image != null and FileAccess.get_sha256(path) == str(spec.sha256), id + " PNG matches generation provenance")
		if image == null: continue
		_check(image.get_width() == int(spec.canvas[0]) and image.get_height() == int(spec.canvas[1]), id + " original PNG canvas preserved")
		for pair: Array in [[8.0, "atlasAlpha8"], [128.0, "opaqueAlpha128"]]:
			var actual := _alpha(image, float(pair[0]) / 255.0)
			var expected: Array = spec[str(pair[1])]
			_check(actual == Rect2i(int(expected[0]), int(expected[1]), int(expected[2]), int(expected[3])), id + " alpha bounds match actual pixels")

func _art(sprite: Sprite3D, id: String) -> void:
	_check(sprite != null and sprite.texture is AtlasTexture, id + " uses original natural PNG via atlas")
	if sprite == null or not sprite.texture is AtlasTexture: return
	var spec: Dictionary = manifest.assets[id]
	var atlas := sprite.texture as AtlasTexture
	var crop: Array = spec.atlasAlpha8
	var opaque: Array = spec.opaqueAlpha128
	_check(atlas.atlas.resource_path.ends_with(str(spec.file)) and atlas.region == Rect2(float(crop[0]), float(crop[1]), float(crop[2]), float(crop[3])), id + " atlas crops only measured transparent margin")
	var body := Vector2(float(opaque[2]), float(opaque[3])) * sprite.pixel_size
	_check(sprite.scale.is_equal_approx(Vector3.ONE) and absf(body.x - float(spec.visibleWorldSize[0])) < .00001 and absf(body.y - float(spec.visibleWorldSize[1])) < .00001, id + " actual opaque body uses uniform measured scale")
	var foot := Vector2(float(spec.footPixel[0]) - float(crop[0]), float(spec.footPixel[1]) - float(crop[1]))
	var error := Vector2(foot.x - sprite.texture.get_width() * .5 + sprite.offset.x, sprite.texture.get_height() * .5 - foot.y + sprite.offset.y) * sprite.pixel_size
	_check(error.length() < .00001 and not sprite.no_depth_test, id + " measured foot sits at declared anchor with real depth")
	_check(body.y < 1.1 and body.x < 1.05, id + " local prop stays below main actor height and near one-tile span")
	measurements.append({"asset":id,"body":[body.x,body.y],"footError":[error.x,error.y]})

func _inspect(world: RefCounted, label: String) -> void:
	var before: Dictionary = world.snapshot().duplicate(true)
	var tiles: Array = world.tiles().duplicate(true)
	stage.set_world(world)
	_check(world.snapshot() == before and world.tiles() == tiles, label + " art preserves state and exact logical support")
	_check(stage._props.find_children("*", "Label3D", true, false).is_empty(), label + " 3-3 scene identity uses no floating text")
	var stable: bool = world.flag("root")
	for pair: Array in [["turn", "NaturalWheel", "wheel"], ["lift", "NaturalLift", "lift"], ["care", "NaturalRootBasin", "root_settled" if stable else "root"]]:
		_art(_mark(str(pair[0])).get_node_or_null(str(pair[1])), str(pair[2]))
	var basin := _mark("care")
	_check(not basin.has_node("StoredDew") and not basin.has_node("SettledLeaf_0"), label + " water and sprouts use registered natural art without flat overlay badges")
	var dormant: Dictionary = manifest.assets.root
	var settled: Dictionary = manifest.assets.root_settled
	_check(dormant.footPixel == settled.footPixel and dormant.pixelSize == settled.pixelSize, label + " both source states retain identical physical foot registration and pixel scale")
	_check(not basin.has_node("flower") and not basin.has_node("bloom"), label + " receiving root is not a second flowerbed")
	var sprite: Sprite3D = basin.get_node("NaturalRootBasin")
	_check(sprite.has_node("FlowerStoneFoot"), label + " natural bowl retains its hard footprint")
	var entries: Array = stage._prop_obstacles.filter(func(entry: Dictionary) -> bool: return str(entry.id).begins_with("mark:care/"))
	_check(entries.size() == 1 and entries[0].rect.size.is_equal_approx(Vector2(.6, .6)), label + " one compact bowl obstacle replaces old flowerbed")
	_check(_mark("root").has_node("GrowthAnchor") and _mark("root").find_children("*", "Sprite3D", true, false).is_empty(), label + " original root interaction remains without duplicate planted art")
	_check(is_equal_approx(stage.get_actor_body("luvie").get_node("Visual/Art").pixel_size, .00625) and is_equal_approx(stage.get_actor_body("buddy").get_node("Visual/Art").pixel_size, .0062), label + " actor scales remain unchanged")

func _before(action: String) -> Dictionary:
	var result: Dictionary = fixture.initial.snapshot
	for step: Dictionary in fixture.steps:
		if str(step.command.value) == action: return result.duplicate(true)
		result = step.snapshot
	_check(false, "original action exists " + action)
	return {}

func _walk_domain(world: RefCounted, destination: String, label: String) -> bool:
	if str(world.state.actors[world.actor()]) == destination: return true
	var path: Array = world.path_to(destination)
	_check(not path.is_empty(), label + " has a legal domain approach")
	if path.is_empty(): return false
	for id: String in path:
		var result: Dictionary = world.move(id)
		_check(result.ok, label + " traverses adjacent support " + id)
		if not result.ok: return false
	_check(str(world.state.actors[world.actor()]) == destination, label + " reaches requested support")
	return str(world.state.actors[world.actor()]) == destination

func _original_route() -> void:
	var world := World.new("3-3")
	_check(fixture.steps.size() == 59, "immutable original 3-3 trace contains 59 intentions")
	var expected_before: Dictionary = fixture.initial.snapshot
	for index: int in fixture.steps.size():
		var step: Dictionary = fixture.steps[index]
		var id := str(step.command.value)
		var label := "original step " + str(index)
		var result := {"ok": false}
		if step.command.kind == "move":
			result.ok = _walk_domain(world, id, label)
		else:
			var destination := str(expected_before.actors[world.actor()])
			if id.begins_with("grow:"):
				destination = str(world.root_growth_station(world.level.roots[0]).id)
			if not _walk_domain(world, destination, label + " interaction approach"): return
			if id.begins_with("grow:"):
				_check(world.can_grow_root(world.level.roots[0]), label + " builds while standing at the current frontier")
			result = world.act(id)
		_check(result.ok == step.result.ok, "original step " + str(index) + " acceptance")
		# Added frontier walks intentionally change actor/follower locations.
		# Check those through legal movement and following above/below; every
		# other original snapshot field still has an exact recursive comparison.
		var actual: Dictionary = world.snapshot().duplicate(true)
		var expected: Dictionary = step.snapshot.duplicate(true)
		actual.erase("actors")
		expected.erase("actors")
		_check(Snapshot.equivalent(actual, expected), label + " exact non-position puzzle snapshot")
		_check(world.together(), label + " automatic companion remains with the walking actor")
		_check(world.normalize_saved(world.snapshot()).get("ok", false), label + " actor supports and all saved progress remain valid")
		_check(world.ready() == step.ready, "original step " + str(index) + " readiness")
		expected_before = step.snapshot
	_check(world.state.completed, "original sequence still completes")

func _boundaries() -> void:
	var base := _before("grow:root:right")
	for direction: int in [1, 2]:
		var state := base.duplicate(true)
		state.turns.water = direction
		var world := World.new("3-3", state)
		var before: Dictionary = world.snapshot()
		_check(not world.act("grow:root:right").ok and world.snapshot() == before, "unwatered roots cannot grow at direction " + str(direction))
	var connected := World.new("3-3", fixture.steps[12].snapshot)
	_check(connected.connected() and not connected.flag("root"), "four connected sections alone never stabilize the root")
	_inspect(connected, "connected but thirsty")
	for high: int in [0, 1]:
		var state := _before("valve:lift")
		state.turns.water = 2
		state.turns.lift = high
		var world := World.new("3-3", state)
		var before: Dictionary = world.snapshot()
		var result: Dictionary = world.act("valve:lift")
		_check(result.ok == (high == 1), "dry lift blocks ascent but permits safe descent")
		if high == 0: _check(world.snapshot() == before, "blocked ascent preserves all progress")
		else: _check(int(world.state.turns.lift) % 2 == 0, "dry descent reaches low state")
	var world := World.new("3-3", _before("use:care"))
	var before: Dictionary = world.snapshot().duplicate(true)
	_inspect(world, "dew delivered but not given")
	_check(world.act("use:care").ok and world.flag("root") and str(world.state.items.dew.get("tile", "")).is_empty() and not world.state.items.dew.has("holder"), "actual care consumes carried dew and stabilizes root")
	_inspect(world, "stable root")
	_inspect(World.new("3-3", world.snapshot()), "stable reload")
	_check(world.undo() and world.snapshot() == before, "undo restores dew ownership and original stability")
	_inspect(world, "care undone")
	var route_ids := ["f:4:2", "f:3:2", "f:2:2", "f:1:2", "f:0:2"]
	var route_reference: Array = []
	for direction: int in [0, 1, 2, 3]:
		var state: Dictionary = fixture.steps[57].snapshot.duplicate(true)
		state.turns.water = direction
		var stable := World.new("3-3", state)
		var route: Array = stable.tiles().filter(func(tile: Dictionary) -> bool: return str(tile.id) in route_ids)
		if direction == 0: route_reference = route.duplicate(true)
		_check(route.size() == 5 and Snapshot.equivalent(route, route_reference), "all water directions preserve the same five final gap tiles " + str(direction))
		var landing: Dictionary = stable.point_for("f:0:3")
		_check(not landing.is_empty() and landing.h == 2 and str(landing.get("kind", "")) not in ["root", "shadow"], "permanent south landing remains a fixed bank " + str(direction))
		_check(stable.ready() and stable.act("repair").ok and stable.state.completed, "stabilized high route permits repair at every water direction " + str(direction))
		for blocker: String in ["unstable", "low"]:
			var blocked_state := state.duplicate(true)
			if blocker == "unstable": blocked_state.flags.erase("root")
			else: blocked_state.turns.lift = 0
			var blocked := World.new("3-3", blocked_state)
			var unchanged: Dictionary = blocked.snapshot()
			_check(not blocked.ready() and not blocked.act("repair").ok and blocked.snapshot() == unchanged, blocker + " route still rejects repair without mutation " + str(direction))
			_check(blocked.tiles().filter(func(tile: Dictionary) -> bool: return str(tile.id) in route_ids).is_empty(), blocker + " route exposes no final gap tiles " + str(direction))

func _float_motion() -> void:
	var before := _before("valve:lift")
	var world := World.new("3-3", before)
	_check(world.act("valve:lift").ok, "actual lift command supplies float transition")
	var after: Dictionary = world.snapshot()
	stage.set_world(World.new("3-3", before))
	var low: Vector3 = _mark("lift").get_node("LiftFloat").position
	var low_floor: float = stage._surfaces["m:lift:0:0"].position.y
	stage.set_world(World.new("3-3", after))
	var high: Vector3 = _mark("lift").get_node("LiftFloat").position
	var high_floor: float = stage._surfaces["m:lift:0:0"].position.y
	_check(high.y > low.y + .15 and high_floor > low_floor, "float actually rises with elevated platform")
	stage.set_world(World.new("3-3", before))
	for phase: float in [0.0, .25, .5, .75, 1.0]:
		stage.set_motion(before, after, phase, "valve:lift")
		var pointer: MeshInstance3D = _mark("lift").get_node("LiftFloat")
		var floor_y: float = stage._surfaces["m:lift:0:0"].position.y
		var amount := (floor_y - low_floor) / (high_floor - low_floor)
		_check(pointer.position.distance_to(low.lerp(high, amount)) < .001, "float follows physical platform fraction " + str(phase))
	stage.set_motion(after, before, .5, "undo")
	var middle: Vector3 = _mark("lift").get_node("LiftFloat").position
	_check(middle.y > low.y and middle.y < high.y, "reverse motion keeps float between real endpoint heights")
	stage.clear_motion(false)
	_check(world.snapshot() == after, "float animation never modifies committed puzzle data")

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	await process_frame
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in reference.cases:
		if str(entry.name) == "authored/3-3": fixture = entry
	_check(not fixture.is_empty(), "original 3-3 fixture exists")
	if fixture.is_empty(): quit(1); return
	_assets()
	_inspect(World.new("3-3"), "cold")
	_original_route()
	_boundaries()
	_float_motion()
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-symbiosis-presentation","passed":failures.is_empty(),"checks":checks,"failures":failures,"measurements":measurements,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
