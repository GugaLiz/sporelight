extends SceneTree
const Foundations = preload("res://presentation/native/island_foundations.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Surface = preload("res://presentation/native/native_surface.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Profiles = preload("res://presentation/native/level_presentation_profiles.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _tile(id: String, x: int, z: int, h: int, kind := "fixed") -> Dictionary:
	return {"id": id, "x": x, "z": z, "h": h, "kind": kind}

func _contracts() -> void:
	var tiles := [_tile("a", 0, 0, 0), _tile("a-high", 1, 0, 2), _tile("b", 3, 0, 3), _tile("c", 9, 0, -2), _tile("root", 2, 0, 1, "root")]
	var saved := tiles.duplicate(true)
	var bottoms := Foundations.bottoms(tiles)
	_check(tiles == saved, "foundation query never mutates source tiles")
	_check(is_equal_approx(bottoms.a, -0.67) and is_equal_approx(bottoms["a-high"], -0.67), "connected high and low tiles share a solid common foundation")
	_check(is_equal_approx(bottoms.b, 1.28), "independent high island retains .67 thickness")
	_check(is_equal_approx(bottoms.c, -1.97), "independent low island does not thicken unrelated islands")
	for kind: String in ["root", "shadow", "bridge", "module", "lift", "gate"]:
		tiles[-1].kind = kind
		tiles[-1].module = "moving"
		var result := Foundations.bottoms(tiles)
		_check(is_equal_approx(result.a, -0.67) and is_equal_approx(result.b, 1.28), kind + " cannot merge fixed island foundations")
		if kind in ["root", "shadow", "bridge"]:
			_check(is_equal_approx(result.root, 0.45), kind + " retains .20 thin slab")
	var module_a := _tile("m:one:0:0", 2, 0, 1, "module")
	module_a.module = "one"
	var module_b := _tile("m:one:1:0", 20, 0, 2, "module")
	module_b.module = "one"
	var module_c := _tile("m:two:0:0", 3, 0, 3, "module")
	module_c.module = "two"
	var parts := [module_a, module_b, module_c]
	var low := Foundations.bottoms(parts)
	_check(is_equal_approx(low[module_a.id], -0.02) and is_equal_approx(low[module_b.id], -0.02), "module identity groups all rigid cells even across gaps")
	_check(is_equal_approx(low[module_c.id], 1.28), "adjacent modules retain independent bottoms")
	for part: Dictionary in parts: part.h += 3
	var high := Foundations.bottoms(parts)
	for id: String in low: _check(is_equal_approx(high[id] - low[id], 1.95), "lifting moves bottom by exactly the support elevation")
	var reordered := tiles.duplicate(true)
	reordered.reverse()
	_check(Foundations.bottoms(reordered) == Foundations.bottoms(tiles), "grouping is independent of tile enumeration")
	for tile: Dictionary in reordered: tile.visible = false
	_check(Foundations.bottoms(reordered) == Foundations.bottoms(tiles), "visibility is never used for grouping")

func _mesh_vertices(mesh: Mesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mesh != null else PackedVector3Array()

func _upward_faces(surface: Node) -> PackedVector3Array:
	var result := PackedVector3Array()
	var faces: PackedVector3Array = surface._body.get_child(0).shape.get_faces()
	for index in range(0, faces.size(), 3):
		var normal := (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index])
		if absf(normal.y) > 0.000001:
			result.append_array(faces.slice(index, index + 3))
	return result

func _run() -> void:
	_contracts()
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	for id: String in ["1-1", "1-2"] + Profiles.CHAPTER_LEVELS:
		var world: RefCounted = Cloud.new(id) if id.begins_with("cloud") else World.new(id)
		stage.set_world(world)
		var tiles: Array = world.tiles()
		var old_minimum := 0.0
		for tile: Dictionary in tiles: old_minimum = minf(old_minimum, float(tile.h) * 0.65)
		var bottom_map := Foundations.bottoms(tiles)
		var snapshot: Dictionary = world.snapshot().duplicate(true)
		for tile: Dictionary in tiles:
			var actual: Node = stage._surfaces[str(tile.id)]
			var materials: Dictionary = stage._terrace_materials(tile) if stage._terrain_profile != null else stage._terrain_materials()
			var exposed: Array[bool] = [true, true, true, true]
			# Compare independent surfaces with identical all-exposed boundaries:
			# only bottom differs, never top vertices/ramp rises or support faces.
			var original := Surface.new()
			var adjusted := Surface.new()
			root.add_child(original)
			root.add_child(adjusted)
			var old_bottom: float = stage._terrain_profile.foundation(tile) if stage._terrain_profile != null else old_minimum - 0.95
			var new_bottom: float = stage._terrain_profile.foundation(tile) if stage._terrain_profile != null else bottom_map[str(tile.id)]
			original.configure(tile, actual.rises, exposed, old_bottom, materials)
			adjusted.configure(tile, actual.rises, exposed, new_bottom, materials)
			_check(original.rises == adjusted.rises and original.transform == adjusted.transform, id + "/" + str(tile.id) + " top elevation and ramp rises unchanged")
			for property: String in ["_top", "_ramps", "_treads", "_risers"]:
				_check(_mesh_vertices(original.get(property).mesh) == _mesh_vertices(adjusted.get(property).mesh), id + "/" + str(tile.id) + " unchanged " + property)
			_check(_upward_faces(original) == _upward_faces(adjusted), id + "/" + str(tile.id) + " collision support triangles unchanged")
			if original.thin_plate or stage._terrain_profile != null:
				_check(original._body.get_child(0).shape.get_faces() == adjusted._body.get_child(0).shape.get_faces(), id + " protected profiles/thin bridges retain entire collision")
			else:
				var integrated_bottom := INF
				for vertex: Vector3 in _mesh_vertices(actual._sides.mesh): integrated_bottom = minf(integrated_bottom, vertex.y + actual.position.y)
				if is_finite(integrated_bottom):
					var exterior := false
					for direction: Vector2 in Stage.DIRECTIONS:
						if not stage._has_neighbor(tile, direction): exterior = true
					if exterior:
						_check(is_equal_approx(integrated_bottom, new_bottom), id + "/" + str(tile.id) + " exposed island wall reaches its local foundation")
					else:
						# An interior ramp cut face stops on the adjoining terrace;
						# it is not an exposed full-height foundation perimeter.
						_check(integrated_bottom >= new_bottom - 0.00001, id + "/" + str(tile.id) + " internal cut face stays inside its island foundation")
			original.free()
			adjusted.free()
		_check(world.snapshot() == snapshot, id + " foundation creation leaves rules/saves unchanged")
	# Cloud lift must not become the fixed bank's base at its high endpoint.
	for raised: int in [0, 1]:
		var cloud := Cloud.new("cloud-2")
		cloud.state.turns.lift = raised
		var bottoms := Foundations.bottoms(cloud.tiles())
		_check(is_equal_approx(bottoms["lift:6:3"], raised * 1.95 - 0.67), "cloud lift keeps .67 thickness in each docked height")
		_check(is_equal_approx(bottoms["floor:8:3"], 1.28), "cloud high bank thickness is independent of lift height")
	print(JSON.stringify({"suite": "native-island-foundations", "checks": checks, "passed": failures.is_empty(), "failures": failures, "gpuPixelsVerified": false}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
