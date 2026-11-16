extends SceneTree
## Physical endpoints and opaque ray/source-image checks; not GPU validation.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Session = preload("res://application/game_session.gd")
const Movement = preload("res://application/native_movement.gd")
const Router = preload("res://application/input_router.gd")
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Array = []
var stage: Node2D
var session: RefCounted
var movement: RefCounted
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	stage = Stage.new(); root.add_child(stage); stage.set_process(false)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id: String in ["1-2","1-3","1-4","2-1","2-3","2-4","3-1","3-2","3-3"]:
		var steps: Array
		for entry: Dictionary in reference.cases:
			if str(entry.name) == "authored/"+id: steps = entry.steps
		for index: int in [steps.size()-2,steps.size()-1]:
			session = Session.new(id,steps[index].snapshot)
			var original: Dictionary = session.world.snapshot()
			stage.set_world(session.world)
			movement = Movement.new(); movement.setup(session,stage,Router.new())
			await physics_frame
			var parent: Node3D = stage._props_nodes["mark:core"]
			var layout := Ratios.core_layout(stage,parent)
			check(Ratios._supported_footprint(stage,parent,layout.width,layout.shift),id+" planter full base support")
			check(is_equal_approx(layout.width,1.12233559801 if id == "1-2" else 110.0/70*sqrt(2.0)),id+" original size or documented narrow-landing exception")
			check(session.world.state.actors == original.actors and session.world.state.completed == original.completed,id+" rule supports/completion preserved")
			for who: String in ["luvie","buddy"]:
				_validate(id,who,"restored",parent,layout)
				var body: CharacterBody3D = stage.get_actor_body(who)
				var before := body.position
				movement.capture(); movement.restore()
				check(body.position.distance_to(before)<.025,id+" "+who+" saved stance restored")
			if index != steps.size()-1: continue
			# Completed old-centre saves migrate within the very same support.
			for who: String in ["luvie","buddy"]:
				var tile: Dictionary = session.world.point_for(str(session.world.state.actors[who]))
				session.world.state.runtime.poses[who] = {"support":str(tile.id),"offset":[0,.018,0],"facing":"front"}
			var memory_before: Dictionary=session.world.snapshot()
			movement.restore()
			for key: String in ["actors","flags","collected","completed","items","growth","turns"]:
				check(session.world.snapshot().get(key)==memory_before.get(key),id+" old-memory recovery preserves "+key)
			for who: String in ["luvie","buddy"]: _validate(id,who,"old-memory",parent,layout)
			# Exercise the real motor from a legal side point. The old centre
			# can now be inside solid masonry; its migration was tested above.
			for who: String in ["luvie","buddy"]:
				session.world.state.active = who; session.world.state.follow = false
				var tile: Dictionary = session.world.point_for(str(session.world.state.actors[who]))
				var body: CharacterBody3D = stage.get_actor_body(who)
				var start := _manual_start(tile,who,body.position)
				check(not start.is_empty(),id+" "+who+" has a legal separated movement start")
				if not start.is_empty():
					body.position=start.point
					session.world.state.actors[who]=start.support
				var actual_start := body.position
				movement.capture(); movement.request_path([str(tile.id)])
				await _drain(180)
				check(not movement.is_moving(),id+" "+who+" click settles")
				var expected: Vector3 = stage.actor_rest_position(tile,who)
				var safe: Dictionary=stage.prop_waypoint(tile,who,expected)
				check(not safe.is_empty(),id+" "+who+" has a real safe destination")
				if not safe.is_empty(): expected=safe.point
				check(Vector2(body.position.x-actual_start.x,body.position.z-actual_start.z).length()>.06,id+" "+who+" motor actually moves")
				check(Vector2(body.position.x-expected.x,body.position.z-expected.z).length()<.06,id+" "+who+" click reaches shared endpoint")
				check(str(session.world.state.actors[who]) == str(tile.id),id+" "+who+" click keeps rule support")
				_validate(id,who,"walked",parent,layout)
			session.world.state.active = "luvie"; session.world.state.follow = true
			await _drain(120)
			check(not movement.is_moving() and session.world.together(),id+" follower settles legally")
			var buddy: CharacterBody3D = stage.get_actor_body("buddy")
			var support: Dictionary = session.world.point_for(str(session.world.state.actors.luvie))
			var target: Vector3 = stage.actor_rest_position(support,"buddy")
			check(Vector2(buddy.position.x-target.x,buddy.position.z-target.z).length()<.065,id+" follow/restore/click endpoint consistent")
			_validate(id,"buddy","followed",parent,layout)
			check(session.world.normalize_saved(session.world.snapshot()).ok,id+" completed positions saveable")
			# A non-default explicit position is preserved even after completion.
			var hero: CharacterBody3D = stage.get_actor_body("luvie")
			# The old arbitrary (.1,.1) can be inside an original stone base.
			# Preserve an actually legal manual pose; invalid poses are covered
			# by the separate recovery suite and must not be grandfathered in.
			var candidate := _manual_start(support,"luvie",hero.position)
			check(not candidate.is_empty(),id+" has a legal non-default saved manual pose")
			if not candidate.is_empty():
				hero.position=candidate.point
				session.world.state.actors.luvie=candidate.support
			var manual := hero.position
			movement.capture(); movement.restore()
			check(hero.position.distance_to(manual)<.025,id+" explicit saved walking position remains authoritative")
	print(JSON.stringify({"suite":"native-core-stance","checks":checks,"passed":failures.is_empty(),"failures":failures,"measurements":measurements,"gpuPixelsVerified":false}))
	stage.free(); quit(0 if failures.is_empty() else 1)
