extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Effects = preload("res://presentation/native/native_garden_effects.gd")
const World = preload("res://core/garden_world.gd")
const Factory = preload("res://core/world_factory.gd")
var checks := 0
var failures: Array[String] = []

class CountedWorld:
	extends World
	static var calls := 0
	func _init(id: String = "1-1", saved: Dictionary = {}) -> void: super(id, saved)
	func tiles() -> Array:
		calls += 1
		return super.tiles()

func _initialize() -> void: call_deferred("_run")
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func _second_garden_runoff(stage: Node) -> void:
	var world := CountedWorld.new("1-2")
	var saved: Dictionary = world.snapshot().duplicate(true)
	stage.set_world(world)
	var fx: Node3D = stage._garden_effects
	_check(not fx.runoff.is_empty() and str(fx.runoff.id) == "f:0:2", "second garden uses the visible entrance bank after removing redundant fixed corner tiles")
	if fx.runoff.is_empty(): return
	var source: Dictionary = stage._tile_map["f:0:2"]
	var centre: Vector3 = stage.tile_position(source)
	var lip: Vector3 = fx.runoff.lip
	_check(absf(lip.x - centre.x + 0.12) < 0.001 and absf(lip.z - centre.z - 0.505) < 0.001 and absf(lip.y - stage.support_height(lip, "f:0:2") - 0.022) < 0.001, "second waterfall follows the physically mapped bank and its real surface height")
	_check(is_zero_approx(float(source.h)) and is_equal_approx(fx.runoff.curtain.scale.y, 1.82), "authored zero-height airborne bank keeps its real falling-water drop")
	var channel: MeshInstance3D = fx.runoff.channel
	_check(lip.z + channel.position.z - channel.scale.z * 0.5 > centre.z + 0.28, "short rim channel stays outside central walking area")
	_check(lip.x + channel.scale.x * 0.5 < centre.x + 0.5, "watercourse stays west of the neighboring eastern root footprint")
	_check(fx.runoff.node.visible and not is_instance_valid(fx.water) and float(fx.runoff.mist.material_override.get_shader_parameter("ring_strength")) == 0.0, "second waterfall is visible and dissolves without a floating pond ring")
	_check(fx.runoff.node.find_children("*", "CollisionObject3D", true, false).is_empty(), "second waterfall never creates collision or a bypass")
	var mesh: RID = fx.runoff.curtain.mesh.get_rid()
	var material: RID = fx.runoff.material.get_rid()
	var builds: int = fx.rebuilds
	CountedWorld.calls = 0
	for frame in range(10): stage.visual_time += 33; fx.update()
	_check(CountedWorld.calls == 0 and fx.rebuilds == builds and fx.runoff.curtain.mesh.get_rid() == mesh and fx.runoff.material.get_rid() == material, "second waterfall animates without topology queries or material rebuilds")
	stage.set_paused(true)
	var frozen: float = fx.runoff.material.get_shader_parameter("effect_time")
	stage._process(0.2)
	_check(float(fx.runoff.material.get_shader_parameter("effect_time")) == frozen, "second waterfall freezes on pause")
	stage.set_paused(false)
	_check(world.snapshot() == saved, "second waterfall leaves puzzle and saved state unchanged")
	# The exception applies to this unmarked fixed rim only. A later mechanism,
	# pickup, root socket, moving module, or occupied edge must veto it.
	for blocker: String in ["core", "observe", "collectible", "root", "module", "south-neighbor", "small", "solid", "moving", "removed"]:
		var level: Dictionary = world.level.duplicate(true)
		var candidate: Dictionary = source.duplicate(true)
		var tiles: Array = [candidate]
		match blocker:
			"core", "observe": level.marks.append({"id": "probe", "tile": "f:0:2", "kind": blocker})
			"collectible": level.collectibles.append({"id": "probe", "tile": "f:0:2"})
			"root": level.roots.append({"at": "f:0:0", "sockets": [[0, 2]]})
			"module": level.modules.append({"id": "probe"})
			"south-neighbor": tiles.append({"id": "probe", "x": 0, "z": 3, "h": 0, "small": true})
			"small": candidate.small = true
			"solid": candidate.solid = true
			"moving": candidate.module = "probe"
			"removed": tiles.clear()
		_check(Effects.runoff_source(level, tiles).is_empty(), "second waterfall rejects mechanism or invalid bank/" + blocker)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	_second_garden_runoff(stage)
	var world := CountedWorld.new()
	stage.set_world(world)
	var fx: Node3D = stage._garden_effects
	var entry: Dictionary = fx.collectibles["spore-0"]
	var sprite: Sprite3D = entry.sprite
	var first := sprite.position.y
	var builds: int = fx.rebuilds
	var mesh: RID = entry.halo.mesh.get_rid()
	var material: RID = entry.halo.material_override.get_rid()
	CountedWorld.calls = 0
	for frame in range(50):
		stage.visual_time = frame * 20.0
		fx.update()
	_check(CountedWorld.calls == 0, "warm effects never query whole board")
	_check(fx.rebuilds == builds and entry.halo.mesh.get_rid() == mesh and entry.halo.material_override.get_rid() == material, "animation reuses geometry and materials")
	_check(not is_equal_approx(first, sprite.position.y), "uncollected original spore art visibly bobs")
	_check(not sprite.no_depth_test, "collectible retains real scene occlusion")
	_check(entry.node.global_position.distance_to(entry.surface.to_global(entry.anchor) + entry.offset) < 0.0001, "collectible and ring share actual support anchor")
	stage.set_paused(true)
	var frozen := sprite.position
	var frozen_time: float = stage.visual_time
	stage._process(0.1)
	_check(sprite.position == frozen and stage.visual_time == frozen_time, "pause freezes clocks and collectible position")
	stage.set_paused(false)
	stage.set_settings({"lowMotion": true, "particles": true, "dynamicLight": false})
	fx.update()
	var quiet := sprite.position
	stage.visual_time += 500
	fx.update()
	_check(sprite.position == quiet and not entry.halo.visible and not entry.aura.visible, "reduced motion freezes bob and light setting hides halos")
	_check(not entry.sparks[0].visible, "reduced motion suppresses orbiting sparkles")
	stage.set_settings({"lowMotion": false, "particles": true, "dynamicLight": true})
	var before: Dictionary = world.snapshot()
	world.state.collected.append("spore-0")
	stage.refresh_world(world)
	_check(not fx.collectibles.has("spore-0") and fx.bursts.size() == 1, "pickup removes collectible and creates finite feedback")
	var restored := CountedWorld.new("1-1", before)
	stage.set_world(restored)
	_check(fx.collectibles.has("spore-0") and fx.bursts.is_empty(), "undo restores collectible and clears stale pickup feedback")
	var mover := World.new("1-3")
	mover.level = mover.level.duplicate(true)
	mover.level.collectibles.append({"id": "moving-probe", "tile": "m:garden:-2:0"})
	stage.set_world(mover)
	var move_entry: Dictionary = fx.collectibles["moving-probe"]
	move_entry.surface.position += Vector3(0.3, 0.4, -0.2)
	move_entry.surface.rotation.y = 0.75
	fx.update()
	_check(move_entry.node.global_position.distance_to(move_entry.surface.to_global(move_entry.anchor)) < 0.0001, "moving support transforms carry the complete effect without world-coordinate drift")
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	for level: Dictionary in levels:
		var model: RefCounted = Factory.create(str(level.id))
		stage.set_world(model)
		var saved: Dictionary = model.snapshot()
		var tiles: Array = model.tiles()
		var wanted := 0
		for item: Dictionary in model.level.get("collectibles", []):
			var tile: Dictionary = stage._tile_map.get(str(item.tile), {})
			if not str(item.id) in model.state.get("collected", []) and not tile.is_empty() and model.visible(tile, tiles): wanted += 1
		_check(fx.collectibles.size() == wanted, str(level.id) + " collectible visibility matches exact world state")
		_check(model.snapshot() == saved, str(level.id) + " effect construction preserves domain state")
		var atmosphere: Node3D = fx.atmosphere
		_check(atmosphere.ready_to_repair == model.ready(), str(level.id) + " core halo uses unchanged readiness rules")
		_check(atmosphere.rain.size() == (76 if str(level.get("chapter", "")) == "pond" else 0), str(level.id) + " rain belongs only to authored pond chapter")
		_check(atmosphere.butterflies.size() == (4 if level.has("sanctuary") else 0), str(level.id) + " butterflies stay in authored sanctuary")
		_check(atmosphere.gold.all(func(node: MeshInstance3D) -> bool: return not node.visible), str(level.id) + " no premature completion celebration")
		_check(fx.runoff.is_empty() or str(level.get("chapter", "")) != "cave", str(level.id) + " no invented cave runoff")
		if not fx.runoff.is_empty():
			var source: Dictionary = stage._tile_map[fx.runoff.id]
			var channel: MeshInstance3D = fx.runoff.channel
			var curtain: MeshInstance3D = fx.runoff.curtain
			# Independent visual contract: a bounded stream with a matching lip.
			_check(curtain.scale.x >= 0.28 and curtain.scale.x <= 0.40, str(level.id) + " falling stream has readable sub-tile width")
			_check(channel.scale.x >= curtain.scale.x * 0.6 and channel.scale.x <= curtain.scale.x, str(level.id) + " source channel feeds the central stream without a hairline neck")
			_check(absf(channel.position.z + channel.scale.z * 0.5) < 0.015, str(level.id) + " channel end meets the waterfall lip")
			_check(fx.runoff.node.find_children("*", "CollisionObject3D", true, false).is_empty(), str(level.id) + " scaled waterfall remains purely visual")
			_check(float(fx.runoff.mist.material_override.get_shader_parameter("ring_strength")) == (0.25 if is_instance_valid(fx.water) else 0.0), str(level.id) + " runoff fades to haze without water and uses a shallow ring only on an actual receiver")
			_check(not source.has("module") and not bool(source.get("small", false)), str(level.id) + " runoff belongs to fixed solid bank")
			_check(not tiles.any(func(t: Dictionary) -> bool: return float(t.x) == float(source.x) and float(t.z) == float(source.z) + 1.0), str(level.id) + " runoff uses exposed south edge only")
	var pond := World.new("2-1")
	stage.set_world(pond)
	var pond_fx: Node3D = fx.atmosphere
	_check(not pond_fx.impacts.is_empty(), "real pond owns rain landing rings")
	for drop: MeshInstance3D in pond_fx.rain:
		_check(drop.basis.x.normalized().dot(stage._camera.global_basis.x) > 0.9999 and drop.basis.y.normalized().dot(stage._camera.global_basis.y) > 0.9999, "anisotropic rain remains in camera plane without world-axis skew")
	for impact: Dictionary in pond_fx.impacts:
		var local: Vector3 = impact.at - fx.water.position
		var water_size: Vector2 = fx.water.mesh.size
		_check(absf(local.x) / water_size.x <= 0.30 and absf(local.z) / water_size.y <= 0.30, "rain impact stays inside fully visible water region rather than feathered sky edge")
	var rain_mesh: RID = pond_fx.rain[0].mesh.get_rid()
	var rain_material: RID = pond_fx.rain[0].material_override.get_rid()
	var rain_start: Vector3 = pond_fx.rain[0].position
	stage.visual_time += 250
	fx.update()
	_check(pond_fx.rain[0].position != rain_start, "rain moves with supplied visual clock")
	_check(pond_fx.rain[0].mesh.get_rid() == rain_mesh and pond_fx.rain[0].material_override.get_rid() == rain_material, "rain reuses mesh and material")
	_check((pond_fx.rain[0].position - pond_fx.rain[1].position).dot(stage._camera.global_basis.z) > 15, "foreground and background rain use distinct true depth layers")
	stage.set_paused(true)
	rain_start = pond_fx.rain[0].position
	stage._process(0.2)
	_check(pond_fx.rain[0].position == rain_start, "paused weather stops at same rain point")
	stage.set_paused(false)
	stage.set_settings({"lowMotion": true, "particles": true, "dynamicLight": true})
	_check(pond_fx.rain.all(func(node: MeshInstance3D) -> bool: return not node.visible) and pond_fx.impacts.all(func(entry: Dictionary) -> bool: return not entry.drop.visible and not entry.ring.visible), "reduced motion hides falling rain and impact animation")
	stage.set_settings({"lowMotion": false, "particles": false, "dynamicLight": true})
	_check(pond_fx.rain.all(func(node: MeshInstance3D) -> bool: return not node.visible), "particle setting hides both rain layers")
	stage.set_settings({"lowMotion": false, "particles": true, "dynamicLight": true})
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for case: Dictionary in reference.cases:
		var states: Array = [case.initial.snapshot]
		for step: Dictionary in case.steps: states.append(step.snapshot)
		for saved: Dictionary in states:
			var model := CountedWorld.new(str(saved.levelId), saved)
			var board: Array = model.tiles()
			var expected_ready: bool = model.ready()
			CountedWorld.calls = 0
			_check(model.ready(board) == expected_ready and CountedWorld.calls == 0, str(case.name) + " scoped readiness preserves original condition without board rebuild")
	var start := {}
	var end := {}
	for case: Dictionary in reference.cases:
		if str(case.name) != "authored/2-1": continue
		var previous: Dictionary = case.initial.snapshot
		for step: Dictionary in case.steps:
			if int(previous.water) != int(step.snapshot.water):
				start = previous
				end = step.snapshot
				break
			previous = step.snapshot
	stage.set_motion(start, end, 0.25, "valve:water")
	fx.update()
	var water: MeshInstance3D = fx.water
	var expected := (-0.55 + lerpf(float(start.water), float(end.water), 0.15625) * 0.18) * 0.65
	_check(absf(water.position.y - expected) < 0.0001, "visible pond interpolates with real water-level transaction: actual=%s expected=%s before=%s after=%s progress=%s" % [water.position.y, expected, stage._motion_before.state.water, stage._motion_after.state.water, stage._motion_progress])
	if not fx.runoff.is_empty():
		_check(absf(fx.runoff.node.global_position.y + fx.runoff.mist.position.y - water.position.y - 0.018) < 0.001, "runoff receiver follows actual interpolated water surface")
	stage.clear_motion(false)
	stage.set_world(World.new("3-1"))
	_check(fx.runoff.is_empty(), "level replacement removes previous waterfall")
	_check(fx.atmosphere.rain.is_empty() and fx.atmosphere.impacts.is_empty(), "level replacement removes pond weather and impacts")
	var sanctuary := CountedWorld.new("1-4")
	stage.set_world(sanctuary)
	var garden: Node3D = fx.atmosphere
	_check(garden.jets.size() == 36 and garden.fountain_drops.size() == 7 and garden.fountain_rings.size() == 3 and garden.butterflies.size() == 4, "sanctuary restores both jets, seven drops, basin rings and four butterflies")
	var before_children: int = garden.get_child_count()
	CountedWorld.calls = 0
	for frame in range(20): stage.visual_time += 33; fx.update()
	_check(CountedWorld.calls == 0 and garden.get_child_count() == before_children, "warm sanctuary performs no board query or geometry construction")
	stage.set_settings({"lowMotion": true, "particles": true, "dynamicLight": true})
	var perched: Vector3 = garden.butterflies[0].node.position
	stage.visual_time += 500
	fx.update()
	_check(garden.butterflies[0].node.position == perched and garden.fountain_drops.all(func(node: MeshInstance3D) -> bool: return not node.visible), "reduced motion preserves still butterflies and freezes fountain drops")
	stage.set_settings({"lowMotion": false, "particles": false, "dynamicLight": true})
	_check(not garden.butterflies[0].node.visible and garden.jets[0].visible, "particle toggle hides butterflies while preserving structural fountain water")
	sanctuary.state.completed = true
	stage.refresh_world(sanctuary)
	stage.set_settings({"lowMotion": false, "particles": true, "dynamicLight": true})
	_check(garden.gold.size() == 16 and garden.gold.all(func(node: MeshInstance3D) -> bool: return node.visible), "completion enables exactly sixteen gold particles")
	_check(garden.cores.values().all(func(value: Dictionary) -> bool: return value.node.visible), "completed core retains repair glow")
	stage.set_settings({"lowMotion": false, "particles": true, "dynamicLight": false})
	_check(garden.cores.values().all(func(value: Dictionary) -> bool: return not value.node.visible), "dynamic light toggle hides core glow")
	print(JSON.stringify({"suite": "native-garden-effects", "passed": failures.is_empty(), "checks": checks, "failures": failures, "gpuPixelsVerified": false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
