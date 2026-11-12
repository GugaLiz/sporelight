extends SceneTree
## CPU geometry/art/state tests. GPU depth and legibility require separate QA.
const Dressing = preload("res://presentation/native/original_cloud_dressing.gd")
const Art = preload("res://presentation/native/original_cloud_art.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
var checks := 0
var failures: Array[String] = []

class Fixture extends Node3D:
	var world: RefCounted
	var _props := Node3D.new()
	var _surfaces: Dictionary = {}
	var _props_nodes: Dictionary = {}
	var settings: Dictionary = {"particles":true,"lowMotion":false}
	var visual_time := 0.0
	func _init() -> void: add_child(_props)
	func tile_position(tile: Dictionary) -> Vector3: return Vector3(float(tile.x),float(tile.h)*.65,float(tile.z))
	func _box(parent: Node3D, dimensions: Vector3, at: Vector3, _color: Color) -> MeshInstance3D:
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new(); mesh.size = dimensions
		node.mesh = mesh; node.position = at
		parent.add_child(node)
		return node

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	var lift_material := Dressing.lift_top()
	check(lift_material == Dressing.lift_top(),"lift artwork cached between support updates")
	check(lift_material.cull_mode == BaseMaterial3D.CULL_DISABLED,"lift top matches native terrain winding on both visible faces")
	var lift_image: Image = lift_material.albedo_texture.get_image()
	for sample: Array in [[Vector2i(128,128),Color("f8f2d3")],[Vector2i(65,128),Color("b2c9b5")],[Vector2i(32,128),Color("cadcce")]]:
		check(lift_image.get_pixelv(sample[0]).is_equal_approx(sample[1]),"lift original centre/inset/base colours "+str(sample[0]))
	# Source 36/58 square must span 158-160 texels at this resolution.
	var inset_width := 0
	for x in range(256):
		if lift_image.get_pixel(x,85).is_equal_approx(Color("b2c9b5")): inset_width += 1
	check(absf(float(inset_width)/256.0-36.0/58.0) < .008,"lift inset preserves source tile proportion")
	for kind: String in ["arch","arch_pink","tower","pool","bench","plant","plant_large","flowers","story_flowers","bird","lanterns","sky_stars","turn","pad","valve","dock","finish","seed","waterfall","drop","island","cloud","background_star"]:
		for complete: bool in [false,true]:
			var data: Dictionary = Art.art(kind,complete)
			var picture: Image = data.texture.get_image()
			check(picture.get_used_rect().size != Vector2i.ZERO,kind+" visible raster")
			check(data.texture == Art.art(kind,complete).texture,kind+" cached")
			check(picture.get_used_rect().position.x > 0 and picture.get_used_rect().end.x < picture.get_width(),kind+" horizontal crop safe")
	for id: String in ["cloud-1","cloud-2","cloud-3"]:
		for complete: bool in [false,true]:
			var fixture := Fixture.new()
			root.add_child(fixture)
			fixture.world = Cloud.new(id)
			fixture.world.state.completed = complete
			var saved: Dictionary = fixture.world.snapshot()
			var tiles: Array = fixture.world.tiles()
			Dressing.scenery(fixture)
			check(fixture.world.snapshot() == saved and fixture.world.tiles() == tiles,id+" dressing preserves gameplay")
			var kinds: Array[String] = []
			for prop: Node3D in fixture._props.get_children():
				_full_footprint(prop,tiles,id)
				kinds.append(str(prop.get_meta("original_kind","")))
				var support := str(prop.get_meta("support_id",""))
				check(tiles.any(func(t: Dictionary) -> bool: return str(t.id) == support),id+" real support "+support)
				check(prop.find_children("*","CollisionObject3D",true,false).is_empty(),id+" no added walkable collision")
				for child: Node in prop.get_children():
					if child is Sprite3D:
						check(not child.no_depth_test,id+" normal depth")
						check(is_equal_approx(child.pixel_size*2,float(child.get_meta("source_pixel_world"))),id+" source pixel ratio")
			check(kinds.count("bench") == 1,id+" original bench")
			check(kinds.count("arch")+kinds.count("arch_pink") == 1,id+" original arch")
			if id == "cloud-1": check(kinds.count("tower") == 1 and kinds.count("plant") == 2,id+" tower plants")
			if id == "cloud-2":
				check(kinds.count("pool") == 1,id+" original pool")
				check(kinds.has("bird") == complete and kinds.has("waterfall") == complete,id+" completion bird waterfall")
				if complete: _motion(fixture)
				if complete: _bird_layout(fixture,tiles)
			if id == "cloud-3": check(kinds.has("lanterns") and kinds.has("sky_stars") == complete,id+" lanterns completion stars")
			var expected_flowers := tiles.filter(func(t: Dictionary) -> bool: return str(t.kind) == "floor" and (int(t.x)*7+int(t.z)*13)%11 == 0).size() if complete else 0
			check(kinds.count("flowers") == expected_flowers,id+" completed floor flower distribution")
			var parent := Node3D.new(); fixture.add_child(parent)
			check(Dressing.build_mark(fixture,parent,{"id":"seed"}),id+" original marker handled")
			check(parent.get_child_count() == 1,id+" seed initially visible")
			parent.free()
			parent = Node3D.new(); fixture.add_child(parent)
			fixture.world.state.cloudSeed = true
			Dressing.build_mark(fixture,parent,{"id":"seed"})
			check(parent.get_child_count() == 0,id+" picked seed gone")
			fixture.world.state.observations = ["story"]
			Dressing.build_mark(fixture,parent,{"id":"story"})
			check(parent.get_child_count() == 1,id+" found story flower")
			fixture.free()
	for kind: String in ["tower","pool","lanterns","finish"]:
		check(Art.art(kind,false).texture.get_image().get_data() != Art.art(kind,true).texture.get_image().get_data(),kind+" complete artwork changes")
		check(Art.art(kind,false).bounds == Art.art(kind,true).bounds and Art.art(kind,false).foot == Art.art(kind,true).foot,kind+" stable completion size anchor")
	for kind: String in ["valve","dock"]:
		var data: Dictionary = Art.art(kind)
		var picture: Image = data.texture.get_image()
		check(not str(data.svg).contains("<text"),kind+" lift sign has no font dependency")
		for source: Vector2 in [Vector2(0,-35),Vector2(0,-31),Vector2(0,-27),Vector2(-1.5,-34.5),Vector2(1.5,-27.5)]:
			var pixel: Vector2 = (source-data.bounds.position)*2
			var color := picture.get_pixel(int(pixel.x),int(pixel.y))
			check(color.b > color.r and color.g > color.r and color.a > .8,kind+" arrow geometry raster visible "+str(source))
	print(JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _motion(fixture: Fixture) -> void:
	var drop: Node3D = fixture._props_nodes.original_cloud_waterfall.get_node("Drop0")
	var start := drop.position
	fixture.visual_time = 1000
	Dressing.update(fixture)
	check(start != drop.position,"waterfall changes with shared clock")
	var paused := drop.position
	Dressing.update(fixture)
	check(paused == drop.position,"waterfall holds at fixed shared clock")
	fixture.settings.lowMotion = true
	Dressing.update(fixture)
	var reduced := drop.position
	fixture.visual_time = 2000
	Dressing.update(fixture)
	check(reduced == drop.position,"reduced motion freezes drops")
	fixture.settings.particles = false
	Dressing.update(fixture)
	check(not drop.visible,"particle preference respected")

func _bird_layout(fixture: Fixture, tiles: Array) -> void:
	var bird_root: Node3D
	var pool_root: Node3D
	for prop: Node3D in fixture._props.get_children():
		if str(prop.get_meta("original_kind","")) == "bird": bird_root = prop
		if str(prop.get_meta("original_kind","")) == "pool": pool_root = prop
	var bird: Sprite3D = bird_root.get_child(0)
	var pool: Sprite3D = pool_root.get_child(0)
	check(is_equal_approx(bird_root.position.y,pool_root.position.y) and is_equal_approx(bird.position.y,0),"bird moves only along same-height terrace")
	check(not bird.no_depth_test and bird.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS,"bird retains real depth and transparency ordering")
	# Both are upright parallel cards: a positive plane separation makes the
	# bird appear in front wherever its body overlaps the pool in projection.
	var front_gap := (bird.global_position-pool.global_position).dot(Dressing.FRONT)
	check(front_gap > .1,"whole bird plane is in front of pool rim")
	for source_x: float in [-7.0,0.0,7.0,13.0]:
		var foot := bird.global_position+Dressing.RIGHT*(source_x*Dressing.PIXEL)
		var supported := false
		for tile: Dictionary in tiles:
			if str(tile.kind) == "floor" and absf(float(tile.x)-foot.x) <= .5 and absf(float(tile.z)-foot.z) <= .5 and is_equal_approx(float(tile.h)*.65,foot.y): supported = true
		check(supported,"bird full width has existing upper-terrace support "+str(source_x))
	check(bird_root.get_meta("support_id") == "floor:11:4", "bird keeps explicit real support identity")

func _full_footprint(prop: Node3D,tiles: Array,id: String) -> void:
	var kind := str(prop.get_meta("original_kind",""))
	# Source solid box bottoms: half-width, half-depth, centre Y (pixels).
	# Hanging lanterns/stars and the falling stream have no ground footprint.
	var sizes := {"arch":Vector3(34,14,1),"arch_pink":Vector3(34,14,1),"tower":Vector3(35,17.5,2),"pool":Vector3(42,21,9),"bench":Vector3(20,10,2),"plant":Vector3(9,4.5,5),"plant_large":Vector3(16,8,9)}
	if not sizes.has(kind): return
	var art: Sprite3D = prop.get_child(0)
	var pixel := float(art.get_meta("source_pixel_world"))
	var size: Vector3 = sizes[kind]
	var supported := true
	var missed := Vector3.ZERO
	for ix in range(9):
		for iz in range(9):
			var u := float(ix)/8-.5; var v := float(iz)/8-.5
			# Invert the painted isometric bottom diamond into its complete
			# existing horizontal footprint, including its rear half.
			var foot := prop.global_position+Dressing.RIGHT*((u-v)*size.x*pixel)+Dressing.FRONT*((size.z+(u+v)*size.y)*2*pixel)
			var hit := false
			for tile: Dictionary in tiles:
				if str(tile.kind) == "floor" and absf(float(tile.x)-foot.x)<=.5001 and absf(float(tile.z)-foot.z)<=.5001 and is_equal_approx(float(tile.h)*.65,foot.y): hit = true; break
			if not hit: supported = false; missed = foot
	check(supported,id+" "+kind+" complete painted base has real same-height support; last unsupported "+str(missed))
