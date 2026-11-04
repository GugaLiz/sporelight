extends SceneTree

const Iso = preload("res://presentation/world/iso_projection.gd")
const Landscape = preload("res://presentation/world/garden_landscape.gd")
const Motion = preload("res://presentation/actors/character_motion.gd")
const Props = preload("res://presentation/world/garden_prop_art.gd")
const ErrorLogger = preload("res://tests/visual_error_logger.gd")
const Conversation = preload("res://presentation/actors/mole_conversation.gd")

var failures: Array[String] = []
var checks := 0
var _logger := ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(_logger)
	_check(Iso.raw({"x": 1, "z": 0, "h": 0}) == Vector2(35, 17.5), "east tile retains 70x35 isometric basis")
	_check(Iso.raw({"x": 0, "z": 1, "h": 0}) == Vector2(-35, 17.5), "south tile retains opposite horizontal basis")
	_check(Iso.raw({"x": 1, "z": 1, "h": 1}) == Vector2(0, -13), "pseudo height offsets visuals by 48px without changing ground depth")
	_check(Iso.ground_depth({"x": 1, "z": 1, "h": 10}) == 2, "draw depth must not be computed from projected screen Y")
	_check(Landscape.face_depth({"h": 2}, {"h": 1}, 112) == 48, "adjacent raised floor exposes the original cliff height")
	_check(Landscape.face_depth({"h": -1}, {}, 112) == 64, "valley lower terrace keeps exposed base depth")
	var tiles := [{"id": "a", "x": 0, "z": 0, "h": 0}, {"id": "b", "x": 1, "z": 0, "h": 1}, {"id": "c", "x": 0, "z": 1, "h": 2}]
	var steps := Landscape.steps(tiles)
	_check(steps.size() == 1 and steps[0][0].id == "a" and steps[0][1].id == "b", "visual stair generation follows traversable one-level differences")
	var pose := Motion.pose(55, "back", false, false, {"progress": 0.2, "started_at": 0, "jump": false, "rolling": false})
	_check(pose.key == "walk-back-2" and pose.clip == "walk-back", "backward movement uses the source 55ms sequence")
	pose = Motion.pose(350, "right", false, false, {"progress": 0.9, "started_at": 0, "jump": true, "rolling": false})
	_check(pose.key == "jump-11" and pose.clip == "landing" and pose.flip, "jump landing keeps authored frame and facing")
	_check(is_equal_approx(Motion.jump_height(0.5, false), 85), "jump apex retains original world-space offset")
	_check(Motion.jump_height(0.5, true) == 0, "reduced motion removes airborne visual displacement")
	pose = Motion.pose(500, "right", true, false, {"progress": 0.5, "rolling": true})
	_check(pose.key == "idle-front" and pose.scale_x == 1, "reduced motion uses the current static pose")
	var butterfly := Props.butterfly_pose(0, 1000, [])
	_check(butterfly.perched and butterfly.point == Vector2(-95, -5), "butterfly remains at the original early-cycle resting point")
	var conversation := Conversation.new()
	var state := {"flags": [], "items": {}, "completed": false}
	_check(conversation.update(state, false, 0).is_empty(), "distant mole does not emit dialogue")
	_check(conversation.update(state, true, 1000).contains("门铃"), "first nearby visit starts the source lost-bell line")
	_check(conversation.update(state, true, 9500).is_empty(), "mole visit dialogue expires after eight seconds")
	state.flags.append("hold")
	_check(conversation.update(state, true, 10000).contains("配合"), "mechanism change advances nearby dialogue without writing rule state")
	state.items["bell"] = {"holder": "luvie"}
	_check(conversation.update(state, false, 11000).is_empty(), "finding bell remotely remains quiet")
	_check(conversation.update(state, true, 12000).contains("小门铃"), "returning with bell selects the source item-aware line")
	state.completed = true
	_check(conversation.update(state, true, 13000).contains("花开"), "restoration selects the source completed line")
	conversation.update(state, false, 22000)
	_check(conversation.update(state, true, 34000).contains("常来"), "a later visit can greet again")
	_validate_assets()
	failures.append_array(_logger.captured_errors())
	if failures.is_empty():
		print("PASS visual contracts: %d checks" % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _validate_assets() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/visual-assets.json"))
	_check(parsed is Dictionary, "visual manifest loads")
	if not parsed is Dictionary:
		return
	var aliases: Dictionary = {}
	for entry in parsed.get("entries", []):
		_check(not aliases.has(entry.id), "unique visual alias: " + str(entry.id))
		aliases[entry.id] = entry
		_check(FileAccess.file_exists(entry.resource), "copied visual resource: " + str(entry.id))
		_check(FileAccess.get_sha256(entry.resource) == entry.sha256, "unchanged source image bytes: " + str(entry.id))
	_check(aliases.get("ball", {}).get("resource", "") == "res://assets/images/journey-gardens/buddy-ball.png", "ball resolves to the final original renderer alias")
	_check(aliases.get("idle-front", {}).get("anchor", []) == [0.5, 0.921875], "character foot anchor preserves source manifest")
	_check(aliases.get("background-pond", {}).get("width", 0) == 1672, "pond source retains full resolution")
	_check(parsed.get("projection", {}).get("height_rise", 0) == 48, "asset metadata and projection agree")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