func _drain(limit: int) -> void:
	for frame in range(limit):
		await physics_frame
		movement.tick(1.0/60)
		if frame>3 and not movement.is_moving(): break
func _flat_support(tile: Dictionary,who: String,point: Vector3) -> bool:
	var capsule: CapsuleShape3D=stage.get_actor_body(who).get_node("Collision").shape
	var height: float=stage.tile_position(tile).y
	for ring: float in [0,.5,1.0]:
		for sector in range(16):
			var probe:=point+Vector3(cos(sector*TAU/16),0,sin(sector*TAU/16))*capsule.radius*ring
			var found:=false
			for key: String in stage._surfaces:
				var surface: Node3D=stage._surfaces[key]
				var definition: Dictionary=stage._tile_map.get(key,{})
				if not surface.is_visible_in_tree() or bool(definition.get("solid",false)) or (who=="luvie" and bool(definition.get("small",false))):continue
				var local:=surface.to_local(probe)
				if absf(local.x)>.5001 or absf(local.z)>.5001: continue
				if absf(float(surface.sample_height(probe))-height)>.025: continue
				found=true;break
			if not found:return false
	return true
func _manual_start(tile: Dictionary,who: String,origin: Vector3) -> Dictionary:
	var target: Vector3=stage.actor_rest_position(tile,who)
	var safe: Dictionary=stage.prop_waypoint(tile,who,target)
	if not safe.is_empty():target=safe.point
	for delta: Vector3 in [Vector3(.14,0,0),Vector3(-.14,0,0),Vector3(0,0,.14),Vector3(0,0,-.14),Vector3(.10,0,.10),Vector3(-.10,0,-.10)]:
		var at:=origin+delta
		var logical: Vector3=stage.logical_position(at)
		var support: Dictionary={}
		for option: Dictionary in [tile]+movement._neighbors(str(tile.id),who):
			if absf(float(option.h)-float(tile.h))>.01:continue
			if absf(logical.x-float(option.x))<=.48 and absf(logical.z-float(option.z))<=.48:
				support=option;break
		if support.is_empty():continue
		if Vector2(at.x-target.x,at.z-target.z).length()<.10:continue
		if not _flat_support(tile,who,at) or not stage.prop_point_clear(at,who) or not stage.prop_segment_clear(at,target,who):continue
		at.y=stage.tile_position(tile).y+.018
		return {"point":at,"support":str(support.id)}
	return {}
