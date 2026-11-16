class_name OriginalSanctuaryDressing
extends RefCounted
## Source: garden2/render.ts (112 px gate, 92 px fountain, 58 px mole).
## Source canvases retain registration. Gate/fountain full-base limits are
## explicit local exceptions; rules/terrain stay intact. The complete basin
## outline is shared with native_prop_obstacles for local anti-entry collision.
const Dressing = preload("res://presentation/native/original_garden_dressing.gd")
const PIXEL := 1.4142135623730951 / 70.0
const FOUNTAIN_PIXEL := PIXEL * 92.0 / 90.0
const RASTER := 4.0
const FOUNTAIN_FOOT := 22.0
const FOUNTAIN_SOURCE_RADIUS := .54
const FOUNTAIN_RIGHT := Vector3(0.70710678, 0, -0.70710678)
const FOUNTAIN_FRONT := Vector3(0.70710678, 0, 0.70710678)
const FOUNTAIN_BASIN := Vector2(43, 20)
const GATE_SOURCE_RADIUS := 112.0 / 70.0 * .5
static var _fountain_texture: Texture2D
static var rasterizations := 0
static var _fountain_offsets: Array[Vector2] = []
static var _placement_offsets: Array[Dictionary] = []
static var _placement_cache: Dictionary = {}
static var _fountain_cache: Dictionary = {}
static var _fountain_outlines: Dictionary = {}
static var placement_cache_hits := 0
static var fountain_cache_hits := 0
static var fountain_searches := 0

static func _support_identity(stage: Node, desired: Vector3, reach: float) -> Array:
	# Only the real surfaces that a local search can touch invalidate it.
	# Remote lever bridges must not restart a static courtyard search, while
	# changed steps, transforms, missing supports and rule flags still do.
	var rows: Array = []
	for id: String in stage._surfaces:
		var surface: Node3D = stage._surfaces[id]
		var at: Vector3 = surface.global_position
		var scale: Vector3 = surface.global_basis.get_scale()
		if absf(at.x-desired.x)>reach+absf(scale.x)*.5 or absf(at.z-desired.z)>reach+absf(scale.z)*.5: continue
		var tile: Dictionary = stage._tile_map.get(id,{})
		rows.append([id, tile.get("kind","fixed"), tile.get("solid",false), tile.get("small",false), surface.global_transform, surface.get("_geometry_key")])
	rows.sort_custom(func(a: Array,b: Array) -> bool: return str(a[0])<str(b[0]))
	return rows

static func placement(stage: Node, desired: Vector3, height: float, radius: float) -> Dictionary:
	# Fine local search is only performed during a props rebuild. Unlike the
	# generic scenery fallback, never migrate between physical height levels.
	var key := hash([str(stage.world.level.id),desired,height,radius,_support_identity(stage,desired,1.6+radius)])
	if _placement_cache.has(key):
		placement_cache_hits += 1
		return (_placement_cache[key] as Dictionary).duplicate(true)
	if _placement_offsets.is_empty():
		for ix in range(-30, 31):
			for iz in range(-30, 31):
				var delta := Vector2(ix, iz) * 0.05
				if delta.length() > 1.6: continue
				_placement_offsets.append({"delta": delta, "score": delta.length_squared()})
		_placement_offsets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
	for entry: Dictionary in _placement_offsets:
		var at := desired + Vector3(entry.delta.x, 0, entry.delta.y)
		var logical: Vector3 = stage.logical_position(at)
		var support := "f:%d:%d" % [roundi(logical.x), roundi(logical.z)]
		if not stage._surfaces.has(support): continue
		if absf(stage.support_height(at, support) - height) > 0.012: continue
		if not Dressing.flat_footprint(stage, at, support, radius): continue
		at.y = stage.support_height(at, support) + 0.008
		var result := {"at": at, "support": support, "radius": radius, "desired": desired}
		_placement_cache[key] = result
		return result.duplicate(true)
	return {}

static func annotate(node: Node3D, data: Dictionary, source_pixels: float) -> void:
	node.set_meta("original_sanctuary_support", data.support)
	node.set_meta("original_sanctuary_foot_radius", data.radius)
	node.set_meta("original_sanctuary_desired", data.desired)
	node.set_meta("original_source_pixels", source_pixels)

