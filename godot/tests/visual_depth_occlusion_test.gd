extends SceneTree
## Independent native-depth pixel oracle. The headless branch is deliberately
## not GPU verification; actual occlusion requires reading the viewport image.

const Stage := preload("res://presentation/world/depth_stage.gd")
const Target := preload("res://presentation/world/depth_paint_target.gd")
const ErrorLogger := preload("res://tests/visual_error_logger.gd")
const SIZE := Vector2i(256, 256)
const ORIGIN := Vector2(128, 128)
const SCALE := 2.0
const SHAPE := Rect2(48, 48, 160, 160)
const SPRITE := Rect2(64, 64, 128, 128)
const WORLD_HEIGHT := 96.0 / (35.0 * sqrt(6.0))
const COLOR_ERROR := 3.0 / 255.0
const ORDER_ERROR := 1.0 / 255.0
const BLUE := Color(0, 0, 1, 1)
const RED := Color(1, 0, 0, 1)
const GREEN := Color(0, 1, 0, 1)

var _output := ""
var _checks := 0
var _pixel_checks := 0
var _failures: Array[String] = []
var _cases: Array = []
var _stage: SubViewport
var _logger := ErrorLogger.new()
var _finished := false
var _gpu_verified := false

func _initialize() -> void:
	OS.add_logger(_logger)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	create_timer(75).timeout.connect(func() -> void:
		if not _finished:
			push_error("Native depth occlusion suite timed out")
			quit(1))
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition and _failures.size() < 60:
		_failures.append(label)

