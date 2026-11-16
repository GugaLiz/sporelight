class_name OriginalGardenDressing
extends RefCounted

## Browser-original authored instances. Generated from the verified TS scenery
## function; source canvas widths are pixels against a 70 px projected tile.
## The complete PNG is retained. Only its opaque painted foot is grounded.
const PIXELS_PER_TILE := 70.0
const TILE_SCREEN_WIDTH := 1.4142135623730951
const Placement = preload("res://presentation/native/original_scenery_placement.gd")
const SOURCE_PROPS := {
	"1-1": [
		["small-pebbles", -1, -1.24, 0, 25],
		["pink-flowers", -2.24, 0, 0, 30],
		["stone-lantern", 1.76, -1, 2, 30],
		["yellow-flowers", -1.24, 2, -1, 35],
		["red-mushroom", 4, -1.24, 2, 30],
		["blue-flowers", 0.24, 3, -1, 30],
	],
	"1-2": [
		["stone-lantern", -1.24, 2, 0, 30],
		["yellow-flowers", 5, -0.24, 2, 30],
		["red-mushroom", 5.24, 2, 1, 30],
	],
	"1-3": [
		["red-mushroom", -4, -1.24, 0, 35],
		["blue-flowers", 1, -5.24, 1, 30],
		["gold-lotus", -1.24, -3, 1, 32],
		["bush", -4, 1.24, 0, 39],
		["berry-bush", 1.24, -3, 1, 39],
		["fern", -1.24, 3, 0, 30],
		["small-pebbles", 2.76, -1, -1, 25],
		["pink-flowers", 1, 2.76, 0, 30],
		["stone-lantern", -1.24, 5, 0, 30],
		["yellow-flowers", 5, -1.24, -1, 35],
		["red-mushroom", 2.76, 1, -1, 30],
		["blue-flowers", 1.24, 5, 0, 30],
		["gold-lotus", 5.24, 1, -1, 32],
		["arch", -5, -1, 0, 90],
	],
	"1-4": [
		["gold-lotus", -2, -1.24, 0, 32],
		["bush", -1.76, 1, 0, 39],
		["berry-bush", -4.24, 4, 0, 39],
		["fern", 1.76, -1, 0, 35],
		["small-pebbles", -4.24, 6, 0, 25],
		["pink-flowers", 4, -1.24, 0, 30],
		["stone-lantern", 1.76, 1, 0, 30],
		["yellow-flowers", 4.24, 1, 0, 30],
		["red-mushroom", 1.76, 4, 0, 30],
		["blue-flowers", 4, 3.76, 0, 35],
		["gold-lotus", 1.76, 6, 0, 32],
		["bush", 4.24, 6, 0, 39],
		["pink-flowers", -11, -2, 2, 42],
		["blue-flowers", -11, 2, 2, 42],
		["yellow-flowers", -9, 2, 1, 42],
		["ivory-lotus", -7, -2, 1, 42],
		["gold-lotus", -7, 2, 1, 42],
		["berry-bush", -11, 0, 2, 46],
		["stone-lantern", -7, -1.7, 1, 29],
	],
	"2-1": [
		["blue-flowers", -1.24, -5, 2, 35],
		["ivory-lotus", -4, -1.24, 0, 30],
		["berry-bush", 1, -5.24, 2, 39],
		["yellow-flowers", -1.24, -3, 2, 35],
		["lotus-pool", -2.76, 0, 0, 47],
		["pink-flowers", 1.24, -3, 2, 30],
		["stone-lantern", -4.24, 2, 0, 30],
		["fern", -4.24, 4, 0, 30],
		["river-rock", 2.76, -1, 1, 30],
		["blue-flowers", 5, -1.24, 1, 35],
		["ivory-lotus", 2.76, 1, 1, 30],
		["berry-bush", 5.24, 1, 1, 39],
	],
	"2-2": [
		["berry-bush", 0, -1.24, 0, 39],
		["yellow-flowers", -1.24, 0, 0, 30],
		["lotus-pool", 3, -1.24, 0, 47],
		["pink-flowers", -1.24, 3, 0, 35],
		["stone-lantern", 2.76, 1, 0, 30],
		["fern", 1, 3.24, 0, 30],
		["river-rock", 5.24, 1, 0, 30],
	],
	"2-3": [
		["lotus-pool", -1.24, -5, 2, 47],
		["pink-flowers", -3, -1.24, 0, 30],
		["stone-lantern", -1.24, -3, 2, 30],
		["fern", -2.76, 1, 0, 35],
	],
	"2-4": [
		["stone-lantern", 11, -1.24, 0, 30],
		["fern", 11.24, 1, 0, 30],
		["wood-lantern", -5, -1, 0, 40],
	],
	"3-1": [
		["fern", -2, -1.24, 0, 35],
		["violet-crystal", -1.76, 1, 0, 30],
		["stone-lantern", -4.24, 4, 0, 30],
		["blue-flowers", -2, 3.76, 0, 35],
		["glow-flower", -4.24, 6, 0, 30],
		["blue-mushroom", 1.76, 1, 0, 30],
		["small-pebbles", -1.76, 6, 0, 25],
		["fern", 1.76, 4, 0, 30],
		["violet-crystal", 4, 3.76, 0, 30],
		["stone-lantern", 1.76, 6, 0, 30],
		["blue-flowers", 4.24, 6, 0, 30],
	],
	"3-2": [
		["stone-lantern", 1.76, 0, 0, 30],
		["blue-flowers", 1.76, 3, 0, 30],
		["glow-flower", 4, 2.76, 0, 30],
		["blue-mushroom", 1.76, 5, 0, 35],
		["small-pebbles", 4.24, 5, 0, 25],
	],
	"3-3": [
		["glow-flower", -1.24, -5, 0, 35],
		["blue-mushroom", -4, -1.24, 0, 30],
		["small-pebbles", -1.24, -3, 0, 25],
		["fern", -4, 1.24, 0, 35],
		["violet-crystal", -1.24, 3, 2, 30],
		["stone-lantern", 1, 2.76, 2, 30],
		["blue-flowers", -1.24, 5, 2, 35],
		["glow-flower", 6.76, -1, 2, 30],
		["blue-mushroom", 1.24, 5, 2, 30],
		["small-pebbles", 9, -1.24, 2, 25],
		["fern", 6.76, 1, 2, 30],
		["violet-crystal", 9.24, 1, 2, 30],
	],
	"3-4": [
		["small-pebbles", -5.24, -1, 0, 25],
		["fern", -1.24, -5, 0, 30],
		["violet-crystal", -3, -1.24, 0, 30],
		["stone-lantern", -5.24, 1, 0, 30],
		["blue-flowers", -1.24, -3, 0, 30],
		["glow-flower", -2.76, 1, 0, 30],
		["blue-mushroom", 6.76, 1, 2, 35],
		["light-tower", 7, -1, 2, 65],
	],
}

