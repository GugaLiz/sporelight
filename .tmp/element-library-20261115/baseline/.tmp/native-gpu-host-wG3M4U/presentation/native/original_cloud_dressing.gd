extends RefCounted
## Original cloud architecture. All nodes are decorative, with normal depth.
const Art = preload("res://presentation/native/original_cloud_art.gd")
const PIXEL := 1.41421356237 / 58.0
const RIGHT := Vector3(0.70710678, 0, -0.70710678)
const FRONT := Vector3(0.70710678, 0, 0.70710678)
const COS_ELEVATION := 0.8660254
# Source identity -> fixed same-height display placement. These authored
# exceptions clear actual pad/turn bases and pots, never actor-dependent.
const FLOWER_PLACEMENTS := {
	"cloud-3": {
		"floor:3:6": {"at":Vector2(2.25,6.20),"support":"floor:2:6"},
		"floor:8:5": {"at":Vector2(7.10,6.15),"support":"floor:7:6"},
		"floor:9:7": {"at":Vector2(8.70,7.12),"support":"floor:9:7"},
		"floor:13:4": {"at":Vector2(14,4),"support":"floor:14:4"}
	}
}
static var _skies: Dictionary = {}
static var _lift_top: StandardMaterial3D

static func lift_top() -> StandardMaterial3D:
	if _lift_top != null: return _lift_top
	# renderer.ts uses a 36x18 inset on the 58x29 tile and an 8x4
	# centre ellipse. A square and a circle on the real top reproduce both
	# isometric silhouettes, and travel with the existing support mesh.
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	var inset_half := 18.0 / 58.0
	var radius := 4.0 * sqrt(2.0) / 58.0
	for y in range(256):
		for x in range(256):
			var at := (Vector2(x,y)+Vector2.ONE*.5)/256.0-Vector2.ONE*.5
			var color := Color("cadcce")
			if absf(at.x) <= inset_half and absf(at.y) <= inset_half: color = Color("b2c9b5")
			if at.length() <= radius: color = Color("f8f2d3")
			image.set_pixel(x,y,color)
	image.generate_mipmaps()
	_lift_top = StandardMaterial3D.new()
	_lift_top.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lift_top.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lift_top.albedo_texture = ImageTexture.create_from_image(image)
	_lift_top.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _lift_top

static func scenery(stage: Node) -> void:
	var complete := bool(stage.world.state.completed)
	match str(stage.world.level.id):
		"cloud-1":
			_place(stage,"plant_large",0,6,0)
			_place(stage,"bench",2,8,0)
			_place(stage,"arch",3,-4,1,0.8)
			# Its full original base extends .0345 beyond the north terrace
			# edge. Slide within the same floor, preserving size and source root.
			var tower := _place(stage,"tower",10,2,1,1,complete)
			tower.position.z += .08
			tower.set_meta("placement_reason","full_base_same_height_terrace")
			var end_plant := _place(stage,"plant",11,4,1)
			_relocate(stage,end_plant,Vector2(11.10,3.65),"floor:11:4","separate_finish_disc")
			_place(stage,"plant",5,2,1)
		"cloud-2":
			_place(stage,"arch",3,3,0,0.9)
			_place(stage,"pool",10,3,3,1,complete)
			_place(stage,"plant_large",8,3,3)
			_place(stage,"bench",0,7,0)
			if complete:
				# The original painter drew the bird over the pool. With real depth,
				# that point hides its entire body behind the front pool wall.
				# Move along the same upper terrace to the near rim, never upward.
				var bird := _place(stage,"bird",11.2,4.4,3)
				bird.set_meta("source_point",Vector3(11,3,3))
				bird.set_meta("placement_reason","near_pool_rim_same_height")
				_waterfall(stage)
		"cloud-3":
			var arch := _place(stage,"arch_pink",7,5,1,0.95)
			arch.position += Vector3(.05,0,.05)
			arch.set_meta("placement_reason","full_base_same_height_terrace")
			_place(stage,"bench",8,-1,1)
			_place(stage,"plant",9,7,1)
			_place(stage,"plant",13,4,1)
			_place(stage,"lanterns",8,-1,1,1,complete)
			if complete: _place(stage,"sky_stars",8,-1,1)
	if complete:
		for tile: Dictionary in stage.world.tiles():
			if str(tile.get("kind","")) == "floor" and (int(tile.x)*7+int(tile.z)*13)%11 == 0:
				var flowers := _place(stage,"flowers",float(tile.x),float(tile.z),float(tile.h))
				var placement: Dictionary = FLOWER_PLACEMENTS.get(str(stage.world.level.id),{}).get(str(tile.id),{})
				if not placement.is_empty():
					_relocate(stage,flowers,placement.at,str(placement.support),"clear_control_or_planter")