func _run() -> void:
	_stage = Stage.new()
	root.add_child(_stage)
	_stage.setup_size(Vector2(SIZE), ORIGIN, SCALE)
	await process_frame
	_geometry_oracle()
	_material_contract()
	_object_bias_geometry_oracle()
	var source: Image = load("res://assets/images/character-refined/idle-front.png").get_image()
	_check(source != null and not source.is_empty(), "original idle PNG is available")
	var transparent_patch := Rect2i(69, 69, 8, 8)
	_check(_source_patch_matches(source, transparent_patch, false), "declared idle PNG corner ROI contains only alpha-zero texels, including filtering margin")
	var opaque_patch := _find_opaque_patch(source)
	_check(opaque_patch.has_area(), "the original idle PNG has a fully opaque interior ROI")
	if DisplayServer.get_name() != "headless":
		for specification in _specifications():
			await _occlusion_case(specification)
		await _checker_case()
		await _object_bias_case()
		if source != null and not source.is_empty() and opaque_patch.has_area():
			await _original_sprite_case(source, transparent_patch, opaque_patch)
		_gpu_verified = _pixel_checks > 0 and _failures.is_empty()
	else:
		_cases.append({"name": "gpu-pixel-occlusion", "skipped": true, "reason": "headless display cannot certify GPU depth, alpha rejection or pixel order invariance"})
		_cases.append({"name": "coplanar-actor-bias-with-real-wall", "gpuVerified": false, "skipped": true, "reason": "headless geometry cannot certify the actor/root tie or the nearer wall's rendered occlusion"})
	_stage.queue_free()
	await process_frame
	_failures.append_array(_logger.captured_errors())
	_finished = true
	var report := {"passed": _failures.is_empty(), "gpuVerified": _gpu_verified and _failures.is_empty(), "checks": _checks, "pixelChecks": _pixel_checks, "display": DisplayServer.get_name(), "size": [SIZE.x, SIZE.y], "cases": _cases, "failures": _failures,
		"budgets": {"expectedColorMaxChannelError": COLOR_ERROR, "reverseOrderMaxChannelError": ORDER_ERROR, "opaqueQuadRoiMinimumBorderInsetPixels": 20},
		"scope": "GPU mode reads DepthStage.get_texture().get_image() after actual native material rendering. Fixed-color ROIs straddle intersecting world planes and reverse submission order, so object-level painter sorting cannot satisfy the oracle. Checker and original PNG tests check alpha-zero holes and opaque interiors. The biased actor case resolves a coplanar root tie in both submission orders while preserving occlusion by a physically nearer x-wall.",
		"limitations": ["Headless success is geometry/material/asset validation only; gpuVerified remains false and no pixel case is claimed.", "ROIs exclude MSAA polygon edges, texture alpha transitions and plane intersections. This suite tests the renderer contract, not full-level composition or input feel."], "sourceHashes": _source_hashes()}
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		var file := FileAccess.open(_output.path_join("checks.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t") + "\n")
		else:
			_check(false, "occlusion report can be written")
	print(JSON.stringify({"suite": "native-depth-occlusion", "passed": _failures.is_empty(), "gpuVerified": _gpu_verified and _failures.is_empty(), "checks": _checks, "pixelChecks": _pixel_checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)

func _specifications() -> Array:
	return [
		{"name": "billboard-near", "kind": "billboard", "total": 4.0, "rois": [{"rect": Rect2i(112, 112, 16, 16), "front": true}]},
		{"name": "billboard-far", "kind": "billboard", "total": -4.0, "rois": [{"rect": Rect2i(144, 144, 16, 16), "front": false}]},
		{"name": "ground-crossing", "kind": "ground", "rois": [{"rect": Rect2i(120, 88, 16, 16), "front": false}, {"rect": Rect2i(120, 152, 16, 16), "front": true}]},
		{"name": "x-wall-crossing", "kind": "x", "rois": [{"rect": Rect2i(88, 120, 16, 16), "front": true}, {"rect": Rect2i(152, 120, 16, 16), "front": false}]},
		{"name": "z-wall-crossing", "kind": "z", "rois": [{"rect": Rect2i(88, 120, 16, 16), "front": false}, {"rect": Rect2i(152, 120, 16, 16), "front": true}]},
		{"name": "ramp-crossing", "kind": "ramp", "rois": [{"rect": Rect2i(120, 88, 16, 16), "front": false}, {"rect": Rect2i(128, 168, 16, 16), "front": true}, {"rect": Rect2i(88, 152, 16, 16), "front": false}, {"rect": Rect2i(152, 152, 16, 16), "front": true}]}
	]

## This oracle uses declared 70/35/48 projection and plane equations directly.
## It never reads candidate batch vertices, depth values or screen_to_world.
func _oracle_world(kind: String, screen: Vector2, total_value := 0.0) -> Vector3:
	var raw := (screen - ORIGIN) / SCALE
	var difference := raw.x / 35.0
	var total := 0.0
	var height := 0.0
	match kind:
		"ground":
			total = raw.y / 17.5
		"x":
			total = -difference
			height = (17.5 * total - raw.y) / 48.0
		"z":
			total = difference
			height = (17.5 * total - raw.y) / 48.0
		"ramp":
			# h=(-z-.2)/.6 for the declared northward ramp; substitute
			# z=(total-difference)/2 into y=17.5*total-48*h.
			total = (raw.y + 40.0 * difference - 16.0) / 57.5
			height = (-(total - difference) * 0.5 - 0.2) / 0.6
		_:
			total = total_value
			height = (17.5 * total - raw.y) / 48.0
	return Vector3((total + difference) * 0.5, height * WORLD_HEIGHT, (total - difference) * 0.5)

func _ramp() -> Dictionary:
	return {"low": {"x": 0.0, "z": 0.0, "h": 0.0}, "high": {"x": 0.0, "z": -1.0, "h": 1.0}, "direction": Vector2(0, -1), "rail_start": 0.2, "rail_end": 0.8}

func _select_plane(target: RefCounted, specification: Dictionary) -> void:
	target.begin_object({"x": 0.0, "z": 0.0, "h": 0.0})
	if specification.kind == "billboard":
		target.billboard({"x": float(specification.get("total", 0.0)) * 0.5, "z": float(specification.get("total", 0.0)) * 0.5, "h": 0.0})
	elif specification.kind == "ramp":
		target.ramp(_ramp())
	else:
		target.surface(str(specification.kind), 0.0)

func _geometry_oracle() -> void:
	var target := Target.new()
	target.configure(ORIGIN, SCALE)
	var ray := Vector3(sqrt(0.375), 0.5, sqrt(0.375))
	for specification in _specifications():
		_select_plane(target, specification)
		for entry in specification.rois:
			var region: Rect2i = entry.rect
			for y in range(region.position.y, region.end.y):
				for x in range(region.position.x, region.end.x):
					var at := Vector2(x + 0.5, y + 0.5)
					var expected := _oracle_world(specification.kind, at, float(specification.get("total", 0.0)))
					_check(target.screen_to_world(at).distance_to(expected) < 0.00001, specification.name + " maps onto the declared world plane")
					var reference := _oracle_world("billboard", at)
					var separation := (expected - reference).dot(ray)
					_check((separation > 0.0) == bool(entry.front) and absf(separation) > 0.04, specification.name + " ROI has the expected near/far geometry with a nonzero depth margin")

func _material_contract() -> void:
	var opaque: StandardMaterial3D = _stage._material({"key": "test-opaque", "texture": null, "transparent": false})
	var alpha: StandardMaterial3D = _stage._material({"key": "test-alpha", "texture": null, "transparent": true})
	_check(opaque.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque geometry uses native opaque depth")
	_check(alpha.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS, "sprite material requests alpha depth pre-pass; GPU pixels must additionally prove it")
	_check(not opaque.no_depth_test and not alpha.no_depth_test, "neither material disables native depth testing")
	_check(opaque.render_priority == 0 and alpha.render_priority == 0, "no priority override substitutes painter ordering for depth")

func _object_bias_regions() -> Array:
	# Each probe is inside the alpha-one part of the actor and well away from
	# both the x-wall intersection at x=128 and the sprite/filtering borders.
	return [{"rect": Rect2i(96, 112, 16, 16), "wallFront": true}, {"rect": Rect2i(144, 112, 16, 16), "wallFront": false}]

func _object_bias_geometry_oracle() -> void:
	var target := Target.new()
	target.configure(ORIGIN, SCALE)
	var ray := Vector3(sqrt(0.375), 0.5, sqrt(0.375))
	var expected_actor := _oracle_world("billboard", SPRITE.position) + ray * 0.001
	target.begin_object({"x": -0.18, "z": 0.18, "h": 0.0}, 0, 0.001)
	_quad(target, SPRITE, GREEN)
	_check(target.batches[0].vertices[0].distance_to(expected_actor) < 0.000001, "actor tie uses the declared 0.001 view-ray offset on the root's x+z=0 plane")
	target.begin_object({"x": 0.0, "z": 0.0, "h": 0.0})
	_quad(target, SHAPE, RED)
	_check(target.batches[0].vertices[4].distance_to(_oracle_world("billboard", SHAPE.position)) < 0.000001, "root starts on its unshifted physical billboard after the biased actor")
	for entry in _object_bias_regions():
		var region: Rect2i = entry.rect
		var margin := INF
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var at := Vector2(x + 0.5, y + 0.5)
				var wall := _oracle_world("x", at)
				var actor := _oracle_world("billboard", at) + ray * 0.001
				var separation := (wall - actor).dot(ray)
				margin = minf(margin, separation if entry.wallFront else -separation)
		_check(margin > 0.01, "biased actor/x-wall ROI retains its declared near/far relationship with a depth margin greater than 0.01")

func _quad(target: RefCounted, rect: Rect2, color: Color) -> void:
	target.draw_colored_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), color)

func _submit_intersection(specification: Dictionary, reverse: bool) -> void:
	_stage.begin_frame()
	var target: RefCounted = _stage.paint_target
	for layer in [1, 0] if reverse else [0, 1]:
		if layer == 0:
			_select_plane(target, {"kind": "billboard", "total": 0.0})
			_quad(target, SHAPE, BLUE)
		else:
			_select_plane(target, specification)
			_quad(target, SHAPE, GREEN)
	_stage.end_frame()

func _read_pixels() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _stage.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.get_size() == SIZE, "native stage returns an actual full-sized GPU image")
	return image