static func mole(stage: Node, sprite: Sprite3D, point: Dictionary) -> bool:
	var desired: Vector3 = stage.tile_position(point) + Vector3(-1, 0, .3)
	# The entrance acquires stairs when home opens. Reserve their future edge
	# now, so opening/undo cannot make the resident shuffle or lose a paw.
	var preferred := desired + Vector3(.15,0,-.25) if str(stage.world.level.id)=="1-4" else desired
	# The restored 3-4 core fully occludes the original painter-ordered NPC.
	# Its existing front-right terrace gives the complete mound genuine support
	# and a visible depth position, without lifting it or disabling depth.
	if str(stage.world.level.id)=="3-4": preferred = desired+Vector3(2.06,0,-1.30)
	var data := placement(stage, preferred, stage.tile_position(point).y, 0.405)
	if data.is_empty(): push_error("Original mole has no same-height complete support"); return false
	data.desired = desired
	# Cached Art.mole is drawn at 150, source draws at 58. The mound's full
	# lower edge is y = 11 in the 62-unit authoring space, not its centre y=0.
	sprite.pixel_size = PIXEL * 58.0 / 150.0
	sprite.offset = Vector2(0, 222.0 + 11.0 * 150.0 / 62.0 - 128.0)
	sprite.position = data.at
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	annotate(sprite, data, 58)
	if str(stage.world.level.id)=="3-4": sprite.set_meta("original_sanctuary_migration","same_height_front_right_terrace_clear_of_final_core_and_actors")
	return true

static func build(stage: Node) -> void:
	var sanctuary: Dictionary = stage.world.level.get("sanctuary", {})
	if sanctuary.is_empty(): return
	var gate: Dictionary = sanctuary.get("gate", {})
	if not gate.is_empty():
		var desired: Vector3 = stage.tile_position(gate)
		# Keep the gate at the actual rule entrance. Its 112 px broad foundation
		# does not fit that one-cell landing: explicitly cap BOTH source canvases
		# together by the complete base, never by only the narrow lowest pixels.
		var radius := GATE_SOURCE_RADIUS
		while radius >= .1 and not gate_footprint(stage,desired,str(gate.id),radius): radius -= .01
		var data := {"at":desired+Vector3.UP*.008,"support":str(gate.id),"radius":radius,"desired":desired} if radius>=.1 else {}
		if not data.is_empty():
			var width := 112.0 * PIXEL * radius / GATE_SOURCE_RADIUS
			var frame: Sprite3D = stage._sprite(stage._props, "flower-gate-frame", width, data.at, true)
			frame.name = "OriginalSanctuaryGateFrame"
			frame.set_meta("opaque_structure",true)
			# Both source PNGs have the same 272 x 405 canvas. The transparent
			# seal must use the FRAME anchor, or its light jumps to the ground.
			frame.offset = Vector2(0, 404.5 - 405.0 * .5)
			annotate(frame, data, 112)
			frame.set_meta("original_ratio_exception","entrance_full_masonry_footprint_limit")
			frame.set_meta("original_canvas_world_width",112.0*PIXEL)
			if not stage.world.flag("home"):
				var seal: Sprite3D = stage._sprite(stage._props, "flower-gate-seal", width, data.at, true)
				seal.name = "OriginalSanctuaryGateSeal"
				seal.offset = frame.offset
				seal.render_priority = 1
				annotate(seal, data, 112)
				seal.set_meta("original_ratio_exception","entrance_full_masonry_footprint_limit")
				seal.set_meta("original_canvas_world_width",112.0*PIXEL)
		else: push_error("Original gate has no same-height complete support")
	var fountain: Dictionary = sanctuary.get("fountain", {})
	if fountain.is_empty(): return
	var desired: Vector3 = stage.tile_position(fountain)
	# Preserve the original permanent solid cell's visible blocking object.
	# Its own solid floor IS legitimate structural support, unlike scenery
	# migration onto arbitrary blocked or preview tiles. Preserve the accepted
	# artwork size; search the complete basin around its real centre instead
	# of shrinking an incorrectly centred square until the old check passes.
	var radius := FOUNTAIN_SOURCE_RADIUS
	var data := fountain_candidate(stage,desired,radius)
	if data.is_empty(): push_error("Original fountain has no same-height complete support"); return
	var ratio := radius/.64
	var sprite := Sprite3D.new()
	sprite.name = "SanctuaryFountain"
	sprite.set_meta("opaque_structure",true)
	sprite.texture = fountain_texture()
	sprite.pixel_size = FOUNTAIN_PIXEL / RASTER * ratio
	sprite.offset = Vector2(0, (FOUNTAIN_FOOT + 22.0) * RASTER)
	sprite.position = fountain_card_position(data.at,ratio)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	annotate(sprite, data, 92)
	sprite.set_meta("original_ratio_exception","solid_fountain_full_basin_and_core_clearance_limit")
	sprite.set_meta("original_fountain_ratio",ratio)
	sprite.set_meta("original_sanctuary_ground_center",data.at)
	sprite.set_meta("original_sanctuary_ground_outline",fountain_ground_outline(data.at,ratio))
	sprite.set_meta("original_sanctuary_ground_bounds",fountain_ground_bounds(data.at,ratio))
	stage._props.add_child(sprite)
	stage._occluders.append(sprite)

