extends RefCounted
## Quiet, asymmetric edge planting made from the existing garden artwork.
## No new objective, obstruction or route hint is introduced here.

static func build(stage: Node) -> void:
	var garden := Node3D.new()
	garden.name = "RearCourtyardPlanting"
	stage._props.add_child(garden)
	# Small moss pockets sit at the outer lip, leaving the tile-center walking
	# corridor and the flowerbed approach open. Avoid another continuous wall.
	for entry: Array in [[4.03, -0.40, 0.68, 0.25], [4.96, -0.42, 0.63, 0.24]]:
		var at: Vector3 = stage.physical_position(Vector3(entry[0], 0.45, entry[1]))
		var mound := CylinderMesh.new()
		mound.top_radius = 0.92
		mound.bottom_radius = 1.0
		mound.height = 0.055
		mound.radial_segments = 11
		var pocket: MeshInstance3D = stage._mesh_instance(garden, mound, Color("aeb38c"), at + Vector3(0, 0.022, 0))
		pocket.scale = Vector3(entry[2], 1, entry[3])
		pocket.material_override.albedo_texture = stage._texture("paving-moss")
	for entry: Array in [
		["berry-bush", 3.98, -0.47, 0.78],
		["river-rock", 3.84, -0.30, 0.42],
		["fern", 4.19, -0.45, 0.48],
		["pink-flowers", 4.18, -0.20, 0.39],
		["blue-flowers", 3.93, -0.15, 0.28],
		["small-pebbles", 4.41, -0.35, 0.26],
		["stone-lantern", 4.83, -0.43, 0.49],
		["fern", 5.08, -0.46, 0.56],
		["river-rock", 5.19, -0.30, 0.39],
		["yellow-flowers", 4.97, -0.20, 0.31],
		["pink-flowers", 5.24, -0.15, 0.28]]:
		var at: Vector3 = stage.physical_position(Vector3(entry[1], 0.465, entry[2]))
		stage._sprite(garden, entry[0], entry[3], at, true)
