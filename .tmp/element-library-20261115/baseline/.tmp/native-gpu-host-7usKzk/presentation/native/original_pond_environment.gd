class_name OriginalPondEnvironment
extends Node3D
## Visual-only ecological layers. No PhysicsBody, collision or walkable surface.
## Geometry changes only when the level/real tile set changes; water height and
## animation use cached transforms/materials, independently of stage._props.
const PondSource = preload("res://presentation/world/garden_environment.gd")
const Paint = preload("res://presentation/world/garden_paint.gd")
const Dressing = preload("res://presentation/native/original_garden_dressing.gd")
const Art = preload("res://presentation/native/original_pond_art.gd")
const WaterShader = preload("res://presentation/native/original_pond_water.gdshader")
const BankShader = preload("res://presentation/native/original_pond_bank.gdshader")
const RibbonShader = preload("res://presentation/native/original_pond_ribbon.gdshader")
var geometry_key := 0
var builds := 0
var water: MeshInstance3D
var water_material: ShaderMaterial
var shoreline := PackedVector2Array()
var geography := {}
var frogs: Array[Dictionary] = []
var inventory := {}
var _materials := {}
const CAMERA_RIGHT := Vector3(.70710678, 0, -.70710678)
const CAMERA_UP := Vector3(-.35355339, .8660254, -.35355339)
var _presentation_rect := Rect2()

func refresh(stage: Node) -> void:
	if str(stage.world.level.get("chapter", "")) != "pond":
		visible = false
		return
	visible = true
	var key := hash([stage.world.level, stage._tiles])
	if geometry_key == key:
		update(stage)
		return
	geometry_key = key
	builds += 1
	for child in get_children(): remove_child(child); child.queue_free()
	frogs.clear()
	inventory = {"bank_props": 0, "meadow_shrubs": 0, "pads": 0, "reeds": 0, "frogs": 0, "leaves": 0, "moss": 0}
	geography = PondSource.build_pond_geometry(stage.world.level, stage._tiles)
	var bank: Array = geography.bank
	var outline := PackedVector2Array()
	for index in range(bank.size()):
		var point: Dictionary = bank[index]
		outline.append(_project(Vector2(float(point.x) + sin(index * .7) * .42, float(point.z) + cos(index * .9) * .36)))
	shoreline = _smooth(outline)
	_build_water(stage)
	_build_bank(stage, outline)
	_build_water_life(stage)
	for point: Dictionary in PondSource.residents(stage.world.level, stage._tiles): _frog(stage, point, frogs.size())
	inventory.frogs = frogs.size()
	set_meta("original_pond_inventory", inventory.duplicate(true))
	_cache_presentation_bounds()
	update(stage)

func presentation_bounds() -> Rect2:
	# The overview can union this projected silhouette with its existing tile
	# bounds without changing normal follow zoom. The expensive mesh/sprite
	# traversal happens only during refresh, never in the camera's frame loop.
	if not visible: return Rect2()
	return Rect2(_presentation_rect.position + Vector2(global_position.dot(CAMERA_RIGHT), global_position.dot(CAMERA_UP)), _presentation_rect.size)

func _cache_presentation_bounds() -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for child in get_children():
		if child is MeshInstance3D and child.mesh != null:
			var bounds: AABB = child.mesh.get_aabb()
			for index in range(8):
				var vertex: Vector3 = child.transform * bounds.get_endpoint(index)
				var point := Vector2(vertex.dot(CAMERA_RIGHT), vertex.dot(CAMERA_UP))
				low = low.min(point)
				high = high.max(point)
		elif child is Sprite3D and child.texture != null:
			var centre := Vector2(child.position.dot(CAMERA_RIGHT), child.position.dot(CAMERA_UP))
			var rect: Rect2 = child.get_item_rect()
			for corner: Vector2 in [rect.position, Vector2(rect.end.x,rect.position.y), rect.end, Vector2(rect.position.x,rect.end.y)]:
				# All ecology sprites are camera-facing; do not use their unused
				# identity world basis as if the card stood in the XY world plane.
				var point: Vector2 = centre + Vector2(corner.x,-corner.y) * child.pixel_size
				low = low.min(point)
				high = high.max(point)
	_presentation_rect = Rect2(low, high-low).grow(Dressing.canvas_width(.35)) if low.is_finite() else Rect2()

