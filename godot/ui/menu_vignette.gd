extends Node2D
## Decorative cover only. Original scene coordinates, foot registration and
## 24-second choreography are shared by all viewport sizes.
const Paint := preload("res://presentation/world/garden_paint.gd")
const Creatures := preload("res://presentation/actors/creature_art.gd")
const Assets := preload("res://elements/element_assets.gd")
const AttentionShader := preload("res://ui/cover_attention.gdshader")
const LOOP_MS := 24000.0
const LIGHTS := [[0, 390, 468], [2400, 444, 458], [5800, 548, 478], [7500, 552, 528], [10000, 542, 530], [11350, 542, 530], [11950, 572, 365], [12750, 475, 355], [14500, 340, 420], [16500, 282, 508], [18500, 280, 400], [21000, 390, 420], [24000, 390, 468]]
# Cover gaze poses are edited from the quarter idle/walk identity, with a closed
# smile and the same view; do not reintroduce the rejected frontal baby-face set.
# Garden profile frames stay local to their world view.
const HERO_POSES := {"idle-front":"idle-front", "idle-side":"cover-idle-side", "turn-quarter":"idle-front"}
const PALM_ART := [
	"res://assets/images/cover-palm-20261118/palm-0.png",
	"res://assets/images/cover-palm-20261118/palm-1.png",
	"res://assets/images/cover-palm-20261118/palm-2.png",
	"res://assets/images/cover-palm-20261118/palm-3.png",
	"res://assets/images/cover-palm-20261118/palm-4.png",
	"res://assets/images/cover-palm-20261118/palm-5.png",
]
# Measured on the registered 512px whole-pose canvases, not on the face/hat.
const PALM_ANCHORS := [Vector2(214,391),Vector2(193,383),Vector2(175,367),Vector2(157,331),Vector2(165,329),Vector2(169,329)]
const ATTENTION_ART := [
	"res://assets/images/cover-identity-20261118/attention-0.png",
	"res://assets/images/cover-identity-20261118/attention-1.png",
	"res://assets/images/cover-identity-20261118/attention-2.png",
	"res://assets/images/cover-identity-20261118/attention-3.png",
	"res://assets/images/cover-identity-20261118/attention-4.png",
	"res://assets/images/cover-identity-20261118/attention-5.png",
]
const ATTENTION_NECKS := [Vector2(246,277),Vector2(240,278),Vector2(260,287),Vector2(245,283),Vector2(241,286),Vector2(262,287)]

class BuddyArt:
	extends Node2D
	var time := 0.0
	var look: Dictionary = {}
	var images: Dictionary = {}
	func _draw() -> void:
		Creatures.buddy(Paint.new(self, images), Vector2.ZERO, 53, time, look)

var elapsed_ms := 0.0
var settings: Dictionary = {}
var current_pose: Dictionary = {}
var hero := Sprite2D.new()
var head_material := ShaderMaterial.new()
var buddy := BuddyArt.new()
var orb := Sprite2D.new()
var backdrop := Sprite2D.new()
var _frames: Dictionary = {}
var _flies: Array[Sprite2D] = []
var _ready_art := false


static func _smooth(value: float) -> float:
	var p := clampf(value, 0, 1)
	return p * p * (3 - 2 * p)


static func _path(time: float) -> Dictionary:
	var progress := _smooth((time - 2400) / 4200) if time < 6600 else 1 - _smooth((time - 13500) / 4200)
	return {"x": 325 + progress * 150, "y": 642 - progress * 36, "progress": progress}


static func _palm_frame(t: float) -> int:
	if t < 7700: return 0
	if t < 8050: return 1
	if t < 8500: return 2
	if t < 9000: return 3
	if t < 10000: return 4
	if t < 11000: return 5
	if t < 11350: return 4
	if t < 11500: return 3
	if t < 11620: return 2
	if t < 11750: return 1
	return 0


