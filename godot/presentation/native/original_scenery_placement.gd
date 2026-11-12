extends RefCounted
const Positions=preload("res://presentation/native/original_scenery_positions.gd")
## Placement-only contract. Source image scale and saved topology are immutable.
## Foot widths describe hard ground contact, not the transparent canvas or crown.
const CONTACT_PIXELS := {"arch":179.0,"stone-lantern":114.0,"wood-lantern":65.0,"light-tower":272.0,"river-rock":108.0,"small-pebbles":109.0,"red-mushroom":79.0,"blue-mushroom":65.0,"violet-crystal":86.0,"lotus-pool":342.0,"bush":57.0,"berry-bush":78.0,"fern":54.0,"pink-flowers":35.0,"blue-flowers":50.0,"yellow-flowers":38.0,"gold-lotus":100.0,"ivory-lotus":24.0,"glow-flower":112.0}
const WIDTHS := {"arch":256.0,"stone-lantern":116.0,"wood-lantern":120.0,"light-tower":272.0,"river-rock":113.0,"small-pebbles":117.0,"red-mushroom":113.0,"blue-mushroom":100.0,"violet-crystal":86.0,"lotus-pool":342.0,"bush":141.0,"berry-bush":134.0,"fern":126.0,"pink-flowers":130.0,"blue-flowers":112.0,"yellow-flowers":106.0,"gold-lotus":128.0,"ivory-lotus":94.0,"glow-flower":182.0}
const HARD_CONTACT := {"arch":[39.0,218.0,160.0],"stone-lantern":[0.0,114.0,62.0],"wood-lantern":[0.0,65.0,31.5],"light-tower":[0.0,272.0,138.5],"river-rock":[4.0,112.0,62.0],"small-pebbles":[8.0,117.0,65.5],"red-mushroom":[19.0,98.0,58.5],"blue-mushroom":[18.0,83.0,51.0],"violet-crystal":[0.0,86.0,45.0]}
# Authored placement targets, not new tiles. The solver validates every target
# against real geometry and semantic reservations during a props rebuild only.
const TARGETS := {
	"1-3": {0:Vector2(-3.9,-1.27),3:Vector2(-4.25,1.25),5:Vector2(-1.25,3.2),7:Vector2(1.2,3.15),8:Vector2(-1.23,5.23),11:Vector2(1.24,5.25)},
	"2-1": {4:Vector2(-3,-.64),8:Vector2(3.3,-1.25)},
	"2-2": {2:Vector2(2.16,-1),4:Vector2(3.36,1.22)},
	"2-4": {0:Vector2(10.0,-1.22),1:Vector2(11.2,.55)},
	"3-2": {0:Vector2(2.26,-.36),1:Vector2(1.75,4.2)},
	"3-3": {4:Vector2(-1.22,3.9)},
	"3-4": {0:Vector2(-5.25,-.2)}
}
static var _contexts: Dictionary={}
static var _placements: Dictionary={}
static var searches:=0
static var cache_hits:=0
static var prepare_cache_hits:=0
static var prepare_microseconds:=0
static var search_microseconds:=0
static var authored_hits:=0

static func radius(alias: String, width: float) -> float:
	var reach:=float(CONTACT_PIXELS[alias])*.5
	if HARD_CONTACT.has(alias):
		var contact: Array=HARD_CONTACT[alias]
		# Current anchor is the front/lowest foot, often NOT the base midpoint.
		# Both arch pillars and asymmetric stone feet must fit from that anchor.
		reach=maxf(float(contact[2])-float(contact[0]),float(contact[1])-float(contact[2]))
	return width*reach/float(WIDTHS[alias])/sqrt(2.0)+.012

