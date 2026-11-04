class_name GardenPropArt
extends RefCounted

static func bell(p: GardenPaint) -> void:
	p.arc(0, -35, 5, 5, PI, TAU, "#ab8751", 3)
	var points := GardenPaint.quadratic_points(Vector2(-14, -7), Vector2(-8, -14), Vector2(-9, -25))
	points.append_array(GardenPaint.quadratic_points(Vector2(-9, -25), Vector2(0, -39), Vector2(9, -25)))
	points.append_array(GardenPaint.quadratic_points(Vector2(9, -25), Vector2(8, -14), Vector2(14, -7)))
	p.poly(points, p.linear(Rect2(-14, -35, 28, 35), ["#fff0b0", "#deb56a", "#a87b41"]), "#ab8751", 1)
	p.oval(0, -7, 14, 4, "#9b743e")
	p.oval(0, -5, 4, 4, "#efd49b")

static func carry_bag(p: GardenPaint, item: String, buddy := false, rolling := false, pose := "idle-front") -> void:
	p.push(Vector2(0, 31 if rolling else 0), Vector2.ONE * (0.66 if buddy else 1.0))
	if not buddy and not rolling:
		if pose == "interact" or pose.begins_with("sow-"):
			p.push(Vector2(8, 7))
		elif pose in ["lean", "salute", "symbiosis"]:
			p.push(Vector2(3, 4))
		else:
			p.push()
	else:
		p.push()
	var show_cord: bool = buddy or (not rolling and (pose == "idle-front" or pose in ["walk-1", "walk-2", "walk-7", "walk-8", "walk-9", "walk-10", "walk-11", "walk-12"]))
	if show_cord:
		p.line(GardenPaint.cubic_points(Vector2(0, -31), Vector2(1, -28), Vector2(4, -26), Vector2(7, -23)), "#7c8862", 1.6)
		p.line(GardenPaint.cubic_points(Vector2(-0.3, -31), Vector2(0.7, -28), Vector2(3.7, -26), Vector2(6.7, -23)), "#bdc69a", 0.5)
	p.push(Vector2(7, -18), Vector2.ONE * 0.65)
	p.push(Vector2(-12, 20))
	if item == "dew":
		p.image("dew-parcel", 12, -8, 25, 1)
	else:
		p.oval(12, -18, 12, 10, p.soft(8, -22, 16, "#d0d598", "#91a364", "#596d48"))
		p.oval(12, -26, 10, 3.7, "#576746")
		if item == "bell":
			p.push(Vector2(12, -17), Vector2.ONE * 0.45)
			bell(p)
			p.pop()
		else:
			p.image("light" if item == "lamp" else "lilypad" if item.begins_with("mirror") else "crystal", 12, -20, 18, 0.72)
		p.leaf(5, -12, 0.8, -1.1)
		p.leaf(17, -11, 0.85, -0.3)
		p.quadratic(Vector2(5, -10), Vector2(12, -6), Vector2(20, -14), "#d3d5a17c", 0.7)
	p.pop()
	p.pop()
	if show_cord:
		p.oval(6, -23, 1.1, 0.8, "#b8bd87", -0.6)
	p.pop()
	p.pop()

static func lever(p: GardenPaint, pull: float) -> void:
	p.shadow(0, 4, 28, 10)
	p.poly([[-24, 0], [0, 12], [24, 0], [0, -12]], "#dccbaa")
	p.poly([[-24, 0], [0, 12], [0, 19], [-24, 7]], "#ad9d7d")
	p.poly([[0, 12], [24, 0], [24, 7], [0, 19]], "#8c8e70")
	for side in [-1, 1]:
		p.line([Vector2(side * 9, -2), Vector2(side * 9, -19)], "#796747", 7)
		p.line([Vector2(side * 9 - 1, -3), Vector2(side * 9 - 1, -20)], "#c3ad75", 2)
	var end := Vector2(-10 + pull * 31, -61 + pull * 18)
	p.line([Vector2(0, -15), end], "#766345", 7)
	p.line([Vector2(-1, -17), end + Vector2(-1, 2)], "#e1c488", 2)
	p.oval(0, -15, 8, 5, p.soft(-2, -17, 10, "#f1d799", "#bea16a", "#826e46"))
	p.oval(-1, -16, 2.5, 2, "#eed9a9")
	p.oval(end.x, end.y, 9, 6, p.soft(end.x - 3, end.y - 3, 12, "#f1b18b", "#ce795b", "#8f5140"))
	p.oval(end.x - 3, end.y - 2, 3, 1.8, "#f9d5ac")
	p.leaf(-20, 7, 0.36, -0.5)
	if pull > 0:
		p.oval(19, -1, 2.2, 1.4, "#efda9f")

