extends SceneTree
## Original cloud small-object layout: complete support and fixed clearances.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Art = preload("res://presentation/native/original_cloud_art.gd")
const D = preload("res://presentation/native/original_cloud_dressing.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var stage: Node2D
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	stage = Stage.new(); root.add_child(stage); stage.set_process(false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for entry: Dictionary in fixture.levels:
		for saved: Dictionary in [{},entry.steps[-1].snapshot]:
			var world := Cloud.new(str(entry.id),saved)
			stage.set_world(world)
			var before: Dictionary = world.snapshot()
			var flower_count := 0
			var obstacles := _obstacles(world)
			for prop: Node3D in stage._props.get_children():
				var kind := str(prop.get_meta("original_kind",""))
				if kind != "flowers": continue
				flower_count += 1
				var card: Sprite3D = prop.get_child(0)
				var label := str(entry.id)+"/"+str(prop.name)
				var source: Vector3 = prop.get_meta("original_point")
				check((int(source.x)*7+int(source.z)*13)%11 == 0,label+" retains authored source identity")
				check(card.texture == Art.art("flowers").texture,label+" retains original complete bouquet")
				check(is_equal_approx(card.pixel_size*2,sqrt(2.0)/58.0),label+" frozen source size")
				var footprint := _bouquet(card,5)
				_support(footprint,card.global_position.y,label)
				for obstacle: Dictionary in obstacles:
					if absf(float(obstacle.y)-card.global_position.y)>.01: continue
					check(Geometry2D.intersect_polygons(footprint,obstacle.footprint).is_empty(),label+" clears "+str(obstacle.id))
				for who: String in ["luvie","buddy"]:
					var tile: Dictionary = world.point_for(str(world.state.actors[who]))
					if absf(float(tile.h)*.65-card.global_position.y)>.01: continue
					var at := Vector2(float(tile.x),float(tile.z))
					check(_distance_to_polygon(at,footprint)>.19,label+" clears completed default "+who)
				rows.append({"level":str(entry.id),"source":str(source),"actualRoot":str(prop.global_position),"support":str(prop.get_meta("support_id")),"kind":kind})
			var expected := world.tiles().filter(func(t: Dictionary) -> bool:return str(t.kind)=="floor" and (int(t.x)*7+int(t.z)*13)%11==0).size() if bool(world.state.completed) else 0
			check(flower_count==expected,str(entry.id)+" no completion flowers removed or duplicated")
			if str(entry.id)=="cloud-1": _finish_pot(world)
			if str(entry.id)=="cloud-2" and bool(world.state.completed): _bird_bouquet()
			check(world.snapshot()==before,str(entry.id)+" layout preserves complete rule snapshot")
			# Move the actor by an otherwise valid source-state edit and rebuild:
			# positions are independent of current occupancy and never jump away.
			var positions := _positions()
			world.state.actors.luvie = str(world.level.start)
			stage.refresh_world(world,true)
			check(_positions()==positions,str(entry.id)+" fixed layout independent of actor position")
	print(JSON.stringify({"suite":"native-cloud-layout","checks":checks,"passed":failures.is_empty(),"failures":failures,"placements":rows,"gpuPixelsVerified":false}))
	stage.free(); quit(0 if failures.is_empty() else 1)

func _positions() -> Dictionary:
	var result := {}
	for prop: Node3D in stage._props.get_children():
		if prop.has_meta("original_kind"): result[str(prop.name)] = prop.global_position
		var story: Sprite3D = prop.get_node_or_null("Original_story_flowers")
		if story != null: result[str(prop.name)+"/story_flowers"] = story.global_position
	return result

func _bouquet(card: Sprite3D,count: int) -> PackedVector2Array:
	var pixel := float(card.get_meta("source_pixel_world"))
	var origin := card.global_position-D.FRONT*(float(card.get_meta("source_foot"))*2*pixel)
	var points := PackedVector2Array()
	for index in range(count):
		var foot := origin+D.RIGHT*(sin(index*8.0)*13*pixel)+D.FRONT*(cos(index*3.0)*5*2*pixel)
		# Entire painted stem width plus a small physical placement margin.
		for sector in range(8): points.append(Vector2(foot.x,foot.z)+Vector2(cos(sector*TAU/8),sin(sector*TAU/8))*.025)
	return Geometry2D.convex_hull(points)

func _support(polygon: PackedVector2Array,y: float,label: String) -> void:
	var valid := true
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: bounds = bounds.expand(point)
	for ix in range(17):
		for iz in range(17):
			var point := bounds.position+bounds.size*Vector2(ix/16.0,iz/16.0)
			if not Geometry2D.is_point_in_polygon(point,polygon): continue
			var foot := Vector3(point.x,y,point.y)
			var found := false
			for id: String in stage._surfaces:
				if not id.begins_with("floor:"): continue
				var surface: Node3D = stage._surfaces[id]
				var local := surface.to_local(foot)
				if absf(local.x)>.5001 or absf(local.z)>.5001: continue
				if absf(float(surface.sample_height(foot))-y)<.001: found = true; break
			if not found: valid = false
	check(valid,label+" complete bouquet footprint supported by fixed same-height floor")

func _diamond(at: Vector3,width: float,depth: float,centre_y: float,pixel: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for corner: Vector2 in [Vector2(-width,centre_y),Vector2(0,centre_y-depth),Vector2(width,centre_y),Vector2(0,centre_y+depth)]:
		var point := at+D.RIGHT*(corner.x*pixel)+D.FRONT*(corner.y*pixel*2)
		result.append(Vector2(point.x,point.z))
	return result

func _obstacles(world: RefCounted) -> Array:
	var result: Array = []
	var sizes := {"arch":Vector3(34,14,1),"arch_pink":Vector3(34,14,1),"tower":Vector3(35,17.5,2),"pool":Vector3(42,21,9),"bench":Vector3(20,10,2),"plant":Vector3(9,4.5,5),"plant_large":Vector3(16,8,9)}
	for prop: Node3D in stage._props.get_children():
		var kind := str(prop.get_meta("original_kind",""))
		if not sizes.has(kind): continue
		var size: Vector3 = sizes[kind]
		var card: Sprite3D = prop.get_child(0)
		result.append({"id":str(prop.name),"y":prop.global_position.y,"footprint":_diamond(prop.global_position,size.x,size.y,size.z,float(card.get_meta("source_pixel_world")))})
	for mark: Dictionary in world.level.marks:
		var prop: Node3D = stage._props_nodes.get("mark:"+str(mark.id))
		if prop==null: continue
		var polygon: PackedVector2Array
		if str(mark.id)=="turn": polygon = _diamond(prop.global_position,13,6.5,5,D.PIXEL)
		elif str(mark.id)=="finish": polygon = _diamond(prop.global_position,16,8,0,D.PIXEL)
		elif str(mark.id)=="pad": polygon = _diamond(prop.global_position,18,10,0,D.PIXEL)
		else: continue
		result.append({"id":"mark:"+str(mark.id),"y":prop.global_position.y,"footprint":polygon})
	return result

func _distance_to_polygon(at: Vector2,polygon: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(at,polygon): return 0
	var distance := INF
	for index in range(polygon.size()):
		distance = minf(distance,at.distance_to(Geometry2D.get_closest_point_to_segment(at,polygon[index],polygon[(index+1)%polygon.size()])))
	return distance

func _finish_pot(world: RefCounted) -> void:
	for prop: Node3D in stage._props.get_children():
		if str(prop.get_meta("original_kind",""))!="plant" or prop.get_meta("original_point",Vector3.ZERO)!=Vector3(11,1,4): continue
		var source: Vector3 = prop.get_meta("original_point")
		check(source==Vector3(11,1,4),"cloud1 finish pot keeps source coordinates")
		var finish: Node3D = stage._props_nodes["mark:finish"]
		var base := _diamond(prop.global_position,9,4.5,5,D.PIXEL)
		_support(base,prop.global_position.y,"cloud1 finish pot")
		# World-axis difference projects horizontally in the fixed camera.
		check(absf((prop.global_position.x-prop.global_position.z)-(finish.global_position.x-finish.global_position.z))>.4,"cloud1 pot separated laterally from finish disc")

func _bird_bouquet() -> void:
	var parent: Node3D = stage._props_nodes["mark:bird"]
	var card: Sprite3D = parent.get_node("Original_story_flowers")
	check(parent.global_position.is_equal_approx(Vector3(11,1.95,5)),"cloud2 bird observation root unchanged")
	check(card.texture==Art.art("story_flowers").texture,"cloud2 retains original three-stem observation flower")
	check(is_equal_approx(card.pixel_size*2,D.PIXEL),"cloud2 story bouquet retains original size")
	var footprint := _bouquet(card,3)
	_support(footprint,parent.global_position.y,"cloud2 bird bouquet")
	for point: Vector2 in [Vector2(10,5),Vector2(11,5),Vector2(10.77,5.2)]:
		check(_distance_to_polygon(point,footprint)>.19,"cloud2 story bouquet clears repair/clear-view default stance "+str(point))
	for prop: Node3D in stage._props.get_children():
		if str(prop.get_meta("original_kind",""))=="bird":
			check(prop.global_position.is_equal_approx(Vector3(11.2,1.95,4.4)),"cloud2 bird position preserved")
			var bird: Sprite3D = prop.get_child(0)
			check(_distance_to_polygon(Vector2(bird.global_position.x,bird.global_position.z),footprint)>.5,"cloud2 bouquet separated from actual bird foot")
			var projected := _paint_overlap(card,bird,bird.texture)
			check(int(projected.overlap)==0,"cloud2 story bouquet and bird source silhouettes are separate")
			rows.append({"level":"cloud-2","projection":"bird","measurement":projected})
	var water: Node3D = stage._props_nodes.original_cloud_waterfall
	check(water.global_position.is_equal_approx(Vector3(11.5,1.95,3)),"cloud2 actual east-edge water outlet preserved")
	# Checking floor footprints alone missed flowers painted over the boots.
	# Both default completion and prepared clear-view stances must separate in
	# screen projection, even where depth would make the overlap invisible.
	for who: String in ["luvie","buddy"]:
		var body: CharacterBody3D = stage.get_actor_body(who)
		var before := body.position
		stage.update_actor_visual(who,Vector3.ZERO,"front","")
		var actor: AnimatedSprite3D = body.get_node("Visual/Art")
		var texture := actor.sprite_frames.get_frame_texture(actor.animation,actor.frame)
		for x: float in ([10.0,11.0] if who=="luvie" else [10.0]):
			body.position=Vector3(x,1.95,5)
			var projected := _paint_overlap(card,actor,texture,who=="buddy")
			check(int(projected.samples)>200,"cloud2 story bouquet full source-alpha sample coverage")
			check(int(projected.overlap)==0,"cloud2 bouquet projection clears "+who+" at floor:"+str(x)+":5")
			rows.append({"level":"cloud-2","projection":who,"actor":str(body.position),"measurement":projected})
		body.position=before

func _paint_overlap(subject: Sprite3D,cover: SpriteBase3D,texture: Texture2D,conservative_buddy := false) -> Dictionary:
	var source := subject.texture.get_image()
	var cover_image: Image = null if conservative_buddy else texture.get_image()
	var ray := Vector3(.61237244,.5,.61237244)
	var normal := cover.global_basis.z.normalized()
	var samples := 0; var overlap := 0
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x,y).a<.5: continue
			var local := Vector3(x-source.get_width()*.5+subject.offset.x,source.get_height()*.5-y+subject.offset.y,0)*subject.pixel_size
			var point := subject.to_global(local)
			var distance := (cover.global_position-point).dot(normal)/ray.dot(normal)
			# Either sign counts: foreground and background stacking are both
			# a composition regression for these three observed flower stems.
			var hit := cover.to_local(point+ray*distance)
			var ix := int(hit.x/cover.pixel_size+texture.get_width()*.5-cover.offset.x)
			var iy := int(texture.get_height()*.5+cover.offset.y-hit.y/cover.pixel_size)
			samples+=1
			if conservative_buddy:
				if Rect2i(24,14,88,99).has_point(Vector2i(ix,iy)): overlap+=1
			elif ix>=0 and iy>=0 and ix<cover_image.get_width() and iy<cover_image.get_height() and cover_image.get_pixel(ix,iy).a>=.5:
				overlap+=1
	return {"samples":samples,"overlap":overlap,"conservativeBuddy":conservative_buddy}