static func _palm_position(at: Dictionary, frame: int) -> Vector2:
	var local: Vector2 = PALM_ANCHORS[frame] - Vector2(256,472)
	var scale := (290.0 - float(at.progress) * 16) * 0.8 / 512.0
	# These poses face left in the sheet and face right during the encounter.
	return Vector2(at.x,at.y) + Vector2(-local.x,local.y) * scale + Vector2(0,-6)


static func attention_for(at: Dictionary, target: Vector2) -> Dictionary:
	# Decide from the light relative to the face, never from a repeating sway.
	var eye := Vector2(at.x,at.y - (290.0 - float(at.progress) * 16) * 0.455)
	var delta := target - eye
	var elevation := atan2(-delta.y,maxf(absf(delta.x),1))
	var frame := 0 if elevation > 0.35 else (2 if elevation < -0.22 else 1)
	var flip := delta.x > 0
	if absf(delta.x) < 30 and delta.y < -18:
		frame = 3 if delta.x < -10 else (4 if delta.x > 10 else 5)
		flip = false
	var base_elevation := [0.7,0.0,-0.45,1.0,1.0,1.4][frame] as float
	var head_angle := clampf((elevation-base_elevation)*0.16,-0.045,0.045)
	if frame >= 3: head_angle = clampf(delta.x / 500,-0.04,0.04)
	return {"key":"attention-%d" % frame,"frame":frame,"flip":flip,"target":target,"eye":eye,"elevation":elevation,"head_angle":head_angle,"neck":ATTENTION_NECKS[frame]/512.0,"lean":clampf(delta.x/180,-1,1)*0.014}


static func pose_at(time: float, low_motion: bool = false) -> Dictionary:
	var t := 0.0 if low_motion else fposmod(time, LOOP_MS)
	var at := _path(t)
	var walking := (t > 2400 and t < 6600) or (t > 13500 and t < 17700)
	var returning := t >= 13100 and t < 18500
	var curious := t >= 6950 and t < 10000
	var delighted := t >= 10000 and t < 11350
	var distance := (1 - float(at.progress) if returning else float(at.progress)) * 150
	var key := "idle-front"
	var flip := false
	if walking:
		key = "step-%d" % (1 + int(floor(distance / 60 * 8)) % 8)
		flip = not returning
	elif t >= 1650 and t < 2000:
		key = "turn-quarter"
		flip = true
	elif t >= 2000 and t < 6950:
		key = "idle-side"
		flip = true
	elif t >= 6950 and t < 7350:
		key = "crouch-lower"
		flip = true
	elif t >= 7350 and t < 11750:
		key = "palm-%d" % _palm_frame(t)
		flip = true
	elif t >= 11750 and t < 12150:
		key = "crouch-lower"
		flip = true
	elif t >= 12150 and t < 12500:
		key = "idle-side"
		flip = true
	elif t >= 12500 and t < 12750:
		key = "turn-quarter"
		flip = true
	elif t >= 13100 and t < 13350:
		key = "turn-quarter"
	elif t >= 13350 and t < 18100:
		key = "idle-side"
	elif t >= 18100 and t < 18500:
		key = "turn-quarter"
	var following := _path(maxf(0, t - 650))
	var light := Vector2(390, 468)
	for index in LIGHTS.size() - 1:
		var a: Array = LIGHTS[index]
		var b: Array = LIGHTS[index + 1]
		if t >= a[0] and t < b[0]:
			light = Vector2(a[1], a[2]).lerp(Vector2(b[1], b[2]), _smooth((t - a[0]) / float(b[0] - a[0])))
			break
	if not low_motion:
		light.y += sin(t / LOOP_MS * TAU * 8) * 3
	var grasp := 0.0
	var palm := _palm_position(at, _palm_frame(t))
	if t >= 8050 and t < 11350:
		grasp = _smooth((t - 8050) / 450)
	elif t >= 11350 and t < 11750:
		grasp = 1 - _smooth((t - 11350) / 400)
		# The mote leaves the last held palm, independently of the retracting arms.
		palm = _palm_position(at, 4)
	light = light.lerp(palm, grasp)
	var attention := attention_for(at,light)
	var tracking := not low_motion and (key in ["idle-front","idle-side","turn-quarter"])
	if tracking:
		key = attention.key
		flip = attention.flip
	return {"time": t, "hero": {"x": at.x, "y": at.y, "progress": at.progress, "key": key, "walking": walking, "flip": flip}, "buddy": {"x": following.x - 74, "y": following.y + 10, "walking": (t > 3050 and t < 7250) or (t > 14150 and t < 18350), "happy": curious or delighted}, "light": light, "palm": palm, "grasp": grasp, "holding": t >= 8500 and t < 11350, "attention":attention,"tracking":tracking}


