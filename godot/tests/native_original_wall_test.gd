extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Walls = preload("res://presentation/native/original_wall_props.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	var stage := Stage.new(); root.add_child(stage); stage.set_process(false)
	stage.set_world(World.new("1-2"))
	check(stage._props.get_node_or_null("IsolatedRockSpire") != null,"1-2 approved isolated spire retained")
	check(stage._props.get_node_or_null("OriginalWall_2_1") == null,"1-2 never uses replacement wall art")
	var world := World.new("2-2")
	# Beam fixture: remove the first mirror from the beam, exposing the wall.
	world.state.items.mirrorA.holder = "luvie"; world.state.items.mirrorA.tile = ""
	var snapshot: Dictionary = world.snapshot()
	var tiles: Array = world.tiles()
	var rays: Array = world.rays()
	var original_walls: Array = world.level.walls.duplicate(true)
	world.level.walls = [[2,1]]
	check(world.rays() == rays,"integer and JSON float wall coordinates terminate identically")
	world.level.walls = [[2.0,2.0]]
	check(world.rays().back().x == 16,"different wall row cannot falsely terminate beam")
	world.level.walls = original_walls
	stage.set_world(world)
	var wall: Node3D = stage._props.get_node("OriginalWall_2_1")
	_validate(wall,"river-rock",46)
	check(world.snapshot() == snapshot and world.tiles() == tiles,"display preserves snapshot and rule tiles")
	check(world.rays() == rays and rays.back().x == 2 and rays.back().z == 1,"original wall still terminates beam")
	check(world.point_for("f:2:1").is_empty() and world.path_to("f:2:1").is_empty(),"wall cell remains unavailable; no new support")
	check(not stage._surfaces.has("f:2:1"),"no invisible walkable surface added under obstacle")
	var shape_count := _physics_count(stage._scene)
	stage._props_signature = 0; stage.refresh_world(world,true)
	check(_physics_count(stage._scene) == shape_count,"prop refresh preserves collision count")
	check(world.rays() == rays,"refresh does not change wall light blocker")
	# Generic source fallback is unused by current non-1-2 authored walls,
	# but retains the original 70px rock if another existing level supplies one.
	stage.set_world(World.new("1-3"))
	var prior: Dictionary = stage.world.snapshot()
	var generic := Walls.build(stage,[2,1])
	_validate(generic,"rock",70)
	check(stage.world.snapshot() == prior,"generic fallback display has no rule effects")
	print(JSON.stringify({"suite":"native-original-wall","checks":checks,"passed":failures.is_empty(),"failures":failures,"gpuPixelsVerified":false}))
	stage.free(); quit(0 if failures.is_empty() else 1)
func _validate(wall: Node3D,alias: String,pixels: float) -> void:
	var rock: Sprite3D = wall.get_node("OriginalRock")
	var footing: MeshInstance3D = wall.get_node("ObstacleFooting")
	check(str(rock.texture.resource_path).ends_with("/"+alias+".png"),alias+" source identity")
	check(is_equal_approx(rock.texture.get_width()*rock.pixel_size,pixels*sqrt(2.0)/70),alias+" original canvas ratio")
	check(not rock.no_depth_test and rock.billboard == BaseMaterial3D.BILLBOARD_DISABLED,alias+" grounded upright real depth")
	var camera_up := Vector3(-.35355339,.8660254,-.35355339)
	check(is_equal_approx(rock.global_basis.y.dot(camera_up),1),alias+" source projected height preserved")
	check(footing.mesh.size == Vector3(.86,.1,.86),alias+" low visible native blockage extent retained")
	check(is_equal_approx(rock.position.y,footing.position.y+footing.mesh.size.y*.5),alias+" source foot rests on visible stone footing")
	check(is_equal_approx(rock.offset.y,(rock.texture.get_height()-1)*.5),alias+" trimmed last pixel anchored at foot")
	check(_physics_count(wall) == 0,alias+" display adds no colliders or support")
func _physics_count(node: Node) -> int:
	var result := 1 if node is PhysicsBody3D or node is CollisionShape3D else 0
	for child in node.get_children(): result += _physics_count(child)
	return result