static func fountain_card_position(center: Vector3, ratio: float) -> Vector3:
	# Preserve the lowest painted front rim as the card's ground anchor.
	# The whole basin centre is behind that foot on the real ground plane;
	# using its source y=2 as a card foot clips the front half into terrain.
	return center+FOUNTAIN_FRONT*(FOUNTAIN_FOOT-2.0)*FOUNTAIN_PIXEL*ratio*2.0

static func fountain_ground_outline(at: Vector3, ratio: float) -> PackedVector2Array:
	if not _fountain_outlines.has(ratio):
		var local := PackedVector2Array()
		var unit := FOUNTAIN_PIXEL * ratio
		for index: int in range(128):
			var angle := TAU * index / 128.0
			var point := FOUNTAIN_RIGHT * cos(angle) * FOUNTAIN_BASIN.x * unit + FOUNTAIN_FRONT * sin(angle) * FOUNTAIN_BASIN.y * unit * 2.0
			local.append(Vector2(point.x,point.z))
		_fountain_outlines[ratio] = local
	var outline: PackedVector2Array = (_fountain_outlines[ratio] as PackedVector2Array).duplicate()
	for index: int in range(outline.size()): outline[index] += Vector2(at.x,at.z)
	return outline

static func fountain_ground_radius(ratio: float) -> float:
	# The source ellipse has axes 43/20 px. Ground depth doubles screen y;
	# the 45-degree ground axes determine the actual X/Z bounding extent.
	return FOUNTAIN_PIXEL * ratio * Vector2(FOUNTAIN_BASIN.x,FOUNTAIN_BASIN.y*2.0).length() / sqrt(2.0)

static func fountain_ground_bounds(at: Vector3, ratio: float) -> Rect2:
	var radius := fountain_ground_radius(ratio)
	return Rect2(Vector2(at.x-radius,at.z-radius),Vector2.ONE*radius*2.0)

static func fountain_candidate(stage: Node, desired: Vector3, radius: float) -> Dictionary:
	var ratio := radius / .64
	if _fountain_offsets.is_empty():
		for ix in range(-7,8):
			for iz in range(-7,8): _fountain_offsets.append(Vector2(ix,iz)*.05)
		_fountain_offsets.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.length_squared()<b.length_squared())
	var core: Node3D = stage._props_nodes.get("mark:core")
	var center := Vector3.ZERO
	var half := Vector2.ZERO
	if core != null:
		for child in core.get_children():
			if child.has_meta("core_planter"):
				center=core.to_global(child.get_meta("ground_footprint_center"))
				half=Vector2(child.get_meta("ground_footprint_span"))*.5
	var key := hash([str(stage.world.level.id),desired,radius,FOUNTAIN_BASIN,FOUNTAIN_PIXEL,center,half,_support_identity(stage,desired,.35+fountain_ground_radius(ratio))])
	if _fountain_cache.has(key):
		fountain_cache_hits += 1
		return (_fountain_cache[key] as Dictionary).duplicate(true)
	fountain_searches += 1
	for delta: Vector2 in _fountain_offsets:
		var at := desired+Vector3(delta.x,0,delta.y)
		var outline := fountain_ground_outline(at,ratio)
		var rect := Rect2(Vector2(center.x,center.z)-half,half*2.0).grow(.02)
		var core_outline := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		if half != Vector2.ZERO and not Geometry2D.intersect_polygons(outline,core_outline).is_empty(): continue
		# Keep the existing solid cell visibly occupied, rather than moving the
		# basin to an unrelated empty corner and leaving an invisible obstacle.
		if not Geometry2D.is_point_in_polygon(Vector2(desired.x,desired.z),outline): continue
		var ground_radius := fountain_ground_radius(ratio)
		if not fountain_footprint(stage,at,ground_radius): continue
		at.y += .008
		var result := {"at":at,"desired":desired,"radius":ground_radius,"support":"f:-9:-2"}
		_fountain_cache[key] = result
		return result.duplicate(true)
	return {}

