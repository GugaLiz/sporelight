class_name SecondGardenDressing
extends RefCounted

const Props = preload("res://presentation/native/integrated_garden_props.gd")
const Surface = preload("res://presentation/native/native_surface.gd")

static func planter(stage: Node, parent: Node3D) -> void:
	# Leave a landing between the arrival flight and the flowerbed footprint.
	Props.planter(stage, parent, 0.98, Vector3(0.10, 0, 0.03))

static func obstacle(stage: Node, wall: Array) -> void:
	var tile := {"id":"rock-foundation", "x":float(wall[0]), "z":float(wall[1]), "h":0, "kind":"fixed"}
	var base := Surface.new()
	stage._props.add_child(base)
	base.configure(tile, [0.0,0.0,0.0,0.0], [true,true,true,true], -0.67, stage._terrace_materials(tile))
	# An obstacle pedestal must not look like an already completed road joining
	# the two islands, nor provide an extra physics support outside the rules.
	base.scale = Vector3(0.68, 1, 0.68)
	base.get_node("SupportCollision").collision_layer = 0
	var stone: Sprite3D = stage._sprite(stage._props, "rock", 0.94, Vector3(float(wall[0]), 0.015, float(wall[1])), true)
	stone.offset.y = stone.texture.get_height() * 0.5
	stage._contact_patch(stage._props, Vector2(0.72,0.64), Vector3(float(wall[0]),0.008,float(wall[1])),0.22)

static func scenery(stage: Node) -> void:
	# Borders remain quiet around both possible root paths; neither is marked
	# as the preferred answer. Plants never occupy the approach to a mechanism.
	for entry: Array in [
		["fern",-1.26,2.27,0.43], ["pink-flowers",-0.76,2.30,0.30],
		["red-mushroom",-1.27,0.24,0.24], ["blue-flowers",-0.22,-0.28,0.29],
		["fern",5.25,-0.26,0.42], ["yellow-flowers",4.28,-0.29,0.26],
		["pink-flowers",5.28,2.26,0.34], ["blue-flowers",4.30,2.30,0.28]]:
		var tile_id := "f:%d:%d" % [int(roundf(float(entry[1]))),int(roundf(float(entry[2]))) ]
		var at := Vector3(float(entry[1]),0,float(entry[2]))
		at = stage.physical_position(at)
		at.y = stage.support_height(at, tile_id) + 0.015
		stage._sprite(stage._props, str(entry[0]), float(entry[3]), at, true)
	for at: Vector3 in [Vector3(-0.8,0,2.503), Vector3(4.72,0.45,2.503)]:
		var vine: Sprite3D = stage._sprite(stage._props,"trailing-vine",0.23,stage.physical_position(at))
		vine.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		vine.offset = Vector2(0,-vine.texture.get_height()*0.44)
