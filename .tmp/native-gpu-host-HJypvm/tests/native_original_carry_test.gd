extends SceneTree
const Carry=preload("res://presentation/native/original_carry_art.gd")
var checks:=0
var failures:Array[String]=[]
class Fixture extends Node:
	var world:Dictionary={"level":{"id":"3-1"}}
	func _texture(alias:String)->Texture2D:
		var folder:="production" if alias=="light" else "grid-world" if alias in ["lilypad","crystal"] else "garden-scenery"
		return load("res://assets/images/"+folder+"/"+alias+".png")
func _initialize()->void: call_deferred("_run")
func _check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func _run()->void:
	var stage:=Fixture.new()
	root.add_child(stage)
	var sprite:=Sprite3D.new()
	var model:=Node3D.new()
	stage.add_child(sprite)
	stage.add_child(model)
	sprite.position=Vector3(.21,.48,.08)
	model.position=Vector3(-.12,.37,.15)
	var transform:=sprite.transform
	var model_transform:=model.transform
	var rows:Array=[]
	for id:String in ["dew","bell","lamp","mirrorA","mirrorB","crystal","sunPost","moonPost"]:
		var item:Dictionary={"holder":"luvie","angle":3}
		var original:=item.duplicate(true)
		Carry.apply(stage,"luvie",sprite,model,id,item)
		_check(item==original,id+" carry leaves item and rule metadata untouched")
		_check(sprite.transform==transform and model.transform==model_transform,id+" native hand anchors stay unchanged")
		_check(not sprite.no_depth_test,id+" normal depth retained")
		_check(sprite.visible and not model.visible,id+" pouch replaces ground model")
		_check(is_equal_approx(sprite.pixel_size*Carry.RASTER,1.6/115.0),id+" character-relative source pixel scale")
		_check(sprite.get_meta("original_carry_angle")==3,id+" orientation identity retained in metadata")
		var image:=sprite.texture.get_image()
		image.save_png("res://../docs/qa-godot-native/original-elements-audit/carry-"+id+".png")
		var bounds:=image.get_used_rect()
		_check(bounds.has_area() and bounds.size.x<image.get_width()*.65,id+" small visible pouch not full canvas icon")
		var texture_id:=sprite.texture.get_instance_id()
		var builds:=Carry.rasterizations
		Carry.apply(stage,"luvie",sprite,model,id,item)
		_check(sprite.texture.get_instance_id()==texture_id and Carry.rasterizations==builds,id+" repeated carry uses cached texture")
		Carry.pose(sprite,"luvie","idle-side")
		_check(not sprite.get_meta("original_carry_cord_visible"),id+" side pose hides cord")
		Carry.pose(sprite,"luvie","idle-front")
		_check(sprite.texture.get_instance_id()==texture_id and Carry.rasterizations==builds,id+" pose swaps cached variant only")
		Carry.apply(stage,"buddy",sprite,model,id,item)
		_check(is_equal_approx(sprite.pixel_size*Carry.RASTER,1.6/115.0*.66),id+" buddy retains original .66 ratio")
		_check(sprite.get_meta("original_carry_cord_visible"),id+" buddy retains cord")
		Carry.pose(sprite,"luvie","walk-1",true)
		_check(not sprite.get_meta("original_carry_cord_visible"),id+" rolling torso hides cord")
		rows.append({"item":id,"texturePixels":[image.get_width(),image.get_height()],"visibleBounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"thumbnailPixels":sprite.get_meta("original_carry_source_pixels"),"pouchScale":sprite.get_meta("original_carry_pouch_scale")})
	stage.world.level.id="cloud-1"
	var before_texture:=sprite.texture
	Carry.apply(stage,"luvie",sprite,model,"cloudSeed",{})
	_check(sprite.texture==before_texture,"cloud seed remains under its dedicated renderer")
	var file:=FileAccess.open("res://../docs/qa-godot-native/original-elements-audit/native-carry-headless.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"CPU-only cached original pouch art/scale/anchor checks; no GPU acceptance","rasterizations":Carry.rasterizations,"rows":rows},"  ")+"\n")
	print(JSON.stringify({"checks":checks,"failures":failures.size(),"rasterizations":Carry.rasterizations}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
