extends SceneTree
const Paint=preload("res://presentation/native/chapter_surface_materials.gd")
const World=preload("res://core/garden_world.gd")
const Stage=preload("res://presentation/native/native_garden_stage.gd")
var checks:=0
var failures:Array[String]=[]
func _check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:
	call_deferred("_run")
func _run()->void:
	# Concrete source examples distinguish all three paints and protect marks.
	var examples:={"1-3":{"f:-5:-1":"paving-valley","f:-4:-1":"paving-grass","f:0:-5":"paving-moss"},"1-4":{"f:-4:-1":"paving-grass","f:-2:-1":"paving-moss","f:-4:0":"paving-valley"},"2-2":{"f:-1:-1":"paving-moss","f:0:-1":"paving-pond","f:2:-1":"paving-grass"},"3-1":{"f:-4:-1":"paving-valley","f:-2:-1":"paving-moss","f:-3:1":"paving-grass"}}
	var stage:=Stage.new();root.add_child(stage)
	for id:String in examples:
		var world:=World.new(id);var before:=world.snapshot()
		stage.set_world(world)
		for tile_id:String in examples[id]:
			var tile:Dictionary=world.point_for(tile_id)
			var expected:String=examples[id][tile_id]
			_check(Paint.paving_for(world.level,tile)==expected,id+" preserves source example "+tile_id)
			var surface:Node3D=stage._surfaces[tile_id]
			var material:Material=surface._top.get_active_material(0)
			_check(material is StandardMaterial3D,id+" source-painted top is a real textured surface "+tile_id)
			if material is StandardMaterial3D:
				_check(material.albedo_texture==stage._texture(expected),id+" actual native top uses original paint "+tile_id)
		var built:int=stage._build_count
		stage.refresh_world(world,true)
		_check(stage._build_count==built,id+" same-state refresh reuses geometry")
		_check(world.snapshot()==before,id+" paint cannot mutate puzzle progress")
	stage.set_world(World.new("1-1"))
	_check(stage._terrain_profile!=null,"approved first garden retains own terrain profile")
	stage.set_world(World.new("1-2"))
	_check(stage._terrain_profile!=null,"second garden retains its own material and stair mapping")
	print(JSON.stringify({"suite":"native-chapter-paving","checks":checks,"passed":failures.is_empty(),"failures":failures,"scope":"concrete source examples, actual assigned native textures, cache reuse and first-two profile protection; GPU separate"}))
	stage.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
