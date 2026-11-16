extends SceneTree
func _initialize() -> void:
	var mesh := CylinderMesh.new()
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.height = 1.0
	mesh.rings = 8
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var rows := []
	for index in range(vertices.size()):
		if absf(absf(vertices[index].y) - 0.5) < 0.0001 and rows.size() < 8:
			rows.append({"y": vertices[index].y, "uv": [uvs[index].x, uvs[index].y]})
	var edge := {}
	for index in range(vertices.size()):
		var y := str(snappedf(vertices[index].y, 0.0001))
		if not edge.has(y): edge[y] = uvs[index].y
	print(JSON.stringify({"ringUVs": edge, "samples": rows}))
	quit()
