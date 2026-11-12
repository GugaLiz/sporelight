extends Node3D
## Cached visual-only attachments. No collision, domain mutation or per-frame
## tile queries; clocks are supplied by the stage so pause freezes every effect.
const Halo = preload("res://presentation/native/garden_effect_halo.gdshader")
const Runoff = preload("res://presentation/native/garden_runoff.gdshader")
const Atmosphere = preload("res://presentation/native/native_garden_atmosphere.gd")
## A readable stream on a one-unit bank; feathering must not reduce it to a thread.
const RUNOFF_WIDTH := 0.32
const RUNOFF_CHANNEL_WIDTH := 0.22
var atmosphere: Node3D
var collectibles := {}
var bursts: Array[Dictionary] = []
var runoff := {}
var level_id := ""
var collected: Array = []
var stage: Node
var water: MeshInstance3D
var _quad: QuadMesh
var _plane: PlaneMesh
var rebuilds := 0
var _runoff_geometry_key := 0
var _runoff_source := {}

func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_plane = PlaneMesh.new()
	_plane.size = Vector2.ONE

func refresh(owner_stage: Node) -> void:
	stage = owner_stage
	if level_id != str(stage.world.level.id):
		for child in get_children(): remove_child(child); child.queue_free()
		collectibles.clear()
		bursts.clear()
		runoff.clear()
		_runoff_geometry_key = 0
		_runoff_source.clear()
		collected = stage.world.state.get("collected", []).duplicate()
		level_id = str(stage.world.level.id)
	var now: Array = stage.world.state.get("collected", [])
	for id: String in collectibles.keys():
		if id in now:
			if id not in collected: _burst(id, collectibles[id].node.global_position)
			_remove_collectible(id)
	for index in range(bursts.size() - 1, -1, -1):
		if str(bursts[index].id) not in now:
			_free_node(bursts[index].node)
			bursts.remove_at(index)
	var live := {}
	for item: Dictionary in stage.world.level.get("collectibles", []):
		var id := str(item.id)
		if id in now: continue
		var tile: Dictionary = stage._tile_map.get(str(item.tile), {})
		if tile.is_empty() or not stage.world.visible(tile, stage._tiles): continue
		live[id] = true
		var surface: Node3D = stage._surface_for_support(str(item.tile))
		if surface == null: continue
		if not collectibles.has(id): collectibles[id] = _collectible(id)
		var entry: Dictionary = collectibles[id]
		entry.surface = surface
		entry.tile = str(item.tile)
		var anchor: Vector3 = surface.global_position
		anchor.y = surface.sample_height(anchor)
		entry.anchor = surface.to_local(anchor)
		# The old renderer offsets a collectible sharing the carried bell tile.
		var bell: Dictionary = stage.world.state.get("items", {}).get("bell", {})
		entry.offset = Vector3(-0.18, 0, 0.18) if str(bell.get("tile", "")) == str(item.tile) else Vector3.ZERO
		if level_id=="1-4":
			# Stable offsets inside the original collection cells. Rules and
			# bobbing stay unchanged; leave the operator and resident readable.
			entry.offset = {"spore-1":Vector3(.42,0,-.42),"spore-2":Vector3(-.42,0,.42),"spore-3":Vector3(.35,0,.30)}.get(id,entry.offset)
	for id: String in collectibles.keys():
		if not live.has(id): _remove_collectible(id)
	collected = now.duplicate()
	water = stage._effects.get_node_or_null("GardenWater")
	_refresh_runoff()
	if not is_instance_valid(atmosphere) or atmosphere.is_queued_for_deletion():
		atmosphere = Atmosphere.new()
		atmosphere.name = "GardenAtmosphere"
		add_child(atmosphere)
	atmosphere.refresh(self)
	update()

func _free_node(node: Node) -> void:
	if not is_instance_valid(node): return
	node.get_parent().remove_child(node)
	node.queue_free()

func _remove_collectible(id: String) -> void:
	_free_node(collectibles[id].node)
	collectibles.erase(id)

