extends SceneTree
## This compares the new buddy composition surface with the original 2D art.
## It does not judge taste, comfort, actor spacing or full-scene native depth.

const Creatures := preload("res://presentation/actors/creature_art.gd")
const ErrorLogger := preload("res://tests/visual_error_logger.gd")
const SURFACE_PATH := "res://presentation/actors/buddy_surface.gd"
const SIZE := Vector2i(128, 128)
const FOOT := Vector2(64.0, 112.0)
const STANDING_LIFT := 5.0
const ROLLING_LIFT := 15.0
const ART_SIZE := 92.0
const CHANNEL_ERROR := 2.0 / 255.0

class BodyPaint:
	extends GardenPaint
	func _init(canvas: Variant, textures: Dictionary = {}) -> void:
		super(canvas, textures)
	func shadow(_x: float, _y: float, _rx: float, _ry: float) -> void:
		# The world owns its ground shadow. The independent 2D reference excludes
		# that one original command, without reading the new surface's painter.
		pass

class ReferenceInk:
	extends Node2D
	var textures: Dictionary = {}
	var pose_time := 0.0
	var look: Dictionary = {}
	func _draw() -> void:
		var lift := ROLLING_LIFT if look.get("rolling", false) else STANDING_LIFT
		var paint := BodyPaint.new(self, textures)
		Creatures.buddy(paint, FOOT - Vector2(0, lift), ART_SIZE, pose_time, look)

var _output := ""
var _checks := 0
var _pixel_checks := 0
var _failures: Array[String] = []
var _cases: Array = []
var _asset_hashes: Array = []
var _images: Dictionary = {}
var _surface: SubViewport
var _reference: SubViewport
var _ink: Node2D
var _logger := ErrorLogger.new()
var _finished := false
var _gpu_verified := false
var _low_motion_reference: Image

func _initialize() -> void:
	OS.add_logger(_logger)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	create_timer(90).timeout.connect(func() -> void:
		if not _finished:
			push_error("Actor appearance comparison timed out")
			quit(1))
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 60:
		_failures.append(label)

func _run() -> void:
	_read_assets()
	_check(FileAccess.file_exists(SURFACE_PATH), "the buddy composition surface exists")
	if not FileAccess.file_exists(SURFACE_PATH):
		_finish()
		return
	var surface_script: Script = load(SURFACE_PATH)
	_surface = surface_script.new()
	root.add_child(_surface)
	_reference = SubViewport.new()
	_reference.size = SIZE
	_reference.transparent_bg = true
	_reference.disable_3d = true
	_reference.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_reference.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_reference)
	_ink = ReferenceInk.new()
	_ink.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ink.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_reference.add_child(_ink)
	await process_frame
	_surface_contract()
	var texture: Texture2D = _surface.get_texture()
	for specification: Dictionary in _specifications():
		var look: Dictionary = specification.look.duplicate(true)
		var unchanged := look.duplicate(true)
		_surface.update_pose(_images, float(specification.time), look)
		_check(look == unchanged, specification.name + " does not mutate the supplied look")
		_check(_surface.get_texture() == texture, specification.name + " reuses the same viewport texture instance")
		_check(_surface.render_target_update_mode != SubViewport.UPDATE_DISABLED, specification.name + " enables drawing after a pose update")
		_ink.textures = _images
		_ink.pose_time = float(specification.time)
		_ink.look = specification.look.duplicate(true)
		_ink.queue_redraw()
		await process_frame
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_compare_pose(specification)
		else:
			_cases.append({"name": specification.name, "time": specification.time, "look": specification.look,
				"pixelsSkipped": true, "reason": "headless display cannot validate 2D composition, alpha or artwork pixels"})
	_surface.deactivate()
	_check(_surface.render_target_update_mode == SubViewport.UPDATE_DISABLED, "deactivate suspends the private composition viewport")
	_check(_surface.get_texture() == texture, "deactivate preserves the texture instance used by world materials")
	_gpu_verified = DisplayServer.get_name() != "headless" and _pixel_checks == _specifications().size() and _failures.is_empty()
	_surface.queue_free()
	_reference.queue_free()
	await process_frame
	_finish()

