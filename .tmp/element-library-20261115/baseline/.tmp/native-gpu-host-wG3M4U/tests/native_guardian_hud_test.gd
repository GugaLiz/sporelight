extends "res://tests/native_ui_test.gd"
## Real 3-4 HUD controls at native viewport sizes. This is not browser/DPR,
## GPU appearance, OS pointer input, or safe-area-inset acceptance.
const World = preload("res://core/garden_world.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
var records: Array = []

func _cases() -> Array:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var fixture := {}
	for entry: Dictionary in reference.cases:
		if entry.name == "authored/3-4": fixture = entry
	_check(not fixture.is_empty(), "immutable guardian intention fixture exists")
	if fixture.is_empty(): return []
	var result: Array = [{"name":"cold","snapshot":fixture.initial.snapshot}]
	var longest := {"name":"","snapshot":{},"count":-1}
	var carrying := {"name":"","snapshot":{},"count":-1}
	for index in fixture.steps.size():
		var snapshot: Dictionary = fixture.steps[index].snapshot
		if bool(snapshot.completed): continue
		var world := World.new("3-4",snapshot)
		var count := _local_choices(world).size()
		var entry := {"name":"fixture-step-"+str(index),"snapshot":snapshot,"count":count}
		if count > longest.count: longest = entry
		if str(snapshot.items.mirror.get("holder","")) == "luvie" and count > carrying.count: carrying = entry
	_check(longest.count > 1 and carrying.count > 0, "fixtures contain a multi-choice menu and a carried-mirror phase")
	result.append(longest)
	result.append(carrying)
	return result

func _local_choices(world: RefCounted) -> Array:
	return world.commands().filter(func(command: Dictionary) -> bool: return not str(command.id) in ["switch","follow"])

func _chrome(hud: Control, viewport: Rect2, label: String) -> void:
	for region: Dictionary in hud.layout_regions():
		var r: Array = region.rect
		_check(viewport.grow(1).encloses(Rect2(r[0],r[1],r[2],r[3])), label + "/contained-"+str(region.name))
	_check(hud._title.text == "3-4 · 沉睡的守护者" and hud._heading.get_global_rect().encloses(hud._title.get_global_rect()),label+"/title-in-heading")
	for group: Control in [hud._nav,hud._tools]:
		for button: Button in _buttons(group):
			if not button.is_visible_in_tree(): continue
			_check(group.get_global_rect().grow(1).encloses(button.get_global_rect()),label+"/button-contained-"+button.text)
			_check(button.size.x >= 44 and button.size.y >= 44,label+"/button-hit-size-"+button.text)
	_check(viewport.encloses(hud._overview.get_global_rect()) and hud._overview.size.y >= 44,label+"/overview-reachable")
	_check(hud._tools.size.y <= (50 if viewport.size.y <= 420 else 60),label+"/single-row-toolbar")
	_check(hud.safe_world_rect().size.y >= viewport.size.y*.3,label+"/world-space-retained")

func _run() -> void:
	var cases := _cases()
	for dimensions: Vector2i in [Vector2i(1460,720),Vector2i(1280,720),Vector2i(844,390),Vector2i(568,320)]:
		var outer := SubViewport.new()
		outer.size = dimensions
		root.add_child(outer)
		var hud := HUD.new()
		outer.add_child(hud)
		hud.command_requested.connect(func(id: String) -> void: _events.append(id))
		var stage := Stage.new()
		outer.add_child(stage)
		var viewport := Rect2(Vector2.ZERO,Vector2(dimensions))
		for entry: Dictionary in cases:
			var world := World.new("3-4",entry.snapshot)
			var before: Dictionary = world.snapshot()
			var label := str(dimensions)+"/"+str(entry.name)
			hud.update_state(world)
			stage.set_world(world)
			hud.set_interaction_context("context","选择附近操作",_local_choices(world))
			await _settle()
			await _settle()
			_check(hud.get_viewport_rect() == viewport and hud.size == viewport.size and stage._viewport.size == dimensions,label+"/hud-and-3d-share-requested-viewport")
			_chrome(hud,viewport,label)
			var baseline := hud.safe_world_rect()
			var choices := _local_choices(world)
			var menu_count := 0
			var last_id := ""
			var scroll_value := 0
			var menu_evidence := {}
			if not choices.is_empty():
				hud.show_context_choices(choices,"选择附近操作")
				await _settle()
				await _settle()
				_chrome(hud,viewport,label+"/menu")
				var buttons := _buttons(hud._commands)
				menu_count = buttons.size()
				_check(menu_count == choices.size(),label+"/all-actual-nearby-commands-retained")
				var last: Button = buttons.back()
				last_id = str(last.get_meta("command_id"))
				_events.clear()
				for unused in range(buttons.size()-1): hud.handle_context_key(_key(KEY_TAB))
				await _settle()
				await _settle()
				scroll_value = hud._context_scroll.scroll_vertical
				menu_evidence = {"panel":str(hud._panel.get_global_rect()),"scrollViewport":str(hud._context_scroll.get_global_rect()),"lastButton":str(last.get_global_rect())}
				_check(last.has_focus() and hud._context_scroll.get_global_rect().grow(1).encloses(last.get_global_rect()),label+"/last-choice-focus-scroll-reveals-entire-button")
				_check(hud._panel.get_global_rect().encloses(last.get_global_rect()) and viewport.encloses(last.get_global_rect()),label+"/last-choice-visible-inside-menu-and-viewport")
				_check(hud.safe_world_rect() == baseline,label+"/menu-does-not-resize-game-camera-area")
				hud.handle_context_key(_key(KEY_ENTER))
				_check(_events == [last_id] and not hud.is_context_open(),label+"/last-choice-emits-original-intent-once")
			_check(world.snapshot() == before,label+"/layout-and-menu-selection-do-not-mutate-world")
			records.append({"viewport":[dimensions.x,dimensions.y],"case":entry.name,"carriedMirror":world.state.items.mirror.get("holder","") == "luvie","menuCount":menu_count,"lastCommand":last_id,"scroll":scroll_value,"menuGeometry":menu_evidence,"regions":hud.layout_regions()})
		outer.queue_free()
		await process_frame
	print(JSON.stringify({"suite":"native-guardian-hud","passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"records":records,"scope":"Headless real HUD and native SubViewport geometry, actual fixture commands and focus/Enter signals. Not browser/DPR, GPU artwork, OS pointer input or system-safe-area acceptance."}))
	quit(0 if _failures.is_empty() else 1)
