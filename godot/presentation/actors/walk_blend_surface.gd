class_name GardenWalkBlendSurface
extends SubViewport

const BLEND_SHADER = preload("res://presentation/actors/walk_blend.gdshader")
var _sprite: Sprite2D
var _blend: ShaderMaterial

func _init() -> void:
	size = Vector2i(256, 256)
	transparent_bg = true
	disable_3d = true
	render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_blend = ShaderMaterial.new()
	_blend.shader = BLEND_SHADER
	_sprite.material = _blend
	add_child(_sprite)

func blend(from: Texture2D, to: Texture2D, weight: float) -> void:
	_sprite.texture = from
	_blend.set_shader_parameter("next_pose", to)
	_blend.set_shader_parameter("pose_weight", clampf(weight, 0, 1))
	render_target_update_mode = SubViewport.UPDATE_ALWAYS

func deactivate() -> void:
	render_target_update_mode = SubViewport.UPDATE_DISABLED
