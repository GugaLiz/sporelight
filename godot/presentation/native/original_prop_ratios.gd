extends RefCounted
const Props = preload("res://elements/prop_definitions.gd")
## Full image-canvas ratios from src/app/garden2/render.ts, not alpha bounds.
## Sprite cropping must not change the meaning of these widths.
const TILE_PIXELS := 70.0
const TILE_PROJECTED_WORLD := 1.41421356237
static var SOURCE_WIDTHS = Props.section("scale").source_widths
static var BODY_BOUNDS = Props.rectangles("scale", "body_bounds")

static func canvas_width(kind: String, level := "") -> float:
	return Props.canvas_width(kind, level)

static func core_layout(stage: Node, parent: Node3D) -> Dictionary:
	var id := str(stage.world.level.id)
	var width := canvas_width("core",id)
	var fixed := Props.core_override(id)
	if not fixed.is_empty():
		return {"width":fixed.width,"shift":fixed.shift,"source_width":width,"limited":true,"reason":fixed.reason}
	if id == "1-2":
		# The widened landing already has enough flat space east of its
		# entrance stairs. Keep the existing narrow-bed size limit, but use
		# that space so the hard base no longer seals the stair's top edge.
		var landing_width := width
		var landing_shift := Vector3(.7,0,0)
		while landing_width>=.9:
			if _supported_footprint(stage,parent,landing_width,landing_shift):
				return {"width":landing_width,"shift":landing_shift,"source_width":width,"limited":landing_width<width-.001,"reason":"existing_wide_landing_clear_of_entrance_stairs"}
			landing_width-=.10
	# Fixed placements leave repair supports and the entrance turn usable by
	# both travellers. The 1-4 planter uses the empty front-left terrace, away
	# from the full fountain and the narrow gate's approach.
	# They never depend on actor occupancy or completion state.
	# The rain courtyard keeps its full planter on the same rear terrace,
	# east of the doorway's masonry; the south approach remains unchanged.
	var rear_placements := Props.rear_placements()
	if rear_placements.has(id) and _supported_footprint(stage,parent,width,rear_placements[id]):
		return {"width":width,"shift":rear_placements[id],"source_width":width,"limited":false,"reason":"source_ratio_supported_repair_landing"}
	# Search translations at the existing interaction, not new support geometry.
	# Only contiguous, level fixed ground is accepted; dynamic and stair tiles
	# never become a planter's dependency. This runs on prop rebuild, not frames.
	var shifts: Array[Vector3] = [Vector3.ZERO]
	for distance: float in [.2,.4,.6]:
		for axis: Vector3 in [Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,0,0),Vector3(0,0,1),Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(-1,0,1),Vector3(1,0,1)]: shifts.append(axis*distance)
	# Prefer the far side of real ground, deterministically, rather than the
	# player's current location. Walking and completion must not move the bed.
	shifts.sort_custom(func(a: Vector3,b: Vector3) -> bool:
		if not is_equal_approx(a.x+a.z,b.x+b.z): return a.x+a.z < b.x+b.z
		if not is_equal_approx(a.length_squared(),b.length_squared()): return a.length_squared() < b.length_squared()
		return a.x < b.x)
	for shift: Vector3 in shifts:
		if _supported_footprint(stage,parent,width,shift):
			return {"width":width,"shift":shift,"source_width":width,"limited":false,"reason":"source_ratio_supported"}
	# Explicit safe candidate if a future layout cannot support the full image.
	# Report its exception rather than stretching the terrain or hiding clipping.
	var candidate := width-.10
	while candidate >= .9:
		for shift: Vector3 in shifts:
			if _supported_footprint(stage,parent,candidate,shift):
				return {"width":candidate,"shift":shift,"source_width":width,"limited":true,"reason":"fixed_ground_footprint_limit"}
		candidate -= .10
	return {"width":.9,"shift":Vector3.ZERO,"source_width":width,"limited":true,"reason":"requires_layout_review"}

static func _supported_footprint(stage: Node,parent: Node3D,width: float,shift: Vector3) -> bool:
	# IntegratedGardenProps' complete square base is 0.80 at canvas width1.16.
	# Include 0.03 of clearance around it; check interior as well as corners.
	var half := Props.planter_span(width) * .5 + Vector2.ONE * float(Props.planter_spec().support_clearance)
	var center: Vector3 = parent.global_position+shift+Props.planter_center()
	var supports: Array[Node3D] = []
	for key: String in stage._surfaces:
		if key.begins_with("f:") and _authored_fixed_support(stage,key): supports.append(stage._surfaces[key])
	for iz in range(9):
		for ix in range(9):
			var point := center+Vector3(lerpf(-half.x,half.x,ix/8.0),0,lerpf(-half.y,half.y,iz/8.0))
			var found := false
			for surface: Node3D in supports:
				var local := surface.to_local(point)
				if absf(local.x) > .5001 or absf(local.z) > .5001: continue
				if absf(float(surface.sample_height(point))-center.y) > .025: continue
				found = true; break
			if not found: return false
	return true

static func _authored_fixed_support(stage: Node,id: String) -> bool:
	# 3-4's returning root line repeats f:-4:0. World deduplication selects
	# the occupied record, so that originally fixed cell can be tagged root
	# after completion. Its authored identity and physical height never moved.
	# Do not shrink the core when only the duplicate record's kind changes.
	var original: Array = stage.world.level.get("tiles",[])
	if stage.world.level.has("sanctuary"):
		original = original + stage.world.level.sanctuary.get("tiles",[])
	var current: Dictionary = stage._tile_map.get(id,{})
	if bool(current.get("solid",false)): return false
	for tile: Dictionary in original:
		if str(tile.get("id","")) != id: continue
		if str(tile.get("kind","fixed")) in ["root","shadow","module","water"] or bool(tile.get("solid",false)): return false
		return is_equal_approx(float(tile.x),float(current.get("x",INF))) and is_equal_approx(float(tile.z),float(current.get("z",INF))) and is_equal_approx(float(tile.h),float(current.get("h",INF)))
	return false
