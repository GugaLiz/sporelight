extends Node3D
## Persistent visual-only weather, sanctuary and state feedback. Geometry and
## anchor lookup are refreshed only with world state; warm updates use caches.
const Butterfly = preload("res://presentation/native/garden_butterfly.gdshader")
const Sanctuary = preload("res://presentation/native/original_sanctuary_dressing.gd")
const FountainEffect = preload("res://presentation/native/original_fountain_effect.gdshader")
var fx: Node3D
var stage: Node
var rain: Array[MeshInstance3D] = []
var gold: Array[MeshInstance3D] = []
var ripples := {}
var cores := {}
var jets: Array[MeshInstance3D] = []
var fountain_drops: Array[MeshInstance3D] = []
var fountain_rings: Array[MeshInstance3D] = []
var butterflies: Array[Dictionary] = []
var flower_anchors: Array[Vector3] = []
var fountain_at := Vector3.ZERO
var fountain_ratio := 1.0
var level_id := ""
var completed := false
var ready_to_repair := false
var impacts: Array[Dictionary] = []
var _impact_key := 0

func refresh(controller: Node3D) -> void:
	fx = controller
	stage = fx.stage
	if level_id != str(stage.world.level.id):
		for child in get_children(): remove_child(child); child.queue_free()
		rain.clear(); gold.clear(); ripples.clear(); cores.clear()
		jets.clear(); fountain_drops.clear(); fountain_rings.clear(); butterflies.clear(); flower_anchors.clear()
		impacts.clear(); _impact_key = 0
		level_id = str(stage.world.level.id)
		_build_weather()
		_build_sanctuary()
	var fountain: Node3D = stage._props.get_node_or_null("SanctuaryFountain")
	if fountain != null:
		fountain_at = fountain.position
		fountain_ratio = float(fountain.get_meta("original_fountain_ratio",1.0))
	completed = bool(stage.world.state.get("completed", false))
	ready_to_repair = stage.world.ready(stage._tiles)
	var live := {}
	if str(stage.world.level.get("chapter", "")) == "pond":
		for tile: Dictionary in stage._tiles:
			if not stage.world.visible(tile, stage._tiles): continue
			if str(tile.get("kind", "")) != "water" and absi(int(tile.x) * 17 + int(tile.z) * 29) % 4 != 0: continue
			var id := str(tile.id)
			var surface: Node3D = stage._surface_for_support(id)
			if surface == null: continue
			live[id] = true
			if not ripples.has(id):
				var node: MeshInstance3D = fx._card(self, fx._plane, fx._material(Color(0.74, 0.94, 0.87, 0.30)), Vector3(0.40, 1, 0.40))
				ripples[id] = {"node": node, "surface": surface, "seed": float(abs(id.hash()) % 100) * 0.1}
			ripples[id].surface = surface
	for id: String in ripples.keys():
		if not live.has(id): fx._free_node(ripples[id].node); ripples.erase(id)
	for mark: Dictionary in stage.world.level.get("marks", []):
		if str(mark.kind) != "core": continue
		var id := str(mark.tile)
		var surface: Node3D = stage._surface_for_support(id)
		if surface == null: continue
		if not cores.has(id): cores[id] = {"node": fx._card(self, fx._plane, fx._material(Color(1, 0.87, 0.42, 0.65)), Vector3(1.05, 1, 1.05)), "surface": surface}
		cores[id].surface = surface
	_refresh_impacts()

func _refresh_impacts() -> void:
	var key := hash([stage._terrain_signature, is_instance_valid(fx.water)])
	if key == _impact_key: return
	_impact_key = key
	for entry: Dictionary in impacts:
		fx._free_node(entry.drop); fx._free_node(entry.ring)
	impacts.clear()
	if not is_instance_valid(fx.water): return
	var size: Vector2 = fx.water.mesh.size
	var origin: Vector3 = fx.water.position
	for index in range(23):
		# Keep the complete splash inside the opaque part of the feathered
		# water footprint. Edge rings otherwise read as floating in the sky.
		var at := origin + Vector3((fposmod(index * 0.75487766 + 0.21, 1) - 0.5) * size.x * 0.60, 0, (fposmod(index * 0.56984029 + 0.37, 1) - 0.5) * size.y * 0.60)
		var nearest_bank := INF
		for tile: Dictionary in stage._tiles:
			nearest_bank = minf(nearest_bank, absf(float(tile.x) - at.x) + absf(float(tile.z) - at.z))
		if nearest_bank < 1.3 or nearest_bank > 2.8: continue
		impacts.append({"at": at, "index": index, "drop": fx._card(self, fx._quad, fx._material(Color(0.90, 0.99, 0.94, 0.70), true), Vector3.ONE), "ring": fx._card(self, fx._plane, fx._material(Color(0.84, 0.98, 0.91, 0.60)), Vector3.ONE)})
		impacts.back().ring.material_override.set_shader_parameter("ring_strength", 0.35)
		impacts.back().ring.material_override.set_shader_parameter("glow_strength", 0.25)

