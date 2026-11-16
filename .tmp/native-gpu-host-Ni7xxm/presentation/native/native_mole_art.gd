extends SubViewport
## The original illustrated NPC is cached once as an asset texture. The final
## sprite uses native world depth; no per-frame scene painter is involved.
class MoleCanvas:
	extends Node2D
	const Paint = preload("res://presentation/world/garden_paint.gd")
	const Art = preload("res://presentation/actors/creature_art.gd")
	func _draw() -> void:
		var paint := Paint.new(self, {})
		Art.mole(paint, Vector2(128, 222), 150, 0, {"low_motion": true})

func _init() -> void:
	name = "CachedOriginalMoleArt"
	size = Vector2i(256, 256)
	transparent_bg = true
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(MoleCanvas.new())
