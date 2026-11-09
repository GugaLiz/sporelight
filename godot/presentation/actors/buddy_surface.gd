class_name GardenBuddySurface
extends SubViewport

## One stable texture restores the authored Canvas composition inside the
## buddy, while the final sprite still participates in native world depth.
const TEXTURE_SIZE := Vector2i(128, 128)
const ART_SIZE := 92.0
const FOOT_ANCHOR := Vector2(64.0, 112.0)
const STANDING_LIFT := 5.0
## Original 89x99 ball, width40, rotating about (0,-18): its solid source
## pixels extend at most 14.73px below the draw anchor at this 2x art size.
const ROLLING_LIFT := 15.0

class BuddyCanvas:
	extends Node2D
	const Paint = preload("res://presentation/world/garden_paint.gd")
	const Creatures = preload("res://presentation/actors/creature_art.gd")
	var images: Dictionary = {}
	var visual_time := 0.0
	var look: Dictionary = {}
	var art_position := Vector2(64.0, 107.0)
	func _draw() -> void:
		var paint := Paint.new(self, images)
		Creatures.buddy(paint, art_position, 92.0, visual_time, look)

var _canvas := BuddyCanvas.new()

func _init() -> void:
	name = "BuddyArtSurface"
	size = TEXTURE_SIZE
	transparent_bg = true
	disable_3d = true
	render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_canvas)

func update_pose(images: Dictionary, time: float, look: Dictionary) -> void:
	_canvas.images = images
	_canvas.visual_time = time
	_canvas.look = look.duplicate(true)
	_canvas.look["draw_shadow"] = false
	_canvas.art_position = FOOT_ANCHOR - Vector2(0.0, ROLLING_LIFT if look.get("rolling", false) else STANDING_LIFT)
	_canvas.queue_redraw()
	render_target_update_mode = SubViewport.UPDATE_ALWAYS

func deactivate() -> void:
	render_target_update_mode = SubViewport.UPDATE_DISABLED