static func planter(stage: Node, parent: Node3D) -> void:
	_card(parent,"finish",1,bool(stage.world.state.completed))

static func build_mark(stage: Node, parent: Node3D, mark: Dictionary) -> bool:
	if not str(stage.world.level.id).begins_with("cloud-"): return false
	var id := str(mark.id)
	if id == "finish": planter(stage,parent)
	elif id in ["turn","pad","valve","dock"]: _card(parent,id)
	elif id == "seed" and not bool(stage.world.state.cloudSeed): _card(parent,"seed")
	if id in stage.world.state.get("observations",[]):
		var flowers := _card(parent,"story_flowers")
		if str(stage.world.level.id) == "cloud-2" and id == "bird":
			# Leave the bird, its observation support and the pool outlet in place.
			# Separate all three stems in projection from both completed and
			# clear-view stances; retain real support on the same upper terrace.
			flowers.position += Vector3(-.60,0,.23)
			flowers.set_meta("display_offset",Vector3(-.60,0,.23))
	# Existing native action badges retain keyboard/touch affordances and hitboxes.
	# The original latch/story/collected seed has no additional physical base.
	return true

static func _place(stage: Node, kind: String, x: float,z: float,h: float, factor := 1.0, complete := false) -> Node3D:
	var root := Node3D.new()
	root.name = "OriginalCloud_" + kind + "_%s_%s" % [x,z]
	stage._props.add_child(root)
	var tile_id := "floor:%s:%s" % [int(x),int(z)]
	var point: Vector3 = stage.tile_position({"x":x,"z":z,"h":h})
	var surface: Node3D = stage._surfaces.get(tile_id)
	if surface != null: point.y = float(surface.sample_height(point))
	root.position = stage._props.to_local(point)
	root.set_meta("original_kind",kind)
	root.set_meta("original_point",Vector3(x,h,z))
	root.set_meta("support_id",tile_id)
	root.set_meta("complete",complete)
	_card(root,kind,factor,complete)
	return root

static func _relocate(stage: Node, root: Node3D, at: Vector2, support_id: String, reason: String) -> void:
	var point := Vector3(at.x,root.global_position.y,at.y)
	var support: Node3D = stage._surfaces.get(support_id)
	if support != null: point.y = float(support.sample_height(point))
	root.position = stage._props.to_local(point)
	root.set_meta("support_id",support_id)
	root.set_meta("placement_reason",reason)

static func _card(parent: Node3D, kind: String, factor := 1.0, complete := false, hanging := false) -> Sprite3D:
	var art: Dictionary = Art.art(kind,complete)
	var bounds: Rect2 = art.bounds
	var foot := 0.0 if hanging else float(art.foot)
	var sprite := Sprite3D.new()
	sprite.name = "Original_" + kind
	sprite.texture = art.texture
	sprite.pixel_size = PIXEL * factor / 2.0
	sprite.rotation.y = PI/4
	sprite.scale.y = 1.0 / COS_ELEVATION
	# Vertical card, with its source frontmost base anchored on the ground.
	# The ground offset preserves the original projected origin (no lift cheat).
	sprite.position = FRONT * (foot * PIXEL * factor / 0.5)
	sprite.offset = Vector2(bounds.get_center().x, foot-bounds.get_center().y)*2.0
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.no_depth_test = false
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.set_meta("source_bounds",bounds)
	sprite.set_meta("source_foot",foot)
	sprite.set_meta("source_pixel_world",PIXEL*factor)
	parent.add_child(sprite)
	return sprite

