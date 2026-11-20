class_name SecondGardenDressing
extends RefCounted

const Props = preload("res://presentation/native/integrated_garden_props.gd")
const RockSpire = preload("res://presentation/native/isolated_rock_spire.gd")
const SceneryScale = preload("res://presentation/native/scenery_scale.gd")
const Original = preload("res://presentation/native/original_garden_dressing.gd")
const OriginalRatios = preload("res://presentation/native/original_prop_ratios.gd")

static func planter(stage: Node, parent: Node3D) -> void:
	var layout: Dictionary = OriginalRatios.core_layout(stage, parent)
	parent.set_meta("original_core_layout", layout)
	Props.planter(stage, parent, float(layout.width), layout.shift)

static func obstacle(stage: Node, wall: Array) -> void:
	RockSpire.build(stage, wall)

static func scenery(stage: Node) -> void:
	var context := Original.Placement.prepare(stage)
	# Borders remain quiet around both possible root paths; neither is marked
	# as the preferred answer. Plants never occupy the approach to a mechanism.
	for entry: Array in [
		["stone-lantern", "f:-1:2", Vector2(-0.29, 0.22)],
		["pink-flowers", "f:-1:2", Vector2(0.24, 0.30)],
		["red-mushroom", "f:-1:0", Vector2(-0.27, 0.24)],
		["blue-flowers", "f:0:0", Vector2(-0.22, -0.28)],
		# Broad plant bases belong on the side landing, not rear stair noses.
		["fern", "f:5:1", Vector2(0.30, -0.30)],
		["yellow-flowers", "f:5:1", Vector2(0.30, 0.30)],
		["red-mushroom", "f:5:2", Vector2(0.29, 0.29)]]:
		var source_index := 0 if entry[0] == "stone-lantern" else 1 if entry[0] == "yellow-flowers" else 2 if entry[0] == "red-mushroom" and entry[1] == "f:5:2" else -1
		var tile: Dictionary=stage._tile_map[str(entry[1])]
		var desired:=Vector3(float(tile.x)+entry[2].x,float(tile.h),float(tile.z)+entry[2].y)
		var safe:=Original.Placement.place(stage,desired,str(entry[0]),Original.canvas_width(30.0),source_index,context)
		if safe.is_empty():continue
		var sprite: Sprite3D=stage._sprite(stage._props,str(entry[0]),Original.canvas_width(30.0),safe.at,true)
		sprite.name="SecondGarden_"+str(entry[0]).replace("-","_")+"_"+str(entry[1]).replace(":","_")
		sprite.set_meta("dressing_support",str(safe.support))
		sprite.set_meta("dressing_alias",str(entry[0]))
		sprite.set_meta("dressing_offset",Vector2(safe.at.x-stage.tile_position_id(str(safe.support)).x,safe.at.z-stage.tile_position_id(str(safe.support)).z))
		Original.ground_sprite(sprite, str(entry[0]))
		sprite.set_meta("original_scenery_pixels", 30.0)
		# Preserve the reviewed positions on the revised physical island. The
		# original north yellow flower moves to this flat east landing; the
		# original lantern and south mushroom retain their corresponding rims.
		sprite.set_meta("original_scenery_index", source_index)
		sprite.set_meta("original_scenery_alias", str(entry[0]))
		sprite.set_meta("original_scenery_support", str(safe.support))
		sprite.set_meta("original_scenery_migration", str(safe.migration))
		sprite.set_meta("original_scenery_position",desired)
		var reference:=desired
		if source_index>=0:
			var original: Array=Original.SOURCE_PROPS["1-2"][source_index]
			reference=Vector3(float(original[1]),float(original[3]),float(original[2]))
		sprite.set_meta("original_scenery_reference_position",reference)
		sprite.set_meta("original_scenery_contact_kind","complete_hard_base" if Original.Placement.HARD_CONTACT.has(str(entry[0])) else "root_cluster_with_free_crown")
		sprite.set_meta("original_scenery_foot_radius",safe.radius)
	for entry: Array in [["f:-1:2", Vector2(0.20, 0.503)], ["f:5:2", Vector2(-0.28, 0.503)]]:
		var vine := _place(stage, "trailing-vine", str(entry[0]), entry[1], SceneryScale.nominal_width("trailing-vine"))
		vine.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		vine.offset = Vector2(0,-vine.texture.get_height()*0.44)
	Original.wall_vines(stage)


static func _place(stage: Node, alias: String, support: String, offset: Vector2, width: float) -> Sprite3D:
	# Anchor to the actual support: island spacing and stair elevations belong
	# to the profile, never to scenery. Rim offsets keep the walking centre free.
	var at: Vector3 = stage.tile_position(stage._tile_map[support]) + Vector3(offset.x, 0, offset.y)
	at.y = stage.support_height(at, support) + 0.015
	var sprite: Sprite3D = stage._sprite(stage._props, alias, width, at, true)
	sprite.name = "SecondGarden_" + alias.replace("-", "_") + "_" + support.replace(":", "_")
	sprite.set_meta("dressing_support", support)
	sprite.set_meta("dressing_alias", alias)
	sprite.set_meta("dressing_offset", offset)
	return sprite
