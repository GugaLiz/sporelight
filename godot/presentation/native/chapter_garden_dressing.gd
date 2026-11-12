class_name ChapterGardenDressing
extends RefCounted

const Props = preload("res://presentation/native/integrated_garden_props.gd")
const SceneryScale = preload("res://presentation/native/scenery_scale.gd")
const Original = preload("res://presentation/native/original_garden_dressing.gd")
const OriginalRatios = preload("res://presentation/native/original_prop_ratios.gd")
const PALETTES := {
	"valley": {"stone": Vector3(1.08, 1.04, 0.86), "plant": Vector3(0.88, 0.88, 0.80), "saturation": 0.32, "plants": ["fern", "pink-flowers", "red-mushroom"]},
	"pond": {"stone": Vector3(0.91, 1.02, 1.05), "plant": Vector3(0.83, 0.91, 0.91), "saturation": 0.38, "plants": ["blue-flowers", "fern", "yellow-flowers"]},
	"cave": {"stone": Vector3(0.88, 0.98, 0.96), "plant": Vector3(0.78, 0.87, 0.83), "saturation": 0.30, "plants": ["blue-mushroom", "fern", "blue-flowers"]},
	"cloud": {"stone": Vector3(1.04, 1.02, 0.98), "plant": Vector3(0.92, 0.91, 0.87), "saturation": 0.42, "plants": ["pink-flowers", "blue-flowers", "yellow-flowers"]}
}

static func planter(stage: Node, parent: Node3D) -> void:
	var layout: Dictionary = OriginalRatios.core_layout(stage, parent)
	parent.set_meta("original_core_layout", layout)
	Props.planter(stage, parent, float(layout.width), layout.shift)
	var chapter := str(stage.world.level.get("chapter", "valley"))
	var palette: Dictionary = PALETTES.get(chapter, PALETTES.valley)
	for child in parent.get_children():
		if not child is Sprite3D: continue
		var sprite: Sprite3D = child
		var key := "chapter_planter_" + chapter + "_" + sprite.texture.resource_path
		if not stage._materials.has(key):
			var material: ShaderMaterial = sprite.material_override.duplicate()
			material.set_shader_parameter("stone_tint", palette.stone)
			material.set_shader_parameter("plant_tint", palette.plant)
			material.set_shader_parameter("stone_saturation", palette.saturation)
			stage._materials[key] = material
		sprite.material_override = stage._materials[key]

static func scenery(stage: Node) -> void:
	if Original.SOURCE_PROPS.has(str(stage.world.level.id)):
		Original.scenery(stage)
		return
	# Cloud gardens have a separate authored renderer and source contract.
	# Their adapter replaces this fallback independently of mainline scenery.
	var chapter := str(stage.world.level.get("chapter", "valley"))
	var palette: Dictionary = PALETTES.get(chapter, PALETTES.valley)
	var candidates: Array = stage._tiles.duplicate()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var planted := 0
	var vines := 0
	for tile: Dictionary in candidates:
		if planted >= 6: break
		if not _quiet_fixed_edge(stage, tile): continue
		var seed := absi(hash(str(tile.id)))
		if seed % 3 != 0: continue
		# Use an exposed corner only; planted feet never occupy a docking edge,
		# dynamic support, narrow corridor, slope shoulder or undiscovered tile.
		var south: bool = not stage._has_neighbor(tile, Vector2(0, 1))
		var east: bool = not stage._has_neighbor(tile, Vector2(1, 0))
		if not south and not east: continue
		var alias := str(palette.plants[int(seed / 7) % palette.plants.size()])
		if planted == 0:
			alias = "wood-lantern" if chapter == "pond" else "stone-lantern"
		var at: Vector3 = stage.tile_position(tile) + Vector3(0.27 if east else -0.27, 0, 0.27 if south else -0.27)
		var support := str(tile.id)
		# In 3-3 the raised f:-1:3 terrace hides this rim's south corner.
		# Keep the lantern on the same flat east edge, north of that sightline.
		if str(stage.world.level.id) == "3-3" and support == "f:-3:1":
			at.z = stage.tile_position(tile).z - 0.27
		var height: float = stage.support_height(at, support)
		if not SceneryScale.flat_footprint(stage, at, support, alias): continue
		at.y = height + 0.015
		# Restore a modest authored lantern, not a second collectible or puzzle
		# post. Chapters keep their existing plant palette and spare rim space.
		var sprite: Sprite3D = stage._sprite(stage._props, alias, SceneryScale.nominal_width(alias), at, true)
		sprite.name = "EdgePlant_" + support.replace(":", "_")
		sprite.set_meta("dressing_support", support)
		sprite.set_meta("dressing_alias", alias)
		if south and vines < 2:
			var lip: Vector3 = stage.tile_position(tile) + Vector3(-0.24, 0, 0.503)
			lip.y = stage.support_height(lip, support) + 0.015
			var vine: Sprite3D = stage._sprite(stage._props, "trailing-vine", SceneryScale.nominal_width("trailing-vine"), lip, true)
			vine.name = "EdgeVine_" + support.replace(":", "_")
			vine.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			vine.offset = Vector2(0, -vine.texture.get_height() * 0.44)
			vine.set_meta("dressing_support", support)
			vine.set_meta("dressing_alias", "trailing-vine")
			vines += 1
		planted += 1

