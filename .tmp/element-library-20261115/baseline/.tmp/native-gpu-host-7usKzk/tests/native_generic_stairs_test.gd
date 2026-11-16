extends SceneTree

const Surface = preload("res://presentation/native/native_surface.gd")
const AXES := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var material := StandardMaterial3D.new()
	var materials := {"top": material, "side": material, "ramp": material, "trim": material, "riser": material, "generic_stairs": true}
	for direction in range(4):
		for thin: bool in [false, true]:
			await _connection(direction, thin, materials)
	print(JSON.stringify({"suite": "native-generic-stairs", "passed": failures.is_empty(), "checks": checks, "failures": failures, "gpuPixelsVerified": false}))
	quit(0 if failures.is_empty() else 1)

func _connection(direction: int, thin: bool, materials: Dictionary) -> void:
	var low := Surface.new()
	var high := Surface.new()
	root.add_child(low)
	root.add_child(high)
	var axis: Vector3 = AXES[direction]
	var across := Vector3(-axis.z, 0, axis.x)
	var low_rises: Array[float] = [0, 0, 0, 0]
	var high_rises: Array[float] = [0, 0, 0, 0]
	low_rises[direction] = 0.65
	high_rises[(direction + 2) % 4] = -0.65
	var low_exposed: Array[bool] = [true, true, true, true]
	var high_exposed: Array[bool] = [true, true, true, true]
	low_exposed[direction] = false
	high_exposed[(direction + 2) % 4] = false
	low.configure({"id": "low", "x": 0, "z": 0, "h": 0, "kind": "bridge" if thin else "fixed"}, low_rises, low_exposed, -0.67, materials)
	high.configure({"id": "high", "x": axis.x, "z": axis.z, "h": 1, "kind": "bridge" if thin else "fixed"}, high_rises, high_exposed, -0.67, materials)
	await physics_frame
	await physics_frame
	var label := str(direction) + ("/thin" if thin else "/solid")
	# Independent expected plateaus, including both sides of support ownership.
	for point: Vector2 in [Vector2(0.125, 0), Vector2(0.20, 0), Vector2(0.30, 0.1625), Vector2(0.35, 0.1625), Vector2(0.475, 0.325), Vector2(0.5, 0.325), Vector2(0.525, 0.325), Vector2(0.65, 0.4875), Vector2(0.75, 0.65), Vector2(0.9, 0.65)]:
		for offset: float in [-0.12, 0.0, 0.12]:
			var at := axis * point.x + across * offset
			var support := low if point.x <= 0.5 else high
			_check(absf(support.sample_height(at) - point.y) < 0.00001, label + " horizontal tread sampling " + str(point))
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2, at + Vector3.DOWN * 2, 1)
			var hit := low.get_world_3d().direct_space_state.intersect_ray(ray)
			_check(not hit.is_empty() and absf(hit.position.y - point.y) < 0.00001, label + " PhysicsServer ray hits actual tread " + str(point))
	for nose: float in [0.275, 0.425, 0.575, 0.725]:
		var before := axis * (nose - 0.002)
		var after := axis * (nose + 0.002)
		var support := low if nose < 0.5 else high
		_check(absf(support.sample_height(after) - support.sample_height(before) - 0.1625) < 0.00001, label + " real vertical riser at " + str(nose))
		# A horizontal ray below the next tread must encounter the real riser.
		var height := support.sample_height(before) + 0.08
		var ray := PhysicsRayQueryParameters3D.create(before + Vector3.UP * height, after + Vector3.UP * height, 1)
		var hit := low.get_world_3d().direct_space_state.intersect_ray(ray)
		_check(not hit.is_empty() and absf(hit.normal.y) < 0.00001, label + " vertical riser has collision " + str(nose))
	for index in range(101):
		var at := axis * (float(index) / 100.0)
		var support := low if index <= 50 else high
		var actual := support.sample_height(at)
		var stride := support.stride_height(at)
		_check(stride >= actual - 0.00001 and stride <= actual + 0.16251, label + " sole envelope remains above physical tread and below one step")
	# Scan independently across the anticipation onset and the pace descriptor
	# boundary. A descriptor-gated envelope used to jump by .025 at d=.20.
	var previous_sole := low.stride_height(axis * 0.15)
	for index in range(1, 101):
		var sole := low.stride_height(axis * (0.15 + float(index) * 0.001))
		_check(sole >= previous_sole - 0.00001 and sole - previous_sole < 0.0025, label + " continuous pre-nose sole scan")
		previous_sole = sole
	_check(is_zero_approx(low.stride_height(axis * 0.174)) and low.stride_height(axis * 0.19) > 0.001, label + " anticipation begins before the pace region")
	_check(low.stair_descriptor(axis * 0.19).is_empty(), label + " anticipation does not widen the pace region")
	_check(low.stair_descriptor(Vector3.ZERO).is_empty(), label + " central landing has no stair gait")
	var descriptor := low.stair_descriptor(axis * 0.35)
	_check(not descriptor.is_empty() and descriptor.axis.is_equal_approx(axis) and is_equal_approx(descriptor.step_height, 0.1625), label + " world gait descriptor")
	var original_rebuilds := low.geometry_rebuilds
	low.position += Vector3(4, 1, 5)
	low.rotation.y = PI / 2
	var moved := low.to_global(axis * 0.35)
	_check(absf(low.sample_height(moved) - 1.1625) < 0.00001, label + " rigid motion retains actual tread height")
	_check(low.stair_descriptor(moved).axis.is_equal_approx(low.global_basis * axis), label + " gait axis follows rigid rotation")
	_check(low.geometry_rebuilds == original_rebuilds, label + " rigid motion needs no mesh rebuilding")
	low.free()
	high.free()
	await physics_frame