func _surface_contract() -> void:
	_check(_surface.size == SIZE, "buddy texture is 128 by 128 physical pixels")
	_check(_surface.size_2d_override == Vector2i.ZERO, "the declared 128-pixel draw space has no hidden 2D size override")
	_check(_surface.transparent_bg, "buddy composition retains an alpha background")
	_check(_surface.disable_3d, "buddy composition uses the original ordered 2D drawing path")
	_check(_surface.render_target_clear_mode == SubViewport.CLEAR_MODE_ALWAYS, "each composition clears the previous pose")
	_check(_surface.has_method("update_pose") and _surface.has_method("deactivate"), "the composition surface exposes its small reusable lifecycle")
	_check(_surface.get_texture().get_width() == 128 and _surface.get_texture().get_height() == 128, "the world receives a stable 128-pixel texture for 64-design-pixel rendering")

func _read_assets() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/visual-assets.json"))
	var repository := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	for entry: Dictionary in manifest.entries:
		if str(entry.get("group", "")) != "character":
			continue
		var resource := str(entry.resource)
		var source := repository.path_join(str(entry.source))
		var actual := FileAccess.get_sha256(resource)
		var original := FileAccess.get_sha256(source)
		_check(not actual.is_empty() and actual == str(entry.sha256), str(entry.id) + " keeps the manifest's original PNG bytes")
		_check(actual == original, str(entry.id) + " keeps the original game asset bytes")
		_asset_hashes.append({"id": entry.id, "expected": entry.sha256, "actual": actual, "original": original})
		if str(entry.id) == "ball":
			_images["ball"] = load(resource)
	_check(_asset_hashes.size() >= 40, "the asset check covers the hero's idle, action, directional walk and jump PNGs")
	_check(_images.get("ball") is Texture2D, "the original buddy ball texture loads")

func _specifications() -> Array:
	return [
		{"name": "idle-zero", "time": 0.0, "look": {}},
		{"name": "idle-breath", "time": 1200.0, "look": {}},
		{"name": "idle-blink", "time": 5100.0, "look": {}},
		{"name": "walk-55", "time": 55.0, "look": {"moving": true}},
		{"name": "walk-165", "time": 165.0, "look": {"moving": true}},
		{"name": "waiting", "time": 1200.0, "look": {"waiting": true}},
		{"name": "low-motion-zero", "time": 0.0, "look": {"moving": true, "low_motion": true}},
		{"name": "low-motion-later", "time": 4000.0, "look": {"moving": true, "low_motion": true}},
		{"name": "happy", "time": 1200.0, "look": {"happy": true}},
		{"name": "roll-zero", "time": 0.0, "look": {"moving": true, "rolling": true}},
		{"name": "roll-turn", "time": 330.0, "look": {"moving": true, "rolling": true}},
		{"name": "roll-low-motion", "time": 4000.0, "look": {"moving": true, "rolling": true, "low_motion": true}}
	]

func _compare_pose(specification: Dictionary) -> void:
	var actual: Image = _surface.get_texture().get_image()
	var reference: Image = _reference.get_texture().get_image()
	_check(actual != null and reference != null and not actual.is_empty() and not reference.is_empty(), specification.name + " obtains both actually rendered images")
	if actual == null or reference == null or actual.is_empty() or reference.is_empty():
		return
	_check(actual.get_size() == SIZE and reference.get_size() == SIZE, specification.name + " compares the same fixed-size art canvas")
	if actual.get_size() != SIZE or reference.get_size() != SIZE:
		return
	var comparison := _pixel_difference(actual, reference)
	_check(comparison.exceeded == 0, specification.name + " preserves the complete original 2D art within two channel levels: " + JSON.stringify(comparison))
	var alpha := _alpha_contract(actual, specification)
	if specification.name == "low-motion-zero":
		_low_motion_reference = actual.duplicate()
	elif specification.name == "low-motion-later":
		_check(_low_motion_reference != null and _pixel_difference(actual, _low_motion_reference).exceeded == 0, "low motion remains the same complete art at different supplied times")
	var record := {"name": specification.name, "time": specification.time, "look": specification.look,
		"comparison": comparison, "alpha": alpha, "pixelsSkipped": false}
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		var pair := Image.create(256, 128, false, Image.FORMAT_RGBA8)
		pair.fill(Color.TRANSPARENT)
		pair.blit_rect(reference, Rect2i(Vector2i.ZERO, SIZE), Vector2i.ZERO)
		pair.blit_rect(actual, Rect2i(Vector2i.ZERO, SIZE), Vector2i(128, 0))
		var filename := str(specification.name) + "-reference-left-composed-right.png"
		_check(pair.save_png(_output.path_join(filename)) == OK, "save paired original/composed art evidence: " + str(specification.name))
		record["file"] = filename
	_pixel_checks += 1
	_cases.append(record)

