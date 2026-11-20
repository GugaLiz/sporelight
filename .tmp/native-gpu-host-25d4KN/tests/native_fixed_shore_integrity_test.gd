extends SceneTree
## Fixed banks retain their own surface when a conditional route ends on them.
## Closed high gates keep a physical cut face until their legal stair opens.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var stage: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(40).timeout.connect(func() -> void: push_error("shore integrity test timed out"); quit(2))
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _settle(world: RefCounted) -> void:
	stage.clear_motion(false)
	stage.set_world(world)
	await physics_frame
	await physics_frame

func _wall_hit(height: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = stage._scene.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-5.3, height, 0), Vector3(-5.7, height, 0), 1)
	return space.intersect_ray(ray)

func _foundation_bottom(surface: Node3D) -> float:
	var bottom := INF
	if surface._sides.mesh == null: return bottom
	var vertices: PackedVector3Array = surface._sides.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		bottom = minf(bottom, surface.to_global(vertex).y)
	return bottom

func _shore(id: String, expected_material: Material, label: String) -> void:
	var surface: Node3D = stage._surfaces[id]
	_check(not surface.thin_plate, label + " permanent shore never becomes a thin route plate")
	_check(expected_material!=null and surface._top.get_active_material(0) == expected_material, label + " permanent shore keeps its paving material")
	# A newly connected interior cell legitimately has no exposed side mesh.
	# Inspect the same bank's outer wall, rather than demand an internal wall.
	var perimeter: Node3D=stage._surfaces["f:2:-1" if id=="f:2:0" else "f:-4:4"]
	_check(absf(_foundation_bottom(perimeter) + .67) < .0001, label + " permanent island keeps its full exposed foundation")
	_check(surface.scale.is_equal_approx(Vector3.ONE), label + " existing shore is never scaled by route reveal")
	_check(surface._growth_overrides.is_empty(), label + " existing shore has no route reveal override")

func _run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var initial := World.new("1-4")
	var initial_snapshot: Dictionary = initial.snapshot().duplicate(true)
	await _settle(initial)
	var east_material: Material = stage._surfaces["f:2:0"]._top.get_active_material(0)
	var south_material: Material = stage._surfaces["f:-3:4"]._top.get_active_material(0)
	var mole_position: Vector3 = stage._props.get_node("MoleResident").position
	for height: float in [.1, .325, .55]:
		var hit := _wall_hit(height)
		_check(not hit.is_empty(), "closed gate seals its high-to-low face at " + str(height))
		if not hit.is_empty():
			_check(str(hit.collider.get_meta("support_id", "")) == "f:-6:0", "closed face belongs to the original gate support")
	_check(initial.snapshot() == initial_snapshot, "closed geometry does not modify rules or saves")
	var held := World.new("1-4")
	held.state.flags.append("hold")
	held.state.actors.buddy = "f:2:0"
	var held_snapshot: Dictionary = held.snapshot().duplicate(true)
	_check(str(held.point_for("f:2:0").get("kind", "fixed")) == "root", "case exercises the occupied logical route endpoint")
	await _settle(held)
	_shore("f:2:0", east_material, "held occupied east bank")
	_check(stage._surfaces["f:1:0"].thin_plate, "actual gap cell remains a conditional thin bridge")
	_check(held.snapshot() == held_snapshot, "shore ownership does not rewrite the occupied logical descriptor")
	var occupied_item := World.new("1-4", held_snapshot)
	occupied_item.state.actors.buddy = "f:3:0"
	occupied_item.state.items.bell.tile = "f:2:0"
	await _settle(occupied_item)
	_shore("f:2:0", east_material, "item occupied east bank")
	var latched := World.new("1-4")
	latched.state.flags.append("latch")
	latched.state.actors.luvie = "f:-3:4"
	await _settle(latched)
	_shore("f:-3:4", south_material, "latched occupied south bank")
	_check(stage._surfaces["f:-3:3"].thin_plate, "permanent latch retains the original connector geometry")
	for progress: float in [0.0, .25, .5, .75, 1.0]:
		stage.set_motion(initial_snapshot, held_snapshot, progress, "use:hold")
		_shore("f:2:0", east_material, "bridge reveal " + str(progress))
		_check(stage._surfaces.has("f:1:0"), "bridge reveal retains its real added support")
	await _settle(initial)
	_check(not stage._surfaces.has("f:0:0"), "release or cancellation removes only the conditional bridge")
	_shore("f:2:0", east_material, "released east bank")
	var opened := World.new("1-4")
	opened.state.flags.append("home")
	await _settle(opened)
	_check(not bool(opened.point_for("f:-6:0").solid), "home opens the original gate rule cell")
	_check(_wall_hit(.55).is_empty(), "opened gate removes the closed high wall above its real stairs")
	_check(is_equal_approx(float(stage._surfaces["f:-6:0"].rises[1]), -.65), "opened high bank installs the authored descending stair")
	_check(stage._props.get_node("MoleResident").position.is_equal_approx(mole_position), "opening never moves the resident to disguise the seam")
	await _settle(initial)
	_check(not _wall_hit(.325).is_empty(), "undo or reentry restores the closed cut face")
	_check(stage._props.get_node("MoleResident").position.is_equal_approx(mole_position), "closed restoration preserves the resident position")
	print(JSON.stringify({"suite":"native-fixed-shore-integrity", "checks":checks, "passed":failures.is_empty(), "failures":failures, "gpuPixelsVerified":false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
