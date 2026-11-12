extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
var stage
var right:Vector3
var up:Vector3
var ray=Vector3(.61237244,.5,.61237244)
func _initialize():call_deferred("run")
func run():
	stage=Stage.new();root.add_child(stage);stage.set_process(false)
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var results=[]
	for id in ["1-4","2-4","3-4"]:
		var state={}
		for case in fixture.cases:
			if case.name=="authored/"+id:state=case.steps.back().snapshot
		stage.set_world(World.new(id,state));await process_frame
		stage.update_actor_visual("buddy",Vector3.ZERO,"front","")
		right=stage._camera.global_basis.x.normalized();up=stage._camera.global_basis.y.normalized()
		var index=18 if id=="1-4" else 0 if id=="2-4" else 3
		var lantern:Sprite3D=find_prop(index)
		var final=lantern.position
		for phase in ["before","candidate"]:
			lantern.position=Vector3(-6.74,.658,-1.64) if id=="1-4" else Vector3(10,.008,.64) if id=="2-4" else Vector3(-4.74,.008,1)
			if phase=="candidate":lantern.position=final
			if id=="1-4":
				var lotus:Sprite3D=find_prop(15)
				var saved=lotus.position
				if phase=="before":lotus.position=Vector3(-7,.658,-2)
				results.append({"level":id,"phase":phase,"lotus_hidden_by_lamp":occlusion(lotus,lotus.texture,lantern),"lamp_hidden_by_lotus":occlusion(lantern,lantern.texture,lotus)})
				lotus.position=saved
			elif id=="2-4":
				var buddy=stage.get_actor_body("buddy").get_node("Visual/Art")
				var texture=buddy.sprite_frames.get_frame_texture(buddy.animation,buddy.frame)
				results.append({"level":id,"phase":phase,"buddy_hidden_by_lamp":occlusion(buddy,texture,lantern,true),"buddyPosition":str(stage.get_actor_body("buddy").position)})
			else:
				var core=stage._props_nodes["mark:core"].get_child(0)
				results.append({"level":id,"phase":phase,"lamp_hidden_by_core_paint":occlusion(lantern,lantern.texture,core)})
		lantern.position=final
	var file=FileAccess.open("res://../.tmp/placement-audit/visual-projection.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"CPU projected source-alpha and actual mesh rays; not GPU","rows":results},"  "))
	print(JSON.stringify(results));stage.free();quit()
func find_prop(index):
	for node in stage._props.get_children():
		if node.has_meta("original_scenery_index") and int(node.get_meta("original_scenery_index"))==index:return node
	return null
func point(node,texture,x,y):
	var local=Vector3(x-texture.get_width()*.5+node.offset.x,texture.get_height()*.5-y+node.offset.y,0)*node.pixel_size
	if node.billboard==BaseMaterial3D.BILLBOARD_ENABLED:
		var scale=node.global_basis.get_scale()
		return node.global_position+right*local.x*scale.x+up*local.y*scale.y
	return node.to_global(local)
func occlusion(subject,texture,occluder,buddy=false):
	var source=null if buddy else texture.get_image();var cover=occluder.texture.get_image()
	var bounds=Rect2i(24,14,88,99) if buddy else source.get_used_rect()
	var count=0;var hidden=0;var head=0;var hidden_head=0
	for y in range(bounds.position.y,bounds.end.y,3):
		for x in range(bounds.position.x,bounds.end.x,3):
			if not buddy and source.get_pixel(x,y).a<.5:continue
			var world:Vector3=point(subject,texture,x,y)
			count+=1;var is_head=y<bounds.position.y+bounds.size.y*.4
			if is_head:head+=1
			var normal=ray if occluder.billboard==BaseMaterial3D.BILLBOARD_ENABLED else occluder.global_basis.z.normalized()
			var distance=(occluder.global_position-world).dot(normal)/ray.dot(normal)
			if distance<=0:continue
			var hit=world+ray*distance-occluder.global_position
			var scale=occluder.global_basis.get_scale()
			var local=Vector3(hit.dot(right)/scale.x,hit.dot(up)/scale.y,0) if occluder.billboard==BaseMaterial3D.BILLBOARD_ENABLED else occluder.to_local(world+ray*distance)
			var ix=int(local.x/occluder.pixel_size+cover.get_width()*.5-occluder.offset.x)
			var iy=int(cover.get_height()*.5+occluder.offset.y-local.y/occluder.pixel_size)
			if ix<0 or iy<0 or ix>=cover.get_width() or iy>=cover.get_height():continue
			if cover.get_pixel(ix,iy).a<.5:continue
			hidden+=1
			if is_head:hidden_head+=1
	return {"samples":count,"hidden":hidden,"headSamples":head,"headHidden":hidden_head}
func mesh_occlusion(subject,parent):
	var faces=[];var pending=[parent]
	while not pending.is_empty():
		var node=pending.pop_back();pending.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh!=null:
			var vertices=node.mesh.get_faces()
			for i in range(0,vertices.size(),3):faces.append([node.to_global(vertices[i]),node.to_global(vertices[i+1]),node.to_global(vertices[i+2])])
	var source=subject.texture.get_image();var bounds=source.get_used_rect();var count=0;var hidden=0;var head=0;var hidden_head=0
	for y in range(bounds.position.y,bounds.end.y,4):
		for x in range(bounds.position.x,bounds.end.x,4):
			if source.get_pixel(x,y).a<.5:continue
			var world:Vector3=point(subject,subject.texture,x,y);count+=1
			var is_head=y<bounds.position.y+bounds.size.y*.5
			if is_head:head+=1
			for face in faces:
				if Geometry3D.ray_intersects_triangle(world+ray*.001,ray,face[0],face[1],face[2])!=null:
					hidden+=1
					if is_head:hidden_head+=1
					break
	return {"samples":count,"hidden":hidden,"upperHalfSamples":head,"upperHalfHidden":hidden_head}