## Source alpha >= 64, last 5% opaque rows: size, foot left/right, last row.
## The arch deliberately retains its transparent margins and complete pillars.
const SOURCE_FEET := {
	"berry-bush": [134, 115, 29, 106, 114],
	"fern": [126, 114, 44, 97, 113],
	"small-pebbles": [117, 50, 19, 111, 49],
	"pink-flowers": [130, 124, 69, 103, 123],
	"stone-lantern": [116, 158, 33, 90, 157],
	"yellow-flowers": [106, 112, 40, 77, 111],
	"red-mushroom": [113, 142, 25, 91, 141],
	"blue-flowers": [112, 118, 38, 87, 117],
	"gold-lotus": [128, 148, 14, 113, 147],
	"bush": [141, 119, 57, 93, 118],
	"river-rock": [113, 97, 30, 93, 96],
	"ivory-lotus": [94, 102, 37, 60, 101],
	"lotus-pool": [342, 200, 96, 252, 199],
	"blue-mushroom": [100, 130, 20, 81, 129],
	"violet-crystal": [86, 111, 8, 81, 110],
	"glow-flower": [182, 272, 37, 148, 271],
	"arch": [256, 256, 127, 192, 231],
	"wood-lantern": [120, 154, 4, 58, 153],
	"light-tower": [272, 405, 63, 213, 404],
	"trailing-vine": [57, 226, 30, 38, 225],
}

static func canvas_width(pixels: float, local_tile_width: float = TILE_SCREEN_WIDTH) -> float:
	return pixels * local_tile_width / PIXELS_PER_TILE

static func ground_sprite(sprite: Sprite3D, alias: String) -> void:
	if sprite.texture == null or not SOURCE_FEET.has(alias): return
	var source: Array = SOURCE_FEET[alias]
	var foot_x := (float(source[2]) + float(source[3]) + 1.0) * 0.5
	sprite.offset = Vector2(float(source[0]) * 0.5 - foot_x, float(source[4]) + 0.5 - float(source[1]) * 0.5)

static func foot_radius(alias: String, width: float) -> float:
	return Placement.radius(alias,width)

static func scenery(stage: Node) -> void:
	var id := str(stage.world.level.id)
	if not SOURCE_PROPS.has(id): return
	stage._props.set_meta("original_deferred_scenery", [])
	var context := Placement.prepare(stage)
	var index := 0
	for entry: Array in SOURCE_PROPS[id]:
		place_original(stage, entry, index,context)
		index += 1
	wall_vines(stage)

