extends RefCounted
## Original obstacle identity and canvas ratio. Display only: blocked cells
## and beam termination remain owned by the unchanged domain walls list.
static func build(stage: Node, wall: Array) -> Node3D:
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
