extends Node2D
## Decorative cover only. Original scene coordinates, foot registration and
## 24-second choreography are shared by all viewport sizes.
const Paint := preload("res://presentation/world/garden_paint.gd")
const Creatures := preload("res://presentation/actors/creature_art.gd")
const LOOP_MS := 24000.0
const LIGHTS := [[0, 390, 468], [2400, 444, 458], [5800, 548, 478], [7500, 552, 528], [10000, 542, 530], [11350, 542, 530], [12750, 475, 460], [14500, 340, 480], [16500, 282, 508], [18500, 280, 440], [21000, 390, 440], [24000, 390, 468]]

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
		key = "crouch-happy" if delighted else "crouch"
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
	return {"time": t, "hero": {"x": at.x, "y": at.y, "progress": at.progress, "key": key, "walking": walking, "flip": flip}, "buddy": {"x": following.x - 74, "y": following.y + 10, "walking": (t > 3050 and t < 7250) or (t > 14150 and t < 18350), "happy": curious or delighted}, "light": light}


func _ready() -> void:
	name = "MenuVignette"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	backdrop.name = "OriginalScenery"
	backdrop.texture = load("res://assets/images/main/bg.png")
	backdrop.centered = false
	backdrop.scale = Vector2(1280, 720) / backdrop.texture.get_size()
	# Draw behind this vignette's shadows without falling behind HUD's older
	# home background in the global CanvasItem z-order.
	backdrop.show_behind_parent = true
	add_child(backdrop)
	for key in ["idle-front", "idle-side", "crouch-lower", "crouch", "crouch-happy", "turn-quarter"]:
		_frames[key] = load("res://assets/images/menu-walk-redrawn/%s.png" % key)
	for index in 8:
		_frames["step-%d" % (index + 1)] = load("res://assets/images/menu-walk-redrawn/step-%d.png" % (index + 1))
	hero.name = "CoverLuvie"
	hero.centered = false
	add_child(hero)
	buddy.name = "CoverBuddy"
	buddy.images = {"ball": load("res://assets/images/journey-gardens/buddy-ball.png")}
	add_child(buddy)
	orb.name = "LeadingLight"
	orb.texture = load("res://assets/images/menu-fx-redrawn/orb.png")
	orb.scale = Vector2.ONE * 86.0 / orb.texture.get_width()
	add_child(orb)
	for index in 4:
		var fly := Sprite2D.new()
		fly.name = "Firefly%d" % index
		fly.texture = load("res://assets/images/menu-fx-redrawn/firefly.png")
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
	hero.scale = Vector2(-1 if person.flip else 1, 1) * art_size / hero.texture.get_width()
	if not low and not person.walking:
		hero.scale.y *= 1 + sin(float(current_pose.time) / 900) * 0.004
	# Registered feet are 236/256 down every original frame, not sprite center.
	hero.offset = Vector2(-hero.texture.get_width() * 0.5, -hero.texture.get_height() * 236.0 / 256.0)
	buddy.position = Vector2(current_pose.buddy.x, current_pose.buddy.y)
	buddy.time = current_pose.time
	buddy.look = {"moving": current_pose.buddy.walking, "happy": current_pose.buddy.happy, "low_motion": low}
	buddy.queue_redraw()
	orb.position = current_pose.light
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
		paint.glow(current_pose.light, 32, "#ffe8a6", 0.5)
	if bool(settings.get("particles", true)) and not bool(settings.get("lowMotion", false)):
		for index in range(1, 8):
			var past: Vector2 = pose_at(maxf(0, elapsed_ms - index * 95)).light
			draw_circle(past, 2.1 - index * 0.18, Color(0.87, 0.66, 0.25, 0.32 * (1 - index / 8.0)))
