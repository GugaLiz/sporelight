class_name IntegratedGardenProps
extends RefCounted
const Props = preload("res://elements/prop_definitions.gd")

static func planter(stage: Node, parent: Node3D, width := 1.16, shift := Vector3.ZERO) -> void:
	var alias := Props.planter_alias(bool(stage.world.state.completed))
	var plant: Sprite3D = stage._sprite(parent, alias, width, Props.planter_anchor(width) + shift, true)
	plant.texture = stage._texture(alias)
	plant.pixel_size = width / plant.texture.get_width()
	# The painted front foot is at the near corner of its ground footprint.
	# Move that anchor in X/Z rather than pushing a vertical sprite into soil.
	plant.offset = Props.vector2(Props.planter_spec().painted_foot)
	stage._integrate_prop(plant, 0)
	plant.set_meta("core_planter", true)
	plant.set_meta("canvas_world_width", width)
	plant.set_meta("ground_footprint_span", Props.planter_span(width))
	plant.set_meta("ground_footprint_center", shift+Props.planter_center())
	stage._contact_patch(parent, Props.planter_span(width), Props.planter_center() + Vector3(0, float(Props.planter_spec().contact_height), 0) + shift, float(Props.planter_spec().contact_opacity), true)

