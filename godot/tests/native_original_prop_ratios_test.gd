extends SceneTree
## Source ratio/support candidates only; screenshots must approve legibility.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
var checks := 0
var failures: Array[String] = []
var layouts: Array = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	var stage := Stage.new(); root.add_child(stage); stage.set_process(false)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id: String in ["1-1","1-2","1-3","1-4","2-1","2-2","2-3","2-4","3-1","3-2","3-3","3-4"]:
		var world := World.new(id)
		var snapshot: Dictionary = world.snapshot()
		stage.set_world(world)
		var parent: Node3D = stage._props_nodes.get("mark:core")
		if parent == null:
			for entry: Dictionary in reference.cases:
				if str(entry.name) == "authored/"+id:
					world = World.new(id,entry.steps.back().snapshot)
					break
			snapshot = world.snapshot()
			stage.set_world(world)
			parent = stage._props_nodes.get("mark:core")
		check(parent != null,id+" core exists")
		if parent == null: continue
		var layout: Dictionary = Ratios.core_layout(stage,parent)
		layouts.append({"level":id,"width":layout.width,"source_width":layout.source_width,"shift":[layout.shift.x,layout.shift.y,layout.shift.z],"reason":layout.reason})
		if id in ["1-3","3-4"]: layouts.back()["initial_opaque_actor_occlusion"] = _opaque_actor_occlusion(stage,parent)
		check(world.snapshot() == snapshot,id+" candidate preserves rule snapshot")
		if id != "1-1": check(Ratios._supported_footprint(stage,parent,float(layout.width),layout.shift),id+" complete candidate footprint on fixed real ground")
		check(float(layout.width) <= float(layout.source_width),id+" never larger than source")
		if id == "1-1": check(is_equal_approx(layout.width,1.16),id+" approved unchanged")
		if id == "3-4": check(is_equal_approx(layout.width,150.0/70*sqrt(2.0)),id+" final core full source ratio")
		for entry: Dictionary in reference.cases:
			if str(entry.name) != "authored/"+id: continue
			var restored := World.new(id,entry.steps.back().snapshot)
			stage.set_world(restored)
			var restored_parent: Node3D = stage._props_nodes.get("mark:core")
			check(restored_parent != null,id+" completed core remains present")
			if restored_parent == null: break
			var restored_layout: Dictionary = Ratios.core_layout(stage,restored_parent)
			if id in ["1-3","3-4"]: layouts.back()["completed_opaque_actor_occlusion"] = _opaque_actor_occlusion(stage,restored_parent)
			check(is_equal_approx(layout.width,restored_layout.width) and layout.shift.is_equal_approx(restored_layout.shift),id+" completion cannot shrink or move core")
			if id != "1-1": check(Ratios._supported_footprint(stage,restored_parent,restored_layout.width,restored_layout.shift),id+" completed footprint remains physically supported")
			if id == "3-4":
				check(Ratios._authored_fixed_support(stage,"f:-4:0"),"occupied returning root retains original fixed foundation identity")
				var limited_width := 1.7
				var limited_shift := Vector3(-.85,0,-.85)
				var half := .4*limited_width/1.16
				var center := Vector2(limited_shift.x,limited_shift.z+.07)
				var distance := Vector2(maxf(absf(center.x)-half,0),maxf(absf(center.y)-half,0)).length()
				check(Ratios._supported_footprint(stage,restored_parent,limited_width,limited_shift) and distance > .25,"documented smaller alternative preserves source art and clears same-tile body physically")
				layouts.append({"level":id,"alternative_only":true,"width":limited_width,"shift":[limited_shift.x,0,limited_shift.z],"same_tile_clearance":distance,"source_ratio_preserved":false})
			break
	for entry: Array in [["root",65],["flower",55],["latch",90],["rest",34],["observe",34],["core",110]]:
		check(is_equal_approx(Ratios.canvas_width(entry[0])/sqrt(2.0),float(entry[1])/70),str(entry[0])+" original tile ratio")
	print(JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"layouts":layouts}))
	stage.free()
	quit(0 if failures.is_empty() else 1)

func _opaque_actor_occlusion(stage: Node,parent: Node3D) -> Dictionary:
	# Independent CPU ray/image calculation with fully opaque core material.
	# This is a geometric diagnostic, not a replacement for GPU screenshots.
	var plant: Sprite3D = parent.get_child(0)
	var actor: AnimatedSprite3D = stage.get_actor_body("luvie").get_node("Visual/Art")
	var texture: Texture2D = actor.sprite_frames.get_frame_texture(actor.animation,actor.frame)
	var actor_image := texture.get_image()
	var plant_image := plant.texture.get_image()
	var normal := plant.global_basis.z.normalized()
	var ray := Vector3(.61237244,.5,.61237244)
	var sampled := 0
	var occluded := 0
	var head_samples := 0
	var head_occluded := 0
	var body_bounds := actor_image.get_used_rect()
	for y in range(body_bounds.position.y,body_bounds.end.y,3):
		for x in range(body_bounds.position.x,body_bounds.end.x,3):
			if actor_image.get_pixel(x,y).a < .5: continue
			var local := Vector3(x-texture.get_width()*.5+actor.offset.x,texture.get_height()*.5-y+actor.offset.y,0)*actor.pixel_size
			var point := actor.to_global(local)
			var is_head := y < body_bounds.position.y+body_bounds.size.y*.4
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
