extends RefCounted

## Render first-use bridge materials during level entry, in a separate world.
## These patches never join the garden's support, collision or rule registries.
const WorldScene = preload("res://presentation/native/native_world.tscn")
const Surface = preload("res://presentation/native/native_surface.gd")

static func prepare(stage: Node, materials: Dictionary) -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport: SubViewport = WorldScene.instantiate()
	viewport.name = "BridgeMaterialPreparation"
	viewport.size = Vector2i(64, 64)
	stage.add_child(viewport)
	var scene: Node3D = viewport.get_node("Garden")
	var camera: Camera3D = scene.get_node("Camera")
	camera.position = Vector3(0, 0, 4)
	camera.size = 3.6
	var vertices := PackedVector3Array([Vector3(-.22,-.22,0),Vector3(.22,-.22,0),Vector3(.22,.22,0),Vector3(-.22,-.22,0),Vector3(.22,.22,0),Vector3(-.22,.22,0)])
	var uvs := PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(0,0)])
	var names := ["top", "side", "ramp", "riser", "trim"]
	for index in range(names.size()):
		var original: Material = materials[names[index]]
		for growing in [false, true]:
			var material: Material = Surface.growth_material(original) if growing else original
			if growing:
				material.set_shader_parameter("growth_axis", Vector3.RIGHT)
				material.set_shader_parameter("growth_progress", .5)
				material.set_shader_parameter("growth_glow", true)
			var patch := MeshInstance3D.new()
			patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			patch.position = Vector3((index-2)*.6, .4 if growing else -.4, 0)
			patch.mesh = Surface._mesh(vertices, uvs, material, uvs if names[index] in ["side","ramp","riser"] else PackedVector2Array())
			scene.add_child(patch)
	_retire(viewport)

static func _retire(viewport: SubViewport) -> void:
	# UPDATE_ALWAYS ensures actual GPU draws even without a displayed texture.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(viewport): viewport.queue_free()