static func fountain_footprint(stage: Node, at: Vector3, radius: float) -> bool:
	var ratio := radius / fountain_ground_radius(1.0)
	for ring: float in [0.0,.25,.5,.75,1.0]:
		for point: Vector2 in fountain_ground_outline(at,ratio*ring):
			var sample := Vector3(point.x,at.y,point.y)
			var logical: Vector3 = stage.logical_position(sample)
			var id := "f:%d:%d" % [roundi(logical.x),roundi(logical.z)]
			if not stage._surfaces.has(id) or not stage._tile_map.has(id): return false
			var tile: Dictionary = stage._tile_map[id]
			if bool(tile.get("solid",false)) and id!="f:-9:-2": return false
			if str(tile.get("kind","fixed"))!="fixed" or bool(tile.get("small",false)): return false
			if absf(logical.x-float(tile.x))>.5001 or absf(logical.z-float(tile.z))>.5001: return false
			if absf(stage.support_height(sample,id)-stage.tile_position_id("f:-9:-2").y)>.012: return false
	return true

static func gate_footprint(stage: Node, at: Vector3, support: String, radius: float) -> bool:
	# A closed gate is intentionally solid in the rules. Its genuine floor
	# remains legal structural support even though it is not a walkable cell.
	if not stage._surfaces.has(support): return false
	var baseline: float = stage.support_height(at,support)
	for ix in range(9):
		for iz in range(9):
			var sample := at+Vector3(lerpf(-radius,radius,ix/8.0),0,lerpf(-radius,radius,iz/8.0))
			var logical: Vector3 = stage.logical_position(sample)
			if absf(logical.x-float(stage._tile_map[support].x))>.499 or absf(logical.z-float(stage._tile_map[support].z))>.499: return false
			if absf(stage.support_height(sample,support)-baseline)>.012: return false
	return true

static func effect_position(at: Vector3, camera: Camera3D, x: float, y: float, ratio := 1.0) -> Vector3:
	# A tiny layer separation prevents coplanar flicker against the illustrated
	# basin; normal depth testing against all world geometry remains enabled.
	return at + (camera.global_basis.x * x + camera.global_basis.y * (FOUNTAIN_FOOT - y)) * FOUNTAIN_PIXEL * ratio + camera.global_basis.z * .002

