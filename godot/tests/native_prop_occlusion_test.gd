extends SceneTree
## CPU card projection/alpha policy; prepared fixed poses, not a GPU verdict.
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var stage: Node2D
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func _run() -> void:
	stage=Stage.new();root.add_child(stage);stage.set_process(false)
	stage.set_world(World.new("1-4"))
	var lotus: Sprite3D
	for node in stage._props.get_children():
		if node.has_meta("original_scenery_index") and int(node.get_meta("original_scenery_index"))==16:lotus=node
	check(lotus!=null,"1-4 fixed south sanctuary gold lotus instance exists")
	if lotus==null: stage.free();quit(1);return
	check(lotus.position.is_equal_approx(Vector3(-7,.658,2)),"gold lotus retains reviewed source placement")
	var width := lotus.pixel_size*lotus.texture.get_width()
	var original: Dictionary = stage.world.snapshot()
	var hero: CharacterBody3D=stage.get_actor_body("luvie")
	var buddy: CharacterBody3D=stage.get_actor_body("buddy")
	hero.set_physics_process(false);buddy.set_physics_process(false)
	stage.world.state.active="luvie"
	# Fixed reproducible pose directly behind the same flower seen in the
	# user screenshot. It is not an exact recovery of unsaved screenshot input.
	_pose("luvie",Vector3(-7.7,.65,1.2))
	buddy.visible=false
	stage._update_occlusion()
	var old_match := _old_root_test(lotus,hero)
	rows.append({"case":"south_lotus_behind","actor":str(hero.position),"alpha":lotus.modulate.a,"oldRootMatch":old_match})
	check(not old_match,"fixed tall flower regression lies outside old root-only radius")
	check(is_equal_approx(lotus.modulate.a,.3),"1-4 foreground gold lotus crown fades over hero legs")
	check(not lotus.no_depth_test,"gold lotus keeps native depth")
	check(is_equal_approx(lotus.pixel_size*lotus.texture.get_width(),width),"occlusion preserves gold lotus approved size")
	# The inactive buddy alone must trigger; hide the active hero to prevent
	# this assertion passing because the original active-only test still runs.
	hero.visible=false;buddy.visible=true
	_pose("buddy",Vector3(-7.7,.65,1.2))
	stage._update_occlusion()
	rows.append({"case":"inactive_buddy_behind","actor":str(buddy.position),"alpha":lotus.modulate.a})
	check(is_equal_approx(lotus.modulate.a,.3),"inactive buddy independently fades foreground flower")
	# A legal front rim pose must restore the flower's alpha, even though its
	# screen rectangle can still overlap the actor's feet.
	hero.visible=true;buddy.visible=false
	_pose("luvie",Vector3(-6.75,.65,2.25))
	stage._update_occlusion()
	rows.append({"case":"hero_in_front","actor":str(hero.position),"alpha":lotus.modulate.a})
	check(is_equal_approx(lotus.modulate.a,1),"actor in foreground restores flower opacity")
	var core: Sprite3D=stage._props_nodes["mark:core"].get_child(0)
	core.modulate.a=.2
	stage._update_occlusion()
	check(core.has_meta("core_planter") and is_equal_approx(core.modulate.a,1),"core stone forced opaque regardless of initial alpha")
	check(not core.no_depth_test,"core stone keeps depth testing")
	_projection_contract()
	_cache_contract(lotus)
	check(stage.world.snapshot()==original,"cosmetic occlusion preserves rule/save snapshot")
	_hard_scenery_contract()
	print(JSON.stringify({"suite":"native-prop-occlusion","checks":checks,"passed":failures.is_empty(),"failures":failures,"rows":rows,"gpuPixelsVerified":false,"inputMode":"fixed supported prepared poses; no gameplay motor run"}))
	stage.free();quit(0 if failures.is_empty() else 1)
func _hard_scenery_contract() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in reference.cases:
		if not str(entry.name).begins_with("authored/") or str(entry.levelId)=="1-1":continue
		var session=preload("res://application/game_session.gd").new(str(entry.levelId),entry.steps[-1].snapshot)
		stage.set_world(session.world)
		for node: Node in stage._occluders:
			if not node is Sprite3D:continue
			var hard: bool=node.has_meta("opaque_structure") or node.has_meta("core_planter") or str(node.get_meta("original_scenery_alias","")) in preload("res://presentation/native/native_prop_obstacles.gd").HARD_SCENERY
			if not hard:continue
			node.modulate.a=.2
			stage._update_occlusion()
			check(is_equal_approx(node.modulate.a,1),str(entry.levelId)+" hard scenery opaque: "+str(node.name))
			check(not node.no_depth_test,str(entry.levelId)+" hard scenery retains native depth: "+str(node.name))
