extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const Session=preload("res://application/game_session.gd")
const Move=preload("res://application/native_movement.gd")
const Router=preload("res://application/input_router.gd")
func _initialize()->void: run.call_deferred()
func run()->void:
	var refs:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var saved:Dictionary
	for entry:Dictionary in refs.cases:
		if str(entry.name)=="authored/3-4":saved=entry.steps[45].snapshot
	var session=Session.new("3-4",saved)
	var stage=Stage.new();root.add_child(stage);stage.set_process(false);stage.set_world(session.world)
	var motor=Move.new();motor.setup(session,stage,Router.new())
	var future=session.world.fork(session.world.snapshot());future.act("turn:light",true)
	for who:String in ["luvie","buddy"]:
		var body:CharacterBody3D=stage.get_actor_body(who)
		var current:Dictionary=session.world.point_for(session.world.state.actors[who])
		var edges:Array=future.neighbors(str(current.id),who,future.tiles())
		print(who," ",body.position," CURRENT ",current," FUTURE ",edges," STAIRS ",motor._occupies_detaching_stair(body,current,future,future.tiles(),edges))
		for tile:Dictionary in session.world.neighbors(str(current.id),who):
			var projection=(stage.logical_position(body.position)-stage.logical_position(stage.tile_position(current))).dot(Vector3(float(tile.x)-float(current.x),0,float(tile.z)-float(current.z)))
			print("EDGE ",tile.id," PROJ ",projection," remains ",edges.any(func(e:Dictionary)->bool:return e.id==tile.id))
	stage.free();quit()
