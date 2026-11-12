extends "res://tests/native_route_test.gd"
## Full stone feet, source size and legal stances. GPU opacity/occlusion review
## remains separate; these tests never certify how a painted silhouette looks.
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
var inspected := 0
var foot_samples := 0
var source_bounds: Dictionary={}

func _painted_projection(art: AnimatedSprite3D,texture: Texture2D,who: String) -> Rect2:
	# A headless ViewportTexture contains no painted pixels. Use the existing
	# BuddyCanvas cap/body/leaf envelope, not its full transparent 128px card.
	var bounds := Rect2(24,14,88,99)
	if who=="luvie":
		if not source_bounds.has(texture):
			var picture: Image=texture.get_image()
			if picture.is_compressed(): picture.decompress()
			var minimum:=Vector2(INF,INF)
			var maximum:=Vector2(-INF,-INF)
			for y in range(picture.get_height()):
				for x in range(picture.get_width()):
					if picture.get_pixel(x,y).a<.5: continue
					minimum=minimum.min(Vector2(x,y))
					maximum=maximum.max(Vector2(x+1,y+1))
			source_bounds[texture]=Rect2(minimum,maximum-minimum)
		bounds=source_bounds[texture]
	var minimum:=Vector2(INF,INF)
	var maximum:=Vector2(-INF,-INF)
	for pixel: Vector2 in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
		var local:=Vector3(pixel.x-texture.get_width()*.5+art.offset.x,texture.get_height()*.5-pixel.y+art.offset.y,0)*art.pixel_size
		var point: Vector3=art.to_global(local)
		if art.billboard==BaseMaterial3D.BILLBOARD_ENABLED:
			point=art.global_position+app.view._camera.global_basis.x.normalized()*local.x+app.view._camera.global_basis.y.normalized()*local.y
		var projected: Vector2=app.view.world_to_screen(point)
		minimum=minimum.min(projected)
		maximum=maximum.max(projected)
	return Rect2(minimum,maximum-minimum)

func _operator_projection(tile_id: String,label: String) -> void:
	var tile: Dictionary=app.session.world.point_for(tile_id)
	var boxes: Array[Rect2]=[]
	for who: String in ["luvie","buddy"]:
		var body: CharacterBody3D=app.view.get_actor_body(who)
		var remembered: Vector3=body.position
		body.position=app.view.actor_rest_position(tile,who)
		var safe: Dictionary=app.view.prop_waypoint(tile,who,body.position)
		_check(not safe.is_empty() and (safe.point as Vector3).distance_to(body.position)<.001,label+"/"+who+" authored stance is fully supported and clear")
		app.view.update_actor_visual(who,Vector3.ZERO,"front","")
		var art: AnimatedSprite3D=body.get_node("Visual/Art")
		var texture: Texture2D=art.sprite_frames.get_frame_texture(art.animation,art.frame)
		boxes.append(_painted_projection(art,texture,who))
		body.position=remembered
	_check(minf(boxes[0].end.x,boxes[1].end.x)<=maxf(boxes[0].position.x,boxes[1].position.x),label+" default operators have separate projected silhouettes")

func _verify_planters(label: String) -> void:
	for key: String in app.view._props_nodes:
		var root_node: Node3D=app.view._props_nodes[key]
		for child: Node in root_node.get_children():
			if not child is Sprite3D or not child.has_meta("hard_planter"): continue
			inspected+=1
			if not label.contains("rotation"):
				_operator_projection(str(root_node.get_meta("tile_id")),label+"/"+key)
			var span: Vector2=child.get_meta("ground_footprint_span")
			var expected: float=Ratios.canvas_width("flower",str(app.session.world.level.id))
			_check(is_equal_approx(child.pixel_size*child.texture.get_width(),expected),label+"/"+key+" retains original 55px canvas size")
			_check(span.is_equal_approx(Vector2.ONE*(.8*expected/1.16)),label+"/"+key+" complete masonry foot is not reduced to clear an actor")
			_check(not child.no_depth_test and is_equal_approx(child.modulate.a,1) and not child in app.view._occluders,label+"/"+key+" masonry stays opaque with ordinary depth")
			var base: StaticBody3D=child.get_node_or_null("FlowerStoneFoot")
			_check(base!=null and base.collision_layer==8,label+"/"+key+" has an actual local hard base")
			if base==null: continue
			var shape: BoxShape3D=base.get_node("BaseVolume").shape
			if root_node.has_meta("flower_fixed_center"):
				var fixed: Vector3=root_node.get_meta("flower_fixed_center")
				var anchor: Vector3=child.get_meta("planter_anchor")
				_check(child.global_position.distance_to(fixed+anchor-Vector3(0,0,.07))<.001,label+" fixed shore art does not ride the stage")
				_check(base.global_position.distance_to(fixed+Vector3(0,shape.size.y*.5,0))<.001,label+" fixed shore collider does not ride the stage")
				_check(root_node.has_node("FlowerPlatformRing") and root_node.has_node("FlowerPlatformSymbol"),label+" original stage centre retains a visible boarding cue")
			var supported := true
			for ix in range(7):
				for iz in range(7):
					var point: Vector3=base.to_global(Vector3(lerpf(-shape.size.x*.5,shape.size.x*.5,ix/6.0),-shape.size.y*.5,lerpf(-shape.size.z*.5,shape.size.z*.5,iz/6.0)))
					foot_samples+=1
					var found := false
					for surface_key: String in app.view._surfaces:
						var surface: Node3D=app.view._surfaces[surface_key]
						if not surface.is_visible_in_tree(): continue
						var local: Vector3=surface.to_local(point)
						if absf(local.x)<=.5001 and absf(local.z)<=.5001 and absf(surface.sample_height(point)-point.y)<.025: found=true;break
					if not found: supported=false
			_check(supported,label+"/"+key+" entire rigid stone foot has real support")

