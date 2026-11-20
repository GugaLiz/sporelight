extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var failures: Array[String] = []
var checks := 0
var samples: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_world(World.new("1-1"))
	await process_frame
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(390, 844), Vector2i(568, 320), Vector2i(2560, 1440)]:
		stage._viewport.size = dimensions
		var top := 74 if dimensions.y < 430 else 100
		var bottom := 124 if dimensions.y < 430 else 110
		var safe := Rect2(16, top, dimensions.x - 32, dimensions.y - top - bottom)
		stage.set_layout(safe)
		stage._calculate_bounds()
		stage._fit_camera(true)
		var origin: Vector2 = stage.world_to_screen(Vector3.ZERO)
		var right: Vector2 = stage.world_to_screen(Vector3(0.70710678, 0, -0.70710678))
		var ppu := right.distance_to(origin)
		_check(stage._camera.keep_aspect == Camera3D.KEEP_HEIGHT, "orthographic lens uses a height-defined size")
		_check(absf(ppu - float(dimensions.y) / stage._camera.size) < 0.002, "actual Camera3D projection matches pixel density")
		if dimensions.x < 650 and dimensions.y > 600:
			_check(ppu >= 65.0, "portrait keeps a readable actor instead of shrinking whole level")
		if dimensions.y < 430:
			_check(ppu >= 48.0, "short landscape keeps a readable actor")
		var foot: Vector2 = stage.actor_screen_footpoint("luvie")
		_check(safe.has_point(foot), "active foot stays inside the chrome-safe game area")
		var focus: Vector3 = stage._focus
		stage.set_layout(safe)
		_check(stage._focus == focus, "repeated HUD refresh does not snap the follow camera")
		var stats: Dictionary = stage.render_statistics()
		stage.overview = not stage.overview
		stage._fit_camera(true)
		_check(stage.render_statistics().meshRebuilds == stats.meshRebuilds, "overview only changes the native camera")
		stage.overview = false
		stage._fit_camera(true)
		samples.append({"size": dimensions, "cameraSize": stage._camera.size, "ppuActual": ppu, "actorFoot": foot})
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-camera-render-contract","passed":failures.is_empty(),"checks":checks,"samples":samples,"failures":failures,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