static func _waterfall(stage: Node) -> void:
	var root := Node3D.new()
	root.name = "OriginalCloudWaterfall"
	stage._props.add_child(root)
	# Original screen x+38 crossed a solid platform in true 3D. The lip is on
	# the actual east exterior of floor:11:3, fed by the adjacent restored pool.
	var point: Vector3 = stage.tile_position({"x":11.5,"z":3.0,"h":3})
	var surface: Node3D = stage._surfaces.get("floor:11:3")
	if surface != null: point.y = float(surface.sample_height(point))
	root.position = stage._props.to_local(point)
	root.set_meta("original_kind","waterfall")
	root.set_meta("support_id","floor:11:3")
	var fall := _card(root,"waterfall",1,false,true)
	fall.position += RIGHT*(-38*PIXEL) + Vector3.UP*(-5*PIXEL/COS_ELEVATION)
	# Water crosses the coping to an open fall, without adding support/collision.
	stage._box(root,Vector3(0.15,0.025,0.34),Vector3(-0.055,0.01,0),Color("badcda"))
	for i in range(3):
		var drop := _card(root,"drop",1,false,true)
		drop.name = "Drop%s" % i
	stage._props_nodes["original_cloud_waterfall"] = root
	update(stage)

static func update(stage: Node) -> void:
	var root: Node3D = stage._props_nodes.get("original_cloud_waterfall")
	if not is_instance_valid(root): return
	var clock := 0.0 if bool(stage.settings.get("lowMotion",false)) else float(stage.visual_time)
	for i in range(3):
		var drop: Sprite3D = root.get_node("Drop%s" % i)
		drop.visible = bool(stage.settings.get("particles",true))
		drop.position = RIGHT*((-3+i*5)*PIXEL) + Vector3.UP*(-(15+fposmod(clock*.035+i*38,110))*PIXEL/COS_ELEVATION)

static func draw_background(stage: Node, target: CanvasItem) -> void:
	if stage.world == null or not str(stage.world.level.id).begins_with("cloud-"): return
	var size: Vector2 = stage.get_viewport_rect().size
	if size.x <= 0 or size.y <= 0: return
	var id := str(stage.world.level.id)
	if not _skies.has(id):
		var gradient := Gradient.new()
		var colors: Array = stage.world.level.sky
		gradient.colors = PackedColorArray([Color(str(colors[0])),Color(str(colors[1]))])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient; texture.width = 256; texture.height = 256
		texture.fill_from = Vector2.ZERO; texture.fill_to = Vector2(.5,1)
		_skies[id] = texture
	if not _skies.has("glow"):
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1,.992,.949,.612),Color(1,.992,.949,0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient; texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(.5,.5); texture.fill_to = Vector2(1,.5)
		texture.width = 256; texture.height = 256
		_skies.glow = texture
	target.draw_texture_rect(_skies[id],Rect2(Vector2.ZERO,size),false)
	var radius := size.x*.65
	target.draw_texture_rect(_skies.glow,Rect2(size*Vector2(.65,.28)-Vector2.ONE*radius,Vector2.ONE*radius*2),false)
	for item: Array in [[.11,.32,.55],[.88,.22,.7],[.83,.75,.4]]:
		_draw_art(target,"island",size*Vector2(item[0],item[1]),float(item[2]),.12)
	var clock := 0.0 if bool(stage.settings.get("lowMotion",false)) else float(stage.visual_time)
	_draw_art(target,"cloud",size*Vector2(.22,.76)+Vector2(sin(clock*.000025)*9,0),size.x*.17/100,.22)
	_draw_art(target,"cloud",size*Vector2(.79,.46),size.x*.12/100,.18)
	_draw_art(target,"cloud",size*Vector2(.48,.9),size.x*.24/100,.35)
	if id == "cloud-3":
		for i in range(18): _draw_art(target,"background_star",Vector2(fposmod(i*137.5,size.x),60+fposmod(i*71,maxf(100,size.y-180))),1.0 if i%3 == 0 else .5,1)

static func _draw_art(target: CanvasItem,kind: String,at: Vector2,factor: float,alpha: float) -> void:
	var data: Dictionary = Art.art(kind)
	var bounds: Rect2 = data.bounds
	target.draw_texture_rect(data.texture,Rect2(at+bounds.position*factor,bounds.size*factor),false,Color(1,1,1,alpha))