func _occlusion_case(specification: Dictionary) -> void:
	_submit_intersection(specification, false)
	var first := await _read_pixels()
	_submit_intersection(specification, true)
	var reverse := await _read_pixels()
	for entry in specification.rois:
		var region: Rect2i = entry.rect
		_color_roi(first, region, GREEN if entry.front else BLUE, specification.name)
		_color_roi(reverse, region, GREEN if entry.front else BLUE, specification.name + "/reversed")
		_equal_roi(first, reverse, region, specification.name + "/call-order-invariant")
	_save_image(first, specification.name + ".png")
	_cases.append({"name": specification.name, "gpuVerified": true, "reverseSubmissionCompared": true, "rois": _report_rois(specification.rois)})

func _checker_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in range(8):
		for x in range(8):
			image.set_pixel(x, y, Color(1, 1, 1, 0 if (x < 4) == (y < 4) else 1))
	return ImageTexture.create_from_image(image)

func _submit_texture(texture: Texture2D, reverse: bool, background: bool) -> void:
	_stage.begin_frame()
	var target: RefCounted = _stage.paint_target
	for layer in [1, 0] if reverse else [0, 1]:
		if layer == 0:
			if background:
				_select_plane(target, {"kind": "billboard", "total": 0.0})
				_quad(target, SHAPE, BLUE)
		else:
			_select_plane(target, {"kind": "billboard", "total": 4.0})
			target.draw_texture_rect(texture, SPRITE, false, Color.WHITE)
	_stage.end_frame()

