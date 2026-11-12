extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
const Dressing=preload("res://presentation/native/original_garden_dressing.gd")
const P=preload("res://presentation/native/original_scenery_placement.gd")
var checks:=0
var failures: Array[String]=[]
var rows: Array=[]
func _initialize()->void:call_deferred("_run")
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _run()->void:
	var stage:=Stage.new();root.add_child(stage)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id: String in Dressing.SOURCE_PROPS:
		if id=="1-1":continue # Approved hand-authored layout is intentionally untouched.
		var initial:=World.new(id)
		var snapshots: Array=[initial.snapshot()]
		for entry: Dictionary in fixture.cases:
			if str(entry.name)!="authored/"+id:continue
			for step: Dictionary in entry.steps:
				if str(step.command.kind)=="act":snapshots.append(step.snapshot)
			if not entry.steps.is_empty():snapshots.append(entry.steps.back().snapshot)
		if id in ["1-3","2-3"]:
			for turn in range(4):
				var variant: Dictionary=initial.snapshot().duplicate(true)
				variant.turns["garden" if id=="1-3" else "stage"]=turn
				snapshots.append(variant)
		if id=="2-1":
			for water in range(3):
				var variant: Dictionary=initial.snapshot().duplicate(true)
				variant.water=water
				snapshots.append(variant)
		var seen: Dictionary={}
		var starting: Dictionary={}
		for snapshot: Dictionary in snapshots:
			var world:=World.new(id,snapshot)
			var key:=hash([world.state.get("turns",{}),world.state.get("flags",[]),world.state.get("water",0),world.state.get("completed",false)])
			if seen.has(key):continue
			seen[key]=true
			var before: Dictionary=world.snapshot().duplicate(true)
			stage.set_world(world);await process_frame
			check(world.snapshot()==before,id+" presentation preserves rules and saves")
			var ctx:=P.prepare(stage)
			var count:=0
			for node in stage._props.get_children():
				if not node is Sprite3D or not node.has_meta("original_scenery_index"):continue
				var index:=int(node.get_meta("original_scenery_index"))
				var alias:=str(node.get_meta("original_scenery_alias"))
				var width: float=node.pixel_size*node.texture.get_width()
				var r:=P.radius(alias,width)
				var at: Vector3=node.position-Vector3.UP*.008
				var source: Vector3=node.get_meta("original_scenery_position")
				var support:=str(node.get_meta("original_scenery_support"))
				check(ctx.fixed.has(support),id+"/"+str(index)+" physical fixed support")
				check(P.supported(stage,at,r,ctx),id+"/"+str(index)+" complete asymmetric base support")
				check(P.clear(at,r,alias,ctx),id+"/"+str(index)+" clear actual core, interaction, spawn, stairs and current/future docks")
				# Independent dense samples detect small unsupported strips that a
				# correct centre or the old last-five-percent foot could overlook.
				for ix in range(9):
					for iz in range(9):
						var probe:=at+Vector3(lerpf(-r,r,ix/8.0),0,lerpf(-r,r,iz/8.0))
						var logical: Vector3=stage.logical_position(probe)
						var key_id:="f:%d:%d"%[roundi(logical.x),roundi(logical.z)]
						check(ctx.fixed.has(key_id) and absf(stage.support_height(probe,key_id)-at.y)<.012,id+" complete footprint sample "+str(index))
				check(is_equal_approx(float(stage._tile_map[support].h),source.y),id+"/"+str(index)+" no hidden height migration")
				check(not node.no_depth_test,id+" original normal world depth")
				for who: String in ["luvie","buddy"]:
					var actor: CharacterBody3D=stage.get_actor_body(who)
					if not actor.visible or absf(actor.position.y-at.y)>.1:continue
					var capsule: CapsuleShape3D=actor.get_node("Collision").shape
					var actor_at:=Vector2(actor.position.x,actor.position.z)
					var nearest:=actor_at.clamp(Vector2(at.x-r,at.z-r),Vector2(at.x+r,at.z+r))
					check(actor_at.distance_to(nearest)>capsule.radius,id+"/"+str(index)+" actual "+who+" capsule clear of complete footprint")
				if index>=0:
					count+=1
					var original: Array=Dressing.SOURCE_PROPS[id][index]
					check(alias==str(original[0]) and is_equal_approx(width,Dressing.canvas_width(float(original[4]))),id+" original identity and approved width unchanged")
				else:check(id=="1-2" and is_equal_approx(width,Dressing.canvas_width(30)),"all reviewed second-garden extras retained at same size")
				ctx.occupied.append({"at":Vector2(at.x,at.z),"y":at.y,"radius":r})
				var stable_key:=str(index)+"/"+alias+"/"+str(node.name)
				if seen.size()==1:starting[stable_key]=node.position
				elif starting.has(stable_key):check(node.position.is_equal_approx(starting[stable_key]),id+" stable decoration across rule changes "+stable_key)
				var reference: Vector3=node.get_meta("original_scenery_reference_position",source)
				rows.append({"level":id,"state":seen.size(),"index":index,"asset":alias,"source":[reference.x,reference.y,reference.z],"layout_reference":[source.x,source.y,source.z],"at":[at.x,node.position.y,at.z],"support":support,"width":width,"radius":r,"reason":str(node.get_meta("original_scenery_migration")),"contact":str(node.get_meta("original_scenery_contact_kind"))})
			var deferred: Array=stage._props.get_meta("original_deferred_scenery",[])
			check(count+deferred.size()==Dressing.SOURCE_PROPS[id].size(),id+" no source instance deleted to satisfy clearance")
			var cached: Array=[]
			for node in stage._props.get_children():
				if node.has_meta("original_scenery_index"):cached.append(node.get_instance_id())
			stage.refresh_world(world)
			var after: Array=[]
			for node in stage._props.get_children():
				if node.has_meta("original_scenery_index"):after.append(node.get_instance_id())
			check(cached==after,id+" warm refresh keeps placement nodes and textures")
			var prior_searches:=P.searches
			var prior_hits:=P.cache_hits
			stage._props_signature=0
			stage.refresh_world(world)
			check(P.searches==prior_searches,id+" forced card rebuild does not rerun same placement search/sort")
			check(P.cache_hits>prior_hits or count==0,id+" forced card rebuild reuses final placement cache")
	check(P.searches==0,"all tested production states use explicit verified placements without runtime candidate search/sort")
	var file:=FileAccess.open("res://../.tmp/placement-audit/placement-test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"gpuVerified":false},"  "))
	print(JSON.stringify({"checks":checks,"failures":failures,"instances":rows.size(),"gpuVerified":false}))
	stage.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