func _stage_arms(fixture: Dictionary) -> void:
	for raised: bool in [false,true]:
		for turn in range(4):
			var saved: Dictionary=fixture.initial.snapshot.duplicate(true)
			saved.turns.stage=turn
			if raised: saved.flags.append("raised")
			saved.actors.luvie="m:stage:0:0"
			saved.follow=false
			app.session=null
			app.repository.data.mainline.runs["2-3"]=saved
			app._enter_level("2-3")
			await _tick()
			var label: String="2-3/arms/"+str(turn)+"/raised="+str(raised)
			# Inspect the two canonical operator poses in the actual isometric
			# projection, not just their physical distance on the floor.
			_operator_projection("m:stage:0:0",label)
			# Prepared geometry states exercise all four orientations at both
			# elevations. Raising/turning permission is still tested by the
			# original authored route, never inferred from this setup.
			for tip: String in ["m:stage:-2:0","m:stage:0:2"]:
				_check(await _walk_to(tip,label+"/out/"+tip),label+" reaches original arm tip "+tip)
				var shores: Array=app.session.world.neighbors(tip,"luvie")
				for shore: Dictionary in shores:
					if str(shore.id).begins_with("m:stage:"): continue
					_check(await _walk_to(str(shore.id),label+"/disembark"),label+" walks onto original connected shore")
					_check(await _walk_to(tip,label+"/board"),label+" reboards through original connection")
				_check(await _walk_to("m:stage:0:0",label+"/return"),label+" leaves arm and returns to original centre")

func _run() -> void:
	_setup()
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json")).cases
	for fixture: Dictionary in fixtures:
		var id: String=str(fixture.get("levelId",""))
		if not id in ["1-4","2-1","2-3","2-4","3-3"] or str(fixture.name)!="authored/"+id: continue
		var actions: Array=fixture.steps.filter(func(step: Dictionary) -> bool: return str(step.command.kind)=="act" and not str(step.command.value) in ["repair","switch","follow"])
		var states: Array=[fixture.initial.snapshot,actions[actions.size()/2].snapshot,fixture.steps[-2].snapshot]
		for index: int in range(states.size()):
			app.session=null
			app.repository.data.mainline.runs[id]=states[index].duplicate(true)
			app._enter_level(id)
			await _tick()
			_verify_planters(id+"/"+str(index))
			for who: String in ["luvie","buddy"]:
				var body: CharacterBody3D=app.view.get_actor_body(who)
				_check(app.view.prop_physical_point_clear(body.position,who),id+"/"+str(index)+"/"+who+" real stance does not enter stone")
		if id!="2-3": continue
		var previous: Dictionary=fixture.initial.snapshot
		for step: Dictionary in fixture.steps:
			if int(previous.turns.stage)!=int(step.snapshot.turns.stage) or ("raised" in previous.flags)!=("raised" in step.snapshot.flags):
				for progress: float in [0.0,.25,.5,.75,1.0]:
					app.view.set_motion(previous,step.snapshot,progress,"turn:stage")
					_verify_planters("2-3/rotation/"+str(progress))
				app.view.clear_motion(false)
			previous=step.snapshot
		await _stage_arms(fixture)
	print(JSON.stringify({"suite":"native-small-planter","checks":checks,"passed":failures.is_empty(),"failures":failures,"planters":inspected,"physicalFootSamples":foot_samples,"gpuPixelsVerified":false}))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