static func prepare(stage: Node) -> Dictionary:
	var started:=Time.get_ticks_usec()
	var ctx := {"occupied":[],"marks":[],"lanes":[],"fixed":{},"core":Rect2(),"height":0.0}
	for tile: Dictionary in stage._tiles:
		if not str(tile.id).begins_with("f:") or bool(tile.get("solid",false)) or bool(tile.get("small",false)): continue
		if str(tile.get("kind","fixed")) in ["root","shadow","module","bridge","lift","water"]:continue
		if not stage._surfaces.has(str(tile.id)): continue
		ctx.fixed[str(tile.id)]=tile
	var core: Node3D=stage._props_nodes.get("mark:core")
	if core!=null:
		for child in core.get_children():
			if not child.has_meta("core_planter"):continue
			var at: Vector3=core.to_global(child.get_meta("ground_footprint_center"))
			var span: Vector2=child.get_meta("ground_footprint_span")
			ctx.core=Rect2(Vector2(at.x,at.z)-span*.5,span).grow(.035)
			ctx.height=at.y
	for mark: Dictionary in stage.world.level.get("marks",[]):
		if not stage._tile_map.has(str(mark.tile)):continue
		var at: Vector3=stage.tile_position_id(str(mark.tile))
		ctx.marks.append({"at":at,"id":str(mark.id),"kind":str(mark.kind),"radius":.22})
		if str(mark.kind) in ["core","turn","valve","flower","latch"]:
			for who: String in ["luvie","buddy"]:
				var stance: Vector3=stage.actor_rest_position(stage._tile_map[str(mark.tile)],who)
				ctx.marks.append({"at":stance,"id":str(mark.id)+"/"+who,"kind":"standing","radius":.18})
	var spawn_id:=str(stage.world.level.get("start",""))
	if stage._tile_map.has(spawn_id):ctx.marks.append({"at":stage.tile_position_id(spawn_id),"id":"spawn","kind":"spawn","radius":.32})
	var cache_key:=hash([str(stage.world.level.id),stage._terrain_signature,ctx.core,ctx.height,ctx.marks])
	ctx.cache_key=cache_key
	if _contexts.has(cache_key):
		var cached: Dictionary=_contexts[cache_key].duplicate()
		cached.occupied=[]
		prepare_cache_hits+=1
		prepare_microseconds+=Time.get_ticks_usec()-started
		return cached
	# Reserve current AND authored future connection approaches. Dynamic cells
	# themselves are never a decoration support. All four rotation poses matter.
	var dynamic: Array[Vector3]=[]
	for module: Dictionary in stage.world.level.get("modules",[]):
		for local: Array in module.get("shape",[]):
			for turn in range(4):
				var delta:=Vector2(float(local[0]),float(local[1])).rotated(turn*PI*.5)
				dynamic.append(Vector3(float(module.x)+roundf(delta.x),float(module.get("h",0)),float(module.z)+roundf(delta.y)))
			if str(module.get("kind",""))=="slide":
				var x:=float(module.x)+float(local[0])
				var z:=float(module.z)+float(local[1])
				if str(module.get("axis","x"))=="x":x+=float(module.get("distance",0))
				else:z+=float(module.get("distance",0))
				dynamic.append(Vector3(x,float(module.get("h",0)),z))
	for root: Dictionary in stage.world.level.get("roots",[]):
		for socket: Array in root.get("sockets",[]):dynamic.append(Vector3(float(socket[0]),float(root.get("h",0)),float(socket[1])))
	for tile: Dictionary in stage._tiles:
		if not str(tile.id).begins_with("f:"):dynamic.append(Vector3(float(tile.x),float(tile.h),float(tile.z)))
	for tile: Dictionary in ctx.fixed.values():
		var at: Vector3=stage.tile_position(tile)
		var flat_neighbors:=0
		for d: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var key:="f:%d:%d"%[int(tile.x)+int(d.x),int(tile.z)+int(d.y)]
			if ctx.fixed.has(key) and is_equal_approx(float(ctx.fixed[key].h),float(tile.h)):flat_neighbors+=1
		for point: Vector3 in dynamic:
			var dx:=point.x-float(tile.x);var dz:=point.z-float(tile.z)
			if absf(dx)+absf(dz)>.999 and absf(dx)+absf(dz)<1.001:
				var end: Vector3=stage.physical_position(Vector3(float(tile.x)+dx*.5,at.y,float(tile.z)+dz*.5))
				ctx.lanes.append({"a":Vector2(at.x,at.z),"b":Vector2(end.x,end.z),"y":at.y,"reason":"current_or_future_docking"})
		# Permanent height connectors require an uncluttered approach too.
		for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var id:="f:%d:%d"%[int(tile.x)+int(direction.x),int(tile.z)+int(direction.y)]
			if not ctx.fixed.has(id):continue
			var other: Dictionary=ctx.fixed[id]
			var end: Vector3=stage.physical_position(Vector3(float(tile.x)+direction.x*.5,at.y,float(tile.z)+direction.y*.5))
			if is_equal_approx(float(other.h),float(tile.h)):
				if flat_neighbors==4:
					var other_at: Vector3=stage.tile_position(other)
					ctx.lanes.append({"a":Vector2(at.x,at.z),"b":Vector2(other_at.x,other_at.z),"y":at.y,"reason":"fixed_interior_walkway"})
			else:ctx.lanes.append({"a":Vector2(at.x,at.z),"b":Vector2(end.x,end.z),"y":at.y,"reason":"permanent_stair_approach"})
	_contexts[cache_key]=ctx.duplicate()
	prepare_microseconds+=Time.get_ticks_usec()-started
	return ctx

