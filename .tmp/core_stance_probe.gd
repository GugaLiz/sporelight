extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var stage := Stage.new(); root.add_child(stage); stage.set_process(false)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id: String in ["1-2","1-4","2-3","2-4","3-1","3-4"]:
		var snapshot: Dictionary
		for entry: Dictionary in reference.cases:
			if str(entry.name) == "authored/"+id: snapshot = entry.steps.back().snapshot
		stage.set_world(World.new(id,snapshot))
		var parent: Node3D = stage._props_nodes["mark:core"]
		var layout: Dictionary = Ratios.core_layout(stage,parent)
		if id == "1-2":
			var supported: Array = []
			for xx: float in [.8,1.0,1.1,1.2,1.3,1.4]:
				for zz: float in [.2,.3,.4,.5,.6,.7]:
					if Ratios._supported_footprint(stage,parent,layout.source_width,Vector3(xx,0,zz)): supported.append([xx,zz])
			print("ONE_TWO_FULL ",supported)
		if id == "1-4":
			var supported: Array = []
			for xx: float in [.4,.6,.8,1.0,1.2,1.4]:
				for zz: float in [-1.6,-1.4,-1.2,-1.0,-.8,-.7,-.6]:
					if Ratios._supported_footprint(stage,parent,layout.width,Vector3(xx,0,zz)): supported.append([xx,zz])
			print("SUPPORTED ",supported," parent ",parent.global_position)
		var candidate_shift: Vector3 = {"1-4":Vector3(1.2,0,-.7),"2-4":Vector3(.35,0,-.7),"2-3":Vector3(-.6,0,-.7),"3-1":Vector3(-.6,0,-.7)}.get(id,layout.shift)
		if Ratios._supported_footprint(stage,parent,layout.width,candidate_shift):
			parent.get_child(0).position += candidate_shift-layout.shift
			layout.shift = candidate_shift
		print("LAYOUT ",id," ",layout)
		for who: String in ["luvie","buddy"]:
			var body: Node3D = stage.get_actor_body(who)
			var tile: Dictionary = stage.world.point_for(str(snapshot.actors[who]))
			var center: Vector3 = stage.tile_position(tile)
			var found: Array = []
			var baseline: Dictionary = occlusion(stage,parent,who)
			for x: float in [-.44,-.32,-.16,0,.16,.32,.44]:
				for z: float in [-.44,-.32,-.16,0,.16,.32,.44]:
					body.position = center+Vector3(x,0,z)
					stage.update_actor_visual(who,Vector3.ZERO,"front","")
					var metric := occlusion(stage,parent,who)
					var distance := bed_clearance(body.position,parent.global_position,layout)
					if float(metric.body_fraction) == 0 and distance >= (.17 if who == "luvie" else .14):
						found.append({"x":x,"z":z,"clearance":distance})
			print(JSON.stringify({"level":id,"actor":who,"tile":tile.id,"baseline":baseline,"candidates":found}))
	stage.free(); quit()

func bed_clearance(point: Vector3,parent: Vector3,layout: Dictionary) -> float:
	var delta: Vector3 = point-parent-layout.shift-Vector3(0,0,.07)
	var half: float = .4*layout.width/1.16
	return Vector2(maxf(absf(delta.x)-half,0),maxf(absf(delta.z)-half,0)).length()

func occlusion(stage: Node,parent: Node3D,who: String) -> Dictionary:
	var plant: Sprite3D = parent.get_child(0)
	var actor: AnimatedSprite3D = stage.get_actor_body(who).get_node("Visual/Art")
	var texture: Texture2D = actor.sprite_frames.get_frame_texture(actor.animation,actor.frame)
	var actor_image: Image = texture.get_image() if who == "luvie" else null
	var plant_image := plant.texture.get_image()
	var bounds: Rect2i = actor_image.get_used_rect() if actor_image != null else Rect2i(24,14,88,99)
	var normal := plant.global_basis.z.normalized()
	var ray := Vector3(.61237244,.5,.61237244)
	var sampled := 0; var occluded := 0; var head_samples := 0; var head_occluded := 0
	for y in range(bounds.position.y,bounds.end.y,3):
		for x in range(bounds.position.x,bounds.end.x,3):
			if actor_image != null and actor_image.get_pixel(x,y).a < .5: continue
			var local := Vector3(x-texture.get_width()*.5+actor.offset.x,texture.get_height()*.5-y+actor.offset.y,0)*actor.pixel_size
			var point := actor.to_global(local)
			var is_head := y < bounds.position.y+bounds.size.y*.4
			sampled += 1
			if is_head: head_samples += 1
			var distance := (plant.global_position-point).dot(normal)/ray.dot(normal)
			if distance <= 0: continue
			var hit := plant.to_local(point+ray*distance)
			var ix := int(hit.x/plant.pixel_size+plant.texture.get_width()*.5-plant.offset.x)
			var iy := int(plant.texture.get_height()*.5+plant.offset.y-hit.y/plant.pixel_size)
			if ix < 0 or ix >= plant_image.get_width() or iy < 0 or iy >= plant_image.get_height(): continue
			if plant_image.get_pixel(ix,iy).a < .5: continue
			occluded += 1
			if is_head: head_occluded += 1
	return {"body_fraction":float(occluded)/maxi(1,sampled),"head_fraction":float(head_occluded)/maxi(1,head_samples),"samples":sampled}