static func _quiet_fixed_edge(stage: Node, tile: Dictionary) -> bool:
	if not stage.world.visible(tile, stage._tiles) or bool(tile.get("solid", false)) or bool(tile.get("small", false)): return false
	if str(tile.get("kind", "fixed")) in ["root", "shadow", "module", "bridge", "lift", "water"]: return false
	if str(tile.id) in [str(stage.world.level.get("start", "")), str(stage.world.level.get("buddy", ""))]: return false
	# Respect all authored future docking positions, not just today's modules.
	for root: Dictionary in stage.world.level.get("roots", []):
		for socket: Array in root.get("sockets", []):
			if Vector2(float(socket[0]) - float(tile.x), float(socket[1]) - float(tile.z)).length() <= 1.01: return false
	for module: Dictionary in stage.world.level.get("modules", []):
		for cell: Array in module.get("shape", []):
			for step in range(4 if str(module.get("kind", "")) == "rotate" else 2):
				var offset := Vector2(float(cell[0]), float(cell[1]))
				if str(module.get("kind", "")) == "rotate":
					for turn in range(step): offset = Vector2(-offset.y, offset.x)
				elif str(module.get("kind", "")) == "slide":
					offset += (Vector2.RIGHT if str(module.get("axis", "")) == "x" else Vector2.DOWN) * step * float(module.get("distance", 0))
				var point := Vector2(float(module.get("x", 0)), float(module.get("z", 0))) + offset
				if point.distance_to(Vector2(float(tile.x), float(tile.z))) <= 1.01: return false
	var near_fixed := 0
	for other: Dictionary in stage.world.level.tiles:
		if bool(other.get("small", false)) or bool(other.get("solid", false)): continue
		if is_equal_approx(absf(float(other.x) - float(tile.x)) + absf(float(other.z) - float(tile.z)), 1.0) and is_equal_approx(float(other.h), float(tile.h)):
			near_fixed += 1
	if near_fixed < 2: return false
	var reserved: Array = stage.world.level.get("marks", []).duplicate()
	reserved.append_array(stage.world.level.get("collectibles", []))
	reserved.append_array(stage.world.state.get("items", {}).values())
	for entry: Dictionary in reserved:
		var point: Dictionary = stage._tile_map.get(str(entry.get("tile", "")), {})
		if not point.is_empty() and Vector2(float(point.x) - float(tile.x), float(point.z) - float(tile.z)).length() <= 1.01: return false
	return true