static func supported(stage: Node, at: Vector3, r: float, ctx: Dictionary) -> bool:
	for ix in range(5):
		for iz in range(5):
			var sample:=at+Vector3(lerpf(-r,r,ix*.25),0,lerpf(-r,r,iz*.25))
			var logical: Vector3=stage.logical_position(sample)
			var id:="f:%d:%d"%[roundi(logical.x),roundi(logical.z)]
			if not ctx.fixed.has(id):return false
			if absf(stage.support_height(sample,id)-at.y)>.012:return false
	return true

static func clear(at: Vector3,r: float,alias: String,ctx: Dictionary) -> bool:
	var p:=Vector2(at.x,at.z)
	if absf(at.y-float(ctx.height))<.02 and Rect2(p-Vector2.ONE*r,Vector2.ONE*r*2).intersects(ctx.core):return false
	for entry: Dictionary in ctx.occupied:
		var other: Vector2=entry.at
		var combined:=r+float(entry.radius)+.025
		if absf(at.y-float(entry.y))<.02 and absf(p.x-other.x)<combined and absf(p.y-other.y)<combined:return false
	for entry: Dictionary in ctx.marks:
		if str(entry.kind)=="rest" and alias in ["arch","wood-lantern"]:continue
		if str(entry.kind)=="core":continue # actual complete base already checked
		var center: Vector3=entry.at
		if absf(at.y-center.y)<.02 and p.distance_to(Vector2(center.x,center.z))<r+float(entry.radius):return false
	for entry: Dictionary in ctx.lanes:
		if absf(at.y-float(entry.y))>.02:continue
		var a: Vector2=entry.a;var b: Vector2=entry.b
		var closest:=Geometry2D.get_closest_point_to_segment(p,a,b)
		if p.distance_to(closest)<r+.16:return false
	return true