static func leaf_plate(p: GardenPaint, pressed: bool) -> void:
	p.shadow(0, 5, 34, 12)
	p.poly([[-31, 0], [0, 15], [31, 0], [0, -15]], "#aaa88a")
	p.poly([[-31, 0], [0, 15], [0, 20], [-31, 5]], "#8d9276")
	p.poly([[0, 15], [31, 0], [31, 5], [0, 20]], "#6b7c65")
	p.push(Vector2(0, 2 if pressed else 0))
	p.oval(0, -1, 23, 10, p.soft(-7, -6, 28, "#dce2b5", "#a5b485", "#708464"))
	p.image("lilypad", 0, -13, 48, 0, 0.92)
	p.quadratic(Vector2(-17, 4), Vector2(0, -1), Vector2(18, -6), "#f4df9c" if pressed else "#d5dfae", 1.3)
	for i in [-1, 0, 1]:
		p.line([Vector2(i * 8, -i * 2), Vector2(i * 8 - 5, -7 - i * 2)], "#dce5b76b", 0.65)
		p.line([Vector2(i * 8, -i * 2), Vector2(i * 8 + 5, 6 - i * 2)], "#dce5b76b", 0.65)
	if pressed:
		p.arc(0, 0, 28, 13, 0, TAU, "#efda9d", 1.2)
		for x in [-26, 25]:
			p.oval(x, -2, 1.8, 1.3, "#ffe7ac")
	p.leaf(-26, 4, 0.3, -0.7)
	p.pop()

static func fountain(p: GardenPaint, time: float, particles: bool) -> void:
	p.shadow(0, 8, 48, 17)
	p.oval(0, 2, 43, 20, p.soft(-8, -8, 51, "#fff4dc", "#e6d0a9", "#b7a180"))
	p.arc(0, 4, 41, 17, 0, PI, "#c4b28d", 1.1)
	for index in range(9):
		var angle := index / 9.0 * TAU
		var point := Vector2(cos(angle) * 39, sin(angle) * 17)
		p.line([Vector2(point.x * 0.86, point.y * 0.8 - 4), point, point + Vector2(0, 4)], "#baaa8550", 0.8)
	p.oval(0, -4, 39, 18, p.soft(-9, -8, 46, "#fff9e8", "#ecdabb", "#c8b18c"))
	p.oval(0, -5, 31, 13, p.soft(-8, -9, 36, "#ecfbef", "#a6dce0", "#74b7c4"))
	for index in range(3):
		p.arc(-2, -5, 9 + index * 7 + sin(time * 0.002 + index), 3 + index * 2.5, 0, PI * 1.7, "#dce6c464" if index % 2 else "#eff3db71", 0.65, -0.06)
	p.oval(0, -12, 12, 6, p.soft(-4, -16, 17, "#fff5dc", "#e1cfaa", "#bba681"))
	var pedestal := GardenPaint.quadratic_points(Vector2(-9, -14), Vector2(-3, -25), Vector2(-7, -35))
	pedestal.append(Vector2(7, -35))
	pedestal.append_array(GardenPaint.quadratic_points(Vector2(7, -35), Vector2(3, -25), Vector2(9, -14)))
	p.poly(pedestal, p.soft(-3, -27, 23, "#fff9e7", "#e8d7b6", "#c2ae8a"))
	p.oval(0, -35, 19, 8, p.soft(-6, -39, 24, "#fff8e3", "#e5d1aa", "#bca680"))
	p.oval(0, -37, 13, 4.8, "#bce6e2")
	p.leaf(0, -44, 0.55, -0.3)
	p.leaf(3, -41, 0.45, 1.6)
	for side in [-1, 1]:
		p.quadratic(Vector2(side * 2, -42), Vector2(side * 12, -65), Vector2(side * 23, -10), "#a6d7d57d", 3)
		p.quadratic(Vector2(side * 2 - 1, -43), Vector2(side * 11, -65), Vector2(side * 22, -11), "#effff2df", 1.1)
	if particles:
		for index in range(7):
			var t := fmod(time * 0.00055 + index / 7.0, 1)
			p.oval((1 if index % 2 else -1) * (8 + t * 16), -50 + t * 38, 1, 1.6, "#dcebd5b5")
	for spot in [Vector3(-32, 5, -0.4), Vector3(28, 9, 0.6), Vector3(-21, 15, 1.2)]:
		p.leaf(spot.x, spot.y, 0.42, spot.z)
		p.oval(spot.x + 4, spot.y - 1, 1.7, 1.3, "#f1d9ac")

