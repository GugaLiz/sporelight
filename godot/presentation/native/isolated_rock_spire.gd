extends RefCounted

const Surface = preload("res://presentation/native/native_surface.gd")

static func build(stage: Node, wall: Array) -> void:
	var root := Node3D.new()
	root.name = "IsolatedRockSpire"
	root.position = Vector3(float(wall[0]), 0, float(wall[1]))
	stage._props.add_child(root)
	# An irregular outcrop rather than another paved, walkable tile. Its entire
	# footprint stays inside the blocked cell, clear of both four-segment routes.
	var outline := [Vector2(-0.27,-0.18),Vector2(-0.05,-0.29),Vector2(0.23,-0.23),Vector2(0.31,0.04),Vector2(0.17,0.28),Vector2(-0.13,0.31),Vector2(-0.30,0.08)]
	var rings: Array = []
	for band in range(3):
		var ring: Array[Vector3] = []
		for i in range(outline.size()):
			var at: Vector2 = outline[i]
			var scale: float = [1.0, 1.08, 0.37][band]
			var height: float = [-0.12, -0.60, -1.22][band]
			if band > 0: height += 0.06 * sin(float(i) * 2.1)
			ring.append(Vector3(at.x * scale + 0.025 * band, height, at.y * scale - 0.018 * band))
		rings.append(ring)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for band in range(2):
		for i in range(outline.size()):
			var next := (i + 1) % outline.size()
			var quad := [rings[band][i],rings[band][next],rings[band+1][next],rings[band+1][i]]
			for index in [0,1,2,0,2,3]:
				vertices.append(quad[index])
				# Sample only the grain inside the existing painted stone, without
				# mapping its overhead paving seams onto a vertical rock face.
				var face: Vector2 = [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)][index]
				uvs.append(Vector2(0.29,0.38) + face * Vector2(0.24,0.23))
	var material: StandardMaterial3D = stage._solid_material(Color("b8bea4"))
	material.albedo_texture = stage._texture("paving-valley")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := MeshInstance3D.new()
	body.name = "UnpavedRockBody"
	body.mesh = Surface._mesh(vertices, uvs, material)
	root.add_child(body)
	var cap_vertices := PackedVector3Array()
	var cap_uvs := PackedVector2Array()
	for i in range(outline.size()):
		for at: Vector3 in [Vector3(0,-0.12,0), rings[0][(i+1)%outline.size()], rings[0][i]]:
			cap_vertices.append(at)
			cap_uvs.append(Vector2(0.5 + at.x, 0.5 + at.z))
	var moss: StandardMaterial3D = stage._solid_material(Color("bfc8a1"))
	moss.albedo_texture = stage._texture("paving-moss")
	moss.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cap := MeshInstance3D.new()
	cap.mesh = Surface._mesh(cap_vertices, cap_uvs, moss)
	root.add_child(cap)
	var stone: Sprite3D = stage._sprite(root, "rock", 0.55, Vector3(0,-0.12,0), true)
	stone.set_meta("opaque_structure",true)
	stone.offset.y = stone.texture.get_height() * 0.5
	stage._sprite(root, "trailing-vine", 0.15, Vector3(0.10,-0.36,0.25))
	# Decoration only: do not add support collision or change the domain graph.