static func place_original(stage: Node, entry: Array, index: int, context: Dictionary = {}) -> Sprite3D:
	var alias := str(entry[0])
	var authored := Vector3(float(entry[1]), float(entry[3]), float(entry[2]))
	var authored_support := "f:%d:%d" % [roundi(authored.x), roundi(authored.z)]
	# Some rule states remove whole fixed islands (2-4 before pollination,
	# 2-1 submerged banks). Their art must wait for the real support to exist.
	# Never manufacture a surface or leave the old 2D prop floating in space.
	if not stage._tile_map.has(authored_support) or not stage._surfaces.has(authored_support):
		var deferred: Array = stage._props.get_meta("original_deferred_scenery", [])
		deferred.append({"index": index, "asset": alias, "support": authored_support})
		stage._props.set_meta("original_deferred_scenery", deferred)
		return null
	var width := canvas_width(float(entry[4]))
	if context.is_empty():context=Placement.prepare(stage)
	var placement := Placement.place(stage,authored,alias,width,index,context)
	if placement.is_empty():
		push_error("Original scenery has no real flat support: " + str(stage.world.level.id) + "/" + str(index) + "/" + alias)
		return null
	var sprite: Sprite3D = stage._sprite(stage._props, alias, width, placement.at, true)
	ground_sprite(sprite, alias)
	sprite.visible = stage.world.visible(stage._tile_map[str(placement.support)], stage._tiles)
	sprite.name = "OriginalScenery_%02d_%s" % [index, alias.replace("-", "_")]
	sprite.set_meta("original_scenery_index", index)
	sprite.set_meta("original_scenery_alias", alias)
	sprite.set_meta("original_scenery_pixels", float(entry[4]))
	sprite.set_meta("original_scenery_position", authored)
	sprite.set_meta("original_scenery_reference_position", authored)
	sprite.set_meta("original_scenery_support", placement.support)
	sprite.set_meta("original_scenery_migration", placement.migration)
	sprite.set_meta("original_scenery_foot_radius", foot_radius(alias, width))
	sprite.set_meta("original_scenery_contact_kind","complete_hard_base" if Placement.HARD_CONTACT.has(alias) or alias=="lotus-pool" else "root_cluster_with_free_crown")
	return sprite

static func _fixed_support(stage: Node, tile: Dictionary) -> bool:
	# Unrevealed fixed islands already have genuine hidden surfaces. Keep the
	# instance with that support and inherit its visibility; do not drop it or
	# migrate its decoration onto a different, already discovered island.
	if bool(tile.get("small", false)) or bool(tile.get("solid", false)): return false
	if str(tile.get("kind", "fixed")) in ["root", "shadow", "module", "bridge", "lift", "water"]: return false
	return stage._surfaces.has(str(tile.id))

static func flat_footprint(stage: Node, at: Vector3, support: String, radius: float) -> bool:
	if not stage._surfaces.has(support): return false
	var baseline: float = stage.support_height(at, support)
	for dx: float in [-radius, 0.0, radius]:
		for dz: float in [-radius, 0.0, radius]:
			var sample := at + Vector3(dx, 0, dz)
			var logical: Vector3 = stage.logical_position(sample)
			var found := false
			for tile: Dictionary in stage._tiles:
				if not _fixed_support(stage, tile): continue
				if absf(logical.x - float(tile.x)) > 0.499 or absf(logical.z - float(tile.z)) > 0.499: continue
				if absf(stage.support_height(sample, str(tile.id)) - baseline) > 0.012: continue
				found = true
				break
			if not found: return false
	return true

static func wall_vines(stage: Node) -> void:
	if str(stage.world.level.get("chapter", "")) != "valley": return
	for tile: Dictionary in stage._tiles:
		if not _fixed_support(stage, tile): continue
		if not stage.world.visible(tile, stage._tiles): continue
		for side: int in range(2):
			var seed := absi(int(float(tile.x) * 19 + float(tile.z) * 31) + (3 if side == 0 else 0))
			if seed % 3 != 0: continue
			var normal := Vector3(0, 0, 1) if side == 0 else Vector3(1, 0, 0)
			var neighbor: Dictionary = {}
			for other: Dictionary in stage._tiles:
				if is_equal_approx(float(other.x), float(tile.x) + normal.x) and is_equal_approx(float(other.z), float(tile.z) + normal.z): neighbor = other; break
			# Native stair connectors occupy shared faces. Only genuine outer
			# walls carry hanging artwork; no foliage may pretend to be a stair.
			if not neighbor.is_empty(): continue
			var surface: Node3D = stage._surfaces[str(tile.id)]
			var foundation: MeshInstance3D = surface.get_node_or_null("Foundation")
			if foundation == null or foundation.mesh == null: continue
			var at: Vector3 = stage.physical_position(Vector3(float(tile.x) + normal.x * 0.502, 0, float(tile.z) + normal.z * 0.502))
			at.y = stage.support_height(at - normal * 0.012, str(tile.id)) - 0.015
			var bottom: float = surface.position.y + foundation.mesh.get_aabb().position.y * surface.scale.y
			var length := minf((at.y - bottom) * 0.75, canvas_width(85.0) / 0.8660254)
			if length <= 0.12: continue
			var width := length * 57.0 / 226.0 * 0.8660254
			var vine: Sprite3D = stage._sprite(stage._props, "trailing-vine", width, at, true)
			vine.name = "OriginalWallVine_" + str(tile.id).replace(":", "_") + "_" + str(side)
			vine.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			vine.rotation.y = PI * 0.5 if side == 1 else 0.0
			vine.scale = Vector3(1.414213562, 1.0 / 0.8660254, 1)
			vine.offset = Vector2(0, (1.0 - float(vine.texture.get_height())) * 0.5)
			vine.set_meta("original_wall_support", str(tile.id))
			vine.set_meta("original_wall_side", side)
			vine.set_meta("original_wall_bottom", bottom)
