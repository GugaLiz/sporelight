extends SceneTree
## First authored meshes and retained second-garden surfaces keep the sealed
## historical golden; only reviewed 1-2 revision 2 topologies use a new file.
## Generic stairs are validated by physical face and adjacency contracts.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Factory = preload("res://core/world_factory.gd")
const Surface = preload("res://presentation/native/native_surface.gd")
const BASELINE := "res://tests/fixtures/native-surface-support-baseline.json"
const SECOND_BASELINE := "res://tests/fixtures/native-surface-second-layout-revision2.json"
const SECOND_CANDIDATE := "res://tests/fixtures/native-surface-second-layout-revision2.candidate.json"
const LEGACY_SHA := "86116d40e268ef77d54289d17a0bde31bf19110d688234b8e6310656f297dce1"
const RevisionGuard = preload("res://tests/second_layout_revision2_geometry_guard.gd")
var checks := 0
var failures: Array[String] = []
var states := 0
var joins := 0
var tread_triangles := 0
var seen := {}
var captured := {}
var baseline := {}
var stage: Node2D
var capture_baseline := false
var second_baseline := {}
var revision_guard := RevisionGuard.new()

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if "--capture-baseline" in OS.get_cmdline_user_args():
		push_error("Historical golden is sealed. Use --capture-second-layout-revision2 to write a separate review candidate; never recapture 1-1.")
		quit(1)
		return
	capture_baseline = "--capture-second-layout-revision2" in OS.get_cmdline_user_args()
	baseline = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	_check(FileAccess.get_sha256(BASELINE) == LEGACY_SHA, "historical geometry golden remains byte-for-byte sealed")
	if not capture_baseline: second_baseline = JSON.parse_string(FileAccess.get_file_as_string(SECOND_BASELINE))
	stage = Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	for level: Dictionary in levels:
		if str(level.id) != "1-2" and not capture_baseline: _state(Factory.create(str(level.id)))
	_second_revision_states()
	var mainline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in mainline.cases:
		if capture_baseline: break
		if not str(entry.name).begins_with("authored/"): continue
		for step: Dictionary in entry.steps: _state(Factory.create(str(entry.levelId), step.snapshot))
	var clouds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for entry: Dictionary in clouds.levels:
		if capture_baseline: break
		for step: Dictionary in entry.steps: _state(Factory.create(str(entry.id), step.snapshot))
	checks += revision_guard.checks
	failures.append_array(revision_guard.failures)
	if capture_baseline:
		var file := FileAccess.open(SECOND_CANDIDATE, FileAccess.WRITE)
		file.store_string(JSON.stringify({"levelId": "1-2", "layoutRevision": 2, "historicalBaselineSha256": LEGACY_SHA, "profileSha256": FileAccess.get_sha256("res://presentation/native/second_garden_profile.gd"), "surfaceSourceSha256": FileAccess.get_sha256("res://presentation/native/native_surface.gd"), "states": captured, "legacyComparison": revision_guard.reports}, "\t") + "\n")
		_check(captured.size() == 9, "capture contains only nine upper/lower 0-through-4 revision 2 topologies")
	else:
		var legacy_other: int = baseline.states.keys().filter(func(key: String) -> bool: return not key.begins_with("1-2/")).size()
		_check(states == legacy_other + second_baseline.states.size(), "all sealed historical and second revision topologies covered")
		_check(second_baseline.levelId == "1-2" and int(second_baseline.layoutRevision) == 2 and second_baseline.states.size() == 9, "revision golden has exact level and topology scope")
		_check(second_baseline.profileSha256 == FileAccess.get_sha256("res://presentation/native/second_garden_profile.gd"), "second authored height/profile geometry remains unchanged")
		_check(_json_equal(second_baseline.legacyComparison, revision_guard.reports), "reviewed historical boundary differences remain exact")
		_check(joins > 20 and tread_triangles > 100, "multi-level real stair coverage")
		_crossing_stairs()
	print(JSON.stringify({"suite": "native-surface-alignment", "passed": failures.is_empty(), "captureSecondLayoutRevision2": capture_baseline, "checks": checks, "states": states, "joins": joins, "treadTriangles": tread_triangles, "failures": failures, "gpuPixelsVerified": false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _second_revision_states() -> void:
	for route: Array in [["g:root:1:0", "g:root:2:0", "g:root:3:0", "g:root:3:1"], ["g:root:1:2", "g:root:2:2", "g:root:3:2", "g:root:3:1"]]:
		for length in range(5):
			var world: RefCounted = Factory.create("1-2")
			world.state.growth.root = route.slice(0, length)
			_state(world)

func _state(world: RefCounted) -> void:
	var tiles: Array = world.tiles()
	var key := str(world.level.id) + "/" + _digest(tiles)
	if seen.has(key): return
	seen[key] = true
	states += 1
	stage.set_world(world)
	var contracts := {}
	for id: String in stage._surfaces:
		var surface: Node3D = stage._surfaces[id]
		var contract := {"collision": _digest(surface._body.get_child(0).shape.get_faces()), "top": _mesh_digest(surface._top.mesh), "ramps": _mesh_digest(surface._ramps.mesh)}
		if surface.authored_terrace:
			contract.merge({"sides": _mesh_digest(surface._sides.mesh), "treads": _mesh_digest(surface._treads.mesh), "risers": _mesh_digest(surface._risers.mesh)})
		contracts[id] = contract
		if not capture_baseline:
			if surface.authored_terrace:
				var expected: Dictionary = second_baseline if str(world.level.id) == "1-2" else baseline
				_check(expected.states.has(key) and expected.states[key].has(id) and contract == expected.states[key][id], key + "/" + id + " support/collision and all meshes byte-identical to scoped golden")
			else:
				_real_steps(surface, key)
	if str(world.level.id) == "1-2": revision_guard.inspect(key, world, stage, contracts, baseline)
	if capture_baseline:
		captured[key] = contracts
		return
	for tile: Dictionary in tiles:
		var surface: Node3D = stage._surfaces[str(tile.id)]
		if surface.authored_terrace: continue
		for direction in range(4):
			if surface.rises[direction] >= -0.0001: continue
			var axis: Vector2 = Stage.DIRECTIONS[direction]
			for neighbor: Dictionary in tiles:
				if is_equal_approx(float(neighbor.x), float(tile.x) + axis.x) and is_equal_approx(float(neighbor.z), float(tile.z) + axis.y) and is_equal_approx(float(neighbor.h) - float(tile.h), surface.rises[direction] / 0.65):
					_join(surface, stage._surfaces[str(neighbor.id)], axis, key)

func _digest(value: Variant) -> String: return var_to_bytes(value).hex_encode().sha256_text()
func _mesh_digest(mesh: Mesh) -> String: return "empty" if mesh == null else _digest(mesh.surface_get_arrays(0))
func _json_equal(expected: Variant, actual: Variant) -> bool:
	# JSON numbers decode as float; typed in-memory arrays must compare by
	# exact values rather than their storage type. No numeric tolerance.
	if expected is Dictionary:
		if not actual is Dictionary or expected.size() != actual.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not _json_equal(expected[key], actual[key]): return false
		return true
	if expected is Array:
		if not actual is Array or expected.size() != actual.size(): return false
		for index in range(expected.size()):
			if not _json_equal(expected[index], actual[index]): return false
		return true
	return expected == actual

func _real_steps(surface: Node3D, key: String) -> void:
	_check(surface.generic_stairs, key + " uses common true stair geometry")
	_check(surface._treads.mesh == null, key + " no decorative stripes masquerading as stair edges")
	var visible := {}
	var collision := {}
	var horizontal := true
	var sampled := true
	var vertical := true
	var thin_closed: bool = not surface.thin_plate
	for part: MeshInstance3D in [surface._top, surface._ramps, surface._sides, surface._risers]:
		if part.mesh == null: continue
		var vertices: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in range(0, vertices.size(), 3):
			var triangle := PackedVector3Array([vertices[index], vertices[index + 1], vertices[index + 2]])
			visible[_digest(triangle)] = true
			var middle := (triangle[0] + triangle[1] + triangle[2]) / 3.0
			var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
			if part in [surface._top, surface._ramps]:
				horizontal = horizontal and absf(normal.y - 1.0) < 0.00001
				var global := surface.to_global(middle)
				sampled = sampled and absf(global.y - surface.sample_height(global)) < 0.00001
				if part == surface._ramps: tread_triangles += 1
			if part == surface._risers: vertical = vertical and absf(normal.y) < 0.00001
			if surface.thin_plate and normal.y < -0.99:
				thin_closed = true
				var global := surface.to_global(middle)
				_check(absf(surface.sample_height(global) - global.y - Surface.TRAVERSAL_THICKNESS) < 0.00001, key + " closed soffit retains exact slab thickness")
	var faces: PackedVector3Array = surface._body.get_child(0).shape.get_faces()
	for index in range(0, faces.size(), 3):
		collision[_digest(PackedVector3Array([faces[index], faces[index + 1], faces[index + 2]]))] = true
	_check(visible == collision, key + " visible structural faces and collision identical")
	_check(horizontal and sampled, key + " all tops are horizontal and agree with motor sampling")
	_check(vertical, key + " all risers are vertical")
	_check(thin_closed, key + " thin support has a closed bottom")
	var has_rise := false
	for rise: float in surface.rises: has_rise = has_rise or not is_zero_approx(rise)
	_check(not has_rise or (surface._ramps.mesh != null and surface._risers.mesh != null), key + " height-changing connection has real tread and riser meshes")

func _join(high: Node3D, low: Node3D, axis: Vector2, key: String) -> void:
	joins += 1
	var cross_axis := Vector2(-axis.y, axis.x)
	var faces: PackedVector3Array = high._sides.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if high._sides.mesh != null else PackedVector3Array()
	var wall_faces: Array = []
	for index in range(0, faces.size(), 3):
		var at_edge := true
		var triangle := PackedVector2Array()
		for vertex: Vector3 in [faces[index], faces[index + 1], faces[index + 2]]:
			if absf(Vector2(vertex.x, vertex.z).dot(axis) - 0.5) > 0.00001: at_edge = false
			triangle.append(Vector2(Vector2(vertex.x, vertex.z).dot(cross_axis), vertex.y))
		if at_edge: wall_faces.append(triangle)
	for across: float in [-0.47, -0.39, -0.35, 0.0, 0.35, 0.39, 0.47]:
		var at := axis * 0.5 + cross_axis * across
		var world_at := high.to_global(Vector3(at.x, 0, at.y))
		var upper: float = high.sample_height(world_at)
		var lower: float = low.sample_height(world_at)
		if absf(across) <= 0.32:
			_check(absf(upper - lower) < 0.00001, key + " walkable seam meets exactly")
		elif upper - lower > 0.0001:
			# Floating root/shadow/bridge slabs must retain their .20 thickness;
			# only that real slab edge is closed, never a new full-height pillar.
			if high.thin_plate: lower = maxf(lower, upper - Surface.TRAVERSAL_THICKNESS)
			for fraction: float in [0.2, 0.5, 0.8]:
				var probe := Vector2(across, lerpf(lower, upper, fraction) - high.global_position.y)
				var covered := false
				for triangle: PackedVector2Array in wall_faces:
					if Geometry2D.is_point_in_polygon(probe, triangle):
						covered = true
						break
				_check(covered, key + "/" + high.tile_id + " shoulder/platform gap closed at " + str(across))


func _crossing_stairs() -> void:
	# Mixed signs and perpendicular connections retain horizontal treads and
	# vertical walls; no diagonal shoulders may reintroduce a hidden ramp.
	var surface := Surface.new()
	root.add_child(surface)
	for rise_values: Array in [[0.65, 0.65, 0.0, 0.0], [0.65, -0.65, 0.65, -0.65], [-0.65, -0.65, 0.0, 0.65], [0.0, 0.65, 0.0, -0.65]]:
		var rises: Array[float] = []
		for value in rise_values: rises.append(float(value))
		surface.configure({"id": "probe", "x": 0, "z": 0, "h": 0}, rises, [true, true, true, true], -0.67, stage._terrain_materials())
		_real_steps(surface, "crossing/" + str(rise_values))
	surface.free()