func _material(color: Color, star := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Halo
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("star", star)
	return material

func _card(parent: Node3D, mesh: Mesh, material: Material, span: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.scale = span
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _collectible(id: String) -> Dictionary:
	rebuilds += 1
	var root := Node3D.new()
	root.name = "Discovery_" + id
	add_child(root)
	var sprite: Sprite3D = stage._sprite(root, "spore", 35.0 * sqrt(2.0) / 70.0, Vector3(0, 0.42, 0))
	sprite.offset = Vector2.ZERO
	# Maintain the source sprite and actual scene depth; glow never overrides it.
	sprite.no_depth_test = false
	var halo := _card(root, _plane, _material(Color(1.0, 0.81, 0.30, 0.62)), Vector3(0.58, 1, 0.58))
	halo.position.y = 0.018
	var aura := _card(root, _quad, _material(Color(1, 0.87, 0.43, 0.35)), Vector3.ONE * 0.66)
	var sparks: Array[MeshInstance3D] = []
	var spark_material := _material(Color(1, 0.95, 0.69, 0.85), true)
	for index in range(4):
		sparks.append(_card(root, _quad, spark_material, Vector3.ONE * (0.075 if index % 2 else 0.11)))
	return {"node": root, "sprite": sprite, "halo": halo, "aura": aura, "sparks": sparks, "seed": float(abs(id.hash()) % 1000) / 159.0}

func _burst(id: String, at: Vector3) -> void:
	if not bool(stage.settings.get("particles", true)) or bool(stage.settings.get("lowMotion", false)): return
	var root := Node3D.new()
	root.name = "Pickup_" + id
	add_child(root)
	root.global_position = at
	var material := _material(Color(1, 0.91, 0.56, 0.9), true)
	var sparks: Array[MeshInstance3D] = []
	for index in range(7): sparks.append(_card(root, _quad, material, Vector3.ONE * 0.10))
	bursts.append({"id": id, "node": root, "sparks": sparks, "material": material, "started": stage.visual_time})

static func runoff_source(level: Dictionary, tiles: Array) -> Dictionary:
	if str(level.get("chapter", "")) in ["cave", "cloud"]: return {}
	var occupied := {}
	var marked := {}
	for tile: Dictionary in tiles: occupied[Vector2(float(tile.x), float(tile.z))] = true
	for mark: Dictionary in level.get("marks", []): marked[str(mark.tile)] = true
	var result := {}
	var minimum := 0.0 if str(level.get("chapter", "")) == "pond" else 1.0
	var second := str(level.get("id", "")) == "1-2"
	for tile: Dictionary in tiles:
		if second and not _second_garden_rim(level, tile): continue
		if tile.has("module") or bool(tile.get("small", false)) or bool(tile.get("solid", false)): continue
		# A grown or moving connector is not an authored fixed water source.
		if str(tile.get("kind", "")) in ["root", "bridge", "shadow", "lift", "gate"]: continue
		if float(tile.h) < (0.0 if second else minimum) or occupied.has(Vector2(float(tile.x), float(tile.z) + 1.0)): continue
		if marked.has(str(tile.id)): continue
		if result.is_empty() or float(tile.h) > float(result.h) or (float(tile.h) == float(result.h) and float(tile.x) > float(result.x)): result = tile
	return result

static func _second_garden_rim(level: Dictionary, tile: Dictionary) -> bool:
	# This authored zero-height tile is still an airborne island. Keep its
	# short watercourse on the unmarked south rim, visible near the entrance.
	if str(level.get("id", "")) != "1-2" or str(tile.get("id", "")) != "f:0:2": return false
	if str(tile.get("kind", "fixed")) != "fixed": return false
	if not level.get("modules", []).is_empty(): return false
	for mark: Dictionary in level.get("marks", []):
		if str(mark.tile) == str(tile.id): return false
	for item: Dictionary in level.get("collectibles", []):
		if str(item.tile) == str(tile.id): return false
	for root: Dictionary in level.get("roots", []):
		if str(root.get("at", "")) == str(tile.id): return false
		for socket: Array in root.get("sockets", []):
			# Test the actual channel footprint, not a one-tile radius: the
			# eastern root route is clear of this west-offset south-rim channel.
			var channel := Rect2(float(tile.x) - 0.12 - RUNOFF_CHANNEL_WIDTH * 0.5, float(tile.z) + 0.285, RUNOFF_CHANNEL_WIDTH, 0.22)
			if channel.intersects(Rect2(float(socket[0]) - 0.5, float(socket[1]) - 0.5, 1, 1)): return false
	return true

func _refresh_runoff() -> void:
	# Candidate selection is topology work, never an animation-frame query.
	if _runoff_geometry_key != int(stage._terrain_signature):
		_runoff_geometry_key = int(stage._terrain_signature)
		_runoff_source = runoff_source(stage.world.level, stage._tiles)
	var source: Dictionary = _runoff_source
	if not source.is_empty() and not stage.world.visible(source, stage._tiles): source = {}
	if source.is_empty():
		if not runoff.is_empty(): _free_node(runoff.node)
		runoff.clear()
		return
	var surface: Node3D = stage._surface_for_support(str(source.id))
	if surface == null: return
	if not runoff.is_empty() and str(runoff.id) != str(source.id):
		_free_node(runoff.node)
		runoff.clear()
	if runoff.is_empty():
		rebuilds += 1
		var root := Node3D.new()
		root.name = "AuthoredRunoff"
		add_child(root)
		var material := ShaderMaterial.new()
		material.shader = Runoff
		var curtain := _card(root, _quad, material, Vector3.ONE)
		var channel := _card(root, _plane, material, Vector3(RUNOFF_CHANNEL_WIDTH, 1, 0.7))
		var mist := _card(root, _plane, _material(Color(0.75, 0.93, 0.87, 0.44)), Vector3(0.65, 1, 0.65))
		var drops: Array[MeshInstance3D] = []
		var drops_material := _material(Color(0.84, 0.98, 0.94, 0.7), true)
		for index in range(5): drops.append(_card(root, _quad, drops_material, Vector3(0.045, 0.11, 0.045)))
		runoff = {"id": str(source.id), "node": root, "surface": surface, "curtain": curtain, "channel": channel, "mist": mist, "drops": drops, "material": material}
	runoff.surface = surface
	var second_rim := _second_garden_rim(stage.world.level, source)
	runoff.channel_length = 0.22 if second_rim else 0.7
	runoff.channel.scale.z = runoff.channel_length
	var lip: Vector3 = surface.to_global(Vector3(-0.12 if second_rim else 0.0, 0, 0.505))
	lip.y = surface.sample_height(lip) + 0.022
	runoff.lip = lip

func update() -> void:
	if stage == null or stage.world == null: return
	var low := bool(stage.settings.get("lowMotion", false))
	var particles := bool(stage.settings.get("particles", true))
	var light := bool(stage.settings.get("dynamicLight", true))
	var time := 0.0 if low else float(stage.visual_time) * 0.001
	for entry: Dictionary in collectibles.values():
		var surface: Node3D = entry.surface
		if not is_instance_valid(surface): entry.node.visible = false; continue
		entry.node.visible = surface.visible
		entry.node.global_position = surface.to_global(entry.anchor) + entry.offset
		var phase: float = time * 3.0 + float(entry.seed)
		entry.sprite.position.y = 0.42 + (sin(phase) * 0.045 if not low else 0.0)
		entry.halo.visible = light
		entry.aura.visible = light
		entry.halo.material_override.set_shader_parameter("phase", phase)
		entry.aura.position = entry.sprite.position
		entry.aura.basis = stage._camera.global_basis.scaled_local(Vector3.ONE * 0.66)
		entry.aura.material_override.set_shader_parameter("phase", phase)
		for index in range(entry.sparks.size()):
			var spark: MeshInstance3D = entry.sparks[index]
			spark.visible = particles and not low
			var angle := phase * 0.5 + index * TAU / 4.0
			spark.position = Vector3(cos(angle) * 0.26, 0.40 + sin(angle * 1.5) * 0.15, sin(angle) * 0.20)
			spark.basis = stage._camera.global_basis.scaled_local(Vector3.ONE * (0.075 if index % 2 else 0.11))
	for index in range(bursts.size() - 1, -1, -1):
		var burst: Dictionary = bursts[index]
		var progress := clampf((float(stage.visual_time) - float(burst.started)) / 620.0, 0, 1)
		if progress >= 1 or not particles or low:
			_free_node(burst.node)
			bursts.remove_at(index)
			continue
		burst.material.set_shader_parameter("strength", 1.0 - progress)
		for particle in range(burst.sparks.size()):
			var spark: MeshInstance3D = burst.sparks[particle]
			var angle := particle * TAU / 7.0
			spark.position = Vector3(cos(angle), 0, sin(angle)) * (0.10 + progress * 0.48) + Vector3.UP * (0.32 + progress * 0.48)
			spark.basis = stage._camera.global_basis.scaled_local(Vector3.ONE * 0.10)
	_update_water(time, particles, low)
	if is_instance_valid(atmosphere): atmosphere.update(time, particles, low, light)

func _update_water(time: float, particles: bool, low: bool) -> void:
	if is_instance_valid(water):
		var water_level: float = float(stage.world.state.get("water", 0))
		if stage._motion_before != null:
			var progress: float = stage._motion_progress
			var eased := progress * progress * (3.0 - 2.0 * progress)
			water_level = lerpf(float(stage._motion_before.state.get("water", 0)), float(stage._motion_after.state.get("water", 0)), eased)
		# Original shallows stay below fixed banks; the hydraulic deck, rather
		# than the whole lake, follows the full lift height.
		water.position.y = (-0.55 + water_level * 0.18 if str(stage.world.level.id) == "2-1" else -0.5) * 0.65
		water.material_override.set_shader_parameter("effect_time", time)
	if runoff.is_empty(): return
	var lip: Vector3 = runoff.lip
	var bottom := water.position.y + 0.014 if is_instance_valid(water) else lip.y - 2.8 * 0.65
	var height := lip.y - bottom
	runoff.node.visible = height > 0.08 and is_instance_valid(runoff.surface) and runoff.surface.visible
	if not runoff.node.visible: return
	runoff.node.global_position = lip
	runoff.curtain.position = Vector3(0, -height * 0.5, 0.012)
	runoff.curtain.scale = Vector3(RUNOFF_WIDTH, height, 1)
	runoff.channel.position = Vector3(0, 0.002, -0.11 if float(runoff.channel_length) < 0.7 else -0.34)
	runoff.material.set_shader_parameter("effect_time", time)
	runoff.mist.position = Vector3(0, -height + 0.004, 0.03)
	runoff.mist.visible = particles
	runoff.mist.material_override.set_shader_parameter("phase", time * 2.0)
	# Without an actual receiver, falling water dissolves into haze: a ring
	# would falsely imply a solid pond floating below the garden.
	var has_receiver := is_instance_valid(water)
	runoff.mist.material_override.set_shader_parameter("ring_strength", 0.25 if has_receiver else 0.0)
	runoff.mist.material_override.set_shader_parameter("glow_strength", 0.7 if has_receiver else 1.6)
	runoff.mist.scale = Vector3(0.65, 1, 0.65) if has_receiver else Vector3(0.85, 1, 0.85)
	for index in range(runoff.drops.size()):
		var drop: MeshInstance3D = runoff.drops[index]
		drop.visible = particles and not low
		var progress := fposmod(time * 0.8 + index * 0.2, 1.0)
		drop.position = Vector3(sin(index * 2.1) * RUNOFF_CHANNEL_WIDTH * 0.40, -height * progress, 0.024)
		drop.basis = stage._camera.global_basis.scaled_local(Vector3(0.045, 0.11, 0.045))
