extends RefCounted
## Test-only migration audit. The historical golden remains authoritative for
## every retained surface; changed triangles must lie on newly exposed edges.
const Surface = preload("res://presentation/native/native_surface.gd")
const REMOVED := ["f:3:1", "f:4:2"]
const EXPECTED := {
	"f:4:1": ["collision", "sides", "treads"],
	"f:5:2": ["collision", "sides", "treads"],
	"g:root:3:0": ["collision", "sides"],
}
var checks := 0
var failures: Array[String] = []
var reports := {}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func inspect(key: String, world: RefCounted, stage: Node, contracts: Dictionary, legacy: Dictionary) -> void:
	var old_key := ""
	var roots: Array = contracts.keys().filter(func(id: String) -> bool: return id.begins_with("g:") and id != "g:root:3:1")
	# The historical file contains only upper-route prefixes. Lower-route
	# surfaces are new coverage; retained fixed cells still compare to prefix 0.
	if roots.any(func(id: String) -> bool: return id.ends_with(":2")): roots.clear()
	roots.sort()
	for candidate: String in legacy.states:
		if not candidate.begins_with("1-2/"): continue
		var candidate_roots: Array = legacy.states[candidate].keys().filter(func(id: String) -> bool: return id.begins_with("g:"))
		candidate_roots.sort()
		if candidate_roots == roots: old_key = candidate; break
	check(not old_key.is_empty(), key + " has a matching historical upper-prefix or fixed-board reference")
	if old_key.is_empty(): return
	var previous: Dictionary = legacy.states[old_key]
	var changed := {}
	var retained := 0
	var added := []
	for id: String in REMOVED: check(not contracts.has(id), key + " removed fixed approach stays absent: " + id)
	for id: String in previous:
		if id in REMOVED: continue
		check(contracts.has(id), key + " retains historical surface " + id)
		if not contracts.has(id): continue
		retained += 1
		var fields := []
		for field: String in previous[id]:
			if contracts[id][field] != previous[id][field]: fields.append(field)
		fields.sort()
		check(fields == EXPECTED.get(id, []), key + "/" + id + " only reviewed boundary fields change: " + str(fields))
		if not fields.is_empty():
			changed[id] = {"fields": fields, "faces": _audit_added_faces(key, id, world, stage, previous[id])}
	for id: String in contracts:
		if not previous.has(id):
			added.append(id)
			check(id.begins_with("g:"), key + " only authored root cells are new surfaces")
			_thin_slab(key, stage._surfaces[id])
	added.sort()
	reports[key] = {"legacyKey": old_key, "retainedCompared": retained, "removed": REMOVED, "changed": changed, "newRootSurfaces": added}

func _audit_added_faces(key: String, id: String, world: RefCounted, stage: Node, previous: Dictionary) -> Dictionary:
	var surface: Node3D = stage._surfaces[id]
	var tile: Dictionary = stage._tile_map[id]
	var fixed: Array = world.level.tiles.duplicate(true)
	fixed.append_array([{"x": 3, "z": 1}, {"x": 4, "z": 2}])
	var exposed: Array[bool] = []
	var new_edges: Array[int] = []
	for index in range(4):
		var direction: Vector2 = stage.DIRECTIONS[index]
		var there := Vector2(float(tile.x), float(tile.z)) + direction
		exposed.append(not fixed.any(func(other: Dictionary) -> bool: return Vector2(float(other.x), float(other.z)) == there))
		if there in [Vector2(3, 1), Vector2(4, 2)]: new_edges.append(index)
	var old := Surface.new()
	stage.get_tree().root.add_child(old)
	old.configure(tile, surface.rises, exposed, stage._terrain_profile.foundation(tile), stage._terrace_materials(tile))
	check(contract(old) == previous, key + "/" + id + " test-only old-neighbor reconstruction exactly matches sealed golden")
	var result := {}
	for part: String in ["sides", "treads", "collision"]:
		var before := _triangles(_vertices(old, part))
		var after := _triangles(_vertices(surface, part))
		var additions := 0
		var correct_edges := true
		for hash_key: String in before: check(after.has(hash_key), key + "/" + id + " retains old " + part + " triangle")
		for hash_key: String in after:
			if before.has(hash_key): continue
			additions += 1
			var on_allowed_edge := false
			for edge: int in new_edges:
				var axis: Vector2 = stage.DIRECTIONS[edge]
				var aligned := true
				for vertex: Vector3 in after[hash_key]:
					aligned = aligned and absf(Vector2(vertex.x, vertex.z).dot(axis) - (0.502 if part == "treads" else 0.5)) < 0.00001
				on_allowed_edge = on_allowed_edge or aligned
			correct_edges = correct_edges and on_allowed_edge
		check(correct_edges, key + "/" + id + " all new " + part + " triangles belong only to deleted-neighbor faces")
		result[part] = {"addedTriangles": additions, "retainedTriangles": before.size(), "edgeIndices": new_edges}
	old.free()
	return result

func _thin_slab(key: String, surface: Node3D) -> void:
	check(surface.authored_terrace and surface.thin_plate, key + "/" + surface.tile_id + " uses unchanged authored profile and thin slab")
	var complete := {}
	var bottom_faces := 0
	var height_valid := true
	for part: String in ["top", "ramps", "sides", "risers"]:
		var triangles := _triangles(_vertices(surface, part))
		for hash_key: String in triangles:
			complete[hash_key] = true
			var below := true
			for vertex: Vector3 in triangles[hash_key]:
				height_valid = height_valid and vertex.y >= -0.20001 and vertex.y <= 0.00001
				below = below and absf(vertex.y + 0.20) < 0.00001
			if below: bottom_faces += 1
	check(height_valid and bottom_faces > 0, key + "/" + surface.tile_id + " flat support at zero and closed soffit at minus .20, no foundation column")
	var collision := _triangles(_vertices(surface, "collision"))
	check(collision.size() == complete.size() and collision.keys().all(func(id: String) -> bool: return complete.has(id)), key + "/" + surface.tile_id + " structural faces exactly match collision")
	for x: float in [-0.49, 0.0, 0.49]:
		for z: float in [-0.49, 0.0, 0.49]:
			var at: Vector3 = surface.to_global(Vector3(x, 0, z))
			check(absf(surface.sample_height(at)) < 0.00001, key + "/" + surface.tile_id + " whole root tread stays at authored height zero")

static func _digest(value: Variant) -> String: return var_to_bytes(value).hex_encode().sha256_text()
static func _mesh_digest(mesh: Mesh) -> String: return "empty" if mesh == null else _digest(mesh.surface_get_arrays(0))
static func contract(surface: Node3D) -> Dictionary:
	var value := {"collision": _digest(surface._body.get_child(0).shape.get_faces()), "top": _mesh_digest(surface._top.mesh), "ramps": _mesh_digest(surface._ramps.mesh)}
	if surface.authored_terrace: value.merge({"sides": _mesh_digest(surface._sides.mesh), "treads": _mesh_digest(surface._treads.mesh), "risers": _mesh_digest(surface._risers.mesh)})
	return value
static func _vertices(surface: Node3D, part: String) -> PackedVector3Array:
	if part == "collision": return surface._body.get_child(0).shape.get_faces()
	var mesh: Mesh = surface.get("_" + part).mesh
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mesh != null else PackedVector3Array()
static func _triangles(vertices: PackedVector3Array) -> Dictionary:
	var result := {}
	for index in range(0, vertices.size(), 3):
		var triangle := PackedVector3Array([vertices[index], vertices[index + 1], vertices[index + 2]])
		result[_digest(triangle)] = triangle
	return result
