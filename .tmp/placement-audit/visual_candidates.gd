extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
const P=preload("res://presentation/native/original_scenery_placement.gd")
func _initialize():call_deferred("run")
func run():
	var stage=Stage.new();root.add_child(stage);stage.set_process(false)
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var results={}
	for spec in [["1-4",18,-7.0,-1.7,1],["2-4",0,11.0,-1.24,0],["3-4",3,-5.24,1.0,0]]:
		var states=[{}]
		for case in fixture.cases:
			if case.name=="authored/"+str(spec[0]):
				for step in case.steps:
					if step.command.kind=="act":states.append(step.snapshot)
		var common={};var first=true
		for state in states:
			stage.set_world(World.new(str(spec[0]),state));await process_frame
			var ctx=P.prepare(stage);var found={};var y=float(spec[4])*.65
			for node in stage._props.get_children():
				if node.has_meta("original_scenery_index") and int(node.get_meta("original_scenery_index"))!=int(spec[1]):
					ctx.occupied.append({"at":Vector2(node.position.x,node.position.z),"y":node.position.y-.008,"radius":float(node.get_meta("original_scenery_foot_radius"))})
			# States before a real target island exists do not constrain its final decoration.
			if not ctx.fixed.has("f:%d:%d"%[roundi(float(spec[2])),roundi(float(spec[3]))]):continue
			var r=P.radius("stone-lantern",float(29 if str(spec[0])=="1-4" else 30)*sqrt(2.0)/70)
			for ix in range(roundi((float(spec[2])-2.8)*20),roundi((float(spec[2])+2.8)*20)):
				for iz in range(roundi((float(spec[3])-2.8)*20),roundi((float(spec[3])+2.8)*20)):
					var at=Vector3(ix*.05,y,iz*.05)
					if P.clear(at,r,"stone-lantern",ctx) and P.supported(stage,at,r,ctx):found[str(ix)+":"+str(iz)]=at
			if first:common=found;first=false
			else:
				for key in common.keys():
					if not found.has(key):common.erase(key)
		var output=[]
		for point in common.values():output.append([point.x,point.y,point.z])
		results[str(spec[0])]=output
	var file=FileAccess.open("res://../.tmp/placement-audit/visual-candidates.json",FileAccess.WRITE);file.store_string(JSON.stringify(results))
	print("candidate counts ",results.keys().map(func(id):return [id,results[id].size()]))
	stage.free();quit()
