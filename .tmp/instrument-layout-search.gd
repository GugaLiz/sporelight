extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Pick = preload("res://presentation/native/native_prop_picking.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var stage := Stage.new(); root.add_child(stage); stage.set_process(false)
	stage.set_world(World.new("1-3"))
	var prop: Node3D = stage._props_nodes["mark:turn"]
	var wheel: MeshInstance3D = prop.get_node("InstrumentWheel")
	var hero: AnimatedSprite3D = stage.get_actor_body("luvie").get_node("Visual/Art")
	var faces := wheel.mesh.get_faces()
	var best: Array = []
	for bx: float in [-.30,-.29,-.28]:
		for bz: float in [-.08,-.04,0,.04,.08]:
			var b := Vector3(bx,0,bz)
			if b.length()+.1995>.5: continue
			for hx: float in [.30,.31,.32]:
				for hz: float in [-.10,-.05,0,.05,.10]:
					var h := Vector3(hx,0,hz)
					var minimum := 1.0
					for turn in range(4):
						wheel.position = Vector3(0,.48,0)+b.rotated(Vector3.UP,-turn*PI/2)
						stage.get_actor_body("luvie").position = prop.global_position+h.rotated(Vector3.UP,-turn*PI/2)+Vector3(0,.018,0)
						stage.update_actor_visual("luvie",Vector3.ZERO,"front")
						var visible := 0; var total := 0
						for index in range(0,faces.size(),48):
							var point := wheel.to_global((faces[index]+faces[index+1]+faces[index+2])/3)
							var screen: Vector2 = stage.world_to_screen(point)
							var origin: Vector3 = stage._camera.project_ray_origin(screen)
							var ray: Vector3 = stage._camera.project_ray_normal(screen)
							if Pick._opaque_distance(hero,stage._camera,origin,ray)>origin.distance_to(point)-.01: visible += 1
							total += 1
						minimum = minf(minimum,float(visible)/total)
					best.append({"base":str(b),"hero":str(h),"min":minimum})
	best.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.min>b.min)
	print(JSON.stringify(best.slice(0,12)))
	stage.free(); quit()