func _build_weather() -> void:
	var gold_material: ShaderMaterial = fx._material(Color(1, 0.91, 0.60, 0.6), true)
	for index in range(16): gold.append(fx._card(self, fx._quad, gold_material, Vector3.ONE * 0.045))
	if str(stage.world.level.get("chapter", "")) != "pond": return
	var near_material: ShaderMaterial = fx._material(Color(0.88, 0.98, 0.92, 0.64), true)
	var far_material: ShaderMaterial = fx._material(Color(0.76, 0.91, 0.92, 0.32), true)
	for index in range(76):
		var drop: MeshInstance3D = fx._card(self, fx._quad, near_material if index % 5 == 0 else far_material, Vector3.ONE)
		drop.name = ("ForegroundRain_" if index % 5 == 0 else "BackgroundRain_") + str(index)
		rain.append(drop)

func _build_sanctuary() -> void:
	var sanctuary: Dictionary = stage.world.level.get("sanctuary", {})
	if sanctuary.is_empty() or sanctuary.get("fountain", {}).is_empty(): return
	var body: Node3D = stage._props.get_node_or_null("SanctuaryFountain")
	if body == null: return
	fountain_at = body.position
	fountain_ratio = float(body.get_meta("original_fountain_ratio",1.0))
	var stream_material := ShaderMaterial.new()
	stream_material.shader = FountainEffect
	# Two parabolic jets made once. Unlike particles, the water supply remains
	# readable when particle animation is disabled.
	for side: int in [-1, 1]:
		for index in range(18):
			var jet: MeshInstance3D = fx._card(self, fx._quad, stream_material, Vector3.ONE * 0.035)
			jet.set_meta("original_jet_side", side)
			jet.set_meta("original_jet_segment", index)
			jets.append(jet)
	var drop_material := ShaderMaterial.new()
	drop_material.shader = FountainEffect
	drop_material.set_shader_parameter("kind", 2)
	for index in range(7): fountain_drops.append(fx._card(self, fx._quad, drop_material, Vector3(0.025, 0.055, 0.025)))
	for index in range(3):
		var ring_material := ShaderMaterial.new()
		ring_material.shader = FountainEffect
		ring_material.set_shader_parameter("kind", 1)
		var ring: MeshInstance3D = fx._card(self, fx._quad, ring_material, Vector3.ONE)
		fountain_rings.append(ring)
	for tile: Dictionary in sanctuary.get("tiles", []):
		if int(tile.x) in [-11, -9, -7] and int(tile.z) in [-2, 2] and not (int(tile.x) == -9 and int(tile.z) == -2): flower_anchors.append(stage.tile_position(tile) + Vector3.UP * 0.42)
	if flower_anchors.size() < 2: return
	for index in range(4):
		var root := Node3D.new()
		root.name = "SanctuaryButterfly_" + str(index)
		add_child(root)
		var material := ShaderMaterial.new()
		material.shader = Butterfly
		material.set_shader_parameter("tint", Color("f9dfce") if index % 2 == 0 else Color("fff3cb"))
		var wings: Array[MeshInstance3D] = []
		for side: int in [-1, 1]:
			var wing: MeshInstance3D = fx._card(root, fx._quad, material, Vector3.ONE * 0.16)
			wing.position.x = side * 0.055
			wings.append(wing)
		butterflies.append({"node": root, "wings": wings})

func _jet_point(u: float, side: int) -> Vector2:
	# Exact quadratic source control points, in the fountain's 90-unit art.
	return Vector2(side * 2.0, -42).bezier_interpolate(Vector2(side * (2.0 + 20.0 / 3.0), -42.0 - 46.0 / 3.0), Vector2(side * (23.0 - 22.0 / 3.0), -10.0 - 110.0 / 3.0), Vector2(side * 23.0, -10), u)

