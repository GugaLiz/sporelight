extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Definitions = preload("res://elements/actor_definitions.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func vector(value: Vector3, expected: Array) -> bool:
	return value.distance_to(Vector3(expected[0],expected[1],expected[2])) < .000001
func _run() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/actor_element_baseline.json"))
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_world(World.new("1-1"))
	await process_frame
	stage.set_paused(true)
	for who: String in baseline:
		var body: CharacterBody3D = stage.get_actor_body(who)
		var original: Dictionary = baseline[who]
		var shape: CapsuleShape3D = body.get_node("Collision").shape
		var art: AnimatedSprite3D = body.get_node("Visual/Art")
		check(is_equal_approx(shape.radius,original.radius) and is_equal_approx(shape.height,original.height),who+" collider unchanged")
		check(vector(body.get_node("Collision").position,original.collisionPosition),who+" collision anchor")
		check(vector(body.get_node("Visual/Carry").position,original.carry),who+" carry anchor")
		check(vector(body.get_node("Visual/CarryModel").position,original.carryModel),who+" carry model anchor")
		check(is_equal_approx(art.pixel_size,original.pixelSize) and art.offset.distance_to(Vector2(original.offset[0],original.offset[1]))<.000001,who+" baseline scale and foot")
		check(art.sprite_frames.get_animation_names().size()==original.clips.size(),who+" complete clip inventory")
		for clip: String in original.clips:
			var expected: Dictionary = original.clips[clip]
			check(art.sprite_frames.has_animation(clip),who+" "+clip)
			check(is_equal_approx(art.sprite_frames.get_animation_speed(clip),expected.fps) and art.sprite_frames.get_animation_loop(clip)==expected.loop,who+" clip timing "+clip)
			var paths: Array = []
			for i: int in art.sprite_frames.get_frame_count(clip):
				var texture := art.sprite_frames.get_frame_texture(clip,i)
				paths.append("procedural_buddy" if texture is ViewportTexture else texture.resource_path)
			check(paths==expected.frames,who+" exact original frames "+clip)
	var world_snapshot: Dictionary = stage.world.snapshot()
	var body := stage.get_actor_body("buddy")
	var body_id := body.get_instance_id()
	var physical := body.transform
	var collision: Shape3D = body.get_node("Collision").shape
	var variant := Definitions.skin("luvie.original").duplicate(true)
	variant.allowed_actors = ["buddy"]
	variant.carry_scale = .66
	check(Definitions.register_skin("test.companion",variant).ok,"register companion cosmetic")
	check(stage.set_actor_skin("buddy","test.companion").ok,"swap companion renderer")
	check(body.get_instance_id()==body_id and body.transform==physical and body.get_node("Collision").shape==collision,"cosmetic swap retains exact body/collider/transform")
	check(stage.world.snapshot()==world_snapshot,"cosmetic swap cannot mutate rule state")
	stage.update_actor_visual("buddy",Vector3(1,0,0),"right")
	var art: AnimatedSprite3D = body.get_node("Visual/Art")
	check(art.animation=="walk_right", "replacement companion uses directional walk")
	art.set_frame_and_progress(4,.3)
	check(stage.set_actor_skin("buddy","test.companion").ok and art.frame==4 and absf(art.frame_progress-.3)<.00001,"refresh preserves walk phase")
	stage.update_actor_visual("buddy",Vector3.ZERO,"front","sow")
	art.set_frame_and_progress(4,1)
	art.pause()
	check(stage.set_actor_skin("buddy","test.companion").ok and art.frame==4 and art.frame_progress==1 and not art.is_playing(),"refresh preserves finished action and pause")
	check(not stage.set_actor_skin("luvie","test.companion").ok,"identity compatibility enforced")
	check(not stage.set_actor_skin("buddy","missing").ok and stage.actor_skin_id("buddy")=="test.companion","unknown replacement atomic rejection")
	var bad := variant.duplicate(true)
	bad.standing.foot = [1]
	check(not Definitions.register_skin("test.bad",bad).ok,"malformed foot rejected")
	bad = variant.duplicate(true)
	bad.clips.idle_front.frames = ["missing-frame"]
	check(Definitions.register_skin("test.missing",bad).ok and not stage.set_actor_skin("buddy","test.missing").ok and stage.actor_skin_id("buddy")=="test.companion","unresolved art rejected before replacing visual")
	check(stage.set_actor_skin("buddy","buddy.original").ok,"restore original companion")
	for chapter: int in range(1,4):
		for level: int in range(1,5):
			var id := "%d-%d" % [chapter,level]
			stage.set_world(World.new(id))
			var snapshot: Dictionary = stage.world.snapshot()
			stage.refresh_actor_visuals()
			check(stage.world.snapshot()==snapshot and stage.actor_skin_id("luvie")=="luvie.original" and stage.actor_skin_id("buddy")=="buddy.original",id+" common actors and unchanged rules")
	check(Definitions.has_capability("buddy","small_passage") and not Definitions.has_capability("luvie","small_passage"),"documented existing companion capability")
	check(not Definitions.visual_motion().jump_changes_support,"jump remains cosmetic emote")
	check(is_equal_approx(Definitions.speed("luvie"),3.25) and is_equal_approx(Definitions.speed("buddy",true),3.45) and is_equal_approx(Definitions.speed("luvie",false,true),3.7375),"original locomotion speeds")
	print(JSON.stringify({"suite":"native-actor-elements","checks":checks,"passed":failures.is_empty(),"failures":failures}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
