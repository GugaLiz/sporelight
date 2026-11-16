extends SceneTree
## Captured before actor extraction. Measures public scene output, not definitions.
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
func _initialize()->void: _run.call_deferred()
func _vec(value:Vector3)->Array:return [value.x,value.y,value.z]
func _run()->void:
	if FileAccess.file_exists("res://tests/fixtures/actor_element_baseline.json"):
		print("Frozen pre-extraction baseline already exists; recorder will not overwrite it."); quit(0); return
	if FileAccess.file_exists("res://tests/fixtures/actor_element_baseline.json"):
		print("Frozen pre-extraction baseline already exists; recorder will not overwrite it."); quit(0); return
	var stage:=Stage.new();root.add_child(stage);stage.set_world(World.new("1-1"));await process_frame
	stage.set_paused(true)
	var result:Dictionary={}
	for who:String in ["luvie","buddy"]:
		var body:CharacterBody3D=stage.get_actor_body(who)
		var shape:CapsuleShape3D=body.get_node("Collision").shape
		var art:AnimatedSprite3D=body.get_node("Visual/Art")
		var clips:Dictionary={}
		for name:StringName in art.sprite_frames.get_animation_names():
			var frames:Array=[]
			for frame:int in art.sprite_frames.get_frame_count(name):
				var texture:Texture2D=art.sprite_frames.get_frame_texture(name,frame)
				frames.append("procedural_buddy" if texture is ViewportTexture else texture.resource_path)
			clips[str(name)]={"frames":frames,"fps":art.sprite_frames.get_animation_speed(name),"loop":art.sprite_frames.get_animation_loop(name)}
		result[who]={"radius":shape.radius,"height":shape.height,"collisionPosition":_vec(body.get_node("Collision").position),"carry":_vec(body.get_node("Visual/Carry").position),"carryModel":_vec(body.get_node("Visual/CarryModel").position),"pixelSize":art.pixel_size,"offset":[art.offset.x,art.offset.y],"clips":clips}
	FileAccess.open("res://tests/fixtures/actor_element_baseline.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  ")+"\n")
	print(JSON.stringify({"passed":true,"actors":result.size(),"baseline":"pre-extraction actual scene"}))
	quit(0)
