extends SceneTree
## Real cover controls, transforms and choreography. GPU/pointer verification
## belongs to the browser acceptance and is not claimed by these checks.
const HUD := preload("res://ui/garden_hud.gd")
const Vignette := preload("res://ui/menu_vignette.gd")
const Store := preload("res://services/save_repository.gd")
var _checks := 0
var _failures: Array[String] = []
var _events: Array[String] = []
var _levels: Array = []
var _progress := {"records": {"1-1": {"completed": true}, "cloud-1": {"completed": true}}, "runs": {}, "memories": {}}
var _hud: Control


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


func _action(id: String) -> Button:
	for button in _buttons(_hud._overlay):
		if str(button.get_meta("action", "")) == id:
			return button
	return null


func _find(text: String) -> Button:
	for button in _buttons(_hud._overlay):
		if button.text == text:
			return button
	return null


func _settle() -> void:
	for index in 5:
		await process_frame


func _command(id: String) -> void:
	_events.append(id)
	if id == "map":
		_hud.show_menu(_levels, _progress)
	elif id == "settings":
		_hud.show_settings({})
	elif id == "home":
		_hud.show_home(_levels, _progress, true)


func _layouts() -> void:
	for extent in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(568, 320), Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3440, 1440)]:
		root.size = extent
		_hud.show_home(_levels, _progress, true)
		await _settle()
		var cover: Control = _hud._home_cover
		var stage: Node2D = cover.scenery
		stage.set_process(false)
		stage.elapsed_ms = 0
		stage.refresh_pose()
		var bounds := Rect2(Vector2.ZERO, Vector2(extent))
		var prefix := "%dx%d/" % [extent.x, extent.y]
		_check(cover.size.is_equal_approx(Vector2(extent)), prefix + "authored cover fills viewport")
		_check(_hud._overlay_paper == null and _hud._overlay.find_child("ModalPaper", true, false) == null, prefix + "home no longer uses the generic central modal")
		_check(cover.logo.texture.resource_path.ends_with("material-ready/menu-logo.png") and cover.logo.size.x >= 225, prefix + "original large brand is visible")
		_check(bounds.encloses(cover.logo.get_global_rect()), prefix + "brand remains inside screen")
		_check(bounds.encloses(cover.invitation.get_global_rect()), prefix + "invitation uses an independent bounded scroll area")
		_check(cover.invitation.follow_focus, prefix + "keyboard focus scrolls offscreen entries into view")
		_check(stage.hero.get_parent() == stage.backdrop.get_parent() and stage.hero.get_parent() == stage.buddy.get_parent(), prefix + "background hero and buddy share scene transform")
		_check(stage.backdrop.show_behind_parent and stage.backdrop.z_index == 0, prefix + "authored backdrop stays above older home background")
		_check(stage.hero.position.is_equal_approx(Vector2(325, 642)), prefix + "actor feet retain original terrace position")
		var anchor: Vector2 = stage.hero.offset + Vector2(stage.hero.texture.get_width() * 0.5, stage.hero.texture.get_height() * 236.0 / 256.0)
		_check(anchor.is_zero_approx(), prefix + "hero registration places original feet at scene anchor")
		var foot: Vector2 = stage.hero.to_global(Vector2.ZERO)
		_check(bounds.has_point(foot) and not cover.invitation.get_global_rect().has_point(foot), prefix + "actor feet stay on visible scenery clear of invitation")
		if extent.y > extent.x:
			var hat_top: float = foot.y - 290 * 236.0 / 256.0 * stage.scale.y + 290 * 0.065 * stage.scale.y
			_check(hat_top > cover.tagline.get_global_rect().end.y, prefix + "authored hat clears the brand tagline")
		for button in _buttons(cover):
			if not button.is_visible_in_tree():
				continue
			_check(button.size.y >= 44 and button.size.x >= 44, prefix + button.text + "/44px hit target")
			_check(button.get_global_rect().position.x >= -0.1 and button.get_global_rect().end.x <= extent.x + 0.1, prefix + button.text + "/no horizontal overflow")
		var primary := _action("continue")
		_check(primary.get_theme_stylebox("normal") is StyleBoxTexture, prefix + "original paper artwork styles the one primary entry")
		_check(root.gui_get_focus_owner() == primary, prefix + "saved journey is the automatic focused destination")
		_check(primary.get_theme_stylebox("focus") is StyleBoxEmpty and primary.get_theme_stylebox("normal") == primary.get_theme_stylebox("hover"), prefix + "keyboard focus paints the exact hover surface without the rectangular ring")
		var primary_count := 0
		var visible_count := 0
		for button in _buttons(cover):
			primary_count += int(button.get_meta("cover_primary", false))
			visible_count += int(button.is_visible_in_tree())
		_check(primary_count == 1 and visible_count == 4, prefix + "compact home has one primary and four visible entries")
		_check(not _action("cloud_map").is_visible_in_tree() and _find("导入 / 导出旅程") == null, prefix + "exploration and save tools do not clutter the initial home")
		_action("map").grab_focus()
		_check(primary.get_theme_stylebox("normal") != primary.get_theme_stylebox("hover"), prefix + "moving focus restores the primary resting surface")
		_check(_action("map").get_theme_stylebox("normal") == _action("map").get_theme_stylebox("hover"), prefix + "secondary keyboard focus also uses its hover surface")
		var progress_label := false
		for node in cover.find_children("*", "Label", true, false):
			if node.text == "已唤醒 1 / 12 片微光":
				progress_label = true
		_check(progress_label, prefix + "independent cloud completion does not inflate the 12 mainline progress")
		_action("home_explore").button_pressed = true
		await _settle()
		_check(_action("cloud_map").is_visible_in_tree() and _find("图鉴").is_visible_in_tree(), prefix + "expanding exploration reveals the original destinations")
		var last := _find("花园纪事")
		last.grab_focus()
		await _settle()
		_check(cover.invitation.get_global_rect().intersects(last.get_global_rect()), prefix + "last menu entry is reachable by focus scrolling")


