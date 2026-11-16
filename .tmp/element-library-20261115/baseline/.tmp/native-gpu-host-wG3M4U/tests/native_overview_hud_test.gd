extends SceneTree
## Exercise real HUD layout and the application's camera-area selection.
const HUD = preload("res://ui/garden_hud.gd")
var checks := 0
var failures: Array[String] = []

class Harness:
	extends "res://application/main.gd"
	func _ready() -> void: pass

class ViewStub:
	extends Node2D
	var overview := false
	var area := Rect2()
	func set_layout(value: Rect2) -> void: area = value

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for unused in range(6): await process_frame

func clear_of_panels(hud: Control, area: Rect2, label: String) -> void:
	check(area.size.x > 0 and area.size.y > 0, label + " has useful area")
	for region: Dictionary in hud.layout_regions():
		var r: Array = region.rect
		check(not area.intersects(Rect2(r[0], r[1], r[2], r[3]).grow(11)), label + " clears " + str(region.name))

func run() -> void:
	var app := Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	app.set_physics_process(false)
	app.safe_camera = true
	app.view = ViewStub.new()
	app.add_child(app.view)
	app.hud = HUD.new()
	app.add_child(app.hud)
	app.hud.set_process(false)
	app.hud.layout_changed.connect(app._on_hud_chrome_changed)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = dimensions
		app.hud.close_context_choices()
		app.hud.set_message("根须已长好，可以试着走上去了。")
		await settle()
		var normal: Rect2 = app.hud.safe_world_rect()
		app.view.overview = false
		app.hud.set_overview(false)
		check(app.view.area == normal, str(dimensions) + " normal uses reference area")
		# This is also the automatic overview entry sequence used by hints.
		app.view.overview = true
		app.hud.set_overview(true)
		check(app.view.area == app.hud.overview_world_rect(), "programmatic overview updates without another command")
		check(app.hud._message_panel.visible, "overview retains feedback")
		clear_of_panels(app.hud, app.view.area, str(dimensions) + " message")
		app.hud.show_hint_content("先观察花床与根台之间的缺口，再选择生长方向。", 0)
		await settle()
		check(app.hud.is_hint_visible(), "overview retains requested hint")
		check(app.hud.safe_world_rect() == normal, "hint cannot change normal camera area")
		clear_of_panels(app.hud, app.view.area, str(dimensions) + " hint")
		app.hud.show_context_choices([{"id": "grow:root:right", "label": "向东生长"}, {"id": "grow:root:down", "label": "向南生长"}])
		await settle()
		check(app.hud.is_context_open(), "overview keeps local choices usable")
		clear_of_panels(app.hud, app.view.area, str(dimensions) + " context")
		app.hud.close_context_choices()
		app.hud.set_message("走近花床。")
		root.size = dimensions + Vector2i(32, 24)
		await settle()
		check(app.view.area == app.hud.overview_world_rect(), "resize refreshes overview area")
		clear_of_panels(app.hud, app.view.area, str(dimensions) + " resized")
		app.hud._process(6.0)
		check(not app.hud._message_panel.visible, "expired feedback releases overview space")
		check(app.view.area == app.hud.overview_world_rect(), "expiry updates overview area immediately")
		app.view.overview = false
		app.hud.set_overview(false)
		check(app.view.area == app.hud.safe_world_rect(), "overview exit restores normal area")
	app.queue_free()
	await process_frame
	print(JSON.stringify({"suite": "native-overview-hud", "checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
