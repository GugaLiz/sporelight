class_name GardenActorVisualFactory
extends RefCounted
const Definitions = preload("res://elements/actor_definitions.gd")
const ActorScene = preload("res://presentation/native/native_actor.tscn")
const Pose = preload("res://presentation/native/native_actor_pose.gd")

static func vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func create_body(who: String) -> CharacterBody3D:
	var definition := Definitions.actor(who)
	assert(not definition.is_empty(), "Unknown actor identity")
	var body := ActorScene.instantiate() as CharacterBody3D
	body.name = str(definition.name)
	body.set_meta("actor_id",who)
	var profile: Dictionary = definition.body
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(profile.radius)
	capsule.height = float(profile.height)
	var collision: CollisionShape3D = body.get_node("Collision")
	collision.shape = capsule
	collision.position = vector3(profile.collision_center)
	body.collision_layer = int(profile.layer)
	body.collision_mask = int(profile.mask)
	body.floor_max_angle = float(profile.floor_max_angle)
	body.floor_snap_length = float(profile.floor_snap_length)
	body.platform_floor_layers = int(profile.platform_floor_layers)
	body.get_node("Visual/Carry").position = vector3(profile.carry_position)
	body.get_node("Visual/CarryModel").position = vector3(profile.carry_model_position)
	var shadow: MeshInstance3D = body.get_node("Shadow")
	var mesh := shadow.mesh.duplicate() as CylinderMesh
	mesh.top_radius = float(profile.shadow_radius)
	mesh.bottom_radius = float(profile.shadow_radius)
	mesh.height = float(profile.shadow_height)
	shadow.mesh = mesh
	shadow.position = vector3(profile.shadow_position)
	return body

static func frames(stage: Node, skin_id: String) -> Dictionary:
	var skin := Definitions.skin(skin_id)
	if skin.is_empty(): return {"ok":false,"error":"unknown_skin"}
	var valid := Definitions.validate_skin(skin)
	if not valid.ok: return valid
	var result := SpriteFrames.new()
	result.remove_animation("default")
	for id: String in skin.clips:
		var clip: Dictionary = skin.clips[id]
		result.add_animation(id)
		result.set_animation_speed(id,float(clip.fps))
		result.set_animation_loop(id,bool(clip.loop))
		for alias: String in clip.frames:
			var texture: Texture2D = stage._buddy_surface.get_texture() if alias=="@procedural_buddy" else stage._texture(alias)
			if texture==null: return {"ok":false,"error":"missing_actor_frame:"+alias}
			result.add_frame(id,texture)
	return {"ok":true,"frames":result}

static func apply_skin(body: CharacterBody3D, skin_id: String, frames: SpriteFrames) -> void:
	var skin := Definitions.skin(skin_id)
	var art: AnimatedSprite3D = body.get_node("Visual/Art")
	var previous := str(art.animation)
	var phase := 0.0
	if art.sprite_frames!=null and art.sprite_frames.has_animation(previous):
		phase = (art.frame+art.frame_progress)/float(art.sprite_frames.get_frame_count(previous))
	var playing := art.is_playing()
	art.set_meta("actor_skin_id",skin_id)
	art.set_meta("actor_skin_definition",skin)
	art.sprite_frames = frames
	var clip := previous if frames.has_animation(previous) else "idle_front"
	art.play(clip)
	var frame_position := phase * frames.get_frame_count(clip)
	var frame_index := mini(int(frame_position),frames.get_frame_count(clip)-1)
	art.set_frame_and_progress(frame_index,clampf(frame_position-frame_index,0,1))
	if not playing and not previous.is_empty(): art.pause()
	Pose.bind_sprite(art)

static func create_animations(player: AnimationPlayer) -> void:
	var profile := Definitions.visual_motion()
	var library := AnimationLibrary.new()
	var breathe := Animation.new()
	breathe.length = float(profile.breath_duration)
	breathe.loop_mode = Animation.LOOP_LINEAR
	var track := breathe.add_track(Animation.TYPE_VALUE)
	breathe.track_set_path(track,NodePath(".:scale"))
	breathe.track_insert_key(track,0,Vector3.ONE)
	breathe.track_insert_key(track,breathe.length*.5,vector3(profile.breath_peak))
	breathe.track_insert_key(track,breathe.length,Vector3.ONE)
	library.add_animation("breathe",breathe)
	for soft: bool in [false,true]:
		var jump := Animation.new()
		jump.length = float(profile.jump_duration)
		var jump_track := jump.add_track(Animation.TYPE_VALUE)
		jump.track_set_path(jump_track,NodePath("Art:position"))
		jump.track_set_interpolation_type(jump_track,Animation.INTERPOLATION_CUBIC)
		jump.track_insert_key(jump_track,0,Vector3.ZERO)
		jump.track_insert_key(jump_track,float(profile.jump_peak_time),Vector3(0,float(profile.jump_soft_height if soft else profile.jump_height),0))
		jump.track_insert_key(jump_track,jump.length,Vector3.ZERO)
		library.add_animation("jump_soft" if soft else "jump",jump)
	player.add_animation_library("",library)