func _checker_case() -> void:
	var texture := _checker_texture()
	var red := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	red.fill(RED)
	var behind := ImageTexture.create_from_image(red)
	_submit_checker(texture, behind, false)
	var first := await _read_pixels()
	_submit_checker(texture, behind, true)
	var reverse := await _read_pixels()
	var regions := [{"rect": Rect2i(88, 88, 16, 16), "opaque": false}, {"rect": Rect2i(152, 88, 16, 16), "opaque": true}, {"rect": Rect2i(88, 152, 16, 16), "opaque": true}, {"rect": Rect2i(152, 152, 16, 16), "opaque": false}]
	for entry in regions:
		_color_roi(first, entry.rect, Color.WHITE if entry.opaque else RED, "checker alpha-one occludes / alpha-zero lets the middle textured layer pass depth")
		_color_roi(reverse, entry.rect, Color.WHITE if entry.opaque else RED, "checker reversed alpha depth rejection")
		_equal_roi(first, reverse, entry.rect, "checker/call-order-invariant")
	_save_image(first, "alpha-checker.png")
	_cases.append({"name": "checker-alpha-depth", "gpuVerified": true, "alphaZeroRevealsMiddleTexture": true, "alphaOneOccludesMiddleTexture": true, "opaqueFallbackColor": "blue", "middleTextureColor": "red", "frontOpaqueColor": "white", "reverseSubmissionCompared": true, "roiPolicy": "16px interiors centered 32px from each checker transition and sprite border; a second alpha-depth material behind the checker must pass its holes, which a previously drawn opaque background alone could not prove"})

func _submit_checker(front: Texture2D, middle: Texture2D, reverse: bool) -> void:
	_stage.begin_frame()
	var target: RefCounted = _stage.paint_target
	for layer in [2, 1, 0] if reverse else [0, 1, 2]:
		_select_plane(target, {"kind": "billboard", "total": float(layer) * 2.0})
		if layer == 0:
			_quad(target, SHAPE, BLUE)
		else:
			target.draw_texture_rect(middle if layer == 1 else front, SPRITE, false, Color.WHITE)
	_stage.end_frame()

func _object_bias_actor_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(GREEN)
	for edge in range(8):
		image.set_pixel(edge, 0, Color.TRANSPARENT)
		image.set_pixel(edge, 7, Color.TRANSPARENT)
		image.set_pixel(0, edge, Color.TRANSPARENT)
		image.set_pixel(7, edge, Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)

func _submit_object_bias(texture: Texture2D, reverse: bool, include_wall: bool) -> void:
	_stage.begin_frame()
	var target: RefCounted = _stage.paint_target
	for layer in [2, 1, 0] if reverse else [0, 1, 2]:
		match layer:
			0:
				target.begin_object({"x": 0.0, "z": 0.0, "h": 0.0})
				_quad(target, SHAPE, RED)
			1:
				target.begin_object({"x": -0.18, "z": 0.18, "h": 0.0}, 0, 0.001)
				target.draw_texture_rect(texture, SPRITE, false, Color.WHITE)
			2:
				if include_wall:
					target.begin_object({"x": 0.0, "z": 0.0, "h": 0.0})
					target.surface("x", 0.0)
					_quad(target, SHAPE, BLUE)
	_stage.end_frame()

func _object_bias_case() -> void:
	var before_failures := _failures.size()
	var before_pixels := _pixel_checks
	var texture := _object_bias_actor_texture()
	var regions := _object_bias_regions()
	for include_wall in [false, true]:
		_submit_object_bias(texture, false, include_wall)
		var first := await _read_pixels()
		_submit_object_bias(texture, true, include_wall)
		var reverse := await _read_pixels()
		var label := "coplanar-actor-bias-with-wall" if include_wall else "coplanar-actor-bias"
		for entry in regions:
			var expected := BLUE if include_wall and entry.wallFront else GREEN
			_color_roi(first, entry.rect, expected, label)
			_color_roi(reverse, entry.rect, expected, label + "/reversed")
			_equal_roi(first, reverse, entry.rect, label + "/call-order-invariant")
		_save_image(first, label + ".png")
	_cases.append({"name": "coplanar-actor-bias-with-real-wall", "gpuVerified": _failures.size() == before_failures and _pixel_checks > before_pixels, "reverseSubmissionCompared": true, "actorDepthBias": 0.001, "rootPlane": "billboard x+z=0", "actorPlane": "billboard x+z=0", "actorMaterial": "green RGBA image with transparent border and alpha-one probe interiors", "wallPlane": "x=0", "wallRoiDepthMarginGreaterThan": 0.01, "tieWithoutWallExpectedColor": "green", "withWallExpectedColorsLeftRight": ["blue", "green"], "rois": [_rect_array(regions[0].rect), _rect_array(regions[1].rect)], "roiPolicy": "16px probe interiors stay at least 16px from the wall intersection and alpha-one texture boundary; all prior color/order budgets remain unchanged"})