func _ready() -> void:
	name = "MenuVignette"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	backdrop.name = "OriginalScenery"
	backdrop.texture = Assets.texture_for_source("res://assets/images/main/bg.png")
	backdrop.centered = false
	backdrop.scale = Vector2(1280, 720) / backdrop.texture.get_size()
	# Draw behind this vignette's shadows without falling behind HUD's older
	# home background in the global CanvasItem z-order.
	backdrop.show_behind_parent = true
	add_child(backdrop)
	for key: String in HERO_POSES:
		_frames[key] = Assets.texture(HERO_POSES[key])
	for index in PALM_ART.size():
		_frames["palm-%d" % index] = Assets.texture_for_source(PALM_ART[index])
	for index in ATTENTION_ART.size():
		_frames["attention-%d" % index] = Assets.texture_for_source(ATTENTION_ART[index])
	_frames["crouch-lower"] = _frames["palm-0"]
	for index in 8:
		_frames["step-%d" % (index + 1)] = Assets.texture("cover-step-%d" % (index + 1))
	hero.name = "CoverLuvie"
	hero.centered = false
	head_material.shader = AttentionShader
	hero.material = head_material
	add_child(hero)
	buddy.name = "CoverBuddy"
	buddy.images = {"ball": Assets.texture_for_source("res://assets/images/journey-gardens/buddy-ball.png")}
	add_child(buddy)
	orb.name = "LeadingLight"
	orb.texture = Assets.texture_for_source("res://assets/images/menu-fx-redrawn/orb.png")
	orb.scale = Vector2.ONE * 86.0 / orb.texture.get_width()
	add_child(orb)
	for index in 4:
		var fly := Sprite2D.new()
		fly.name = "Firefly%d" % index
		fly.texture = Assets.texture_for_source("res://assets/images/menu-fx-redrawn/firefly.png")
		_flies.append(fly)
		add_child(fly)
	_ready_art = true
	refresh_pose()


func configure(value: Dictionary) -> void:
	settings = value.duplicate(true)
	set_process(not bool(settings.get("lowMotion", false)))
	refresh_pose()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	elapsed_ms = fposmod(elapsed_ms + minf(delta, 0.064) * 1000, LOOP_MS)
	refresh_pose()


