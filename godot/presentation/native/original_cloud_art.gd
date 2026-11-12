extends RefCounted
## Independent original cloud props, transcribed from src/app/cloud/renderer.ts.
## Source pixels retain the original 58px tile ratio. Never a scene screenshot.
static var _cache: Dictionary = {}

static func art(kind: String, complete := false) -> Dictionary:
	var key := kind + (":complete" if complete else ":idle")
	if _cache.has(key): return _cache[key]
	var bounds := Rect2(-48, -190, 96, 224)
	var foot := 0.0
	var body := ""
	match kind:
		"arch", "arch_pink":
			body = _arch(kind == "arch_pink")
			bounds = Rect2(-36, -71, 72, 88); foot = 15
		"tower":
			body = _box(0, -98, 35, 17.5, 100, "f5e8d6", "ecddcb", "d0c8b8")
			body += _box(0, -103, 42, 21, 10, "fff7e6", "e3c8b5", "c2bba8")
			body += _box(0, -145, 26, 13, 42, "f9efdd", "edcfb9", "c9bfae")
			body += _poly([[-32,-145],[0,-179],[32,-145],[0,-130]], "c6a896")
			body += _poly([[0,-179],[32,-145],[0,-130]], "b08d82")
			body += _ellipse(0,-122,7,9,"83968b") + _ellipse(0,-123,4,6,"ffe4a4" if complete else "c8c7af")
			body += '<g transform="translate(0 6) scale(.78)">' + _arch(true) + '</g>'
			if complete:
				body += _line([[-24,9],[-30,-40],[-20,-70],[-25,-110]], "94aa82",4)
				for i in range(7): body += _flowers(-24+sin(i*2.0)*7,-i*17,3)
				body += _flowers(19,-95,5) + _star(0,-122,3,"ffe6a2")
			body += '<g opacity=".45">' + _line([[15,-73],[15,-92]], "fff9e9",5) + '</g>'
			foot = 19.5
		"pool":
			body = _box(0,-3,42,21,12,"f6efdc","d9d5c1","aebeb0")
			body += _poly([[-31,-3],[0,-18],[31,-3],[0,12]],"94c3c5" if complete else "d6d7bf")
			if complete: body += _line([[-18,-1],[0,7],[22,-4]],"dfefdf",1.5) + _ellipse(-10,-5,6,3,"a2bc90") + _flowers(-9,-6,2)
			bounds = Rect2(-44,-26,88,58); foot = 30
		"bench":
			body = _box(0,-6,20,10,8,"d2b79c","bfaa92","a99782") + _line([[-17,-10],[-17,-18],[2,-9]],"d6c1a5",3)
			bounds = Rect2(-22,-21,44,35); foot = 12
		"plant", "plant_large":
			var large := kind == "plant_large"
			body = _box(0,-3,16 if large else 9,8 if large else 4.5,12 if large else 8,"e2bdaa","d2ae9b","b6a58f")
			for i in range(5): body += _ellipse(sin(i*2.3)*(10 if large else 6),-11-i*3,10 if large else 6,6 if large else 4,"a9b89a" if i%2 else "8fa88d")
			bounds = Rect2(-22,-31,44,50); foot = 17 if large else 9.5
		"flowers", "story_flowers":
			body = _flowers(0,0,3 if kind == "story_flowers" else 5)
			bounds = Rect2(-19,-18,38,25); foot = 5
		"bird":
			body = _ellipse(0,-9,7,5,"eee6cb") + _ellipse(5,-13,4,4,"f8edce") + _poly([[8,-14],[13,-12],[8,-10]],"d9ad7f") + _ellipse(6,-14,1,1,"666c61")
			bounds = Rect2(-9,-19,24,21); foot = -4
		"lanterns":
			body = _line([[-30,-43],[0,-33],[35,-43]],"a6a798",1)
			for i in range(5):
				var x := -28+i*15; var y := -40+sin(i/4.0*PI)*9
				body += _ellipse(x,y,3,5,"ffe8ad" if complete else "c4beb6")
				if complete: body += _star(x,y,2,"fff3c7")
			bounds = Rect2(-36,-49,77,28)
		"sky_stars":
			for i in range(3): body += _star(i*29,-70-i*21.1,3,"fff2c2")
			bounds = Rect2(-11,-124,80,65)
		"turn":
			body = _box(0,-3,13,6.5,8,"e6d6bd","c5b59e","b9b7a0") + _ellipse(0,-4,8,4,"c7b58e") + _line([[-7,-4],[7,-4]],"fff4d5",2)
			bounds = Rect2(-15,-12,30,26); foot = 11.5
		"pad":
			body = _poly([[-18,0],[-2,-9],[18,0],[2,10]],"a8bc98") + _line([[-12,0],[12,0]],"e1e6be",1)
			bounds = Rect2(-20,-11,40,23); foot = 10
		"valve", "dock":
			body = _ellipse(0,0,9,5,"b4c9b7") + _line([[0,0],[0,-16]],"8caa9c",3) + _ellipse(0,-17,8,5,"e4cc9f")
			# Original floating round sign + lift glyph. SVG text has no portable
			# font fallback in exports; draw both arrowheads as ordinary geometry.
			body += '<g opacity=".863">' + _ellipse(0,-31,11,11,"fff8e6") + '</g>'
			body += _line([[0,-36],[0,-26]],"82aeb8",1.2)
			body += _line([[-2.5,-33],[0,-36],[2.5,-33]],"82aeb8",1.2)
			body += _line([[-2.5,-29],[0,-26],[2.5,-29]],"82aeb8",1.2)
			bounds = Rect2(-13,-44,26,51); foot = 5
		"finish":
			body = _ellipse(0,0,16,8,"d7d6b7") + _ellipse(0,-3,11,6,"a6bc94" if complete else "bcbda3") + _star(0,-17,4,"fff0b5" if complete else "ecdcaf")
			bounds = Rect2(-18,-31,36,41); foot = 8
		"seed":
			body = _ellipse(0,0,9,5,"c7d3b0") + _star(0,-10,4,"e4b692")
			bounds = Rect2(-14,-24,28,31); foot = 5
		"waterfall":
			body = '<g opacity=".6">' + _line([[38,-5],[39,124]],"badcda",12) + _line([[34,-5],[35,123]],"f0f4db",3) + '</g>'
			bounds = Rect2(30,-12,18,144)
		"drop":
			body = _ellipse(0,0,1.8,4,"edf7e7"); bounds = Rect2(-3,-5,6,10)
		"island":
			body = _box(0,0,63,31,70,"ffffef","aabdb1","9fafa7") + _box(12,-33,16,8,39,"fff9eb","abbcb0","9bafa5") + _ellipse(-20,-10,12,8,"8fae9d")
			bounds = Rect2(-65,-43,130,146)
		"cloud":
			body = _ellipse(0,0,100,12,"fffdf5") + _ellipse(-35,-4,45,14,"fffdf5") + _ellipse(20,-5,50,17,"fffdf5")
			bounds = Rect2(-102,-24,204,38)
		"background_star":
			body = _star(0,0,2,"fff9e9"); bounds = Rect2(-7,-7,14,14)
		_:
			push_error("Unknown original cloud prop: " + kind)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="%s %s %s %s">%s</svg>' % [bounds.size.x,bounds.size.y,bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y,body]
	var picture := Image.new()
	var error := picture.load_svg_from_string(svg, 2.0)
	assert(error == OK, "Original cloud vector rasterization failed: " + kind)
	_cache[key] = {"texture": ImageTexture.create_from_image(picture), "bounds": bounds, "foot": foot, "svg": svg}
	return _cache[key]

