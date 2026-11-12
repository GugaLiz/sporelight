extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const Cloud=preload("res://core/cloud_garden_world.gd")
const D=preload("res://presentation/native/original_cloud_dressing.gd")
var stage
var ray=Vector3(.61237244,.5,.61237244)
func _initialize():call_deferred("run")
func run():
	stage=Stage.new();root.add_child(stage);stage.set_process(false)
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"));var saved={}
	for entry in fixture.levels:
		if entry.id=="cloud-2":saved=entry.steps[-1].snapshot
	stage.set_world(Cloud.new("cloud-2",saved));await process_frame
	for who in ["luvie","buddy"]:stage.update_actor_visual(who,Vector3.ZERO,"front","")
	var card=stage._props_nodes["mark:bird"].get_node("Original_story_flowers")
	var base=card.position-card.get_meta("display_offset")
	var bird
	for prop in stage._props.get_children():
		if prop.get_meta("original_kind","")=="bird":bird=prop.get_child(0)
	var covers=[]
	for who in ["luvie","buddy"]:
		var node=stage.get_actor_body(who).get_node("Visual/Art")
		var texture=node.sprite_frames.get_frame_texture(node.animation,node.frame)
		covers.append({"who":who,"node":node,"texture":texture,"image":texture.get_image() if who=="luvie" else null})
	var output=[]
	for ix in range(-65,-54):
		for iz in range(16,25):
			var offset=Vector3(ix*.01,0,iz*.01);card.position=base+offset
			var foot_ok=true
			var origin=card.global_position-D.FRONT*(float(card.get_meta("source_foot"))*2*D.PIXEL)
			for index in range(3):
				var foot=origin+D.RIGHT*(sin(index*8.0)*13*D.PIXEL)+D.FRONT*(cos(index*3.0)*10*D.PIXEL)
				for side in range(8):
					var probe=foot+Vector3(cos(side*TAU/8),0,sin(side*TAU/8))*.025
					var key="floor:%d:%d"%[roundi(probe.x),roundi(probe.z)]
					if not stage._surfaces.has(key) or absf(stage.support_height(probe,key)-probe.y)>.001:foot_ok=false
				for at in [Vector2(10,5),Vector2(11,5),Vector2(10.77,5.2)]:
					if at.distance_to(Vector2(foot.x,foot.z))<.215:foot_ok=false
			if not foot_ok:continue
			var overlap=0
			for cover in covers:
				for x in ([10.0,11.0] if cover.who=="luvie" else [10.0]):
					stage.get_actor_body(cover.who).position=Vector3(x,1.95,5)
					overlap+=count_overlap(card,cover.node,cover.texture,cover.image,cover.who=="buddy")
			var bird_overlap=count_overlap(card,bird,bird.texture,bird.texture.get_image(),false)
			output.append({"x":offset.x,"z":offset.z,"actorOverlap":overlap,"birdOverlap":bird_overlap})
	output.sort_custom(func(a,b):return a.actorOverlap+a.birdOverlap<b.actorOverlap+b.birdOverlap if a.actorOverlap+a.birdOverlap!=b.actorOverlap+b.birdOverlap else Vector2(a.x+.4,a.z-.1).length_squared()<Vector2(b.x+.4,b.z-.1).length_squared())
	var file=FileAccess.open("res://../.tmp/placement-audit/cloud-story-candidates.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "))
	print(JSON.stringify(output.slice(0,15)));stage.free();quit()
func count_overlap(subject,cover,texture,cover_image,buddy):
	var image=subject.texture.get_image();var count=0
	var normal=cover.global_basis.z.normalized()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a<.5:continue
			var local=Vector3(x-image.get_width()*.5+subject.offset.x,image.get_height()*.5-y+subject.offset.y,0)*subject.pixel_size
			var world=subject.to_global(local)
			var distance=(cover.global_position-world).dot(normal)/ray.dot(normal)
			var hit=cover.to_local(world+ray*distance)
			var ix=int(hit.x/cover.pixel_size+texture.get_width()*.5-cover.offset.x)
			var iy=int(texture.get_height()*.5+cover.offset.y-hit.y/cover.pixel_size)
			if buddy:
				if Rect2i(24,14,88,99).has_point(Vector2i(ix,iy)):count+=1
			elif ix>=0 and iy>=0 and ix<cover_image.get_width() and iy<cover_image.get_height() and cover_image.get_pixel(ix,iy).a>=.5:count+=1
	return count
