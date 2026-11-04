extends Node

const Session = preload("res://application/game_session.gd")
const World = preload("res://core/garden_world.gd")
const View = preload("res://presentation/world/garden_view.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Repository = preload("res://services/save_repository.gd")
const Audio = preload("res://services/audio_service.gd")
const Router = preload("res://application/input_router.gd")
const Command = preload("res://contracts/game_command.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const Journey = preload("res://application/journey_view.gd")

var session: RefCounted
var view: Node2D
var hud: Control
var repository: RefCounted
var audio: Node
var input_router: RefCounted
var levels: Array = []
var settings: Dictionary = {}
var route: Array = []
var motion: Dictionary = {}
var paused: bool = false
var strolling: bool = false
var reviewing: bool = false
var rolling: bool = false
var storage_ready: bool = true
var waiting_repair: bool = false
var last_direction: String = "right"
var beat_clock: float = 0.0
var comfort_mode: bool = false
var safe_camera: bool = false
var qa_mode: bool = false
var status_message: String = ""
var _qa_callback: JavaScriptObject
var _qa_timer: float = 0.0
var _hint_remaining: float = 0.0
var _growth_hint: bool = false
var _command_cache_session: int = 0
var _command_cache_revision: int = -1
var _command_cache: Dictionary = {}

func _ready() -> void:
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	levels = content.get("levels", [])
	comfort_mode = "--comfort" in OS.get_cmdline_user_args()
	qa_mode = "--qa" in OS.get_cmdline_user_args()
	var web_options: Dictionary = {}
	if OS.has_feature("web") and OS.is_debug_build():
		var option_json: Variant = JavaScriptBridge.eval("JSON.stringify(Object.fromEntries(new URLSearchParams(location.search)))")
		if option_json is String:
			var parsed: Variant = JSON.parse_string(option_json)
			if parsed is Dictionary:
				web_options = parsed
		qa_mode = qa_mode or web_options.get("qa", "") == "1"
		comfort_mode = comfort_mode or web_options.get("comfort", "") == "1"
	input_router = Router.new()
	input_router.continuous = comfort_mode
	repository = Repository.new()
	repository.configure_levels(levels)
	repository.snapshot_validator = _normalize_snapshot
	var loaded: Dictionary = repository.load_store()
	storage_ready = bool(loaded.get("ok", false))
	settings = repository.data.settings.duplicate(true)
	input_router.continuous = comfort_mode or bool(settings.get("continuousInput", false)) or "--continuous" in OS.get_cmdline_user_args()
	safe_camera = comfort_mode or bool(settings.get("safeCamera", false)) or "--safe-camera" in OS.get_cmdline_user_args()
	if qa_mode:
		input_router.continuous = input_router.continuous or web_options.get("continuous", "") == "1"
		safe_camera = safe_camera or web_options.get("safeCamera", "") == "1"
	settings["continuousInput"] = input_router.continuous
	settings["safeCamera"] = safe_camera
	view = View.new()
	add_child(view)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	layer.add_child(hud)
	audio = Audio.new()
	add_child(audio)
	audio.configure(settings)
	view.set_settings(settings)
	hud.set_repository(repository)
	hud.command_requested.connect(_on_command)
	hud.level_requested.connect(_enter_level)
	hud.settings_changed.connect(_configure)
	hud.menu_requested.connect(_show_menu)
	view.tile_selected.connect(_go)
	view.command_selected.connect(_on_command)
	view.label_font = hud.theme.default_font
	get_viewport().size_changed.connect(_update_layout)
	var level_id: String = str(repository.data.mainline.get("last_level", "1-1"))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			level_id = argument.trim_prefix("--level=")
	if qa_mode and web_options.has("level"):
		level_id = str(web_options.level)
	_enter_level(level_id)
	if not storage_ready:
		_message("暂时无法读取存档。当前仍可游玩，请先从存档工具恢复备份。")
	_update_layout.call_deferred()
	_install_qa_bridge()

func _validate_snapshot(snapshot: Dictionary) -> bool:
	return bool(_normalize_snapshot(snapshot).get("ok", false))

func _normalize_snapshot(snapshot: Dictionary) -> Dictionary:
	var id: String = str(snapshot.get("levelId", ""))
	var valid: bool = false
	for level in levels:
		if str(level.id) == id:
			valid = true
			break
	if not valid:
		return {"ok": false}
	var initial: RefCounted = World.new(id)
	return initial.normalize_saved(snapshot)

func _enter_level(level_id: String, review: bool = false) -> void:
	var found: bool = false
	for level in levels:
		if str(level.id) == level_id:
			found = true
	if not found:
		level_id = "1-1"
	route.clear()
	motion.clear()
	input_router.clear()
	waiting_repair = false
	strolling = false
	reviewing = review
	rolling = false
	paused = false
	beat_clock = 0.0
	_hint_remaining = 0.0
	_growth_hint = false
	var saved: Dictionary = repository.data.mainline.memories.get(level_id, {}) if review else repository.data.mainline.runs.get(level_id, {})
	if not review and bool(saved.get("completed", false)):
		saved = {}
		repository.data.mainline.runs.erase(level_id)
	session = Session.new(level_id, saved)
	view.clear_motion(false)
	view.overview = false
	view.hint_visible = false
	view.set_visual_time(0.0)
	view.resume_visual_time()
	view.set_paused(false)
	view.set_world(session.world)
	hud.set_overview(false)
	_message(str(session.world.level.get("intro", "")))
	_sync_hud()
	_update_layout()
	if session.world.state.completed:
		hud.show_ending(session.world.level, session.world.snapshot())

func _process(delta: float) -> void:
	if input_router != null:
		input_router.advance(delta)
	if qa_mode:
		_qa_timer += delta
		if _qa_timer >= 0.05:
			_qa_timer = 0.0
			_publish_qa()
	if session == null or paused:
		return
	if _hint_remaining > 0.0:
		_hint_remaining = maxf(0.0, _hint_remaining - minf(delta, 0.05))
	view.hint_visible = _hint_remaining > 0.0 or (_growth_hint and not session.world.connected())
	if not motion.is_empty():
		motion.elapsed += minf(delta, 0.05)
		var progress: float = minf(1.0, float(motion.elapsed) / float(motion.duration))
		view.set_motion(motion.before, motion.after, progress, motion.kind)
		if progress >= 1.0:
			var prepared: GardenCommandResult = motion.get("prepared")
			motion.clear()
			if prepared != null:
				_commit(prepared)
			_after_motion()
			# Start the next segment before drawing an idle frame or resetting the walk clock.
			_advance_actions(0.0)
			if motion.is_empty():
				view.clear_motion()
		return
	_advance_actions(delta)

func _advance_actions(delta: float) -> void:
	if _locked():
		return
	if not route.is_empty():
		_execute(Command.move_to(str(route.pop_front())), "roll" if rolling else "move")
	elif waiting_repair:
		if session.world.together():
			waiting_repair = false
			_execute(Command.interact("repair"), "repair")
		else:
			_execute(Command.interact("rejoin"), "rejoin")
	elif session.world.state.playing:
		beat_clock += delta
		if beat_clock >= 0.6:
			beat_clock = 0.0
			_execute(Command.interact("beat"), "beat")
	else:
		var direction: String = input_router.take_next()
		if not direction.is_empty():
			_step(direction, false)

func _input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventKey:
		if not event.pressed:
			input_router.handle_key(event)
			return
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
			return
		if event.keycode == KEY_ESCAPE:
			if session.world.state.completed and not strolling:
				get_viewport().set_input_as_handled()
				return
			if paused:
				hud.close_overlay()
			else:
				_on_command("settings")
			get_viewport().set_input_as_handled()
			return
		if paused:
			return
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if event.keycode in [KEY_SPACE, KEY_ENTER] and focus is BaseButton:
			return
		var direction: String = input_router.handle_key(event)
		if not direction.is_empty():
			_step(direction)
			get_viewport().set_input_as_handled()
			return
		if event.echo:
			return
		match event.keycode:
			KEY_E: _on_command("primary")
			KEY_T: _on_command("switch")
			KEY_Z: _on_command("undo")
			KEY_H: _on_command("hint")
			KEY_J, KEY_SPACE: _on_command("jump")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var index: int = event.keycode - KEY_1
				var commands: Array = _local_commands()
				if index < commands.size():
					_on_command(str(commands[index].id))

func _locked() -> bool:
	return paused or not motion.is_empty() or (session.world.state.completed and not strolling)

func _step(direction: String, manual: bool = true) -> void:
	if _locked():
		if manual and not paused and not motion.is_empty():
			input_router.buffer(direction)
			# A deliberate direction supersedes an old click route or automatic catch-up.
			route.clear()
			waiting_repair = false
		return
	if manual:
		input_router.discard_buffer()
	audio.start()
	if session.world.state.playing:
		_message("雨歌正在试奏。先点「暂停试奏」，就能继续走动。")
		input_router.suppress_held(direction)
		return
	route.clear()
	last_direction = direction
	var point: Dictionary = session.world.point()
	var offset: Vector2i = Router.OFFSETS[direction]
	for tile in session.world.neighbors(str(point.id)):
		if tile.x == point.x + offset.x and tile.z == point.z + offset.y:
			_execute(Command.move_to(str(tile.id)), "roll" if rolling else "move")
			return
	_message("这里尚未连通。不同高度和低拱，也会改变谁能通过。")
	input_router.suppress_held(direction)

func _go(tile_id: String) -> void:
	if _locked() or session.world.state.playing:
		return
	audio.start()
	var path: Array = session.world.path_to(tile_id)
	if path.is_empty() and tile_id != str(session.world.point().id):
		_message("这里暂时走不到。" + str(session.world.hint().get("message", "")))
		return
	route = path.duplicate()

func _local_commands() -> Array:
	var local: Array = []
	for command in session.world.commands():
		if str(command.id) not in ["switch", "follow"]:
			local.append(command)
	return local

func _command_states() -> Dictionary:
	var session_id: int = session.get_instance_id()
	if _command_cache_session == session_id and _command_cache_revision == session.revision:
		return _command_cache
	_command_cache_session = session_id
	_command_cache_revision = session.revision
	_command_cache = {}
	var snapshot: Dictionary = session.world.snapshot()
	for command in session.world.commands():
		var preview: RefCounted = session.world.fork(snapshot)
		var result: Dictionary = preview.act(str(command.id))
		var available: bool = bool(result.get("ok", false))
		_command_cache[str(command.id)] = {"available": available, "reason": "" if available else str(result.get("message", ""))}
	return _command_cache

func _primary() -> String:
	var commands: Array = _local_commands()
	var guide: Dictionary = session.world.mirror_guidance()
	var preferred: String = str(guide.get("action", ""))
	for command in commands:
		if str(command.id) == preferred:
			return preferred
	for id in ["repair", "rejoin"]:
		for command in commands:
			if str(command.id) == id and (id != "repair" or session.world.ready()):
				return id
	for command in commands:
		if not str(command.id).begins_with("observe:"):
			if bool(_command_states().get(str(command.id), {}).get("available", false)):
				return str(command.id)
	return str(commands[0].id) if not commands.is_empty() else ""

func _on_command(id: String) -> void:
	if id == "pause":
		paused = true
		input_router.clear()
		view.set_paused(true)
		audio.pause(true)
		return
	if id == "resume":
		paused = false
		view.set_paused(false)
		audio.pause(false)
		_update_layout()
		return
	if id == "save_imported":
		storage_ready = true
		settings = repository.data.settings.duplicate(true)
		view.set_settings(settings)
		audio.configure(settings)
		_enter_level(str(repository.data.mainline.last_level))
		return
	if id == "settings":
		hud.show_settings(settings)
		return
	if id.begins_with("review:"):
		var level_id: String = id.trim_prefix("review:")
		if repository.data.mainline.memories.has(level_id):
			hud.close_overlay()
			_enter_level(level_id, true)
		else:
			_message("这片花园还没有可回看的完成纪念。")
		return
	if id == "stay":
		strolling = true
		_message("留下走走，坐一会儿。已经修复的花园会在纪事里等你。")
		_sync_hud()
		return
	if id == "next":
		var index: int = 0
		for i in levels.size():
			if str(levels[i].id) == str(session.world.level.id):
				index = i + 1
		if index < levels.size():
			_enter_level(str(levels[index].id))
		else:
			hud.show_journal(levels, repository.data.mainline)
		return
	if _locked():
		return
	if id.begins_with("dir:"):
		_step(id.trim_prefix("dir:"))
		return
	audio.start()
	match id:
		"restart":
			repository.data.mainline.runs.erase(str(session.world.level.id))
			_enter_level(str(session.world.level.id))
			_save()
		"hint":
			if str(session.world.level.id) == "1-2" and not session.world.connected():
				_show_growth_hint()
			else:
				_hint_remaining = 20.0 if str(session.world.level.id) == "2-2" else 12.0
				view.hint_visible = true
				if str(session.world.level.id) == "2-2" and get_viewport().get_visible_rect().size.x < 650:
					view.overview = true
					hud.set_overview(true)
				_message(str(session.world.hint().get("message", "")))
			audio.play("chime")
		"overview":
			view.overview = not view.overview
			hud.set_overview(view.overview)
			_message("看看整片花园。" if view.overview else "回到露薇身边。")
			view.queue_redraw()
		"mode":
			rolling = not rolling
			_message("变成蘑菇球，沿接通的石板轻轻滚动。" if rolling else "站起来，和伙伴慢慢走。")
			hud.set_action_label("mode", "滚动中" if rolling else "行走")
		"undo":
			if bool(session.world.state.completed):
				return
			route.clear()
			input_router.clear()
			waiting_repair = false
			_execute(Command.undo_action(), "undo")
		"jump":
			if bool(session.world.state.playing):
				return
			route.clear()
			var point: Dictionary = session.world.point()
			var offset: Vector2i = Router.OFFSETS[last_direction]
			for tile in session.world.neighbors(str(point.id)):
				if tile.x == point.x + offset.x and tile.z == point.z + offset.y:
					_execute(Command.move_to(str(tile.id)), "hop")
					return
			if bool(settings.get("lowMotion", false)):
				_message("前方没有相连的落脚点，先调整方向或接通道路。")
				return
			var snapshot: Dictionary = session.world.snapshot()
			motion = {"before": snapshot, "after": snapshot, "elapsed": 0.0, "duration": 0.62, "kind": "jump"}
			_sync_hud()
		"primary":
			var primary: String = _primary()
			if not primary.is_empty():
				_on_command(primary)
			else:
				_message("走近根台、物件或庭院中心，再看看能做什么。")
		_:
			route.clear()
			if id == "repair" and not session.world.together() and session.world.state.follow:
				for command in session.world.commands():
					if str(command.id) == "rejoin":
						waiting_repair = true
						_execute(Command.interact("rejoin"), "rejoin")
						return
			_execute(Command.interact(id), id)

func _execute(command: GardenCommand, clip: String) -> void:
	var outcome: GardenCommandResult = session.apply(command) if command.kind == GardenCommand.Kind.UNDO else session.prepare(command)
	_message(outcome.message)
	if not outcome.accepted:
		route.clear()
		waiting_repair = false
		if command.value == "repair" and str(session.world.level.id) == "1-2" and not session.world.connected():
			_show_growth_hint()
		return
	if not outcome.changed:
		return
	var immediate: bool = bool(settings.get("lowMotion", false)) or clip in ["switch", "follow", "play", "undo"] or clip.begins_with("swap:")
	if immediate:
		if command.kind == GardenCommand.Kind.UNDO:
			_save()
		else:
			_commit(outcome)
		view.clear_motion(false)
		_after_motion()
		return
	var duration: float = 0.205 if clip in ["move", "rejoin"] else (0.155 if clip == "roll" else (0.62 if clip == "hop" else 0.78))
	motion = {"before": outcome.before, "after": outcome.after, "elapsed": 0.0, "duration": duration, "kind": clip, "prepared": outcome}
	view.set_motion(outcome.before, outcome.after, 0.0, clip)
	_sync_hud()

func _commit(prepared: GardenCommandResult) -> void:
	var committed: GardenCommandResult = session.commit(prepared)
	if not committed.accepted:
		route.clear()
		waiting_repair = false
		_message(committed.message)
		return
	_save()
	input_router.world_changed()
	var kind: String = "grow"
	if committed.command.kind == GardenCommand.Kind.MOVE:
		kind = "move"
	elif session.world.state.completed:
		kind = "complete"
	elif committed.command.value.begins_with("take:"):
		kind = "collect"
	audio.play(kind)

func _after_motion() -> void:
	view.hint_visible = _hint_remaining > 0.0 or (_growth_hint and not session.world.connected())
	_sync_hud()
	if session.world.state.completed and not strolling:
		route.clear()
		input_router.clear()
		hud.show_ending(session.world.level, session.world.snapshot())

func _show_growth_hint() -> void:
	_growth_hint = true
	view.hint_visible = true
	if get_viewport().get_visible_rect().size.x < 650:
		view.overview = true
		hud.set_overview(true)
	var guidance: Dictionary = session.world.growth_guidance()
	if bool(guidance.get("retract", false)):
		_message("这段根线需要调整：先回发光的根台，收回最后一节，再跟随箭头。")
	elif session.world.near(str(session.world.level.roots[0].at)):
		_message("点击地图上发光的＋，让根须沿箭头长出下一节；最后一节也要接入花床。")
	else:
		_message("根线还没接入花床。先回地图上标出的根台，再点击发光的＋补齐。")

func _save() -> void:
	if strolling or reviewing:
		return
	if not storage_ready:
		repository.stage_run(session.world.snapshot())
		return
	var result: Dictionary = repository.commit_run(session.world.snapshot())
	if not bool(result.get("ok", false)):
		storage_ready = false
		_message("暂时无法保存，当前仍可游玩；请先导出进度。")

func _configure(value: Dictionary) -> void:
	settings = value.duplicate(true)
	input_router.continuous = bool(settings.get("continuousInput", comfort_mode))
	input_router.clear()
	safe_camera = bool(settings.get("safeCamera", comfort_mode))
	view.set_settings(settings)
	audio.configure(settings)
	if storage_ready:
		var result: Dictionary = repository.save_settings(settings)
		if not bool(result.get("ok", false)):
			storage_ready = false
			_message("设置暂时无法保存。")
	_update_layout()

func _show_menu() -> void:
	var progress: Dictionary = repository.data.mainline.duplicate(true)
	progress["unlock_all"] = qa_mode
	hud.show_menu(levels, progress)

func _sync_hud() -> void:
	hud.update_state(session.world, _locked(), status_message)
	hud.set_journey(Journey.describe(session.world))
	var primary: String = _primary()
	var primary_label: String = "走近后互动 · E"
	for command in session.world.commands():
		if str(command.id) == primary:
			primary_label = str(command.label) + " · E"
	hud.set_action_label("primary", primary_label)
	hud.set_action_label("mode", "滚动中" if rolling else "行走")
	hud.set_action_feedback(primary, _command_states())
	_update_layout()
	_publish_qa()

func _message(text: String) -> void:
	if text == status_message:
		return
	status_message = text
	if hud != null:
		hud.set_message(text)

func _update_layout() -> void:
	if view != null and hud != null:
		view.set_layout(hud.safe_world_rect() if safe_camera else Rect2())
		if view.has_method("set_ui_regions") and hud.has_method("layout_regions"):
			view.set_ui_regions(hud.layout_regions())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and input_router != null:
		input_router.clear()
	if what == NOTIFICATION_APPLICATION_PAUSED and view != null:
		input_router.clear()
		view.set_paused(true)
		audio.pause(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED and view != null:
		view.set_paused(paused)
		audio.pause(paused)

func _install_qa_bridge() -> void:
	if not qa_mode or not OS.has_feature("web") or not OS.is_debug_build():
		return
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	_qa_callback = JavaScriptBridge.create_callback(_qa_request)
	window.__sporelightRequest = _qa_callback
	_publish_qa()

func _qa_request(arguments: Array) -> void:
	if arguments.is_empty() or not arguments[0] is String:
		return
	var request: Variant = JSON.parse_string(arguments[0])
	if not request is Dictionary:
		return
	match str(request.get("type", "")):
		"snapshot":
			var snapshot: Dictionary = request.get("snapshot", {})
			if not _validate_snapshot(snapshot):
				return
			hud.close_overlay()
			route.clear()
			motion.clear()
			input_router.clear()
			waiting_repair = false
			strolling = false
			reviewing = false
			var normalized: Dictionary = _normalize_snapshot(snapshot)
			session = Session.new(str(snapshot.levelId), normalized.snapshot)
			view.clear_motion(false)
			view.set_world(session.world)
			view.set_visual_time(float(request.get("time", 1200)))
			hud.visible = not bool(request.get("hideHud", false))
			_sync_hud()
		"action":
			view.resume_visual_time()
			_on_command(str(request.get("command", "")))
		"movement":
			view.resume_visual_time()
			_go(str(request.get("tile", "")))
	_publish_qa()

func _qa_buttons(node: Node, result: Array) -> void:
	if node is BaseButton and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		var visible_rect: Rect2 = rect
		var parent: Node = node.get_parent()
		while parent != null:
			if parent is Control and parent.clip_contents:
				visible_rect = visible_rect.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		if not visible_rect.has_area():
			return
		result.append({"text": str(node.get("text")), "disabled": node.disabled,
			"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y,
			"visibleRect": [visible_rect.position.x, visible_rect.position.y, visible_rect.size.x, visible_rect.size.y],
			"path": str(node.get_path()), "action": str(node.get_meta("action", "")),
			"command_id": str(node.get_meta("command_id", "")), "tooltip": str(node.get("tooltip_text")),
			"clipped": visible_rect != rect})
	for child in node.get_children():
		_qa_buttons(child, result)

func _publish_qa() -> void:
	if not qa_mode or not OS.has_feature("web") or not OS.is_debug_build() or session == null or hud == null:
		return
	var buttons: Array = []
	_qa_buttons(hud, buttons)
	var targets: Array = []
	for tile in session.world.tiles():
		if not bool(tile.get("solid", false)) and session.world.visible(tile):
			var point: Vector2 = view.project(tile)
			targets.append({"id": str(tile.id), "x": point.x, "y": point.y})
	var safe_rect: Rect2 = hud.safe_world_rect()
	var payload: Dictionary = {"snapshot": session.world.snapshot(), "moving": not motion.is_empty(),
		"paused": paused, "revision": session.revision, "message": status_message,
		"scale": view.scale_factor, "origin": [view.origin.x, view.origin.y], "buttons": buttons,
		"progress": repository.data.mainline, "reviewing": reviewing, "strolling": strolling,
		"targets": targets, "safeCamera": safe_camera, "continuousInput": input_router.continuous,
		"safeRect": [safe_rect.position.x, safe_rect.position.y, safe_rect.size.x, safe_rect.size.y],
		"character": view.character_presentation(),
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"hudRegions": hud.layout_regions(),
		"motion": {} if motion.is_empty() else {"kind": str(motion.kind), "elapsed": float(motion.elapsed),
			"duration": float(motion.duration), "before": motion.before, "after": motion.after},
		"input": {"buffered": input_router.buffered_direction, "remaining": input_router.buffer_remaining,
			"held": input_router.held.duplicate(), "blocked": input_router.get("_blocked_held")},
		"performance": {"fps": Performance.get_monitor(Performance.TIME_FPS),
			"processMs": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"memoryBytes": Performance.get_monitor(Performance.MEMORY_STATIC),
			"textureBytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}}
	var encoded: String = JSON.stringify(JSON.stringify(payload))
	JavaScriptBridge.eval("window.__sporelightState=JSON.parse(" + encoded + ");")
