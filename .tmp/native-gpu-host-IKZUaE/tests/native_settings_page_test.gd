extends "res://tests/service_modal_lifecycle_test.gd"
## Real UI -> application -> save/audio/view; no audible playback claim.
func _run() -> void:
	root.size = Vector2i(1280,720)
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	var app := _real_app("2-1")
	app._on_command("settings")
	await process_frame
	await process_frame
	var before: Dictionary = app.session.world.snapshot()
	var progress: Dictionary = app.repository.data.duplicate(true)
	var page: Control = app.hud._settings_page
	for key: String in ["bgm","sfx","ambient"]:
		page._sliders[key].value = .75
		_check(is_equal_approx(float(app.repository.persisted.settings[key]),.75),key+"/actual-slider-persists")
		_check(is_equal_approx(float(app.audio.applied_settings[key]),.75),key+"/audio-receives-volume")
	for key: String in ["dynamicLight","particles","lowMotion","touchControls"]:
		page._toggles[key].button_pressed = not bool(page.values[key])
		_check(app.repository.persisted.settings[key] == page.values[key],key+"/actual-switch-persists")
		_check(app.view.applied_settings[key] == page.values[key],key+"/view-receives-setting")
	page._quality.hd.pressed.emit()
	_check(app.repository.persisted.settings.quality == "hd" and app.view.applied_settings.quality == "hd","quality/actual-option-reaches-save-and-view")
	_same(before,app.session.world.snapshot(),"settings/do-not-alter-puzzle")
	_find_button(page,"恢复默认").pressed.emit()
	_same(Repository.default_settings(),app.repository.persisted.settings,"reset/persists-real-defaults")
	for key: String in progress:
		if key != "settings": _same(progress[key],app.repository.data[key],"reset/preserves/"+key)
	_same(before,app.session.world.snapshot(),"reset/preserves-puzzle")
	_paused_modal(app,"settings/until-dismissed")
	for node: Button in page.footer.get_children():
		_check(node.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,"footer/full-button-text/"+node.text)
	page.dismissed.emit()
	_returned(app,"settings/dismiss")
	app.free()
	await process_frame
	_failures.append_array(_logger.captured_errors())
	print(JSON.stringify({"suite":"native-settings-page","passed":_failures.is_empty(),"checks":_checks,"failures":_failures}))
	quit(0 if _failures.is_empty() else 1)
