extends SceneTree

const Stage = preload("res://presentation/native/native_garden_stage.gd")
const First = preload("res://presentation/native/first_garden_profile.gd")
const Second = preload("res://presentation/native/second_garden_profile.gd")

var checks := 0
var failures: Array[String] = []

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	var stage := Stage.new()
	var candidates: Array = []
	for x in range(-2, 3):
		for z in range(-2, 3):
			for h in [1.0, -1.0, 0.0]:
				candidates.append({"x":float(x),"z":float(z),"h":h,"solid":x == -1 and h == 0.0,"module":"moving" if z > 0 else ""})
	stage._tiles = candidates
	stage._architecture_tiles = candidates
	stage._motion_geometry_modules = {"moving":true}
	var before := JSON.stringify(candidates)
	var index: Dictionary = stage._terrain_neighbor_index(candidates)
	_check(not index.is_empty(), "integer board indexed")
	_check(index[Vector2i(1,0)].size() == 3, "all coincident heights retained")
	for moving in [false, true]:
		stage._motion_geometry_active = moving
		for group in ["", "moving"]:
			for solid in [false, true]:
				for h in [-1.0, 0.0, 1.0]:
					for x in range(-2, 3):
						for z in range(-2, 3):
							var tile := {"x":float(x),"z":float(z),"h":h,"solid":solid,"module":group}
							for direction: Vector2 in stage.DIRECTIONS:
								_check(stage._ramp_rise(tile,direction,candidates) == stage._ramp_rise(tile,direction,candidates,index), "ramp parity")
								_check(stage._has_neighbor(tile,direction) == stage._has_neighbor(tile,direction,index), "static face parity")
								_check(stage._has_motion_neighbor(tile,direction,candidates) == stage._has_motion_neighbor(tile,direction,candidates,index), "moving face parity")
	stage._motion_geometry_active = false
	var origin := {"x":0.0,"z":0.0,"h":0.0,"solid":false,"module":""}
	_check(stage._ramp_rise(origin,Vector2.RIGHT,candidates,index) == stage.HEIGHT_UNIT, "first acceptable coincident candidate wins")
	_check(stage._terrain_neighbor_index([{"x":0.125,"z":0.0,"h":0.0}]).is_empty(), "fractional fallback")
	_check(stage._terrain_neighbor_index([{"x":200000.0,"z":0.0,"h":0.0}]).is_empty(), "approximate integer alias fallback")
	for profile: Script in [First, Second]:
		stage._terrain_profile = profile
		_check(stage._terrain_neighbor_index(candidates).is_empty(), "dedicated profile bypass")
	_check(JSON.stringify(candidates) == before, "candidates unchanged")
	stage.free()
	print(JSON.stringify({"suite":"terrain-neighbor-equivalence","checks":checks,"passed":failures.is_empty(),"failures":failures,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
