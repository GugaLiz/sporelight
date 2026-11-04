class_name GardenCreatureArt
extends RefCounted

static func buddy(p: GardenPaint, at: Vector2, size: float, time: float, look: Dictionary = {}) -> void:
	var low: bool = look.get("low_motion", false)
	var t := 0.0 if low else time
	var breath := sin(t / 780.0)
	var walk := sin(t / 110.0) if look.get("moving", false) else 0.0
	p.push(at, Vector2.ONE * size / 48.0)
	p.shadow(1, 1, 20, 5)
	if look.get("rolling", false):
		p.push(Vector2(0, -18), Vector2.ONE, 0 if low else t / 220.0)
		p.image("ball", 0, -22, 40, 0)
		p.pop()
		p.pop()
		return
	p.push(Vector2(0, 0 if low else breath * 0.65 - absf(walk) * 1.8))
	if look.get("waiting", false):
		p.push(Vector2(0, 3), Vector2(1.045, 0.92))
	p.oval(-6, -1 + walk, 5, 2.8, p.soft(-7, -2, 6, "#e3c3a1", "#b89170", "#85674f"))
	p.oval(6, -1 - walk, 5, 2.8, p.soft(5, -2, 6, "#e3c3a1", "#b89170", "#85674f"))
	var body := GardenPaint.cubic_points(Vector2(-10, -23), Vector2(-10, -15), Vector2(-15, -4), Vector2(-7, -2))
	body.append_array(GardenPaint.quadratic_points(Vector2(-7, -2), Vector2(0, 1), Vector2(8, -2)))
	body.append_array(GardenPaint.cubic_points(Vector2(8, -2), Vector2(14, -5), Vector2(10, -17), Vector2(10, -23)))
	p.poly(body, p.soft(-1, -13, 15, "#fff8e7", "#efdfba", "#bba383"))
	for i in range(18):
		p.oval(sin(i * 7.3) * 8, -19 + (i * 7 % 16), 0.35, 0.6, "#fff9e847" if i % 2 else "#bca58432")
	p.oval(0, -23, 15.5, 4.6, p.soft(-3, -24, 19, "#f1c5a2", "#d49b78", "#975e49"))
	for i in range(-13, 14, 3):
		p.line([Vector2(i * 0.35, -21), Vector2(i, -26)], "#a56d594c", 0.55)
	var hat := GardenPaint.cubic_points(Vector2(-20, -25), Vector2(-20, -36), Vector2(-10, -48), Vector2(0, -47))
	hat.append_array(GardenPaint.cubic_points(Vector2(0, -47), Vector2(12, -47), Vector2(24, -34), Vector2(21, -25)))
	hat.append_array(GardenPaint.cubic_points(Vector2(21, -25), Vector2(13, -18), Vector2(-13, -18), Vector2(-20, -25)))
	p.poly(hat, p.soft(-5, -37, 26, "#f59b73", "#d85b44", "#8f352d"))
	# Reuse the original shaded ball surface, clipped to the same cap outline.
	var hat_uv := PackedVector2Array()
	var ball: Texture2D = p.images.get("ball")
	if ball != null:
		var ball_height := 44.0 * ball.get_height() / float(ball.get_width())
		for point in hat:
			hat_uv.append(Vector2((point.x + 22) / 44.0, (point.y + 48) / ball_height))
		p.textured_poly(hat, "ball", hat_uv)
	for i in range(36):
		var angle := i * 2.399
		var radius := 3 + sqrt(float(i)) * 2.6
		p.oval(cos(angle) * radius, -35 + sin(angle) * radius * 0.58, 0.3, 0.45, "#ffdcba24" if i % 3 else "#74352821")
	p.quadratic(Vector2(-18, -25), Vector2(0, -19), Vector2(19, -25), "#efb18c8c", 1.1)
	var blink := not low and fmod(t, 5200) > 5010
	p.eye(-4.5, -13, blink or look.get("happy", false))
	p.eye(4.5, -13, blink or look.get("happy", false))
	p.oval(-7.5, -9.6, 2.4, 1.3, "#db9b805a")
	p.oval(7.5, -9.6, 2.4, 1.3, "#db9b805a")
	p.arc(0, -10, 1.8, 1.8, 0.15, PI - 0.15, "#9c7155", 0.8)
	p.leaf(10, -4, 0.65, -0.5)
	p.oval(5, -4, 2.9, 2, p.soft(5, -5, 4, "#fff5dc", "#dfc89e", "#b89b76"))
	if look.get("waiting", false):
		p.leaf(15, -12, 0.55, -0.6)
		p.line([Vector2(9, -4), Vector2(14, -11)], "#799061", 0.9)
		p.pop()
	p.pop()
	p.pop()

