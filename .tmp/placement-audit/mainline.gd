extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
const Art=preload("res://presentation/native/original_garden_dressing.gd")
var rows=[]
var feet={}
func _initialize():call_deferred("run")
func run():
	var stage=Stage.new();root.add_child(stage)
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id in Art.SOURCE_PROPS:
		var states={"initial":{}}
		for case in fixture.cases:
			if str(case.name)=="authored/"+id and not case.steps.is_empty():states["completed"]=case.steps.back().snapshot
		for phase in states:
			var world=World.new(id,states[phase]);stage.set_world(world)
			await process_frame
			for node in stage._props.get_children():
				if not node is Sprite3D:continue
				if not node.has_meta("original_scenery_index"):continue
				var alias=str(node.get_meta("original_scenery_alias"));var width=node.texture.get_width()*node.pixel_size
				var radius=Art.foot_radius(alias,width);var support=str(node.get_meta("original_scenery_support"))
				var at=node.position;var gaps=[];var marks=[];var actors=[];var lanes=[]
				for ix in range(11):
					for iz in range(11):
						var p=at+Vector3(lerpf(-radius,radius,ix/10.0),0,lerpf(-radius,radius,iz/10.0))
						var logical=stage.logical_position(p);var found=false
						for t in stage._tiles:
							if not Art._fixed_support(stage,t):continue
							if absf(logical.x-float(t.x))<.5 and absf(logical.z-float(t.z))<.5 and absf(stage.support_height(p,t.id)-(at.y-.008 if id!="1-2" else at.y-.015))<.012:found=true;break
						if not found:gaps.append([ix,iz])
				for mark in world.level.get("marks",[]):
					if not stage._tile_map.has(mark.tile):continue
					var p=stage.tile_position_id(mark.tile)
					if absf(at.y-p.y)>.1:continue
					var d=Vector2(at.x-p.x,at.z-p.z).length()
					if d<radius+.6:marks.append({"id":mark.id,"kind":mark.kind,"distance":d})
				for who in ["luvie","buddy"]:
					var p=stage.get_actor_body(who).position
					var d=Vector2(at.x-p.x,at.z-p.z).length()
					if absf(at.y-p.y)<.1 and d<radius+.2:actors.append({"who":who,"distance":d})
				var core_intersection=false
				var core=stage._props_nodes.get("mark:core")
				if core:
					for plant in core.get_children():
						if not plant.has_meta("core_planter"):continue
						var p=core.to_global(plant.get_meta("ground_footprint_center"));var span=plant.get_meta("ground_footprint_span")
						if absf(at.y-p.y)<.1 and absf(at.x-p.x)<span.x*.5+radius and absf(at.z-p.z)<span.y*.5+radius:core_intersection=true
				for t in stage._tiles:
					if str(t.id)!=support:continue
					for near in world.neighbors(support,"luvie",stage._tiles):
						var p=stage.tile_position(t);var q=stage.tile_position(near)
						var v=Vector2(q.x-p.x,q.z-p.z);var w=Vector2(at.x-p.x,at.z-p.z)
						if v.length_squared()<.001:continue
						var along=clampf(w.dot(v)/v.length_squared(),0,1);var d=(w-v*along).length()
						if d<radius+.16:lanes.append({"to":near.id,"clearance":d-radius-.16,"heightDelta":q.y-p.y})
				if not feet.has(alias):
					var image=node.texture.get_image();var bottom=int(Art.SOURCE_FEET[alias][4]);var ranges=[]
					for fraction in [.05,.15,.25]:
						var left=9999;var right=-1
						for y in range(maxi(0,bottom-int(image.get_height()*fraction)),bottom+1):
							for x in range(image.get_width()):
								if image.get_pixel(x,y).a>=.25:left=mini(left,x);right=maxi(right,x)
						ranges.append([fraction,left,right])
					feet[alias]=ranges
				rows.append({"level":id,"phase":phase,"index":node.get_meta("original_scenery_index"),"asset":alias,"at":[at.x,at.y,at.z],"support":support,"visible":node.visible,"radius":radius,"gaps":gaps,"near_marks":marks,"actor_intersections":actors,"core_intersection":core_intersection,"center_lane_risks":lanes})
	FileAccess.open("res://../.tmp/placement-audit/mainline.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"foot_bands":feet},"  "))
	print("audit rows ",rows.size());stage.queue_free();await process_frame;quit()