static func _poly(points: Array, color: String) -> String:
	var values := PackedStringArray()
	for p: Array in points: values.append("%s,%s" % [p[0],p[1]])
	return '<polygon points="%s" fill="#%s"/>' % [" ".join(values),color]

static func _line(points: Array, color: String, width: float) -> String:
	var values := PackedStringArray()
	for p: Array in points: values.append("%s,%s" % [p[0],p[1]])
	return '<polyline points="%s" fill="none" stroke="#%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % [" ".join(values),color,width]

static func _ellipse(x: float, y: float, rx: float, ry: float, color: String) -> String:
	return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="#%s"/>' % [x,y,rx,ry,color]

static func _box(x: float,y: float,w: float,d: float,h: float,top: String,left: String,right: String) -> String:
	return _poly([[x-w,y],[x,y+d],[x,y+d+h],[x-w,y+h]],left) + _poly([[x,y+d],[x+w,y],[x+w,y+h],[x,y+d+h]],right) + _poly([[x,y-d],[x+w,y],[x,y+d],[x-w,y]],top)

static func _star(x: float,y: float,r: float,color: String) -> String:
	return _poly([[x,y-r*3],[x+r*.7,y-r*.7],[x+r*3,y],[x+r*.7,y+r*.7],[x,y+r*3],[x-r*.7,y+r*.7],[x-r*3,y],[x-r*.7,y-r*.7]],color)

static func _flowers(x: float,y: float,count: int) -> String:
	var result := ""
	for i in range(count):
		var xx := x+sin(i*8.0)*13; var yy := y+cos(i*3.0)*5
		result += _line([[xx,yy],[xx-2,yy-8]],"8da88a",1.5) + _ellipse(xx-2,yy-9,3,2.5,"f1beac" if i%2 else "f6dda5") + _ellipse(xx-2,yy-9,1,1,"fff8dc")
	return result

static func _arch(pink: bool) -> String:
	return _box(0,-54,34,14,55,"edcabc" if pink else "f7eddb","dcb7a6" if pink else "e5d9c4","bfc5b5") + '<path d="M-13 0V-30 A13 13 0 0 1 13 -30 V0Z" fill="#829e98"/><path d="M-8 0V-29 A10 10 0 0 1 12 -29 V0Z" fill="#b6c9ba"/>' + _line([[-28,-54],[0,-68],[29,-54]],"fff9ec",3) + _box(-24,-7,7,3.5,8,"fff8e8","e5d3bd","c7bdab") + _box(24,-7,7,3.5,8,"fff8e8","e5d3bd","c7bdab")
