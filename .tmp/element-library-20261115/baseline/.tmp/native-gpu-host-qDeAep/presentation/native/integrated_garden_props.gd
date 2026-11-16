class_name IntegratedGardenProps
extends RefCounted

static func planter(stage: Node, parent: Node3D, width := 1.16, shift := Vector3.ZERO) -> void:
	var alias := "bloom" if bool(stage.world.state.completed) else "flower"
	var plant: Sprite3D = stage._sprite(parent, alias, width, Vector3(0.27, 0.012, 0.34) * (width / 1.16) + shift, true)
	plant.texture = stage._texture(alias)
	plant.pixel_size = width / plant.texture.get_width()
	# The painted front foot is at the near corner of its ground footprint.
	# Move that anchor in X/Z rather than pushing a vertical sprite into soil.
	plant.offset = Vector2(0, 102)
	stage._integrate_prop(plant, 0)
	plant.set_meta("core_planter", true)
	plant.set_meta("canvas_world_width", width)
	plant.set_meta("ground_footprint_span", Vector2(0.80,0.80)*(width/1.16))
	plant.set_meta("ground_footprint_center", shift+Vector3(0,0,.07))
	stage._contact_patch(parent, Vector2(0.80, 0.80) * (width / 1.16), Vector3(0, 0.008, 0.07) + shift, 0.23, true)

