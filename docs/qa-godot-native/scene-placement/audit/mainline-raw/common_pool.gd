extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
const P=preload("res://presentation/native/original_scenery_placement.gd")
func _initialize():call_deferred("run")
func run():
	var stage=Stage.new();root.add_child(stage)
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var states=[{}]
	for case in fixture.cases:
		if case.name=="authored/2-1":states.append(case.steps.back().snapshot)
	var sets=[]
	for state in states:
		stage.set_world(World.new("2-1",state));var ctx=P.prepare(stage);var found={}
		for ix in range(-75,-44):
			for iz in range(-30,31):
				var at=Vector3(ix*.05,0,iz*.05)
				if P.clear(at,P.radius("lotus-pool",47*sqrt(2.0)/70),"lotus-pool",ctx) and P.supported(stage,at,P.radius("lotus-pool",47*sqrt(2.0)/70),ctx):found[str(ix)+":"+str(iz)]=at
		sets.append(found)
	var common=[]
	for key in sets[0]:
		if sets[1].has(key):common.append(sets[0][key])
	print("common ",common);quit()
