class_name FirstGardenDressing
extends RefCounted

## Authored props only. Never changes traversability, objectives or save data.
const Terrain = preload("res://presentation/native/first_garden_profile.gd")

static func planter(stage: Node, parent: Node3D) -> void:
	preload("res://presentation/native/integrated_garden_props.gd").planter(stage, parent)


static func scenery(stage: Node) -> void:
	# Fixed edge planting establishes quiet pockets; no prop selects a route.
	for entry: Array in [
		["fern", -2.27, -1.22, 0.45], ["pink-flowers", -2.25, 0.27, 0.34],
		["red-mushroom", -1.65, -1.28, 0.26], ["fern", -1.24, 3.26, 0.46],
		["pink-flowers", -0.78, 3.30, 0.33], ["fern", 4.28, -2.24, 0.48],
		["red-mushroom", 3.94, -2.27, 0.28], ["blue-flowers", 4.29, 0.27, 0.30]]:
		var at := Vector3(float(entry[1]), 0, float(entry[2]))
		at.y = Terrain.height(Vector2(at.x, at.z)) + 0.015
		stage._sprite(stage._props, str(entry[0]), float(entry[3]), stage.physical_position(at), true)
	stage._sprite(stage._props, "stone-lantern", 0.43, stage.physical_position(Vector3(2.04, 1.30, -2.12)))
	# The extended terrace has planted back corners and a clear central walk.
	# Use the same authored artwork at different heights and modest scales.
	for entry: Array in [
		["fern", 1.78, -2.30, 0.34],
		["pink-flowers", 2.38, -2.31, 0.36],
		["yellow-flowers", 1.83, -1.77, 0.25],
		["small-pebbles", 2.64, -2.30, 0.25],
		["bush", 3.35, -2.32, 0.40],
		["blue-flowers", 3.60, -2.18, 0.35],
		["small-pebbles", 4.25, -1.91, 0.26],
		["yellow-flowers", 4.27, -1.65, 0.24]]:
		var at := Vector3(float(entry[1]), 0, float(entry[2]))
		at.y = Terrain.height(Vector2(at.x, at.z)) + 0.015
		stage._sprite(stage._props, str(entry[0]), float(entry[3]), stage.physical_position(at), true)
	stage._sprite(stage._props, "yellow-flowers", 0.42, Vector3(-1.18, -0.65, 2.24), true)
	for at: Vector3 in [Vector3(-1.1, 0, 0.503), Vector3(-0.15, -0.65, 3.503), Vector3(2.65, 0.65, 0.503), Vector3(4.22, 0.65, 0.503)]:
		var vine: Sprite3D = stage._sprite(stage._props, "trailing-vine", 0.23, stage.physical_position(at))
		vine.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		vine.offset = Vector2(0, -vine.texture.get_height() * 0.44)

