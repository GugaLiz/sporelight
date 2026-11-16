extends Control
## A small watercolor still life inside the existing selected-level paper.
## Reuses game art; never adds another card, button, or landscape platform.
const ROOT := "res://assets/images/"
const ART := {
	"1-1":[["production/vine.png",Rect2(39,0,64,52)]],
	"1-2":[["garden-scenery/river-rock.png",Rect2(24,15,55,36)],["production/vine.png",Rect2(66,0,55,51)]],
	"1-3":[["reference-scenes/terrain-steps.png",Rect2(31,3,58,48)],["garden-scenery/trailing-vine.png",Rect2(76,7,40,43)]],
	"1-4":[["garden-scenery/flower-gate-frame.png",Rect2(43,0,56,53)]],
	"2-1":[["garden-scenery/lotus-pool.png",Rect2(25,0,90,53)]],
	"2-2":[["material-ready/icon-leaf.png",Rect2(48,3,44,45)]],
	"2-3":[["grid-world/lilypad.png",Rect2(20,21,34,28)],["grid-world/lilypad.png",Rect2(55,13,34,28)],["grid-world/lilypad.png",Rect2(90,5,34,28)]],
	"2-4":[["production/lily-open.png",Rect2(34,9,62,42)],["production/bug.png",Rect2(87,0,30,30)]],
	"3-1":[["garden-scenery/wood-lantern.png",Rect2(42,0,57,54)]],
	"3-2":[["garden-scenery/stone-lantern.png",Rect2(29,7,40,44)],["garden-scenery/stone-lantern.png",Rect2(77,7,40,44)]],
	"3-3":[["garden-scenery/dew-plant.png",Rect2(27,0,59,53)],["production/vine.png",Rect2(76,9,47,42)]],
	"3-4":[["garden-scenery/light-tower.png",Rect2(42,0,57,54)],["garden-scenery/gold-lotus.png",Rect2(88,23,30,28)]]
}
var level_id := ""
var _art: Array[Dictionary] = []

func configure(id: String) -> void:
	level_id=id;name="SelectedMechanismArt";mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(140,54);size=custom_minimum_size;clip_contents=true
	_art.clear()
	for item: Array in ART.get(id,[]):
		var texture: Texture2D=load(ROOT+str(item[0]))
		var box: Rect2=item[1]
		var image_size:=texture.get_size()
		var fitted:=(image_size*minf(box.size.x/image_size.x,box.size.y/image_size.y)).min(box.size)
		_art.append({"texture":texture,"rect":Rect2(box.position+(box.size-fitted)*.5,fitted)})
	queue_redraw()

func _draw() -> void:
	# These few accents support the watercolor objects without a schematic
	# grid, route arrows, outline panel, or new hit target.
	if level_id=="2-2":
		draw_line(Vector2(17,35),Vector2(68,23),Color("e5c77988"),2,true)
		draw_line(Vector2(68,23),Vector2(121,11),Color("e5c77988"),2,true)
	if level_id=="3-2":
		draw_circle(Vector2(42,5),3,Color("ddc57d"))
		draw_arc(Vector2(98,5),3,0,PI*1.5,16,Color("aaa3bd"),1.5,true)
	for item: Dictionary in _art:draw_texture_rect(item.texture,item.rect,false)
	if level_id=="1-4":
		draw_line(Vector2(71,16),Vector2(71,25),Color("8f7857"),1.2,true)
		draw_circle(Vector2(71,29),4,Color("dfbd70"))
		draw_line(Vector2(66,32),Vector2(76,32),Color("9d8152"),1.5,true)
	if level_id=="2-3":
		for at: Vector2 in [Vector2(38,15),Vector2(74,7),Vector2(109,1)]:
			draw_circle(at,1.5,Color("8ab4b9aa"))
