extends Control
## All plant states share one stone well and one planted root. The source
## flower's old rear platform is excluded by a silhouette in its measured 256px canvas.
const Assets := preload("res://elements/element_assets.gd")
const ROOT := "res://assets/images/"
const PIT_CENTRE := Vector2(128, 195)
const PETAL_SEAT := Vector2(128, 159)
var completed := false
var unlocked := false
var selected := false
var clock := 0.0
var low_motion := false
var particles := true
var paused := false
var _pending := 0.0
var _well: Texture2D
var _plant: Texture2D
var _actor: Texture2D
var _fly: Texture2D

func configure(entry: Dictionary, _chapter: String, chosen: bool, settings: Dictionary, time: float, stopped: bool) -> void:
	name = "RegisteredMapNodeArt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(140, 140)
	completed = bool(entry.completed)
	unlocked = bool(entry.unlocked)
	selected = chosen and unlocked
	clock = time
	paused = stopped
	apply_settings(settings)
	_well = Assets.texture_for_source(ROOT + "reference-scenes/plant-dormant.png")
	var art := "bloom" if completed else "bud"
	_plant = load(ROOT + "menu-node-plants-20261118/%s.png" % art) if unlocked else null
	_actor = load(ROOT + "menu-map-refine-20261118/map-sitting.png") if selected and completed else Assets.texture_for_source(ROOT + "character-refined/idle-front.png") if selected else null
	_fly = Assets.texture_for_source(ROOT+"menu-fx-redrawn/firefly.png")
	_refresh_processing()
	queue_redraw()

func apply_settings(settings: Dictionary) -> void:
	low_motion = bool(settings.get("lowMotion", false))
	particles = bool(settings.get("particles", true))
	_refresh_processing()
	queue_redraw()

func set_paused(value: bool) -> void:
	paused = value
	_refresh_processing()

func _refresh_processing() -> void:
	set_process(selected and completed and not low_motion and not paused)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	clock += minf(delta, .1)
	_pending += delta
	if _pending >= .05:
		_pending = 0
		queue_redraw()

func _draw() -> void:
	if _well == null: return
	var unit := 140.0 / 256.0
	if selected:
		draw_set_transform(PIT_CENTRE * unit + Vector2(0,3), 0, Vector2(1,.42))
		draw_circle(Vector2.ZERO, 62, Color("ffe7a326"))
		draw_arc(Vector2.ZERO, 56, 0, TAU, 64, Color("ffe8a9c4"), 2, true)
		draw_set_transform(Vector2.ZERO)
	draw_texture_rect(_well, Rect2(Vector2.ZERO, size), false)
	if not unlocked:
		var lock_at := Vector2(70,53)
		draw_circle(lock_at, 16, Color("86836fe8"))
		draw_arc(lock_at + Vector2(0,-3), 4, PI, TAU, 16, Color("fff4df"), 2, true)
		draw_rect(Rect2(lock_at + Vector2(-5,-3),Vector2(10,11)), Color("fff4df"))
		draw_circle(lock_at + Vector2(0,2), 1.4, Color("86836f"))
	if _plant != null:
		# Whole generated alpha layers have no rear platform to crop. Register
		# the neck of the root inside the soil, behind the actual curved lip.
		var plant_extent := Vector2.ONE * (82 if completed else 60)
		var plant_root := Vector2(.49,.765)
		# Only the bare root below the soil is excluded; every petal and leaf
		# remains inside the complete alpha layer, with no silhouette mask.
		draw_texture_rect_region(_plant,Rect2(PIT_CENTRE*unit-plant_root*plant_extent,plant_extent*Vector2(1,plant_root.y)),Rect2(Vector2.ZERO,_plant.get_size()*Vector2(1,plant_root.y)))
		# Follow the curved inner lip rather than a horizontal crop through the
		# leaves. The complete stones have already been drawn underneath.
		var front := PackedVector2Array([Vector2(28,178),Vector2(78,181),Vector2(90,192),Vector2(108,200),Vector2(128,203),Vector2(148,199),Vector2(161,190),Vector2(170,181),Vector2(230,178),Vector2(230,256),Vector2(28,256)])
		var rim := PackedVector2Array()
		var rim_uv := PackedVector2Array()
		for point in front:
			rim.append(point*unit)
			rim_uv.append(point/_well.get_size())
		draw_polygon(rim,PackedColorArray([Color.WHITE]),rim_uv,_well)
	if _actor == null: return
	var t := 0.0 if low_motion else clock
	if completed:
		# Measured seated hips on the full generated 1280px alpha canvas.
		# Register the hips to the flower petal, never to the well rim.
		var seat := PETAL_SEAT * unit + Vector2(0, sin(t * 1.4) * .45)
		var extent := Vector2(110, 110)
		draw_texture_rect(_actor, Rect2(seat - Vector2(.49, .75) * extent, extent), false)
		if particles:
			_firefly(seat + Vector2(36 + sin(t * .9) * 6, -28 + cos(t * 1.1) * 6), t)
	else:
		# The front sprite's boot soles sit at 95% of its alpha canvas.
		# Stand beside the well on the same ground ellipse, not above its rim.
		draw_texture_rect(_actor, Rect2(-9, 37, 78, 78), false)

func _firefly(at: Vector2, time: float) -> void:
	if _fly == null: return
	# Same gold-bodied, translucent-winged insect as the cover. Keep the
	# body steady; compress the wing half around its root for a small flutter.
	var root := Vector2(.51,.50)
	var flutter := .78+.22*absf(sin(time*19))
	var extent := Vector2(38,38)
	draw_set_transform(at, sin(time*.9)*.10)
	var wing_source := Rect2(Vector2.ZERO,Vector2(_fly.get_width()*.51,_fly.get_height()))
	var body_source := Rect2(wing_source.size.x,0,_fly.get_width()-wing_source.size.x,_fly.get_height())
	draw_texture_rect_region(_fly,Rect2(-root*extent+Vector2(extent.x*.51*(1-flutter),0),Vector2(extent.x*.51*flutter,extent.y)),wing_source)
	draw_texture_rect_region(_fly,Rect2(Vector2(0,-root.y*extent.y),Vector2(extent.x*.49,extent.y)),body_source)
	draw_set_transform(Vector2.ZERO)
