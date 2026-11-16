extends RefCounted
## Original obstacle identity and canvas ratio. Display only: blocked cells
## and beam termination remain owned by the unchanged domain walls list.
static func build(stage: Node, wall: Array) -> Node3D:
	if str(stage.world.level.id)=="3-4": return _guardian_backstone(stage,wall)
	var alias := "river-rock" if str(stage.world.level.id) == "2-2" else "rock"
	var pixels := 46.0 if alias == "river-rock" else 70.0
	var root := Node3D.new()
	root.name = "OriginalWall_%d_%d" % [int(wall[0]),int(wall[1])]
	root.position = stage.physical_position(Vector3(float(wall[0]),0,float(wall[1])))
	root.set_meta("original_wall_alias",alias)
	root.set_meta("original_wall_pixels",pixels)
	root.set_meta("original_wall_cell",Vector2(float(wall[0]),float(wall[1])))
	root.set_meta("native_footing_extent",Vector2(.86,.86))
	stage._props.add_child(root)
	# Keep the former obstacle's visible horizontal extent as a low stone
	# footing, rather than making a full blocked cell look like a tiny pickup.
	# The former box had no collider; neither this footing nor the art adds one.
	var footing: MeshInstance3D = stage._box(root,Vector3(.86,.10,.86),Vector3(0,.025,0),Color("a7ada0"))
	footing.name = "ObstacleFooting"
	var rock: Sprite3D = stage._sprite(root,alias,pixels*sqrt(2.0)/70.0,Vector3(0,.075,0))
	rock.name = "OriginalRock"
	rock.offset = Vector2(0,(rock.texture.get_height()-1)*.5)
	# Upright depth keeps the source foot on the footing; compensate projected
	# height so the source image retains its original width/height proportion.
	rock.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var right := Vector3(1,0,-1).normalized()
	rock.basis = Basis(right,Vector3.UP/cos(PI/6),right.cross(Vector3.UP))
	rock.set_meta("original_wall_pixels",pixels)
	return root

static func _guardian_backstone(stage: Node, wall: Array) -> Node3D:
	var tile_id := "f:%d:%d" % [int(wall[0]),int(wall[1])]
	var tile: Dictionary = stage._tile_map[tile_id]
	var root := Node3D.new()
	root.name = "GuardianBackstone"
	root.position = stage.tile_position(tile)
	root.set_meta("support_id",tile_id)
	root.set_meta("inset_footprint",Vector2(.84,.72))
	root.set_meta("visual_only",true)
	stage._props.add_child(root)
	# A single rounded, weathered rock owns the same .84 x .72 grounded
	# footprint. Its closed irregular crown replaces the man-made box/cap.
	var stone: MeshInstance3D = stage._mesh_instance(root,_guardian_rock_mesh(),Color.WHITE,Vector3.ZERO)
	stone.name = "BeamStopStone"
	var material: StandardMaterial3D = stone.material_override
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	return root

static func _guardian_rock_mesh() -> ArrayMesh:
	var profiles: Array[Vector4] = [Vector4(.42,.36,0,0),Vector4(.40,.34,.11,0),Vector4(.34,.29,.39,-.015),Vector4(.23,.20,.58,-.03),Vector4(.10,.08,.64,-.04)]
	var radial: Array[float] = [1.0,.95,.97,1.0,.94,.98,1.0,.94,.98,1.0,.96,.93]
	var rings: Array = []
	for ring_index in range(profiles.size()):
		var ring: Array[Vector3] = []
		var profile: Vector4 = profiles[ring_index]
		for index in range(12):
			var angle := float(index)*TAU/12
			var irregular_height := 0.0 if ring_index==0 else sin(float(index)*1.7+float(ring_index))*.012
			ring.append(Vector3(cos(angle)*profile.x*radial[index]+profile.w,profile.z+irregular_height,sin(angle)*profile.y*radial[index]-.004*ring_index))
		rings.append(ring)
	var triangles: Array = []
	for ring_index in range(rings.size()-1):
		for index in range(12):
			var next := (index+1)%12
			triangles.append([rings[ring_index][index],rings[ring_index+1][index],rings[ring_index+1][next]])
			triangles.append([rings[ring_index][index],rings[ring_index+1][next],rings[ring_index][next]])
	for index in range(12):
		triangles.append([Vector3.ZERO,rings[0][index],rings[0][(index+1)%12]])
		triangles.append([Vector3(-.04,.66,-.02),rings.back()[(index+1)%12],rings.back()[index]])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(triangles.size()):
		var triangle: Array = triangles[index]
		var normal: Vector3 = (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
		var center: Vector3 = (triangle[0]+triangle[1]+triangle[2])/3.0
		var paint := Color("7e887a").lerp(Color("89936d"),clampf((center.y-.30)*2.0,0,.60))
		paint = paint.lightened(float(index%5)*.012)
		# Godot's front faces are clockwise. Vertex normals remain outward.
		for vertex_index: int in [0,2,1]:
			vertices.append(triangle[vertex_index])
			normals.append(normal)
			colors.append(paint)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