func update(stage: Node) -> void:
	if not visible or water_material == null: return
	var fx: Node3D = stage._garden_effects
	if is_instance_valid(fx) and is_instance_valid(fx.water):
		global_position.y = fx.water.global_position.y
	else:
		position.y = (-.55 + float(stage.world.state.get("water", 0)) * .18 if str(stage.world.level.id) == "2-1" else -.5) * .65
	var time := 0.0 if bool(stage.settings.get("lowMotion", false)) else float(stage.visual_time) / 1000.0
	water_material.set_shader_parameter("effect_time", time)
	for entry: Dictionary in frogs:
		var blink := fmod(time * 1000.0, 6200.0) > 6010.0
		if blink != bool(entry.blink):
			entry.sprite.texture = entry.closed if blink else entry.open
			entry.blink = blink
		entry.sprite.position.y = .025 + sin(time / 1.6 + float(entry.index)) * Dressing.canvas_width(.35)

static func _project(point: Vector2) -> Vector2:
	return Vector2((point.x - point.y) * 35.0, (point.x + point.y) * 17.5)

static func _unproject(point: Vector2) -> Vector2:
	return Vector2(point.x / 70.0 + point.y / 35.0, point.y / 35.0 - point.x / 70.0)

static func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size()):
		var a := (points[posmod(index - 1, points.size())] + points[index]) * .5
		var b := (points[index] + points[(index + 1) % points.size()]) * .5
		var segment := Paint.quadratic_points(a, points[index], b, 6)
		# Omit shared endpoints; duplicate vertices can invalidate triangulation.
		for sample in range(segment.size() - 1): result.append(segment[sample])
	return result

func _build_water(stage: Node) -> void:
	water_material = ShaderMaterial.new()
	water_material.shader = WaterShader
	water_material.set_shader_parameter("pigment", stage._texture("water-pigment"))
	water_material.set_shader_parameter("woodland", stage._texture("background-pond"))
	water = _polygon("OrganicPondWater", shoreline, 0.0, water_material)
	water.set_meta("original_water_outline", true)
	# An irregular shallow margin follows every organic edge; it has no walls.
	# landscape.ts strokes the outer moss at alpha 0x55. Opaque textured moss
	# made the same contour look like a continuous raised rim in native view.
	var shore_material := _material(Color("8da68b55"))
	var dark_material := _material(Color("537e7670"))
	# Bank layers are under the water face, matching the source's paint order;
	# the interior half is naturally covered instead of forming a raised tray.
	_ribbon("SoftMossShore", shoreline, 17.0, -.003, shore_material)
	_ribbon("ShallowShoreMargin", shoreline, 10.0, .003, dark_material)
	_ribbon("ShallowShoreLine", shoreline, 1.5, .006, _material(Color("d9ebe15c")))

func _build_bank(stage: Node, outline: PackedVector2Array) -> void:
	var minimum := INF
	var maximum := -INF
	for point in outline: minimum = minf(minimum, point.y); maximum = maxf(maximum, point.y)
	var rear := PackedVector2Array()
	for index in range(outline.size()):
		var point := outline[index]
		var seed := index * 29 % 67
		if point.y < minimum + (maximum - minimum) * .24: rear.append(point)
		if index % 3 != 0:
			_ellipse("MossPocket_" + str(index), point + Vector2(0,-2), Vector2(10 + seed % 18,5 + seed % 7), -.002, _material(Color("a7bd92"),stage._texture("paving-grass")))
			inventory.moss += 1
		if index % 5 == 0: _bank_sprite(stage, "river-rock" if index % 2 else "small-pebbles", point + Vector2(0,-2), 22 + seed % 16, index)
		if index % 4 == 1: _bank_sprite(stage,"fern",point,20 + seed % 10,index,.75)
		if index % 13 == 4 and point.y < minimum + (maximum-minimum)*.65: _bank_sprite(stage,"berry-bush" if index % 2 else "fern",point+Vector2(0,-5),33+seed%13,index)
		if index % 7 == 2:
			_art_sprite("BankLeaves_"+str(index),Art.leaves(),point+Vector2(0,-4),24*.7,18.0/22.0,.025)
			inventory.leaves += 1
	for index in range(2):
		if rear.is_empty(): break
		var point := rear[int(floor((rear.size()-1)*(.18 if index==0 else .76)))]
		var radii := Vector2(62,23) if index==0 else Vector2(48,18)
		_ellipse("MeadowBank_"+str(index),point+Vector2(0,-8),radii,-.001,_material(Color("a6bd8c"),stage._texture("paving-grass")))
		var pixels := 53.0 if index==0 else 44.0
		_bank_sprite(stage,"bush" if index==0 else "berry-bush",point+Vector2(-pixels*.2,-15),pixels,-1)
		inventory.bank_props -= 1
		inventory.meadow_shrubs += 1