static func place(stage: Node, authored: Vector3, alias: String, width: float, index: int, ctx: Dictionary) -> Dictionary:
	var started:=Time.get_ticks_usec()
	var r:=radius(alias,width)
	var id:=str(stage.world.level.id)
	# Geometry/reservations plus already placed preceding instances form the
	# cache identity. Discoveries, care and replay rebuild cards but do not
	# search/sort the same island again. Never key only by level or item id.
	var cache_key:=hash([ctx.cache_key,authored,alias,width,index,ctx.occupied])
	if _placements.has(cache_key):
		var cached: Dictionary=_placements[cache_key]
		var at: Vector3=cached.at-Vector3.UP*.008
		ctx.occupied.append({"at":Vector2(at.x,at.z),"y":at.y,"radius":r})
		cache_hits+=1
		return cached
	var authored_key:="%s/%d/%s/%.3f,%.3f,%.3f"%[id,index,alias,authored.x,authored.y,authored.z]
	if Positions.POINTS.has(authored_key):
		var at: Vector3=Positions.POINTS[authored_key]
		var logical: Vector3=stage.logical_position(at)
		var support:="f:%d:%d"%[roundi(logical.x),roundi(logical.z)]
		if ctx.fixed.has(support) and absf(float(ctx.fixed[support].h)-authored.y)<.001 and clear(at,r,alias,ctx) and supported(stage,at,r,ctx):
			ctx.occupied.append({"at":Vector2(at.x,at.z),"y":at.y,"radius":r})
			var result:={"at":at+Vector3.UP*.008,"support":support,"migration":"authored same-height full-foot placement; core/standing/docking reserved","radius":r}
			_placements[cache_key]=result
			authored_hits+=1
			return result
	searches+=1
	var desired:=Vector2(authored.x,authored.z)
	var target: Vector2=TARGETS.get(id,{}).get(index,desired)
	var candidates: Array[Dictionary]=[]
	var connected: Dictionary={}
	var start:="f:%d:%d"%[roundi(authored.x),roundi(authored.z)]
	var pending: Array[String]=[start]
	while not pending.is_empty():
		var key: String=pending.pop_back()
		if connected.has(key) or not ctx.fixed.has(key):continue
		var tile: Dictionary=ctx.fixed[key]
		if absf(float(tile.h)-authored.y)>.001:continue
		connected[key]=true
		for d: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:pending.append("f:%d:%d"%[int(tile.x)+int(d.x),int(tile.z)+int(d.y)])
	for tile: Dictionary in ctx.fixed.values():
		if not connected.has(str(tile.id)):continue
		if absf(float(tile.h)-authored.y)>.001:continue
		var center: Vector3=stage.tile_position(tile)
		if Vector2(float(tile.x)-authored.x,float(tile.z)-authored.z).length()>2.8:continue
		if roundi(target.x)==int(tile.x) and roundi(target.y)==int(tile.z):
			candidates.append({"at":stage.physical_position(Vector3(target.x,center.y,target.y)),"score":0.0,"support":str(tile.id)})
		for dx: float in [-.36,-.275,-.26,-.16,0,.16,.26,.275,.36]:
			for dz: float in [-.36,-.275,-.26,-.16,0,.16,.26,.275,.36]:
				var logical:=Vector3(float(tile.x)+dx,center.y,float(tile.z)+dz)
				var at: Vector3=stage.physical_position(logical)
				var score:=Vector2(logical.x-target.x,logical.z-target.y).length_squared()
				# Prefer quiet corners over tile centre without globally pushing
				# every object to the same edge or steering the puzzle solution.
				score+=.08*(1.0-minf(absf(dx)+absf(dz),.6))
				candidates.append({"at":at,"score":score,"support":str(tile.id)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.score)<float(b.score))
	for candidate: Dictionary in candidates:
		var at: Vector3=candidate.at
		if not clear(at,r,alias,ctx) or not supported(stage,at,r,ctx):continue
		ctx.occupied.append({"at":Vector2(at.x,at.z),"y":at.y,"radius":r})
		var result:={"at":at+Vector3.UP*.008,"support":candidate.support,"migration":"same-height complete-foot placement; core/interaction/docking reserved","radius":r}
		_placements[cache_key]=result
		search_microseconds+=Time.get_ticks_usec()-started
		return result
	push_error("No safe scenery placement "+id+"/"+str(index)+"/"+alias)
	return {}
