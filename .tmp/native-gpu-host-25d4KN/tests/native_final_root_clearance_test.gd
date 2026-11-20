extends SceneTree
## Prepared support/obstacle diagnostic. Actual route is validated separately.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Obstacles = preload("res://presentation/native/native_prop_obstacles.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func _check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	await process_frame
	var world := World.new("3-4")
	world.state.actors.luvie = "f:1:-4"
	world.state.active = "luvie"
	_check(world.act("grow:root:right").ok,"first root grows under unchanged rules")
	var saved := world.snapshot().duplicate(true)
	stage.set_world(world)
	var start := world.point_for("f:1:-4")
	var target := world.point_for("g:root:2:-4")
	var radius: float = stage._prop_actor_radius("luvie")
	var from := Vector3(.5412,.0009,-3.9992)
	var waypoint: Dictionary = stage.prop_waypoint(target,"luvie",stage.actor_rest_position(target,"luvie"))
	var route: Array = stage.prop_edge_route_from(start,target,"luvie",from)
	var obstacles: Array = []
	for entry: Dictionary in stage._prop_obstacles:
		if absf(entry.rect.get_center().x-1.0)<1.5 and absf(entry.rect.get_center().y+4.0)<1.5:
			obstacles.append({"id":entry.id,"rect":str(entry.rect),"floor":entry.get("floor"),"top":entry.top})
	print("ROOT CLEARANCE ",JSON.stringify({"radius":radius,"waypoint":str(waypoint),"route":str(route),"nearbyObstacles":obstacles,"mirror":world.state.items.mirror}))
	_check(not waypoint.is_empty(),"first built root has supported safe destination")
	_check(not route.is_empty(),"original root stance has physical passage to first built root")
	var mirror: Node3D = stage._props_nodes["item:mirror"]
	_check(mirror.get_meta("physical_item_offset").is_equal_approx(Vector3(0,0,-.20)),"mirror artwork uses original tile's local north placement")
	var stone: Dictionary = {}
	for entry: Dictionary in stage._prop_obstacles:
		if str(entry.id)=="item:mirror": stone=entry
	_check(not stone.is_empty(),"mirror stone remains a hard obstacle")
	if not stone.is_empty():
		_check(stone.rect.size.is_equal_approx(Vector2(.41,.41)),"original mirror hard-base size remains")
		_check(stone.rect.get_center().is_equal_approx(Vector2(1,-4.2)),"hard base and visible item share local offset")
		var support_rect := Rect2(Vector2(.5,-4.5),Vector2.ONE)
		_check(support_rect.encloses(stone.rect),"whole hard base stays inside original fixed tile")
		_check(not stage.prop_physical_point_clear(Vector3(1,0,-4.2),"luvie"),"new base centre still blocks body penetration")
	_check(not stage.prop_edge_route(target,start,"luvie").is_empty(),"first root retains physical return to mirror shore")
	_check(world.snapshot()==saved,"presentation offset does not mutate item tile, angle or puzzle state")
	_check(Obstacles.placement_offset("mirror","f:8:0","3-4")==Vector3.ZERO,"final high mirror slot remains unchanged")
	_check(Obstacles.placement_offset("mirrorB","f:1:-4","2-2")==Vector3.ZERO,"other garden mirrors remain unchanged")
	_check(world.act("take:mirror").ok,"original mirror pickup remains legal")
	stage.set_world(world)
	_check(not stage._prop_obstacles.any(func(entry: Dictionary) -> bool: return str(entry.id)=="item:mirror"),"pickup removes old stone obstacle")
	_check(world.undo(),"pickup can be undone")
	stage.set_world(world)
	_check(world.snapshot()==saved,"undo restores exact original item and growth state")
	_check(not stage.prop_edge_route_from(world.point_for("f:1:-4"),world.point_for("g:root:2:-4"),"luvie",from).is_empty(),"restored mirror still leaves first-root passage")
	var restored := World.new("3-4",saved)
	stage.set_world(restored)
	_check(not stage.prop_edge_route_from(restored.point_for("f:1:-4"),restored.point_for("g:root:2:-4"),"luvie",from).is_empty(),"old partial save gets local placement without migration")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-final-root-clearance","checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