func _build_water_life(stage: Node) -> void:
	for cell: Dictionary in geography.cells:
		if bool(cell.near): continue
		var seed := int(cell.seed)
		var point := _project(Vector2(float(cell.x)+.23,float(cell.z)+.15))
		if seed % 7 == 0:
			var pixels := 19.0 + float(seed % 11)
			_ground_image("WaterPad_"+str(cell.x)+"_"+str(cell.z),stage._texture("lilypad"),Rect2(point-Vector2(pixels*.5,pixels*.25),Vector2(pixels,pixels*.54)),.016)
			inventory.pads += 1
			if seed % 2 == 0: _art_sprite("TinyLotus_"+str(seed),Art.flower(),point,10,9.0/12.0,.019)
		if seed % 13 == 0:
			_art_sprite("Reeds_"+str(cell.x)+"_"+str(cell.z),Art.reeds(),point,24,40.0/42.0,.018)
			inventory.reeds += 1

func _frog(stage: Node, point: Dictionary, index: int) -> void:
	var source := Vector2(float(point.x),float(point.z))
	var at := _resident_position(stage, source)
	var projected := _project(at)
	_ground_image("ResidentPad_"+str(index),stage._texture("lilypad"),Rect2(projected+Vector2(-22,-9),Vector2(44,21)),.017)
	var sprite := _art_sprite("PondFrog_"+str(index),Art.frog(false),projected,64,32.0/48.0,.025)
	sprite.set_meta("original_resident_source",source)
	sprite.set_meta("original_resident_position",at)
	frogs.append({"sprite":sprite,"index":index,"blink":false,"open":Art.frog(false),"closed":Art.frog(true)})

func _resident_position(stage: Node, source: Vector2) -> Vector2:
	# The original 2-1 second candidate lies outside its own clipped water.
	# Keep the frog and complete 44x21 leaf, moving to the nearest real water
	# pocket rather than inventing collision or leaving a leaf over the sky.
	for ring in range(21):
		for angle in range(24 if ring>0 else 1):
			var at:=source+Vector2(cos(angle*TAU/24.0),sin(angle*TAU/24.0))*float(ring)*.15
			var projected:=_project(at)
			var valid:=true
			for corner:Vector2 in [Vector2(-23,-10),Vector2(23,-10),Vector2(23,13),Vector2(-23,13),Vector2.ZERO]:
				if not Geometry2D.is_point_in_polygon(projected+corner,shoreline): valid=false; break
			if not valid: continue
			for tile:Dictionary in stage._tiles:
				if absf(float(tile.x)-at.x)+absf(float(tile.z)-at.y)<1.45: valid=false; break
			if not valid: continue
			for module:Dictionary in stage.world.level.get("modules",[]):
				if absf(at.y-float(module.z))<3.0 and at.x>=float(module.x)-3.0 and at.x<=float(module.x)+absf(float(module.get("distance",0)))+3.0: valid=false; break
			if valid: return at
	push_error("No real water pocket for original pond resident: "+str(stage.world.level.id))
	return source

func _bank_sprite(stage: Node, alias: String, point: Vector2, pixels: float, index: int, alpha: float=1.0) -> void:
	var sprite := _art_sprite("Bank_"+alias.replace("-","_")+"_"+str(index),stage._texture(alias),point,pixels,1.0,.024)
	Dressing.ground_sprite(sprite,alias)
	sprite.modulate.a=alpha
	sprite.set_meta("original_bank_asset",alias)
	sprite.set_meta("original_bank_pixels",pixels)
	inventory.bank_props += 1