func _choreography() -> void:
	var poses := {0: "idle-front", 1800: "turn-quarter", 2100: "idle-side", 7100: "crouch-lower", 8000: "crouch", 10500: "crouch-happy", 11900: "crouch-lower", 12300: "idle-side", 12600: "turn-quarter", 12900: "idle-front", 13200: "turn-quarter", 18200: "turn-quarter", 21000: "idle-front"}
	for time: int in poses:
		_check(Vignette.pose_at(time).hero.key == poses[time], "original choreography/pose at %dms" % time)
	_check(Vignette.pose_at(4500).hero.walking and Vignette.pose_at(4500).hero.flip, "outbound walking uses original direction")
	_check(Vignette.pose_at(15000).hero.walking and not Vignette.pose_at(15000).hero.flip, "returning walk reverses only after turn poses")
	_check(Vignette.pose_at(0) == Vignette.pose_at(24000), "24-second loop closes without a reset jump")
	var previous: Dictionary = Vignette.pose_at(0)
	for time in range(16, 24001, 16):
		var current: Dictionary = Vignette.pose_at(time)
		var delta := Vector2(current.hero.x - previous.hero.x, current.hero.y - previous.hero.y)
		_check(delta.length() < 1.0, "walking path continuous at %dms" % time)
		previous = current
	for time in [0, 4000, 10000, 17000, 23999]:
		_check(Vignette.pose_at(time, true) == Vignette.pose_at(0, true), "reduced motion holds a stable authored pose")


func _navigation_and_settings() -> void:
	root.size = Vector2i(1280, 720)
	_hud.show_home(_levels, _progress, true)
	await _settle()
	var old_cover: WeakRef = weakref(_hud._home_cover)
	var stage: Node2D = _hud._home_cover.scenery
	_hud.apply_settings({"lowMotion": true, "particles": false, "dynamicLight": false})
	_check(not stage.is_processing() and stage.current_pose.hero.key == "idle-front", "reduced motion stops cover processing and holds original idle")
	for fly in stage._flies:
		_check(not fly.visible, "particle setting hides decorative fireflies")
	_check(not stage.settings.dynamicLight, "dynamic light preference reaches decorative scene")
	_hud.apply_settings({"lowMotion": false, "particles": true, "dynamicLight": true})
	_check(stage.is_processing() and stage._flies[0].visible, "animation and particles resume when settings enable them")
	for text in ["图鉴", "花园纪事", "设置", "导入 / 导出旅程"]:
		_hud.show_home(_levels, _progress, true)
		await _settle()
		if text in ["图鉴", "花园纪事"]:
			_action("home_explore").button_pressed = true
		elif text == "导入 / 导出旅程":
			_action("settings").pressed.emit()
			await _settle()
		_find(text).pressed.emit()
		await _settle()
		_check(_hud._page_kind != "home" and _hud._home_cover == null, text + "/child page uses its normal modal")
		_events.clear()
		_hud.navigate_back()
		await _settle()
		if text == "导入 / 导出旅程":
			_check(_hud._page_kind == "settings", "save tools return to their settings category")
			_hud.navigate_back()
			await _settle()
		_check(_hud._page_kind == "home" and is_instance_valid(_hud._home_cover) and not _events.has("resume"), text + "/back restores cover without entering hidden level")
		if text in ["图鉴", "花园纪事"]:
			_check(_action("home_explore").button_pressed and _find("图鉴").is_visible_in_tree(), text + "/back remembers the expanded collection group")
	_check(old_cover.get_ref() == null, "leaving cover frees its actors and animation processing")
	_events.clear()
	_action("home_explore").button_pressed = true
	_action("cloud_map").pressed.emit()
	await _settle()
	_check(_hud._page_kind == "map" and _events.count("map") == 1, "cloud cover entry uses existing map intent exactly once")
	var focused := root.gui_get_focus_owner()
	_check(focused is Button and str(focused.get_meta("level_id", "")) == "cloud-1", "cloud entry focuses the real independent garden in the existing map")
	_find("返回主界面").pressed.emit()
	await _settle()
	_check(_hud._page_kind == "home", "map returns to authored cover")
	_events.clear()
	_action("continue").pressed.emit()
	_check(_events == ["continue"], "continue entry retains the existing controller intent")
	_hud.show_home(_levels, _progress, false)
	await _settle()
	_check(_action("continue").disabled and root.gui_get_focus_owner() == _action("map"), "new game keeps unavailable continue disabled and focuses start")
	_check(_action("continue").focus_mode == Control.FOCUS_NONE, "unavailable continue cannot trap Tab or directional navigation")


func _run() -> void:
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	_levels.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json")).levels)
	_hud = HUD.new()
	root.add_child(_hud)
	_hud.set_repository(Store.new("user://unused-cover-contract.json"))
	_hud.command_requested.connect(_command)
	await _layouts()
	_choreography()
	await _navigation_and_settings()
	_hud.queue_free()
	await _settle()
	print(JSON.stringify({"suite": "native-cover", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "scope": "Actual cover controls, transforms, resource registration, navigation and motion timing; not GPU/pointer verification."}))
	quit(0 if _failures.is_empty() else 1)