func refresh_pose() -> void:
	if not _ready_art:
		return
	var low := bool(settings.get("lowMotion", false))
	current_pose = pose_at(elapsed_ms, low)
	var person: Dictionary = current_pose.hero
	var art_size := 290.0 - float(person.progress) * 16
	hero.texture = _frames[person.key]
	hero.position = Vector2(person.x, person.y)
	var pose_scale := 1.0
	hero.rotation = 0
	head_material.set_shader_parameter("head_angle",0.0)
	# Whole crouching poses share one registered scale and grounded boot point.
	var crouched := str(person.key).begins_with("crouch") or str(person.key).begins_with("palm-")
	if crouched:
		pose_scale = 0.8
	var t := float(current_pose.time)
	if person.key == "crouch-lower":
		var crouch_weight := _smooth((t - 6950) / 400) if t < 7350 else 1 - _smooth((t - 11750) / 400)
		# Use a single opaque pose at each instant: crossfading separate heads
		# creates ghost faces. Both poses retain the same registered foot point.
		if crouch_weight < 0.5:
			hero.texture = _frames["attention-2"]
			pose_scale = lerpf(1.0, 0.96, crouch_weight * 2)
		else:
			pose_scale = lerpf(0.84, 0.8, (crouch_weight - 0.5) * 2)
	elif person.key == "turn-quarter":
		var side_weight := 0.0
		if t < 2000: side_weight = _smooth((t - 1650) / 350)
		elif t < 12750: side_weight = 1 - _smooth((t - 12500) / 250)
		elif t < 13350: side_weight = _smooth((t - 13100) / 250)
		else: side_weight = 1 - _smooth((t - 18100) / 400)
		hero.texture = _frames["idle-side"] if side_weight >= 0.5 else _frames["idle-front"]
	hero.scale = Vector2(-1 if person.flip else 1, 1) * art_size * pose_scale / hero.texture.get_width()
	if not low and not person.walking and not crouched:
		hero.scale.y *= 1 + sin(float(current_pose.time) / 900) * 0.004
	# Registered feet are 236/256 down every original frame, not sprite center.
	hero.offset = Vector2(-hero.texture.get_width() * 0.5, -hero.texture.get_height() * 236.0 / 256.0)
	if current_pose.tracking:
		var attention: Dictionary = current_pose.attention
		hero.rotation = attention.lean
		head_material.set_shader_parameter("neck",attention.neck)
		head_material.set_shader_parameter("head_angle",attention.head_angle)
	elif person.walking and not low:
		# Keep the full walk clip/stride while the head attends to the leading mote.
		var walking_angle := clampf((float(current_pose.attention.elevation)-0.25)*0.10,-0.035,0.035)
		head_material.set_shader_parameter("neck",Vector2(0.5,0.65))
		head_material.set_shader_parameter("head_angle",walking_angle)
	buddy.position = Vector2(current_pose.buddy.x, current_pose.buddy.y)
	buddy.time = current_pose.time
	buddy.look = {"moving": current_pose.buddy.walking, "happy": current_pose.buddy.happy, "low_motion": low}
	buddy.queue_redraw()
	orb.position = current_pose.light
	orb.scale = Vector2.ONE * lerpf(86,48,current_pose.grasp) / orb.texture.get_width()
	var insects := [[580, 348, 46, 39, 19, 0.3], [145, 408, 42, 25, 16, 2.4], [649, 491, 56, 26, 22, 4.1], [185, 562, 72, 30, 18, 1.8]]
	for index in _flies.size():
		var spec: Array = insects[index]
		var fly := _flies[index]
		var angle: float = (0 if low else float(current_pose.time) / LOOP_MS * TAU) + spec[5]
		fly.position = Vector2(spec[0] + sin(angle) * spec[3], spec[1] + sin(angle * 2) * spec[4])
		fly.rotation = 0 if low else cos(angle) * 0.13
		fly.scale = Vector2.ONE * float(spec[2]) / fly.texture.get_width()
		fly.modulate.a = 0.92 if index == 3 else 0.72
		fly.visible = bool(settings.get("particles", true))
	queue_redraw()


func _draw() -> void:
	if current_pose.is_empty():
		return
	var paint := Paint.new(self)
	paint.shadow(current_pose.hero.x, current_pose.hero.y + 2, 43, 11)
	if bool(settings.get("dynamicLight", true)):
		paint.glow(Vector2(current_pose.light.x, current_pose.hero.y + 2), 66, "#ffdc7b", 0.27, 0.26)
		paint.glow(current_pose.light, lerpf(32,15,current_pose.grasp), "#ffe8a6", 0.5)
	if bool(settings.get("particles", true)) and not bool(settings.get("lowMotion", false)) and not current_pose.holding:
		for index in range(1, 8):
			var past: Vector2 = pose_at(maxf(0, elapsed_ms - index * 95)).light
			draw_circle(past, 2.1 - index * 0.18, Color(0.87, 0.66, 0.25, 0.32 * (1 - index / 8.0)))
