extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
const Waterworks=preload("res://presentation/native/guardian_waterworks.gd")
var checks:=0
var failures: Array[String]=[]
var measurements: Array=[]
var stage: Node
var original: Dictionary
func _initialize() -> void: _run.call_deferred()
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func _inspect(world: RefCounted,label: String) -> void:
	var snapshot: Dictionary=world.snapshot().duplicate(true)
	var tiles: Array=world.tiles().duplicate(true)
	stage.set_world(world)
	var root: Node3D=stage._effects.get_node("GuardianWaterworks")
	_check(root.find_children("*","CollisionObject3D",true,false).is_empty(),label+" water dressing adds no collision or walkable support")
	_check(root.find_children("*","Label3D",true,false).is_empty(),label+" hydraulic chain needs no text plaques")
	_check(stage._water_links.is_empty() and stage._water_module_roots.is_empty(),label+" old cross-void drops and central mini-channel are absent")
	var rotor: Node3D=root.get_node("RotatingTrough")
	var outlet: Vector3=rotor.to_global(Vector3(0,.04,2.43))
	var receiver:=Vector3(-2.60,.025,8)
	var turn:=int(world.state.turns.water)
	_check((outlet.distance_to(receiver)<.18)==(turn==1),label+" only west-facing real outlet aligns with fixed inlet")
	_check(bool(root.get_meta("water_docked"))==(turn==1),label+" current physical alignment controls short water transfer")
	_check(bool(root.get_meta("water_stored"))==bool(world.flag("rain")),label+" stored water reads persisted rain rather than current rotation")
	for reservoir: Node3D in [root.get_node("WestReservoir"),root.get_node("LiftReservoirAssembly/LiftReservoir")]:
		var support: Dictionary=stage._tile_map[str(reservoir.get_meta("support_id"))]
		var at: Vector3=stage.tile_position(support)
		var size: Vector2=reservoir.get_meta("inset_footprint")
		_check(absf(reservoir.global_position.x-at.x)+size.x*.5<=.5001 and absf(reservoir.global_position.z-at.z)+size.y*.5<=.5001,label+" complete inset reservoir lies within real support")
		_check(absf(reservoir.global_position.y-at.y)<.0001,label+" reservoir is flush with its real bank")
		_check(reservoir.get_node("StoredWater").visible==world.flag("rain"),label+" stored level survives turning away")
	for group: Node3D in [root.get_node("PermanentBankPipe"),root.get_node("RootBankPipe")]:
		if not group.visible: continue
		for pipe: Node in group.get_children():
			if not str(pipe.name).begins_with("MountedPipe"): continue
			var length: float=pipe.mesh.height
			for fraction: float in [0.0,.1,.25,.5,.75,.9,1.0]:
				var point: Vector3=pipe.to_global(Vector3(0,(fraction-.5)*length,0))
				var supported:=false
				for tile: Dictionary in tiles:
					var at: Vector3=stage.tile_position(tile)
					if absf(point.x-at.x)<=.5001 and absf(point.z-at.z)<=.5001 and point.y<=at.y and point.y>=at.y-.25:
						supported=true
						break
				_check(supported,label+" closed bank pipe follows existing permanent/root sidewall")
	_check(world.snapshot()==snapshot and world.tiles()==tiles,label+" art preserves saved state and topology")
	measurements.append({"case":label,"turn":turn,"outlet":[outlet.x,outlet.y,outlet.z],"docked":root.get_meta("water_docked"),"stored":root.get_meta("water_stored")})

func _run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if entry.name=="authored/3-4": original=entry
	stage=Stage.new()
	root.add_child(stage)
	await process_frame
	_inspect(World.new("3-4"),"cold")
	for turn in range(4):
		var world:=World.new("3-4",original.steps[34].snapshot)
		world.state.turns.water=turn
		_inspect(world,"charged-turn-"+str(turn))
	var before:=World.new("3-4",original.steps[33].snapshot)
	var after:=World.new("3-4",original.steps[34].snapshot)
	stage.set_world(after)
	var water: Node3D=stage._effects.get_node("GuardianWaterworks")
	var stable_id:=water.get_instance_id()
	for progress: float in [0.0,.25,.5,.9999,1.0]:
		Waterworks.update(stage,before,after,progress)
		_check(bool(water.get_meta("water_docked"))==(progress>=1.0),"short inflow waits for real docking")
		_check(bool(water.get_meta("water_stored"))==(progress>=1.0),"new stored water waits for settled charging action")
	var turned_away:=World.new("3-4",after.snapshot())
	turned_away.state.turns.water=2
	Waterworks.update(stage,after,turned_away,.5)
	_check(not water.get_node("DockedWater").visible and water.get_node("WestReservoir/StoredWater").visible,"turning away stops inflow but preserves charged reservoir")
	Waterworks.update(stage,after,before,.5)
	_check(not water.get_node("WestReservoir/StoredWater").visible,"undoing first charge removes stored water")
	var high:=World.new("3-4",original.steps[36].snapshot)
	for progress: float in [0.0,.5,1.0,.5,0.0]:
		Waterworks.update(stage,after,high,progress)
		_check(is_equal_approx(water.get_node("LiftReservoirAssembly").position.y,progress*1.30),"lift reservoir physically follows ascent/descent height")
		_check(water.get_instance_id()==stable_id,"water motion never rebuilds geometry")
	stage.set_world(World.new("3-3"))
	_check(stage._effects.get_node_or_null("GuardianWaterworks")==null,"3-3 does not inherit final-garden hydraulic chain")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-guardian-waterworks","checks":checks,"failures":failures,"passed":failures.is_empty(),"measurements":measurements,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
