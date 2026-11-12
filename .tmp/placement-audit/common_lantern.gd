extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
const P=preload("res://presentation/native/original_scenery_placement.gd")
func _initialize():call_deferred("run")
func run():
	var stage=Stage.new();root.add_child(stage)
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"));var states=[{}]
	for case in fixture.cases:
		if case.name=="authored/2-2":
			for step in case.steps:
				if step.command.kind=="act":states.append(step.snapshot)
	var common={};var first=true
	for state in states:
		stage.set_world(World.new("2-2",state));var ctx=P.prepare(stage);var found={}
		for node in stage._props.get_children():
			if node.has_meta("original_scenery_index") and int(node.get_meta("original_scenery_index"))<4:
				ctx.occupied.append({"at":Vector2(node.position.x,node.position.z),"y":node.position.y-.008,"radius":float(node.get_meta("original_scenery_foot_radius"))})
		for ix in range(20,106):
			for iz in range(-5,65):
				var at=Vector3(ix*.05,0,iz*.05)
				if P.clear(at,P.radius("stone-lantern",30*sqrt(2.0)/70),"stone-lantern",ctx) and P.supported(stage,at,P.radius("stone-lantern",30*sqrt(2.0)/70),ctx):found[str(ix)+":"+str(iz)]=at
		if first:common=found;first=false
		else:
			for key in common.keys():
				if not found.has(key):common.erase(key)
	var output=common.values();output.sort_custom(func(a,b):return Vector2(a.x-2.76,a.z-1).length_squared()<Vector2(b.x-2.76,b.z-1).length_squared())
	print("common nearest ",output.slice(0,20));quit()
