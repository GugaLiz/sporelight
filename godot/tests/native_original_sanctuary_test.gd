extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Sanctuary = preload("res://presentation/native/original_sanctuary_dressing.gd")
const Dressing = preload("res://presentation/native/original_garden_dressing.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	for id: String in ["1-4","3-4"]:
		var world := World.new(id)
		for state: String in ["initial","opened","completed","undo"]:
			world.state.flags.erase("home")
			world.state.completed = state == "completed"
			if state in ["opened","completed"] and id == "1-4": world.state.flags.append("home")
			var snapshot: Dictionary = world.snapshot().duplicate(true)
			stage.set_world(world)
			await process_frame
			_check(snapshot == world.snapshot(), id+"/"+state+" rendering preserves rules/save")
			var tagged: Array[Node] = []
			for child in stage._props.get_children():
				if child.has_meta("original_sanctuary_support"): tagged.append(child)
			for child: Sprite3D in tagged:
				var support := str(child.get_meta("original_sanctuary_support"))
				var radius := float(child.get_meta("original_sanctuary_foot_radius"))
				var desired: Vector3 = child.get_meta("original_sanctuary_desired")
				_check(stage._surfaces.has(support), id+"/"+state+" physical support "+child.name)
				var gate := str(child.name).begins_with("OriginalSanctuaryGate")
				var full_support: bool = Sanctuary.gate_footprint(stage,child.position,support,radius) if gate else Sanctuary.fountain_footprint(stage,child.position,radius) if child.name=="SanctuaryFountain" else Dressing.flat_footprint(stage,child.position,support,radius)
				_check(full_support, id+"/"+state+" complete same-height footprint "+child.name)
				_check(absf(child.position.y-stage.support_height(child.position,support)-.008)<.0001, "foot meets physical top "+child.name)
				_check(absf(child.position.y-desired.y-.008)<.0001, "no vertical migration "+child.name)
				_check(not child.no_depth_test and child.get_child_count()==0,"normal depth and no added collision "+child.name)
				rows.append({"level":id,"state":state,"node":child.name,"at":[child.position.x,child.position.y,child.position.z],"source_at":[desired.x,desired.y,desired.z],"support":support,"support_visible":stage._surfaces[support].visible,"width":child.pixel_size*child.texture.get_width(),"radius":radius})
			var mole: Sprite3D = stage._props.get_node_or_null("MoleResident")
			_check((mole!=null)==(id=="1-4" or state=="completed"),id+"/"+state+" original mole visibility condition")
			if mole != null:
				_check(is_equal_approx(mole.pixel_size*150,58*sqrt(2.0)/70),"mole uses 58 px source with 150 px cached draw scale")
				_check(is_equal_approx(mole.offset.y+128,222+11*150.0/62),"mole retains full mound and paws above its foot")
				if id=="3-4":
					_check(mole.position.is_equal_approx(Vector3(-2.92,.008,-.20)),"final resident uses complete supported front-right terrace")
					_check(Vector3(mole.get_meta("original_sanctuary_desired")).is_equal_approx(Vector3(-5,0,.3)),"final resident preserves original source location metadata")
					_check(str(mole.get_meta("original_sanctuary_migration",""))=="same_height_front_right_terrace_clear_of_final_core_and_actors","final resident records real-depth core occlusion migration")
					_mole_clearance(stage,mole)
			if id=="1-4": _sanctuary(stage,world,state)
			var ids := tagged.map(func(n: Node) -> int: return n.get_instance_id())
			for frame in range(3): stage.refresh_world(world)
			var next_ids: Array = []
			for child in stage._props.get_children():
				if child.has_meta("original_sanctuary_support"): next_ids.append(child.get_instance_id())
			_check(ids==next_ids,id+"/"+state+" unchanged refresh preserves props cache")
	_check(Sanctuary.rasterizations==1,"fountain CPU art rasterized once across states")
	var image := Sanctuary.fountain_texture().get_image()
	_check(image.get_size()==Vector2i(416,384),"fountain original art uses complete 104 by 96 source canvas at 4x")
	_check(image.get_pixel(208,367).a>.9,"fountain lower basin edge is present")
	var output := {"checks":checks,"failures":failures,"scope":"CPU source ratios, feet, full support, state reversal, retained effects clocks and caches; GPU pending","rows":rows}
	var file := FileAccess.open("res://../docs/qa-godot-native/original-elements-audit/native-sanctuary-headless.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"  ")+"\n")
	print(JSON.stringify({"checks":checks,"failures":failures,"states":8,"gpuPixelsVerified":false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _mole_clearance(stage: Node, mole: Sprite3D) -> void:
	var radius := float(mole.get_meta("original_sanctuary_foot_radius"))
	var core: Node3D = stage._props_nodes["mark:core"]
	for child in core.get_children():
		if not child.has_meta("core_planter"): continue
		var center: Vector3 = core.to_global(child.get_meta("ground_footprint_center"))
		var span: Vector2 = child.get_meta("ground_footprint_span")
		_check(absf(center.x-mole.position.x)>span.x*.5+radius or absf(center.z-mole.position.z)>span.y*.5+radius,"resident complete square stays outside actual final planter base")
	var foot := Vector2(mole.position.x,mole.position.z)
	var core_tile: Dictionary = stage._tile_map["f:-4:0"]
	for who: String in ["luvie","buddy"]:
		var stance: Vector3 = stage.actor_rest_position(core_tile,who)
		var capsule: CapsuleShape3D = stage.get_actor_body(who).get_node("Collision").shape
		var center := Vector2(stance.x,stance.z)
		var nearest := center.clamp(foot-Vector2.ONE*radius,foot+Vector2.ONE*radius)
		_check(center.distance_to(nearest)>capsule.radius,who+" completed capsule does not intersect resident's full footprint")
	for ix in range(9):
		for iz in range(9):
			var sample := mole.position+Vector3(lerpf(-radius,radius,ix/8.0),0,lerpf(-radius,radius,iz/8.0))
			var support := "f:%d:%d" % [roundi(sample.x),roundi(sample.z)]
			var tile: Dictionary = stage._tile_map.get(support,{})
			_check(not tile.is_empty() and stage._surfaces.has(support) and not bool(tile.get("solid",false)) and str(tile.get("kind","fixed"))=="fixed" and absf(stage.support_height(sample,support)-(mole.position.y-.008))<.001,"resident complete mound dense flat support sample "+str(ix)+":"+str(iz))

func _sanctuary(stage: Node, world: RefCounted, state: String) -> void:
	var frame: Sprite3D = stage._props.get_node("OriginalSanctuaryGateFrame")
	var seal: Sprite3D = stage._props.get_node_or_null("OriginalSanctuaryGateSeal")
	var fountain: Sprite3D = stage._props.get_node("SanctuaryFountain")
	_check(is_equal_approx(float(frame.get_meta("original_canvas_world_width")),112*sqrt(2.0)/70),state+" gate records its 112 px source canvas")
	_check(frame.get_meta("original_ratio_exception","")=="entrance_full_masonry_footprint_limit", "gate exposes local full-base support exception")
	_check(frame.position.is_equal_approx(Vector3(-6,.658,0)),"gate remains on the actual interactive entrance")
	_check(not Sanctuary.gate_footprint(stage,frame.position,"f:-6:0",float(frame.get_meta("original_sanctuary_foot_radius"))+.01),"one more centimetre fails complete gate-base support")
	_check((seal==null)==world.flag("home"),state+" no lingering seal after gate opens")
	if seal != null:
		_check(seal.offset==frame.offset and seal.position==frame.position and seal.pixel_size==frame.pixel_size,"frame and seal retain identical source registration")
	var fountain_ratio := float(fountain.get_meta("original_fountain_ratio"))
	_check(is_equal_approx(fountain.pixel_size*4*86,92.0/90*86*sqrt(2.0)/70*fountain_ratio),"fountain 86-unit lower basin retains original 92/90 proportions within explicit local scale")
	_check(Sanctuary.fountain_candidate(stage,fountain.get_meta("original_sanctuary_desired"),float(fountain.get_meta("original_sanctuary_foot_radius"))+.01).is_empty(),"larger complete fountain cannot fit without intersecting actual core or losing support")
	_check(bool(stage._tile_map["f:-9:-2"].solid) and absf(fountain.position.x+9)<.36 and absf(fountain.position.z+2)<.36,"original permanent solid cell still visibly contains fountain")
	var core: Node3D = stage._props_nodes["mark:core"]
	var planter: Sprite3D = null
	for child in core.get_children():
		if child.has_meta("core_planter"): planter=child
	_check(planter!=null,"core exposes real complete planter footprint")
	if planter != null:
		var center: Vector3 = core.to_global(planter.get_meta("ground_footprint_center"))
		var span: Vector2 = planter.get_meta("ground_footprint_span")
		for prop: Sprite3D in [fountain,frame]:
			var radius := float(prop.get_meta("original_sanctuary_foot_radius"))
			_check(absf(center.x-prop.position.x)>span.x*.5+radius or absf(center.z-prop.position.z)>span.y*.5+radius,prop.name+" clear of actual relocated planter square, not interaction origin")
	var combined_radius := float(frame.get_meta("original_sanctuary_foot_radius"))+float(fountain.get_meta("original_sanctuary_foot_radius"))
	_check(absf(frame.position.x-fountain.position.x)>combined_radius or absf(frame.position.z-fountain.position.z)>combined_radius,"gate and fountain full footprints do not intersect")
	var garden: Node = stage._garden_effects.atmosphere
	_check(garden.fountain_at==fountain.position,"fountain effects follow actual supported body, not old logical edge")
	_check(is_equal_approx(garden.fountain_ratio,fountain_ratio),"jets drops and ripples share basin's supported ratio")
	_check(garden.jets.size()==36 and garden.fountain_drops.size()==7 and garden.fountain_rings.size()==3 and garden.butterflies.size()==4,"two 18-segment jets, seven droplets, three rings, four butterflies retained")
	_check(garden._jet_point(0,-1).is_equal_approx(Vector2(-2,-42)) and garden._jet_point(1,1).is_equal_approx(Vector2(23,-10)),"jet source nozzle and basin landing")
	_check(garden._jet_point(.5,1).is_equal_approx(Vector2(12.25,-45.5)),"jet source quadratic control point")
	stage.set_settings({"lowMotion":false,"particles":true,"dynamicLight":true})
	stage.set_visual_time(1000)
	stage._garden_effects.update()
	var before: Vector3 = garden.fountain_drops[0].position
	stage.set_visual_time(1500)
	stage._garden_effects.update()
	_check(before!=garden.fountain_drops[0].position,"droplets advance on stage visual clock")
	stage.set_paused(true)
	before=garden.fountain_drops[0].position
	stage._process(.03)
	_check(before==garden.fountain_drops[0].position,"pause freezes effects")
	stage.set_paused(false)
	stage.set_settings({"lowMotion":true,"particles":true,"dynamicLight":true})
	_check(garden.fountain_drops.all(func(drop: Node3D) -> bool: return not drop.visible),"reduced motion hides falling droplets")
	stage.set_settings({"lowMotion":false,"particles":false,"dynamicLight":true})
	_check(garden.jets.all(func(jet: Node3D) -> bool: return jet.visible),"particle setting preserves static water supply")
