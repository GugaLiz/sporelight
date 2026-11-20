extends SceneTree

const Pond = preload("res://presentation/native/original_pond_environment.gd")
const World = preload("res://core/garden_world.gd")
const Art = preload("res://presentation/native/original_pond_art.gd")
const COUNTS := {"2-1": [48,25,2], "2-2": [36,19,2], "2-3": [42,22,1], "2-4": [36,19,2]}
var checks := 0
var failures: Array[String] = []
var rows: Array = []

class WaterCarrier extends Node3D:
	var water := MeshInstance3D.new()
	func _init() -> void:
		water.mesh = PlaneMesh.new()
		add_child(water)

class StageFixture extends Node3D:
	var world: RefCounted
	var _tiles: Array = []
	var _garden_effects := WaterCarrier.new()
	var visual_time := 0.0
	var settings := {"lowMotion": false}
	func _init() -> void: add_child(_garden_effects)
	func _texture(alias: String) -> Texture2D:
		if alias == "background-pond": return load("res://assets/images/garden-scenery/pond-rain-forest-v2.png")
		if alias in ["bush","lilypad"]: return load("res://assets/images/grid-world/" + alias + ".png")
		return load("res://assets/images/garden-scenery/" + alias + (".jpg" if alias in ["paving-grass","water-pigment"] else ".png"))

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	var fixture := StageFixture.new()
	root.add_child(fixture)
	var pond := Pond.new()
	fixture.add_child(pond)
	for id: String in COUNTS:
		fixture.world = World.new(id)
		fixture._tiles = fixture.world.tiles()
		fixture._garden_effects.water.position.y = -.3575 if id == "2-1" else -.325
		var snapshot: Dictionary = fixture.world.snapshot().duplicate(true)
		pond.refresh(fixture)
		_check(fixture.world.snapshot() == snapshot,id+" environment does not mutate rules/save")
		_check(pond.geography.bank.size() == COUNTS[id][0],id+" original bank samples")
		_check(pond.inventory.bank_props == COUNTS[id][1],id+" original bank rocks/ferns/shrubs")
		_check(pond.inventory.meadow_shrubs == 2,id+" two broad back-bank shrubs")
		_check(pond.frogs.size() == COUNTS[id][2],id+" original resident count")
		var resident_pads:=0
		for child in pond.get_children():
			if str(child.name).begins_with("ResidentPad_"): resident_pads+=1
		_check(resident_pads==COUNTS[id][2],id+" every frog has a complete leaf on actual water")
		for frog:Dictionary in pond.frogs:
			var at:Vector2=frog.sprite.get_meta("original_resident_position")
			for corner:Vector2 in [Vector2(-22,-9),Vector2(22,-9),Vector2(22,12),Vector2(-22,12)]:
				_check(Geometry2D.is_point_in_polygon(Pond._project(at)+corner,pond.shoreline),id+" full frog leaf footprint stays within organic water")
		_check(pond.water.mesh is ArrayMesh,id+" organic water is polygon mesh")
		var arrays: Array = pond.water.mesh.surface_get_arrays(0)
		_check(arrays[Mesh.ARRAY_INDEX].size()>6,id+" organic water is not a rectangle")
		_check(pond.shoreline.size()==COUNTS[id][0]*6,id+" original smooth contour samples retained")
		_check(pond.find_children("*","CollisionObject3D",true,false).is_empty(),id+" no walkable support/collision")
		_check(pond.inventory.pads>0 and pond.inventory.reeds>0,id+" original water seed creates pads and reeds")
		_check_ribbons(pond,id)
		var presentation:Rect2=pond.presentation_bounds()
		_check(presentation.has_area(),id+" overview ecological bounds exist")
		for child in pond.get_children():
			if child is MeshInstance3D:
				var box:AABB=child.mesh.get_aabb()
				for corner in range(8):
					var vertex:Vector3=child.global_transform*box.get_endpoint(corner)
					_check(presentation.grow(.001).has_point(Vector2(vertex.dot(Pond.CAMERA_RIGHT),vertex.dot(Pond.CAMERA_UP))),id+" overview includes full ecological mesh")
		for child in pond.get_children():
			if child is Sprite3D:
				_check(child.texture!=null,id+" complete environment art exists/"+str(child.name))
				_check(not child.no_depth_test,id+" props retain normal depth testing")
			if child.has_meta("original_bank_pixels"):
				var pixels:=float(child.get_meta("original_bank_pixels"))
				_check(is_equal_approx(child.pixel_size*child.texture.get_width(),pixels*sqrt(2.0)/70.0),id+" bank art uses original tile-relative size")
			if str(child.name).begins_with("WaterPad_") or str(child.name).begins_with("Reeds_"):
				var at: Vector2
				if child is Sprite3D: at=Vector2(child.position.x,child.position.z)
				else:
					var bounds: AABB=child.mesh.get_aabb()
					var centre:=bounds.get_center()
					at=Vector2(centre.x,centre.z)
				_check(Geometry2D.is_point_in_polygon(Pond._project(at),pond.shoreline),id+" water life is inside organic water")
		var builds:=pond.builds
		var mesh_id:=pond.water.mesh.get_instance_id()
		var child_ids:=_ids(pond)
		var cache_size:=Art._textures.size()
		for time: float in [0.0,1000.0,6100.0,6300.0]:
			fixture.visual_time=time
			fixture._garden_effects.water.position.y=-.2+time*.00001
			pond.update(fixture)
			_check(is_equal_approx(pond.global_position.y,fixture._garden_effects.water.global_position.y),id+" environment follows actual carrier height")
			_check(pond.builds==builds and pond.water.mesh.get_instance_id()==mesh_id and _ids(pond)==child_ids,id+" animation does not rebuild geometry/nodes")
			_check(Art._textures.size()==cache_size,id+" blinking uses already cached textures")
			_check(pond.presentation_bounds().size.is_equal_approx(presentation.size),id+" dynamic water height translates cached overview bounds without rebuild")
		pond.refresh(fixture)
		_check(pond.builds==builds,id+" same tile set refresh uses cached geometry")
		var resident_positions:Array=[]
		for frog:Dictionary in pond.frogs:
			var source:Vector2=frog.sprite.get_meta("original_resident_source")
			var actual:Vector2=frog.sprite.get_meta("original_resident_position")
			resident_positions.append({"source":[source.x,source.y],"actual":[actual.x,actual.y]})
		rows.append({"level":id,"bankSamples":pond.geography.bank.size(),"inventory":pond.inventory.duplicate(true),"meshVertices":arrays[Mesh.ARRAY_VERTEX].size(),"meshIndices":arrays[Mesh.ARRAY_INDEX].size(),"children":pond.get_child_count(),"residents":resident_positions})
		if id in ["2-1","2-4"]:
			for state_index in [1,0]:
				if id=="2-1": fixture.world.state.water=state_index
				elif state_index==1: fixture.world.state.flags.append("pollinated")
				else: fixture.world.state.flags.erase("pollinated")
				fixture._tiles=fixture.world.tiles()
				var prior_builds:=pond.builds
				var state_snapshot:Dictionary=fixture.world.snapshot().duplicate(true)
				pond.refresh(fixture)
				_check(pond.builds==prior_builds+1,id+" changed real tile set rebuilds environmental exclusions once")
				_check(fixture.world.snapshot()==state_snapshot,id+" state cycle remains visual-only")
				_check(pond.frogs.size()==COUNTS[id][2],id+" state cycle preserves residents")
				_check(pond.find_children("*","CollisionObject3D",true,false).is_empty(),id+" state cycle adds no collision")
				pond.refresh(fixture)
				_check(pond.builds==prior_builds+1,id+" repeated state refresh remains cached")
	fixture.world=World.new("1-3")
	fixture._tiles=fixture.world.tiles()
	pond.refresh(fixture)
	_check(not pond.visible,"non-pond level hides the independent environment")
	var file:=FileAccess.open("res://../docs/qa-godot-native/original-elements-audit/native-pond-headless.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"CPU-only original pond geometry, inventory, support isolation, size and cached animation; no GPU acceptance","rows":rows},"  ")+"\n")
	print(JSON.stringify({"checks":checks,"failures":failures.size(),"rows":rows}))
	fixture.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _ids(node: Node) -> Array:
	var result: Array=[]
	for child in node.get_children(): result.append(child.get_instance_id())
	return result

func _check_ribbons(pond:Node,id:String)->void:
	for label:String in ["SoftMossShore","ShallowShoreMargin","ShallowShoreLine"]:
		var node:MeshInstance3D=pond.get_node(label)
		var arrays:Array=node.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var count:int=pond.shoreline.size()
		var pixels:float=node.get_meta("original_ribbon_pixels")
		var material:ShaderMaterial=node.material_override
		_check(bool(material.get_shader_parameter("inner_only"))==(label!="SoftMossShore"),id+" original water-edge strokes clipped to pond interior/"+label)
		if label=="SoftMossShore":
			_check(material.get_shader_parameter("tint").is_equal_approx(Color("8da68b55")),id+" outer moss preserves source translucent stroke, not opaque rim")
		_check(pixels==17.0 if label=="SoftMossShore" else pixels==10.0 if label=="ShallowShoreMargin" else pixels==1.5,id+" original shore width retained/"+label)
		_check(vertices.size()==count*2 and indices.size()==count*6,id+" one shared pair per shoreline join/"+label)
		var edge_uses:Dictionary={}
		for tri in range(0,indices.size(),3):
			var a:=indices[tri]
			var b:=indices[tri+1]
			var c:=indices[tri+2]
			_check((vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).length()>.0000001,id+" joined shore triangle has nonzero area")
			for pair:Array in [[a,b],[b,c],[c,a]]:
				var key:=str(mini(pair[0],pair[1]))+":"+str(maxi(pair[0],pair[1]))
				edge_uses[key]=int(edge_uses.get(key,0))+1
		for index in range(count):
			var a:=index*2
			var join_key:=str(a)+":"+str(a+1)
			_check(int(edge_uses.get(join_key,0))==2,id+" every join including wraparound is shared by both segments")
			var left:=Pond._project(Vector2(vertices[a].x,vertices[a].z))
			var right:=Pond._project(Vector2(vertices[a+1].x,vertices[a+1].z))
			_check(((left+right)*.5).distance_to(pond.shoreline[index])<.001,id+" miter stays centred on original shore")
			_check(left.distance_to(right)<=pixels*2.0+.001,id+" acute miter never spikes beyond limit")
		for uses:int in edge_uses.values():_check(uses in [1,2],id+" manifold shore has no overlaid segment edges")