static func butterfly_pose(index: int, time: float, anchors: Array) -> Dictionary:
	var spots: Array = anchors if anchors.size() >= 2 else [Vector2(-95, -5), Vector2(-45, 30), Vector2(55, 12), Vector2(75, -45), Vector2(-25, -62)]
	var group := index if index < 2 else 2
	var duration: float = [34000, 41000, 46000][group]
	var elapsed: float = time + [0, 19000, 14000][group]
	var cycle := int(floor(elapsed / duration))
	var phase := fmod(elapsed, duration) / duration
	var a: Vector2 = spots[(cycle + group * 2) % spots.size()]
	var b: Vector2 = spots[(cycle + group * 2 + 1) % spots.size()]
	var perched := phase < 0.38
	var u := 0.0 if perched else (phase - 0.38) / 0.62
	var point := _butterfly_position(index, a, b, u)
	var next := _butterfly_position(index, a, b, minf(1, u + 0.004))
	var period: float = [1000, 1180, 1100, 1280][index]
	return {"point": point, "perched": perched, "size": [0.64, 0.84, 1.05, 0.73][index], "heading": -0.5 + index * 0.45 if perched else (next - point).angle() + PI / 2, "wing": 1.05 + sin(time * 0.002 + index) * 0.12 if perched else sin(time * TAU / period + index * 1.7) * 1.35}

static func _butterfly_position(index: int, a: Vector2, b: Vector2, progress: float) -> Vector2:
	var ease := progress * progress * (3 - 2 * progress)
	var arc := sin(progress * PI)
	var point := a.lerp(b, ease) + Vector2(0, -arc * 22)
	if index >= 2:
		var sign_value := -1.0 if index == 2 else 1.0
		point += Vector2(sign_value * (cos(progress * PI * 3) * 15 * arc + 5), sign_value * sin(progress * PI * 3) * 10 * arc)
	else:
		point += Vector2(sin(progress * TAU + index) * 10 * arc, sin(progress * TAU) * 4 * arc)
	return point

static func butterflies(p: GardenPaint, time: float, anchors: Array = []) -> void:
	for index in range(4):
		var pose := butterfly_pose(index, time, anchors)
		p.push(pose.point, Vector2.ONE * float(pose.size), float(pose.heading))
		for side in [-1, 1]:
			# The original wing uses an affine shear as well as a scale.
			p.push()
			p.matrix = p.matrix * Transform2D(Vector2(side * cos(float(pose.wing)), -sin(float(pose.wing)) * 0.6), Vector2(0, 1), Vector2.ZERO)
			var wing := GardenPaint.cubic_points(Vector2(0, 0), Vector2(1, -8), Vector2(9, -15), Vector2(12, -9))
			wing.append_array(GardenPaint.cubic_points(Vector2(12, -9), Vector2(16, -2), Vector2(8, 2), Vector2(2, 2)))
			wing.append_array(GardenPaint.cubic_points(Vector2(2, 2), Vector2(10, 0), Vector2(12, 9), Vector2(6, 8)))
			wing.append_array(GardenPaint.quadratic_points(Vector2(6, 8), Vector2(1, 8), Vector2(0, 0)))
			p.poly(wing, p.soft(4, -5, 14, "#fff3cb" if index % 2 else "#f9dfce", "#dcb574" if index % 2 else "#d1a4a1", "#a58961" if index % 2 else "#9b8284"), "#a48b6b", 0.55)
			for tip in [Vector2(10, -9), Vector2(11, -4), Vector2(7, 5)]:
				p.quadratic(Vector2(1, 0), Vector2(5, -1), tip, "#816f5b64", 0.45)
			p.oval(9, -7, 1.7, 2.3, "#b48f6e73", -0.3)
			p.oval(10, -7.5, 0.75, 1.2, "#f7e3bd")
			p.oval(5, 5, 1, 0.8, "#f7e5cc")
			p.pop()
		p.oval(0, -0.5, 1.25, 4.2, p.soft(-1, -2, 5, "#d1b88c", "#8c795a", "#514f40"))
		p.oval(0, -4.4, 1.7, 1.5, "#8c8062")
		for side in [-1, 1]:
			p.quadratic(Vector2(0, -4), Vector2(side, -8), Vector2(side * 3, -8), "#897a5d", 0.6)
		p.pop()