func _source_patch_matches(source: Image, rect: Rect2i, opaque: bool) -> bool:
	if source == null or source.is_empty():
		return false
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var uv := (Vector2(x + 0.5, y + 0.5) - SPRITE.position) / SPRITE.size
			var sx := int(floor(uv.x * source.get_width()))
			var sy := int(floor(uv.y * source.get_height()))
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					if sx + ox < 0 or sx + ox >= source.get_width() or sy + oy < 0 or sy + oy >= source.get_height():
						return false
					var alpha := source.get_pixel(sx + ox, sy + oy).a
					if alpha < 0.99999 if opaque else alpha > 0.00001:
						return false
	return true

func _find_opaque_patch(source: Image) -> Rect2i:
	for y in range(88, 168, 4):
		for x in range(88, 168, 4):
			var patch := Rect2i(x, y, 6, 6)
			if _source_patch_matches(source, patch, true):
				return patch
	return Rect2i()

func _original_sprite_case(source: Image, transparent_patch: Rect2i, opaque_patch: Rect2i) -> void:
	var texture := ImageTexture.create_from_image(source)
	_submit_texture(texture, false, true)
	var first := await _read_pixels()
	_submit_texture(texture, true, true)
	var reverse := await _read_pixels()
	_submit_texture(texture, false, false)
	var alone := await _read_pixels()
	_color_roi(first, transparent_patch, BLUE, "idle PNG alpha-zero corner reveals the rear quad")
	_color_roi(reverse, transparent_patch, BLUE, "idle PNG reversed alpha-zero corner reveals the rear quad")
	_equal_roi(first, reverse, transparent_patch, "idle PNG transparent corner is call-order invariant")
	_equal_roi(first, reverse, opaque_patch, "idle PNG opaque interior is call-order invariant")
	_equal_roi(first, alone, opaque_patch, "idle PNG opaque interior matches the isolated front sprite and occludes the rear quad")
	var visible := false
	for y in range(opaque_patch.position.y, opaque_patch.end.y):
		for x in range(opaque_patch.position.x, opaque_patch.end.x):
			visible = visible or _color_error(first.get_pixel(x, y), BLUE) > 0.1
	_check(visible, "the idle opaque comparison is not vacuously comparing background pixels")
	_save_image(first, "original-idle-alpha.png")
	_cases.append({"name": "original-idle-alpha", "gpuVerified": true, "source": "character-refined/idle-front.png", "sourceAlphaVerified": true, "transparentRoi": _rect_array(transparent_patch), "opaqueRoi": _rect_array(opaque_patch), "reverseSubmissionCompared": true, "isolatedSpriteCompared": true})

func _color_error(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))

func _color_roi(image: Image, region: Rect2i, expected: Color, label: String) -> void:
	var maximum := 0.0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			maximum = maxf(maximum, _color_error(image.get_pixel(x, y), expected))
			_pixel_checks += 1
	_check(maximum <= COLOR_ERROR, label + " expected-color ROI max error " + str(maximum))

func _equal_roi(first: Image, second: Image, region: Rect2i, label: String) -> void:
	var maximum := 0.0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			maximum = maxf(maximum, _color_error(first.get_pixel(x, y), second.get_pixel(x, y)))
			_pixel_checks += 1
	_check(maximum <= ORDER_ERROR, label + " max error " + str(maximum))

func _save_image(image: Image, name: String) -> void:
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		_check(image.save_png(_output.path_join(name)) == OK, "GPU evidence PNG can be saved: " + name)

func _rect_array(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _report_rois(entries: Array) -> Array:
	var result: Array = []
	for entry in entries:
		result.append({"rect": _rect_array(entry.rect), "expectedFrontPlane": entry.front})
	return result

func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://presentation/world/depth_stage.gd", "res://presentation/world/depth_paint_target.gd", "res://tests/visual_depth_occlusion_test.gd", "res://assets/images/character-refined/idle-front.png"]:
		result[path] = FileAccess.get_sha256(path)
	return result
