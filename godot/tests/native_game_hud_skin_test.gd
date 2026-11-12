extends "res://tests/native_ui_test.gd"
## Existing geometry stays fixed while original artwork and live totals update.


func _run() -> void:
	var hud := HUD.new()
	root.add_child(hud)
	var world := SampleWorld.new()
	hud.update_state(world)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(568, 320), Vector2i(390, 844)]:
		root.size = dimensions
		world.state.collected = []
		hud.update_state(world)
		await _settle()
		var label := "%dx%d" % [dimensions.x, dimensions.y]
		var before := hud.safe_world_rect()
		var heading := hud._heading.get_rect()
		var tools := hud._tools.get_rect()
		_check(hud._collection_count.is_visible_in_tree() and hud._collection_count.text == "0 / 3", label + "/collection-visible-beside-seed-budget")
		_check(hud._status.text.contains("芽节 1/1"), label + "/original-budget-retained")
		_check(hud._collection_icon.texture.resource_path == "res://assets/images/material-ready/icon-spore.png", label + "/original-gold-spore-art")
		_check(hud._heading.get_global_rect().encloses(hud._collection_count.get_global_rect()), label + "/count-contained-in-existing-heading")
		_check(hud._status.get_global_rect().end.x <= hud._collection_icon.get_global_rect().position.x, label + "/count-does-not-cover-status")
		world.state.collected = ["a", "b", "c"]
		hud.update_state(world)
		await _settle()
		_check(hud._collection_count.text == "3 / 3", label + "/count-reflects-real-world-state")
		_check(hud.safe_world_rect() == before and hud._heading.get_rect() == heading and hud._tools.get_rect() == tools, label + "/collecting-does-not-reframe-world-or-grow-ui")
		# Removing only the new counter should not recover extra world space.
		hud._collection_count.hide()
		hud._collection_icon.hide()
		await _settle()
		_check(hud.safe_world_rect() == before and hud._heading.get_rect() == heading, label + "/counter-fits-existing-row-height")
		hud._collection_count.show()
		hud._collection_icon.show()
		var primary := _action(hud._tools, "primary")
		hud.set_action_feedback("grow:root:right", {"grow:root:right": {"available": true}})
		_check(primary.get_theme_stylebox("normal") is StyleBoxTexture and primary.get_theme_stylebox("normal").texture.resource_path == "res://assets/images/material-ready/button-green.png", label + "/legal-primary-uses-original-green-button")
		var cached: StyleBox = primary.get_theme_stylebox("normal")
		hud.set_action_feedback("grow:root:right", {"grow:root:right": {"available": false, "reason": "道路还没接通"}})
		_check(primary.get_meta("game_action_skin") == "unavailable" and primary.get_theme_stylebox("normal") is StyleBoxFlat, label + "/unavailable-action-is-not-promoted")
		hud.set_action_feedback("grow:root:right", {"grow:root:right": {"available": true}})
		_check(primary.get_theme_stylebox("normal") == cached, label + "/primary-texture-styles-reused")
		_check(primary.get_global_rect().size.y >= 44 and primary.get_global_rect().size.x >= 44, label + "/primary-keeps-hit-area")
		_check(hud.safe_world_rect() == before, label + "/action-skin-does-not-change-safe-area")
		for panel: PanelContainer in [hud._heading, hud._tools, hud._message_panel]:
			_check(panel.has_meta("game_paper_role"), label + "/original-border-art-attached-to-game-paper")
	world.level.total = 8
	world.state.collected = ["a"]
	hud.update_state(world)
	_check(hud._collection_count.text == "1 / 8", "total-is-read-from-current-level-not-screenshot")
	hud.show_settings({})
	_check(not hud._overlay_paper.has_meta("game_paper_role"), "game-skin-does-not-restyle-settings-or-other-menus")
	hud.free()
	print(JSON.stringify({"suite": "native-game-hud-skin", "passed": _failures.is_empty(), "checks": _checks, "failures": _failures, "scope": "Live counters, existing layout/safe-area preservation and cached artwork bindings; GPU appearance remains separate."}))
	quit(0 if _failures.is_empty() else 1)