func _validate(id: String,who: String,phase: String,parent: Node3D,layout: Dictionary) -> void:
	var body: CharacterBody3D = stage.get_actor_body(who)
	var tile: Dictionary = session.world.point_for(str(session.world.state.actors[who]))
	var center: Vector3 = stage.tile_position(tile)
	var logical: Vector3 = stage.logical_position(body.position)-stage.logical_position(center)
	check(absf(logical.x)<.5 and absf(logical.z)<.5,id+" "+who+" "+phase+" same logical support")
	var capsule: CapsuleShape3D = body.get_node("Collision").shape
	var base_y: float = stage.support_height(body.position,str(tile.id),who)
	var supported := true
	for ring: float in [0,.5,1.0]:
		for sector in range(16):
			var probe := body.position+Vector3(cos(sector*TAU/16),0,sin(sector*TAU/16))*capsule.radius*ring
			var hit := false
			for key: String in stage._surfaces:
				var surface: Node3D = stage._surfaces[key]
				var definition: Dictionary=stage._tile_map.get(key,{})
				if not surface.is_visible_in_tree() or bool(definition.get("solid",false)) or (who=="luvie" and bool(definition.get("small",false))):continue
				var local := surface.to_local(probe)
				if absf(local.x)>.5001 or absf(local.z)>.5001: continue
				if absf(float(surface.sample_height(probe))-base_y)>.025: continue
				hit = true; break
			if not hit: supported = false
	check(supported,id+" "+who+" "+phase+" full capsule real flat support")
	check(absf(body.position.y-base_y)<.08,id+" "+who+" "+phase+" contacts ground")
	var delta: Vector3 = body.position-parent.global_position-layout.shift-Vector3(0,0,.07)
	var half: float = .4*layout.width/1.16
	var distance := Vector2(maxf(absf(delta.x)-half,0),maxf(absf(delta.z)-half,0)).length()
	check(distance>=capsule.radius,id+" "+who+" "+phase+" clears planter base")
	check(stage.prop_physical_point_clear(body.position,who),id+" "+who+" "+phase+" clears every hard base")
	for action: String in (["","repair"] if who == "luvie" else [""]):
		stage.update_actor_visual(who,Vector3.ZERO,"front",action)
		var metric := _occlusion(parent,who)
		measurements.append({"level":id,"actor":who,"phase":phase,"completed":session.world.state.completed,"action":action,"position":str(body.position),"opaque":metric,"clearance":distance})
		check(metric.samples>100,id+" "+who+" source coverage")
		check(metric.face_samples>=24,id+" "+who+" real face sampled")
		# Normal foreground overlap of a leg is allowed by the current 71/75
		# contract. Physical entry is checked above; hats alone are not faces.
		check(metric.head_fraction == 0 and metric.face_fraction == 0,id+" "+who+" "+phase+" "+action+" head and face clear of opaque flower")
		check(not body.get_node("Visual/Art").no_depth_test,id+" "+who+" real depth")
		if who == "luvie" and action == "repair":
			var art: AnimatedSprite3D = body.get_node("Visual/Art")
			for frame in range(1,art.sprite_frames.get_frame_count(art.animation)):
				art.set_frame_and_progress(frame,0.5)
				var animated := _occlusion(parent,who)
				check(animated.head_fraction == 0 and animated.face_fraction == 0,id+" "+phase+" repair frame "+str(frame)+" head and face clear of opaque flower")
	stage.update_actor_visual(who,Vector3.ZERO,"front","")
func _occlusion(parent: Node3D,who: String) -> Dictionary:
	var plant: Sprite3D = parent.get_child(0)
	var actor: AnimatedSprite3D = stage.get_actor_body(who).get_node("Visual/Art")
	var texture: Texture2D = actor.sprite_frames.get_frame_texture(actor.animation,actor.frame)
	var actor_image: Image = texture.get_image() if who == "luvie" else null
	var plant_image := plant.texture.get_image()
	# Buddy source at(64,107), scale92/48: conservative cap/body/leaf bounds.
	var bounds: Rect2i = actor_image.get_used_rect() if actor_image != null else Rect2i(24,14,88,99)
	var normal := plant.global_basis.z.normalized()
	var ray := Vector3(.61237244,.5,.61237244)
	var sampled := 0; var occluded := 0; var head_samples := 0; var head_occluded := 0
	var face_samples:=0;var face_occluded:=0
	# The buddy's eyes are around y82, below the cap-only top-40% region.
	var face_bounds:=Rect2i(40,70,48,27) if who=="buddy" else Rect2i(bounds.position+Vector2i(bounds.size.x*.25,bounds.size.y*.32),Vector2i(bounds.size.x*.5,bounds.size.y*.34))
	for y in range(bounds.position.y,bounds.end.y,3):
		for x in range(bounds.position.x,bounds.end.x,3):
			if actor_image != null and actor_image.get_pixel(x,y).a<.5: continue
			var local := Vector3(x-texture.get_width()*.5+actor.offset.x,texture.get_height()*.5-y+actor.offset.y,0)*actor.pixel_size
			var point := actor.to_global(local)
			var head := y<bounds.position.y+bounds.size.y*.4
			var face:=face_bounds.has_point(Vector2i(x,y))
			sampled += 1
			if head: head_samples += 1
			if face:face_samples+=1
			var distance := (plant.global_position-point).dot(normal)/ray.dot(normal)
			if distance<=0: continue
			var hit := plant.to_local(point+ray*distance)
			var ix := int(hit.x/plant.pixel_size+plant.texture.get_width()*.5-plant.offset.x)
			var iy := int(plant.texture.get_height()*.5+plant.offset.y-hit.y/plant.pixel_size)
			if ix<0 or ix>=plant_image.get_width() or iy<0 or iy>=plant_image.get_height(): continue
			if plant_image.get_pixel(ix,iy).a<.5: continue
			occluded += 1
			if head: head_occluded += 1
			if face:face_occluded+=1
	return {"body_fraction":float(occluded)/maxi(1,sampled),"head_fraction":float(head_occluded)/maxi(1,head_samples),"face_fraction":float(face_occluded)/maxi(1,face_samples),"samples":sampled,"face_samples":face_samples}