func update(time: float, particles: bool, low: bool, light: bool) -> void:
	var camera: Camera3D = stage._camera
	var span: float = camera.size
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var width := span * viewport_size.x / maxf(1.0, viewport_size.y)
	var focus_depth: float = (camera.global_position - stage._focus).dot(camera.global_basis.z)
	var center: Vector3 = camera.global_position - camera.global_basis.z * focus_depth
	for index in range(rain.size()):
		var node := rain[index]
		node.visible = particles and not low
		if not node.visible: continue
		var phase := fposmod(time / (2.8 + float(index * 137 % 1700) * 0.001) + index * 0.61803398875, 1.0)
		var near := index % 5 == 0
		node.global_position = center + camera.global_basis.x * ((fposmod(index * 0.754877666 + 0.13, 1.0) - 0.5) * width) + camera.global_basis.y * ((0.5 - phase) * span * 1.15) + camera.global_basis.z * (8.0 if near else -8.0)
		node.basis = camera.global_basis.scaled_local(Vector3(0.016, 0.16 if near else 0.10, 1))
	for index in range(gold.size()):
		var node := gold[index]
		node.visible = completed and particles and not low
		if not node.visible: continue
		node.global_position = center + camera.global_basis.x * ((fposmod(index * 0.618, 1.0) - 0.5) * width + sin(time + index) * 0.12) + camera.global_basis.y * ((fposmod(index * 0.381 + time * 0.035, 1.0) - 0.5) * span) + camera.global_basis.z * 8.0
		node.basis = camera.global_basis.scaled_local(Vector3.ONE * 0.045)
	for entry: Dictionary in impacts:
		var phase := fposmod(time / (3.3 + int(entry.index) % 5 * 0.43) + int(entry.index) * 0.381966, 1)
		var falling := phase < 0.64
		entry.drop.visible = particles and not low and falling and is_instance_valid(fx.water)
		entry.ring.visible = particles and not low and not falling and is_instance_valid(fx.water)
		if not is_instance_valid(fx.water): continue
		var at: Vector3 = entry.at
		at.y = fx.water.position.y + 0.025
		entry.drop.position = at + Vector3.UP * maxf(0, (1 - phase / 0.64) * 1.5)
		entry.drop.basis = camera.global_basis.scaled_local(Vector3(0.018, 0.12, 1))
		entry.ring.position = at
		var size := 0.05 + maxf(0, (phase - 0.64) / 0.36) * 0.52
		entry.ring.scale = Vector3(size, 1, size)
		entry.ring.material_override.set_shader_parameter("strength", clampf((1 - phase) / 0.36, 0, 1))
	for entry: Dictionary in ripples.values():
		if not is_instance_valid(entry.surface): entry.node.visible = false; continue
		entry.node.visible = entry.surface.visible
		var at: Vector3 = entry.surface.global_position
		at.y = entry.surface.sample_height(at) + 0.022
		entry.node.global_position = at
		entry.node.material_override.set_shader_parameter("phase", time * 1.5 + entry.seed)
	for entry: Dictionary in cores.values():
		if not is_instance_valid(entry.surface): entry.node.visible = false; continue
		entry.node.visible = light and (ready_to_repair or completed) and entry.surface.visible
		var at: Vector3 = entry.surface.global_position
		at.y = entry.surface.sample_height(at) + 0.025
		entry.node.global_position = at
		entry.node.material_override.set_shader_parameter("phase", time * 2.0)
	for jet in jets:
		var index := int(jet.get_meta("original_jet_segment"))
		var side := int(jet.get_meta("original_jet_side"))
		var a := _jet_point(index / 18.0, side)
		var b := _jet_point((index + 1) / 18.0, side)
		var midpoint := (a + b) * .5
		var direction := Vector2(b.x - a.x, a.y - b.y)
		jet.position = Sanctuary.effect_position(fountain_at, camera, midpoint.x, midpoint.y,fountain_ratio)
		jet.basis = camera.global_basis * Basis(Vector3.BACK, direction.angle() - PI*.5).scaled_local(Vector3(3.0, direction.length()+.7, 1)*Sanctuary.FOUNTAIN_PIXEL*fountain_ratio)
	for index in range(fountain_drops.size()):
		var drop := fountain_drops[index]
		drop.visible = particles and not low
		var phase := fposmod(time * .55 + index / 7.0, 1)
		var side := -1.0 if index % 2 == 0 else 1.0
		drop.position = Sanctuary.effect_position(fountain_at, camera, side * (8 + phase * 16), -50 + phase * 38,fountain_ratio)
		drop.basis = camera.global_basis.scaled_local(Vector3(2, 3.2, 1)*Sanctuary.FOUNTAIN_PIXEL*fountain_ratio)
	for index in range(fountain_rings.size()):
		var rx := 9.0 + index * 7 + sin(time * 2 + index)
		var ry := 3.0 + index * 2.5
		fountain_rings[index].position = Sanctuary.effect_position(fountain_at, camera, -2, -5,fountain_ratio)
		fountain_rings[index].basis = camera.global_basis.scaled_local(Vector3(rx*2, ry*2, 1)*Sanctuary.FOUNTAIN_PIXEL*fountain_ratio)
		fountain_rings[index].material_override.set_shader_parameter("source_radius", Vector2(rx,ry))
	for index in range(butterflies.size()):
		var entry: Dictionary = butterflies[index]
		entry.node.visible = particles
		var group := mini(index, 2)
		var duration: float = [34.0, 41.0, 46.0][group]
		var elapsed: float = time + [0.0, 19.0, 14.0][group]
		var cycle := int(elapsed / duration)
		var phase := fposmod(elapsed, duration) / duration
		var u := maxf(0, (phase - 0.38) / 0.62)
		var a := flower_anchors[(cycle + group * 2) % flower_anchors.size()]
		var b := flower_anchors[(cycle + group * 2 + 1) % flower_anchors.size()]
		entry.node.global_position = a.lerp(b, smoothstep(0, 1, u)) + Vector3(0, sin(u * PI) * 0.35, (index - 1.5) * 0.08)
		entry.node.basis = camera.global_basis
		var flap := 0.45 if low else 0.25 + absf(cos(time * TAU / (1.0 + index * 0.09) + index)) * 0.75
		for wing_index in range(2):
			var side := -1.0 if wing_index == 0 else 1.0
			entry.wings[wing_index].scale = Vector3(side * 0.16 * flap, 0.16, 0.16)
			entry.wings[wing_index].position.x = side * 0.055 * flap