func _art_sprite(label: String, texture: Texture2D, point: Vector2, pixels: float, origin_y: float, height: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name=label
	sprite.texture=texture
	sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded=false
	sprite.no_depth_test=false
	sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.pixel_size=Dressing.canvas_width(pixels)/float(texture.get_width())
	sprite.offset=Vector2(0,float(texture.get_height())*(origin_y-.5))
	var at := _unproject(point)
	sprite.position=Vector3(at.x,height,at.y)
	add_child(sprite)
	return sprite

func _material(color: Color, texture: Texture2D=null) -> Material:
	var key := str(color)+":"+str(texture.get_instance_id() if texture else 0)
	if _materials.has(key): return _materials[key]
	if texture != null and texture.resource_path.ends_with("paving-grass.jpg"):
		var grass_material := ShaderMaterial.new()
		grass_material.shader = BankShader
		grass_material.set_shader_parameter("grass", texture)
		grass_material.set_shader_parameter("tint", color)
		_materials[key] = grass_material
		return grass_material
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.albedo_color=color
	material.albedo_texture=texture
	if texture or color.a < 1.0: material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_materials[key]=material
	return material

func _polygon(label: String, points: PackedVector2Array, height: float, material: Material, uvs: PackedVector2Array=PackedVector2Array()) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for point in points: low=low.min(point); high=high.max(point)
	var extent := (high-low).max(Vector2(.001,.001))
	for index in range(points.size()):
		var at := _unproject(points[index])
		vertices.append(Vector3(at.x,height,at.y))
		uv.append(uvs[index] if uvs.size()==points.size() else (points[index]-low)/extent)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=Geometry2D.triangulate_polygon(points)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=mesh
	node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _ground_image(label: String, texture: Texture2D, rect: Rect2, height: float) -> void:
	var points := PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
	# Water pads inherit the source canvas clip. Their edge cannot float beyond
	# the actual organic mesh merely because the centre is inside its bounds.
	var clipped := Geometry2D.intersect_polygons(points, shoreline)
	for index in range(clipped.size()):
		var polygon: PackedVector2Array = clipped[index]
		var uv := PackedVector2Array()
		for point in polygon: uv.append((point-rect.position)/rect.size)
		_polygon(label if index==0 else label+"_"+str(index),polygon,height,_material(Color.WHITE,texture),uv)

func _ellipse(label: String, centre: Vector2, radii: Vector2, height: float, material: Material) -> void:
	var points:=PackedVector2Array()
	for index in range(28): points.append(centre+Vector2(cos(index*TAU/28.0),sin(index*TAU/28.0))*radii)
	_polygon(label,points,height,material)

static func ribbon_arrays(points: PackedVector2Array, width: float, height: float) -> Array:
	# Every original contour vertex owns one pair of joined edge vertices.
	# Adjacent triangles share the same indices, including the closing seam.
	# Limit acute miters to twice the half-width instead of growing spikes.
	var vertices:=PackedVector3Array()
	var uv:=PackedVector2Array()
	var indices:=PackedInt32Array()
	var distance:=0.0
	for index in range(points.size()):
		var previous:=points[posmod(index-1,points.size())]
		var current:=points[index]
		var next:=points[(index+1)%points.size()]
		var incoming:=(current-previous).normalized()
		var outgoing:=(next-current).normalized()
		var normal_a:=Vector2(-incoming.y,incoming.x)
		var normal_b:=Vector2(-outgoing.y,outgoing.x)
		var join:=(normal_a+normal_b).normalized()
		if join.is_zero_approx(): join=normal_b
		var denominator:=maxf(absf(join.dot(normal_b)),.5)
		var offset:=join*width*.5/denominator
		if index>0: distance+=current.distance_to(previous)
		for edge in range(2):
			var point:=current+offset*(-1.0 if edge==0 else 1.0)
			var at:=_unproject(point)
			vertices.append(Vector3(at.x,height,at.y))
			uv.append(Vector2(distance/70.0,float(edge)))
		var a:=index*2
		var b:=((index+1)%points.size())*2
		indices.append_array(PackedInt32Array([a,b,b+1,a,b+1,a+1]))
	var arrays:Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

func _ribbon(label: String, points: PackedVector2Array, width: float, height: float, material: Material) -> void:
	var arrays:=ribbon_arrays(points,width,height)
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var ribbon_key:="ribbon:"+str(material.get_instance_id())
	if not _materials.has(ribbon_key):
		var ribbon:=ShaderMaterial.new()
		ribbon.shader=RibbonShader
		if material is ShaderMaterial and material.shader==BankShader:
			ribbon.set_shader_parameter("tint",material.get_shader_parameter("tint"))
			ribbon.set_shader_parameter("grass",material.get_shader_parameter("grass"))
			ribbon.set_shader_parameter("use_grass",true)
		elif material is StandardMaterial3D:
			ribbon.set_shader_parameter("tint",material.albedo_color)
		# Original water strokes are clipped by the filled pond; only the inner
		# half of each 10/1.5px stroke remains. The outer 17px moss is separate.
		ribbon.set_shader_parameter("inner_only",label!="SoftMossShore")
		_materials[ribbon_key]=ribbon
	var node:=MeshInstance3D.new()
	node.name=label
	node.mesh=mesh
	node.material_override=_materials[ribbon_key]
	node.set_meta("original_ribbon_pixels",width)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