func _pixel_difference(actual: Image, reference: Image) -> Dictionary:
	if actual.get_size() != reference.get_size():
		return {"pixels": 0, "exceeded": 1, "maxChannelError": 1.0, "reason": "image dimensions differ"}
	var exceeded := 0
	var maximum := 0.0
	for y in range(actual.get_height()):
		for x in range(actual.get_width()):
			var a := actual.get_pixel(x, y)
			var b := reference.get_pixel(x, y)
			# RGB in an alpha-zero texel has no visible meaning. Compare actual
			# premultiplied visible color plus alpha across the whole image.
			var error := maxf(absf(a.a - b.a), maxf(absf(a.r * a.a - b.r * b.a), maxf(absf(a.g * a.a - b.g * b.a), absf(a.b * a.a - b.b * b.a))))
			maximum = maxf(maximum, error)
			if error > CHANNEL_ERROR + 0.000001:
				exceeded += 1
	return {"pixels": actual.get_width() * actual.get_height(), "exceeded": exceeded, "maxChannelError": maximum}

func _alpha_contract(image: Image, specification: Dictionary) -> Dictionary:
	var opaque := 0
	var transparent := 0
	for y in range(128):
		for x in range(128):
			var alpha := image.get_pixel(x, y).a
			if alpha >= 0.98:
				opaque += 1
			if alpha <= 0.001:
				transparent += 1
	_check(opaque > 500 and transparent > 5000, specification.name + " has an opaque character interior and a substantial transparent exterior")
	var corner_alpha := 0.0
	for corner: Vector2i in [Vector2i.ZERO, Vector2i(120, 0), Vector2i(0, 120), Vector2i(120, 120)]:
		for y in range(corner.y, corner.y + 8):
			for x in range(corner.x, corner.x + 8):
				corner_alpha = maxf(corner_alpha, image.get_pixel(x, y).a)
	_check(corner_alpha <= 0.001, specification.name + " does not turn its texture rectangle into an opaque billboard")
	var body_opaque := 0
	if not specification.look.get("rolling", false):
		for y in range(78, 88):
			for x in range(59, 69):
				if image.get_pixel(x, y).a >= 0.98:
					body_opaque += 1
		_check(body_opaque >= 95, specification.name + " retains an opaque torso instead of exposing intermediate body layers")
	return {"opaquePixels": opaque, "transparentPixels": transparent, "cornerMaxAlpha": corner_alpha, "torsoOpaquePixels": body_opaque}

func _finish() -> void:
	_failures.append_array(_logger.captured_errors())
	var report := {"passed": _failures.is_empty(), "gpuVerified": _gpu_verified and _failures.is_empty(), "checks": _checks,
		"pixelCases": _pixel_checks, "display": DisplayServer.get_name(), "size": [128, 128], "cases": _cases, "failures": _failures,
		"assetHashes": _asset_hashes, "sourceHashes": _source_hashes(),
		"budgets": {"artSize": ART_SIZE, "footAnchor": [FOOT.x, FOOT.y], "standingLift": STANDING_LIFT, "rollingLift": ROLLING_LIFT, "maxChannelError": CHANNEL_ERROR},
		"scope": "GPU compares the new private buddy surface with original CreatureArt ordered 2D drawing at the same fixed canvas, size, time and look. The independent reference suppresses only the ground-shadow command. All source character PNG bytes are checked against the original asset manifest and repository assets.",
		"limitations": ["Headless success validates assets and surface lifecycle only; gpuVerified remains false and every pixel case is explicitly skipped.", "Matching isolated art does not certify the native world material, correct stairs/plant/actor occlusion, actor formation or pleasing overall composition. Root must inspect normal-scene GPU evidence.", "The comparison retains the original buddy drawing commands, ball rotation and expressions. It does not use image centroids or source-alpha bounds as a proxy for artistic quality."]}
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		var file := FileAccess.open(_output.path_join("checks.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t") + "\n")
		else:
			_check(false, "actor appearance report can be written")
	_finished = true
	print(JSON.stringify({"suite": "actor-appearance", "passed": _failures.is_empty(), "gpuVerified": _gpu_verified and _failures.is_empty(), "checks": _checks, "pixelCases": _pixel_checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)

func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for file: String in [SURFACE_PATH, "res://presentation/actors/creature_art.gd", "res://presentation/world/garden_paint.gd", "res://tests/visual_actor_appearance_test.gd", "res://content/visual-assets.json"]:
		if FileAccess.file_exists(file):
			result[file] = FileAccess.get_sha256(file)
	return result