static func mole(p: GardenPaint, at: Vector2, size: float, time: float, look: Dictionary = {}) -> void:
	var low: bool = look.get("low_motion", false)
	var t := 0.0 if low else time
	p.push(at, Vector2.ONE * size / 62.0)
	p.shadow(0, 1, 30, 9)
	p.oval(0, 1, 29, 10, p.soft(-4, -2, 32, "#b1a17a", "#877557", "#594e3e"))
	p.oval(0, -1, 23, 6, "#514638")
	for i in range(9):
		var angle := i * 0.65
		p.oval(cos(angle) * 26, sin(angle) * 6, 4 + i % 3, 2.5, p.soft(0, -5, 35, "#b7c18e", "#8b9d68", "#5b714e"), angle * 0.3)
	p.push(Vector2(0, sin(t / 950.0) * 0.65))
	for side in [-1, 1]:
		p.oval(side * 16, -22, 3.4, 4, p.soft(side * 15, -25, 6, "#d5baa0", "#a98c72", "#785f50"))
	p.oval(0, -15, 20, 22, p.soft(-6, -24, 26, "#dfccb0", "#aa9278", "#574d43"))
	for i in range(220):
		var angle := i * 2.399
		var radius := sqrt(float(i)) * 1.2
		var point := Vector2(cos(angle) * radius, -16 + sin(angle) * radius)
		p.line([point, point + Vector2(0.3, 0.85)], "#f4dec119" if i % 3 else "#5b49351c", 0.35)
	p.oval(-1, -8, 12, 9, p.soft(-4, -13, 17, "#efddbd", "#cdb594", "#99816a"))
	var blink := not low and fmod(t, 6100) > 5920
	p.eye(-8, -19, blink, 0.95)
	p.eye(8, -19, blink, 0.95)
	p.oval(0, -11, 5.2, 3.7, p.soft(-2, -13, 7, "#eac0aa", "#bc8975", "#825c50"))
	p.oval(-1.6, -12.3, 1.4, 0.65, "#f5ddc6a6")
	p.line([Vector2(0, -7), Vector2(0, -5)], "#78604b", 0.8)
	p.quadratic(Vector2(0, -5), Vector2(3, -3), Vector2(5, -5), "#78604b", 0.8)
	if look.get("speaking", false) and not low:
		p.oval(2, -5, 2, 1.3 + absf(sin(t / 145.0)) * 1.3, "#7e6150")
	for side in [-1, 1]:
		for i in range(2):
			p.line([Vector2(side * 9, -9 + i * 3), Vector2(side * (19 + i * 2), -11 + i * 6)], "#dbccb099", 0.55)
	p.leaf(-6, -1, 0.85, 0.4)
	p.leaf(5, -1, 0.8, 1.1)
	for side in [-1, 1]:
		p.push(Vector2(side * 18, -9 + sin(t / 250.0) * 2 if look.get("greet", false) and side == 1 else 0), Vector2.ONE, side * 0.2)
		p.oval(0, 0, 6.7, 4.6, p.soft(-2, -2, 9, "#ebd2b6", "#c2a284", "#8a6e58"))
		for i in range(3):
			p.oval(-3 + i * 2.5, 2.5, 0.85, 1.7, "#ecddc1")
		p.pop()
	p.pop()
	p.pop()
