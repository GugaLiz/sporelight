extends SceneTree

const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Dressing = preload("res://presentation/native/original_garden_dressing.gd")
## Independently extracted from the deployed TypeScript gardenScenery output.
const COUNTS := {"1-1": 6, "1-2": 3, "1-3": 14, "1-4": 19, "2-1": 12, "2-2": 7, "2-3": 4, "2-4": 3, "3-1": 11, "3-2": 5, "3-3": 12, "3-4": 8}
var failures: Array[String] = []
var checks := 0
var rows: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	for id: String in COUNTS:
		_check(Dressing.SOURCE_PROPS[id].size() == COUNTS[id], id + " original source inventory count")
		var world := World.new(id)
		var initial_state: Dictionary = world.snapshot().duplicate(true)
		stage.set_world(world)
		await process_frame
		_check(world.snapshot() == initial_state, id + " construction preserves rule and save state")
		_verify(stage, world, "initial")
		var instances := _instances(stage)
		for unused in range(3):
			stage.refresh_world(world)
			await process_frame
		_check(_instances(stage) == instances, id + " unchanged frames retain existing scenery nodes")
		if id == "2-4":
			world.state.flags.append("pollinated")
			_refresh_and_verify(stage, world, "pollinated")
			world.state.flags.erase("pollinated")
			_refresh_and_verify(stage, world, "pollination undone")
		if id == "2-1":
			for water in [1, 2, 0]:
				world.state.water = water
				_refresh_and_verify(stage, world, "water " + str(water))
		if id == "3-1":
			world.state.flags.append("window")
			_refresh_and_verify(stage, world, "window open")
			world.state.flags.erase("window")
			_refresh_and_verify(stage, world, "window undone")
		if id == "1-3":
			for turn in [1, 2, 3, 0]:
				world.state.turns.garden = turn
				_refresh_and_verify(stage, world, "turn " + str(turn))
	_test_pond_bank_transition(stage)
	var report := {"checks": checks, "failures": failures, "scope": "Headless source-instance, real-support, state-visibility and cache checks; no GPU acceptance", "rows": rows}
	var file := FileAccess.open("res://../docs/qa-godot-native/original-elements-audit/native-dressing-headless.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  ") + "\n")
	print(JSON.stringify({"checks": checks, "failures": failures.size(), "states": rows.size()}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _instances(stage: Node) -> Array:
	var result: Array = []
	for child in stage._props.get_children():
		if child.has_meta("original_scenery_index") or child.has_meta("original_wall_support"): result.append(child.get_instance_id())
	return result

func _test_pond_bank_transition(stage: Node) -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var authored_low: Dictionary = {}
	for entry: Dictionary in fixture.cases:
		if str(entry.name) != "authored/2-1": continue
		var previous: Dictionary = entry.initial.snapshot
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "act" and str(step.command.value) == "valve:water":
				authored_low = previous
				break
			previous = step.snapshot
	_check(not authored_low.is_empty(), "2-1 legal low-water fixture exists before real valve action")
	var low_world := World.new("2-1", authored_low)
	var low: Dictionary = low_world.snapshot().duplicate(true)
	_check(low_world.act("valve:water", true).ok, "2-1 real valve action prepares middle water")
	var middle: Dictionary = low_world.snapshot().duplicate(true)
	_check(int(middle.water) == 1, "2-1 transition starts at middle water")
	stage.set_world(World.new("2-1", middle))
	_check(not stage._surfaces.has("f:-4:4"), "2-1 middle water has no fern-bank physical surface")
	for progress: float in [0.0, 0.25, 0.5, 0.75, 0.999]:
		stage.set_motion(middle, low, progress, "undo")
		_check(stage._tile_map.has("f:-4:4"), "2-1 low preview already names the future fern support")
		_check(not stage._surfaces.has("f:-4:4"), "2-1 returning bank stays absent until geometry settles")
		_check(_original_at(stage, 7) == null, "2-1 fern is not instantiated on future logical-only support")
		var deferred: Array = stage._props.get_meta("original_deferred_scenery", [])
		_check(deferred.any(func(item: Dictionary) -> bool: return int(item.index) == 7 and str(item.support) == "f:-4:4"), "2-1 fern explicitly waits for its real surface")
	stage.set_motion(middle, low, 1.0, "undo")
	_check(stage._surfaces.has("f:-4:4"), "2-1 low endpoint restores bank geometry")
	var fern := _original_at(stage, 7)
	_check(fern != null, "2-1 low endpoint restores original fern without missing-support ERROR")
	if fern != null:
		_check(str(fern.get_meta("original_scenery_alias")) == "fern", "2-1 restored instance keeps fern identity")
		_check(absf(fern.position.y - stage.support_height(fern.position, "f:-4:4")) < .02, "2-1 restored fern is planted on the returning bank")
	stage.clear_motion(false)
	_check(_original_at(stage, 7) != null, "2-1 clear motion retains settled fern")
	stage.set_world(World.new("2-1", middle))
	stage.set_motion(middle, low, .5, "undo")
	_check(_original_at(stage, 7) == null, "2-1 interrupted mid-to-low also defers fern")
	stage.clear_motion(false)
	_check(stage._surfaces.has("f:-4:4") and _original_at(stage, 7) != null, "2-1 clearing transition rebuilds settled geometry and fern together")
	rows.append({"level": "2-1", "phase": "middle-to-low geometry boundary", "samples": 6, "fernIndex": 7, "logicalSupport": "f:-4:4", "deferredUntilSettled": true})

func _original_at(stage: Node, index: int) -> Sprite3D:
	for child in stage._props.get_children():
		if child is Sprite3D and int(child.get_meta("original_scenery_index", -1)) == index: return child
	return null

func _refresh_and_verify(stage: Node, world: RefCounted, phase: String) -> void:
	var before: Dictionary = world.snapshot().duplicate(true)
	stage.refresh_world(world)
	_check(world.snapshot() == before, str(world.level.id) + "/" + phase + " refresh preserves rule and save state")
	_verify(stage, world, phase)

func _verify(stage: Node, world: RefCounted, phase: String) -> void:
	var before: Dictionary = world.snapshot().duplicate(true)
	var id := str(world.level.id)
	var count := 0
	var visible := 0
	var vines := 0
	var migrations: Array = []
	for child in stage._props.get_children():
		if child.has_meta("original_scenery_index"):
			var index := int(child.get_meta("original_scenery_index"))
			var alias := str(child.get_meta("original_scenery_alias"))
			var support := str(child.get_meta("original_scenery_support"))
			var width: float = child.pixel_size * child.texture.get_width()
			_check(Dressing.flat_footprint(stage, child.position, support, Dressing.foot_radius(alias, width)), id + "/" + phase + " flat painted foot/" + str(index))
			_check(absf(child.position.y - stage.support_height(child.position, support)) < 0.02, id + "/" + phase + " grounded foot/" + str(index))
			var dimensions: Array = Dressing.SOURCE_FEET[alias]
			_check(child.texture.get_width() == dimensions[0] and child.texture.get_height() == dimensions[1], id + " complete original PNG is not cropped/" + alias)
			_check(child.get_children().is_empty(), id + " scenery creates no hidden support or collision")
			if index < 0: continue # Preserved, explicitly labelled 1-2 additions.
			count += 1
			visible += int(child.visible)
			var entry: Array = Dressing.SOURCE_PROPS[id][index]
			_check(alias == str(entry[0]), id + " original asset identity/" + str(index))
			_check(is_equal_approx(width, Dressing.canvas_width(float(entry[4]))), id + " original 70 px tile width ratio/" + str(index))
			_check(child.visible == world.visible(stage._tile_map[support], stage._tiles), id + " scenery inherits real support visibility/" + str(index))
			var reason := str(child.get_meta("original_scenery_migration"))
			if reason != "original logical position": migrations.append({"index": index, "asset": alias, "support": support, "position": [child.position.x, child.position.y, child.position.z], "reason": reason})
		if child.has_meta("original_wall_support"):
			vines += 1
			var height: float = child.texture.get_height() * child.pixel_size * child.scale.y
			_check(child.position.y - height >= float(child.get_meta("original_wall_bottom")) - 0.02, id + " vine stays within foundation wall")
			_check(child.billboard == BaseMaterial3D.BILLBOARD_DISABLED, id + " wall vine follows wall plane")
	var deferred: Array = stage._props.get_meta("original_deferred_scenery", []) if id != "1-1" else []
	if id != "1-1": _check(count + deferred.size() == COUNTS[id], id + "/" + phase + " every original instance is placed or waits for its real island")
	for item: Dictionary in deferred:
		_check(not stage._tile_map.has(str(item.support)) or not stage._surfaces.has(str(item.support)), id + " deferred art has no existing logical and physical support pair")
	if id == "2-4": _check(count == (3 if world.flag("pollinated") else 1), "2-4 far-bank art follows pollination and undo")
	_check(world.snapshot() == before, id + "/" + phase + " presentation leaves rule and save state unchanged")
	rows.append({"level": id, "phase": phase, "sourceCount": COUNTS[id], "placed": count, "visible": visible, "vines": vines, "migrations": migrations, "deferred": deferred})