func _pose(who: String,at: Vector3) -> void:
	var body: CharacterBody3D=stage.get_actor_body(who)
	body.position=at
	stage.update_actor_visual(who,Vector3.ZERO,"front","")
	var capsule: CapsuleShape3D=body.get_node("Collision").shape
	var supported := true
	for ring: float in [0,.5,1]:
		for sector in range(16):
			var probe:=at+Vector3(cos(sector*TAU/16),0,sin(sector*TAU/16))*capsule.radius*ring
			var found:=false
			for key: String in stage._surfaces:
				if not key.begins_with("f:"):continue
				var surface: Node3D=stage._surfaces[key]
				var local:=surface.to_local(probe)
				if absf(local.x)>.5001 or absf(local.z)>.5001:continue
				if absf(float(surface.sample_height(probe))-at.y)<.015:found=true;break
			if not found:supported=false
	check(supported,who+" entire capsule supported at fixed regression pose "+str(at))
func _old_root_test(sprite: Sprite3D,body: CharacterBody3D) -> bool:
	var foot: Vector2=stage.world_to_screen(body.global_position)
	var head: Vector2=stage.world_to_screen(body.global_position+Vector3(0,.9,0))
	var point: Vector2=stage.world_to_screen(sprite.global_position)
	var radius: float=.42*float(stage._viewport.size.y)/stage._camera.size
	return (sprite.global_position-body.global_position).dot(Stage.CAMERA_RAY)>.02 and point.x>foot.x-radius and point.x<foot.x+radius and point.y>head.y-radius and point.y<foot.y+radius
func _projection_contract() -> void:
	# An asymmetric solid source rectangle makes transparent padding, offset,
	# flips and nonuniform scale observable without relying on arbitrary art.
	var image:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT);image.fill_rect(Rect2i(4,10,12,20),Color.WHITE)
	var texture:=ImageTexture.create_from_image(image)
	var card:=Sprite3D.new();stage._props.add_child(card)
	card.texture=texture;card.pixel_size=.01;card.offset=Vector2(9,13)
	card.position=Vector3(-8,.7,1);card.scale=Vector3(1.3,.8,1)
	stage._cache_occlusion_bounds(texture)
	check(stage._occlusion_texture_bounds[texture]==Rect2(4,10,12,20),"cache measures opaque source instead of padded canvas")
	for billboard: int in [BaseMaterial3D.BILLBOARD_DISABLED,BaseMaterial3D.BILLBOARD_ENABLED]:
		card.billboard=billboard;card.rotation.y=.37
		for flip: bool in [false,true]:
			card.flip_h=flip;card.flip_v=flip
			var result: Dictionary=stage._occlusion_projection(card,texture)
			var x: float=54 if flip else 10
			var y: float=44 if flip else 20
			var local:=Vector3(x-32+9,32-y+13,0)*.01
			var world: Vector3=card.global_transform*local
			if billboard==BaseMaterial3D.BILLBOARD_ENABLED:
				world=card.global_position+stage._camera.global_basis.x.normalized()*local.x*1.3+stage._camera.global_basis.y.normalized()*local.y*.8
			var expected: Vector2=stage.world_to_screen(world)
			check(result.rect.get_center().distance_to(expected)<.001,"projected opaque centre honors offset/flip/scale/billboard "+str(billboard)+"/"+str(flip))
	card.queue_free()
func _cache_contract(lotus: Sprite3D) -> void:
	stage._prepare_occlusion_bounds()
	var initial: Dictionary=stage._occlusion_texture_bounds.duplicate()
	var hero: AnimatedSprite3D=stage.get_actor_body("luvie").get_node("Visual/Art")
	var frames_checked:=0
	for animation: StringName in hero.sprite_frames.get_animation_names():
		for frame in hero.sprite_frames.get_frame_count(animation):
			hero.animation=animation;hero.frame=frame
			stage._update_occlusion();frames_checked+=1
	check(stage._occlusion_texture_bounds==initial,"all animation frames use prewarmed bounds without cache growth or mutation")
	# Simulate a newly assigned texture before the next rebuild: the hot path
	# must use its conservative card rather than lazily read/insert pixels.
	var saved:=lotus.texture
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	lotus.texture=ImageTexture.create_from_image(image)
	for tick in range(10):stage._update_occlusion()
	check(stage._occlusion_texture_bounds==initial,"unknown hot-path texture never populates cache")
	lotus.texture=saved
	var source:=FileAccess.get_file_as_string("res://presentation/native/native_garden_stage.gd")
	for name: String in ["_update_occlusion","_occlusion_projection"]:
		var body:=source.split("func "+name+"(",false)[1].split("\nfunc ",false)[0]
		check(not body.contains("get_image(") and not body.contains("get_pixel(") and not body.contains("_cache_occlusion_bounds("),name+" contains no image read/pixel scan/lazy prewarm")
	rows.append({"case":"cache","textures":initial.size(),"animationFrames":frames_checked,"unknownTextureUpdates":10})