static func fountain_texture() -> Texture2D:
	if _fountain_texture != null: return _fountain_texture
	var definitions := '<defs>'
	var gradients := [["basin",-8,-8,51,"#fff4dc","#e6d0a9","#b7a180"],["rim",-9,-8,46,"#fff9e8","#ecdabb","#c8b18c"],["water",-8,-9,36,"#ecfbef","#a6dce0","#74b7c4"],["base",-4,-16,17,"#fff5dc","#e1cfaa","#bba681"],["stem",-3,-27,23,"#fff9e7","#e8d7b6","#c2ae8a"],["upper",-6,-39,24,"#fff8e3","#e5d1aa","#bca680"]]
	for g: Array in gradients:
		definitions += '<radialGradient id="%s" gradientUnits="userSpaceOnUse" cx="%s" cy="%s" r="%s" fx="%s" fy="%s"><stop stop-color="%s"/><stop offset=".48" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient>' % [g[0],float(g[1])+float(g[3])*.18,float(g[2])+float(g[3])*.3,float(g[3])*1.2,float(g[1])-float(g[3])*.32,float(g[2])-float(g[3])*.4,g[4],g[5],g[6]]
	definitions += '<linearGradient id="glint"><stop stop-color="#ffffff" stop-opacity=".55"/><stop offset="1" stop-color="#c5eeee" stop-opacity=".16"/></linearGradient></defs>'
	var body := '<ellipse cy="2" rx="43" ry="20" fill="url(#basin)"/><path d="M41 4 A41 17 0 0 1 -41 4" fill="none" stroke="#c4b28d" stroke-width="1.1"/>'
	for i in range(9):
		var a := i / 9.0 * TAU
		var x := cos(a) * 39.0
		var y := sin(a) * 17.0
		body += '<path d="M%f %f L%f %f L%f %f" fill="none" stroke="#baaa85" stroke-opacity=".31" stroke-width=".8"/>' % [x*.86,y*.8-4,x,y,x,y+4]
	body += '<ellipse cy="-4" rx="39" ry="18" fill="url(#rim)"/><ellipse cy="-5" rx="31" ry="13" fill="url(#water)"/><ellipse cy="-5" rx="29" ry="11" fill="url(#glint)"/><ellipse cy="-12" rx="12" ry="6" fill="url(#base)"/><path d="M-9 -14 Q-3 -25 -7 -35 L7 -35 Q3 -25 9 -14 Z" fill="url(#stem)"/><path d="M-4 -17 Q-1 -26 -3 -33" fill="none" stroke="#eee5c1" stroke-opacity=".49" stroke-width="1.3"/><ellipse cy="-35" rx="19" ry="8" fill="url(#upper)"/><ellipse cy="-37" rx="13" ry="4.8" fill="#bce6e2"/>'
	for spot: Array in [[0,-44,.55,-.3],[3,-41,.45,1.6],[-32,5,.42,-.4],[28,9,.42,.6],[-21,15,.42,1.2]]:
		body += '<g transform="translate(%s %s) rotate(%s) scale(%s)"><path d="M-8 3 Q-10 -6 7 -8 Q11 1 -8 3" fill="#8caa72"/><path d="M-7 2 L5 -6" stroke="#d7ddb2" stroke-opacity=".5" stroke-width=".65"/></g>' % [spot[0],spot[1],rad_to_deg(float(spot[3])),spot[2]]
		if float(spot[1]) > 0: body += '<ellipse cx="%s" cy="%s" rx="1.7" ry="1.3" fill="#f1d9ac"/>' % [float(spot[0])+4,float(spot[1])-1]
	var image := Image.new()
	var error := image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="104" height="96" viewBox="-52 -70 104 96">'+definitions+body+'</svg>', RASTER)
	if error != OK: push_error("Original fountain SVG failed")
	_stone_grain(image)
	image.generate_mipmaps()
	_fountain_texture = ImageTexture.create_from_image(image)
	rasterizations += 1
	return _fountain_texture

static func _stone_grain(image: Image) -> void:
	# Original texturedOval uses the actual terrain stone at .08/.06/.08.
	# Composite only exposed stone, once. Water, stem, nozzle and leaves keep
	# their authored colours; no resource reads or pixel loops happen warm.
	var texture: Texture2D = load("res://assets/images/grid-world/stone.png")
	var stone := texture.get_image()
	if stone.is_compressed(): stone.decompress()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p := Vector2((x+.5)/RASTER-52,(y+.5)/RASTER-70)
			var ellipse := Vector3.ZERO
			var opacity := .08
			if (Vector2(p.x/43,(p.y-2)/20)).length_squared()<1 and (Vector2(p.x/39,(p.y+4)/18)).length_squared()>1: ellipse=Vector3(2,43,20)
			elif (Vector2(p.x/39,(p.y+4)/18)).length_squared()<1 and (Vector2(p.x/31,(p.y+5)/13)).length_squared()>1:
				ellipse=Vector3(-4,39,18); opacity=.06
			elif (Vector2(p.x/19,(p.y+35)/8)).length_squared()<1 and (Vector2(p.x/13,(p.y+37)/4.8)).length_squared()>1: ellipse=Vector3(-35,19,8)
			if ellipse==Vector3.ZERO: continue
			var color := image.get_pixel(x,y)
			if color.a<.9: continue
			var uv := Vector2(p.x/ellipse.y,(p.y-ellipse.x)/ellipse.z)*.5+Vector2.ONE*.5
			var sample := stone.get_pixel(clampi(int(uv.x*stone.get_width()),0,stone.get_width()-1),clampi(int(uv.y*stone.get_height()),0,stone.get_height()-1))
			sample.a *= opacity
			image.set_pixel(x,y,color.blend(sample))
