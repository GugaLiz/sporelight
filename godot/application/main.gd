extends Node

const NativeInteraction = preload("res://application/native_interaction.gd")
const NativeActionPolicy = preload("res://application/native_action_policy.gd")
const HintNavigation = preload("res://application/hint_navigation.gd")
const PresentationProfiles = preload("res://presentation/native/level_presentation_profiles.gd")

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
const NativeMovement = preload("res://application/native_movement.gd")

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
var qa_unlock_all: bool = true
var status_message: String = ""
var _qa_callback: JavaScriptObject
var _qa_timer: float = 0.0
var _qa_sequence: int = 0
var _hint_remaining: float = 0.0
var _growth_hint: bool = false
var _command_cache_session: int = 0
var _command_cache_revision: int = -1
var _command_cache: Dictionary = {}
var pending_button: String = ""
var home_active: bool = false
var has_active_game: bool = true
var native_movement: RefCounted
var native_enabled := false
var _hint_tier := 0
var _native_save_clock := 0.0
var _native_was_moving := false
var _portrait_blocked := false

func _ready() -> void:
	# The playtest reuses this application with an in-memory repository.
	var root_weaving := "--root-weaving" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		root_weaving = root_weaving or bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('playtest') === 'root-weaving'"))
	if root_weaving and not has_meta("playtest_controller"):
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		add_child(load("res://prototypes/root_weaving.gd").new())
		return
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	levels = content.get("levels", [])
	if FileAccess.file_exists("res://content/cloud-levels.json"):
		var cloud_content: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/cloud-levels.json"))
		if cloud_content is Dictionary:
			levels.append_array(cloud_content.get("levels", []))
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
		qa_unlock_all = web_options.get("unlockAll", "") != "0"
		comfort_mode = comfort_mode or web_options.get("comfort", "") == "1"
	input_router = Router.new()
	input_router.continuous = true
	repository = _create_repository()
	repository.configure_levels(levels)
	repository.snapshot_validator = _normalize_snapshot
	var loaded: Dictionary = repository.load_store()
	var had_saved_journey: bool = not repository.data.mainline.runs.is_empty() or not repository.data.mainline.records.is_empty()
	storage_ready = bool(loaded.get("ok", false))
	settings = repository.data.settings.duplicate(true)
	input_router.continuous = comfort_mode or bool(settings.get("continuousInput", true)) or "--continuous" in OS.get_cmdline_user_args()
	safe_camera = comfort_mode or bool(settings.get("safeCamera", false)) or "--safe-camera" in OS.get_cmdline_user_args()
	if qa_mode:
		input_router.continuous = input_router.continuous or web_options.get("continuous", "") == "1"
		safe_camera = safe_camera or web_options.get("safeCamera", "") == "1"
	settings["continuousInput"] = input_router.continuous
	settings["safeCamera"] = safe_camera
	native_enabled = not "--legacy" in OS.get_cmdline_user_args()
	if native_enabled:
		Router.install_native_actions()
		view = _create_native_view()
	else:
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
	if hud.has_method("apply_settings"):
		hud.apply_settings(settings)
	hud.command_requested.connect(_on_command)
	hud.level_requested.connect(_enter_level)
	hud.settings_changed.connect(_configure)
	hud.menu_requested.connect(_show_menu)
	if hud.has_signal("layout_changed"):
		hud.connect("layout_changed", _on_hud_chrome_changed)
	view.tile_selected.connect(_go)
	view.command_selected.connect(_on_command)
	view.label_font = hud.theme.default_font
	get_viewport().size_changed.connect(_update_layout)
	var level_id: String = str(repository.data.mainline.get("last_level", "1-1"))
	var explicit_level := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			level_id = argument.trim_prefix("--level=")
			explicit_level = true
	if qa_mode and web_options.has("level"):
		level_id = str(web_options.level)
	_enter_level(level_id)
	if (not qa_mode and not explicit_level) or web_options.get("home", "") == "1":
		has_active_game = had_saved_journey
		_show_home(false)
	if not storage_ready:
		_message("暂时无法读取存档。当前仍可游玩，请先从存档工具恢复备份。")
	_update_layout.call_deferred()
	if native_enabled:
		# The saved garden is already built, but home pauses its SubViewport
		# before its first draw. Prepare that frame beneath the startup cover,
		# instead of compiling all 3D materials on the Continue click.
		view.prepare_initial_frame()
	_install_qa_bridge()

func _create_repository() -> RefCounted:
	return Repository.new()

func _create_native_view() -> Node2D:
	return load("res://presentation/native/native_garden_stage.gd").new()

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
	var factory: Script = load("res://core/world_factory.gd")
	var initial: RefCounted = factory.create(id) if factory != null else World.new(id)
	return initial.normalize_saved(snapshot)

func _enter_level(level_id: String, review: bool = false) -> void:
	# Scene changes own the old modal's lifetime; do not leave a live overlay
	# above an unpaused world or resume the previous scene on the way out.
	if hud is HUD:
		hud.close_overlay(false)
		hud.set_game_interface_visible(true)
	home_active = false
	has_active_game = true
	view.show()
	var found: bool = false
	for level in levels:
		if str(level.id) == level_id:
			found = true
	if not found:
		level_id = "1-1"
	route.clear()
	motion.clear()
	pending_button = ""
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
	strolling = review and bool(session.world.state.completed)
	view.clear_motion(false)
	view.overview = false
	view.hint_visible = false
	view.set_visual_time(0.0)
	view.resume_visual_time()
	view.set_paused(false)
	audio.pause(false)
	view.set_world(session.world)
	if native_enabled:
		native_movement = NativeMovement.new()
		native_movement.setup(session, view, input_router)
		native_movement.support_changed.connect(_on_native_support_changed)
		native_movement.blocked.connect(_message)
		_hint_tier = 0
	hud.set_overview(false)
	_message(_entry_message())
	_sync_hud()
	_update_layout()
	if session.world.state.completed and not strolling:
		_show_ending()

func _process(delta: float) -> void:
	if OS.has_feature("web"):
		_set_portrait_blocked(bool(JavaScriptBridge.eval("window.__sporelightPortraitBlocked === true")))
	if _portrait_blocked: return
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
		if native_movement != null:
			native_movement.advance_mechanism(progress)
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
	if native_movement != null:
		_advance_native_actions(delta)
		return
	if not pending_button.is_empty():
		var intent := pending_button
		pending_button = ""
		_on_command(intent)
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
	if _portrait_blocked: return
	if session == null:
		return
	if event is InputEventScreenTouch and hud.has_method("set_touch_mode"):
		hud.set_touch_mode(true)
	if native_movement != null and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		if _handle_native_pad_ui(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		if not event.pressed:
			input_router.handle_key(event)
			return
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
			return
		if event.echo:
			return
		if hud.has_method("handle_context_key") and hud.handle_context_key(event):
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if paused and hud.has_method("navigate_back"):
				hud.navigate_back()
			elif home_active:
				_show_home(false)
			elif paused:
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
	if native_movement != null:
		if not _locked():
			audio.start()
			waiting_repair = false
			native_movement.rejoining = false
			pending_button = ""
			last_direction = direction
			if input_router.held.is_empty():
				native_movement.nudge(direction)
		return
	if manual and not paused:
		pending_button = ""
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
	if hud.has_method("close_context_choices"):
		hud.close_context_choices()
	waiting_repair = false
	audio.start()
	var path: Array = session.world.path_to(tile_id)
	if path.is_empty() and tile_id != str(session.world.point().id):
		_message("这里暂时走不到，先观察道路的连接。")
		return
	route = path.duplicate()
	if native_movement != null:
		native_movement.request_path(route)
		route.clear()

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
	if native_movement != null:
		var context := _native_interaction_context()
		var choices: Array = context.get("choices", [])
		return str(choices[0].id) if choices.size() == 1 and not str(choices[0].id).begins_with("grow:") else "context" if not choices.is_empty() else ""
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
	if id == "home":
		_show_home()
		return
	if id == "map":
		_show_menu()
		return
	if id == "continue":
		if not has_active_game:
			return
		if reviewing:
			_enter_level(str(repository.data.mainline.last_level))
			return
		home_active = false
		if hud is HUD:
			hud.close_overlay(false)
			hud.set_game_interface_visible(true)
		view.show()
		_on_command("resume")
		return
	if id == "pause":
		pending_button = ""
		paused = true
		input_router.clear()
		if native_movement != null:
			native_movement.suspended = true
			if motion.is_empty():
				native_movement.stop()
		view.set_paused(true)
		audio.pause(true)
		return
	if id == "resume":
		# An overlay keeps ownership of input until it is actually removed.
		if hud is HUD and hud.is_modal_open():
			return
		if home_active:
			_show_home(false)
			return
		if session != null and bool(session.world.state.completed):
			strolling = true
		paused = false
		if native_movement != null:
			native_movement.suspended = false
		view.set_paused(false)
		audio.pause(false)
		_sync_hud()
		return
	if id == "save_imported":
		storage_ready = true
		settings = repository.data.settings.duplicate(true)
		_apply_settings()
		_enter_level(str(repository.data.mainline.last_level))
		_message("旅程已导入，可以继续探索花园。")
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
	if paused or (session.world.state.completed and not strolling):
		return
	# A clicked direction waits for the whole pending action. Keyboard taps use
	# _step's short-lived buffer; an explicit button choice must not expire there.
	if id.begins_with("dir:") and motion.is_empty():
		_step(id.trim_prefix("dir:"))
		return
	if not motion.is_empty() and id not in ["mode", "hint", "hint_next", "overview"]:
		var action := _primary() if id == "primary" else id
		var current := str(motion.get("kind", ""))
		if action == current or (id == "jump" and current in ["jump", "hop"]):
			_message("正在完成这次动作，稍等它落稳。")
			return
		pending_button = id
		route.clear()
		input_router.clear()
		waiting_repair = false
		_message("这一步落稳后，就会回应你的新选择。")
		_sync_hud()
		return
	audio.start()
	match id:
		"restart":
			repository.data.mainline.runs.erase(str(session.world.level.id))
			_enter_level(str(session.world.level.id))
			_save()
		"hint":
			if native_movement != null and hud.has_method("show_hint"):
				_apply_native_hint("toggle")
				return
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
		"hint_next":
			if native_movement != null and hud.is_hint_visible():
				_apply_native_hint("next")
			return
		"overview":
			if native_movement != null:
				view.overview = not view.overview
				hud.set_overview(view.overview)
				view.set_layout(hud.safe_world_rect())
				return
			if get_viewport().get_visible_rect().size.x >= 650 or safe_camera:
				_message("当前镜头已展示整片花园。全景切换适用于小屏跟随镜头。")
				return
			view.overview = not view.overview
			hud.set_overview(view.overview)
			_message("看看整片花园。" if view.overview else "回到露薇身边。")
			view.queue_redraw()
		"mode":
			rolling = not rolling
			if native_movement != null:
				native_movement.rolling = rolling
				if view.has_method("set_actor_mode"):
					view.set_actor_mode(session.world.actor(), rolling)
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
			if native_movement != null:
				if view.has_method("play_emote"):
					view.play_emote(session.world.actor(), "jump")
				return
			if bool(session.world.state.playing):
				_message("雨歌正在试奏。先暂停试奏，再轻轻跳跃。")
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
			if native_movement != null:
				var context := _native_interaction_context()
				var choices: Array = context.get("choices", [])
				if choices.size() == 1 and not str(choices[0].id).begins_with("grow:"):
					_on_command(str(choices[0].id))
				elif not choices.is_empty():
					native_movement.stop()
					input_router.clear()
					hud.show_context_choices(choices, str(context.get("label", "选择操作")))
				else:
					_message("走近根台、物件或庭院把手，再看看能做什么。")
				return
			var primary: String = _primary()
			if not primary.is_empty():
				_on_command(primary)
			else:
				_message("走近根台、物件或庭院中心，再看看能做什么。")
		_:
			route.clear()
			if native_movement != null and id == "rejoin":
				native_movement.rejoining = true
				return
			if id == "repair" and not session.world.together() and session.world.state.follow:
				if native_movement != null:
					waiting_repair = true
					native_movement.rejoining = true
					_message("等伙伴沿着接通的小路走近。")
					return
				for command in session.world.commands():
					if str(command.id) == "rejoin":
						waiting_repair = true
						_execute(Command.interact("rejoin"), "rejoin")
						return
			_execute(Command.interact(id), id)

func _execute(command: GardenCommand, clip: String) -> void:
	if native_movement != null:
		if command.kind == GardenCommand.Kind.MOVE:
			var path: Array = session.world.path_to(command.value)
			if not path.is_empty():
				native_movement.request_path(path)
			return
		if command.value not in ["repair", "rejoin"]:
			waiting_repair = false
		native_movement.stop()
	var outcome: GardenCommandResult = session.apply(command) if command.kind == GardenCommand.Kind.UNDO else session.prepare(command)
	_message(outcome.message)
	if not outcome.accepted:
		route.clear()
		waiting_repair = false
		if native_movement != null and command.value == "repair" and not session.world.ready():
			_message("花园还在等待道路或机关接通。可以继续观察，也可以主动请求提示。")
		if native_movement == null and command.value == "repair" and str(session.world.level.id) == "1-2" and not session.world.connected():
			_show_growth_hint()
		return
	if not outcome.changed:
		return
	if native_movement != null and command.kind != GardenCommand.Kind.UNDO and not native_movement.can_change_to(outcome.after):
		_message("先离开这段道路的边缘，再让它收回。")
		return
	var immediate: bool = (native_movement == null and bool(settings.get("lowMotion", false))) or clip in ["switch", "follow", "play", "undo"] or clip.begins_with("swap:")
	if immediate:
		if command.kind == GardenCommand.Kind.UNDO:
			if native_movement != null:
				view.set_world(session.world)
				native_movement.restore()
			_save()
		else:
			_commit(outcome)
		view.clear_motion(false)
		_after_motion()
		return
	var duration: float = 0.205 if clip in ["move", "rejoin"] else (0.155 if clip == "roll" else (0.62 if clip == "hop" else 0.78))
	if native_movement != null:
		duration = _native_action_duration(clip)
		native_movement.begin_mechanism(outcome.before, outcome.after)
	motion = {"before": outcome.before, "after": outcome.after, "elapsed": 0.0, "duration": duration, "kind": clip, "prepared": outcome}
	view.set_motion(outcome.before, outcome.after, 0.0, clip)
	_sync_hud()

func _commit(prepared: GardenCommandResult) -> void:
	var committed: GardenCommandResult = session.commit(prepared)
	if not committed.accepted:
		route.clear()
		waiting_repair = false
		if native_movement != null:
			native_movement.restore()
		_message(committed.message)
		return
	if native_movement != null:
		native_movement.finish_mechanism()
		if view.has_method("set_actor_mode"):
			for who: String in ["luvie", "buddy"]:
				view.set_actor_mode(who, rolling and who == session.world.actor())
		if committed.command.value == "resetSong":
			native_movement.restore()
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
		pending_button = ""
		route.clear()
		input_router.clear()
		_show_ending()

func _show_ending() -> void:
	var presentation: Dictionary = session.world.level.duplicate()
	presentation["has_next_garden"] = not levels.is_empty() and str(session.world.level.id) != str(levels.back().id)
	hud.show_ending(presentation, session.world.snapshot())

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
	settings.merge(value, true)
	_apply_settings()
	if storage_ready:
		var result: Dictionary = repository.save_settings(settings)
		if not bool(result.get("ok", false)):
			storage_ready = false
			_message("设置暂时无法保存。")
	_update_layout()

func _apply_settings() -> void:
	input_router.continuous = bool(settings.get("continuousInput", true))
	input_router.clear()
	safe_camera = bool(settings.get("safeCamera", comfort_mode))
	view.set_settings(settings)
	if hud.has_method("apply_settings"):
		hud.apply_settings(settings)
	audio.configure(settings)

func _show_menu() -> void:
	var progress: Dictionary = repository.data.mainline.duplicate(true)
	progress["unlock_all"] = qa_mode and qa_unlock_all
	hud.show_menu(levels, progress)

func _show_home(save_progress: bool = true) -> void:
	var was_home := home_active
	route.clear()
	motion.clear()
	pending_button = ""
	input_router.clear()
	waiting_repair = false
	view.clear_motion(false)
	if native_movement != null:
		native_movement.restore()
		native_movement.suspended = true
	if save_progress and not was_home and has_active_game:
		_save()
	home_active = true
	_on_command("pause")
	view.hide()
	if hud is HUD:
		hud.set_game_interface_visible(false)
		var progress: Dictionary = repository.data.mainline.duplicate(true)
		if not storage_ready:
			progress["storage_warning"] = "存档暂时不可用，可从导入 / 导出旅程恢复备份。"
		hud.show_home(levels, progress, has_active_game)
	_update_layout()
	_publish_qa()

func _sync_hud() -> void:
	if hud is HUD:
		hud.update_state(session.world, paused or (session.world.state.completed and not strolling), status_message, not motion.is_empty())
	else:
		# Existing nonvisual harnesses retain their three-argument HUD contract.
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
	if native_movement != null and hud.has_method("set_interaction_context"):
		var context := _native_interaction_context()
		var point: Vector2 = view.project(context.get("tile", session.world.point()))
		hud.set_interaction_context(str(context.get("id", "")), str(context.get("label", "")), context.get("choices", []), point)
		if view.has_method("set_interaction_context"):
			view.set_interaction_context(context)
	_update_layout()
	_publish_qa()

func _message(text: String) -> void:
	status_message = text
	if hud != null:
		hud.set_message(text)

func _entry_message() -> String:
	if native_enabled:
		return str(Journey.describe(session.world).get("goal", "慢慢探索这片花园。"))
	return str(session.world.level.get("intro", ""))

func _update_layout() -> void:
	if view != null and hud != null:
		if hud is HUD:
			hud.set_overview_available(get_viewport().get_visible_rect().size.x < 650 and not safe_camera)
		view.set_layout(hud.safe_world_rect() if safe_camera or native_movement != null else Rect2())
		if view.has_method("set_ui_regions") and hud.has_method("layout_regions"):
			view.set_ui_regions(hud.layout_regions())

func _on_hud_chrome_changed() -> void:
	# Keep framing in sync with settled HUD containers, even while standing still.
	_update_layout()

func _set_portrait_blocked(value: bool) -> void:
	if value == _portrait_blocked: return
	_portrait_blocked = value
	pending_button = ""
	if input_router != null: input_router.clear()
	if native_movement != null and motion.is_empty(): native_movement.stop()
	if view != null: view.set_paused(value or paused)
	if audio != null: audio.pause(value or paused)
	if hud != null: hud.set_process(not value)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and input_router != null:
		pending_button = ""
		input_router.clear()
		if native_movement != null and motion.is_empty():
			native_movement.stop()
	if what == NOTIFICATION_APPLICATION_PAUSED and view != null:
		pending_button = ""
		input_router.clear()
		view.set_paused(true)
		audio.pause(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED and view != null:
		view.set_paused(paused or _portrait_blocked)
		audio.pause(paused or _portrait_blocked)

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
			if hud is HUD:
				hud.close_overlay(false)
				hud.set_game_interface_visible(true)
			else:
				hud.close_overlay()
			home_active = false
			has_active_game = true
			view.show()
			route.clear()
			motion.clear()
			pending_button = ""
			input_router.clear()
			waiting_repair = false
			strolling = false
			reviewing = false
			paused = false
			rolling = false
			view.set_paused(false)
			var normalized: Dictionary = _normalize_snapshot(snapshot)
			session = Session.new(str(snapshot.levelId), normalized.snapshot)
			view.clear_motion(false)
			view.set_world(session.world)
			if native_movement != null:
				native_movement.setup(session, view, input_router)
			_message(_entry_message())
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
		var visible_rect: Rect2 = rect.intersection(get_viewport().get_visible_rect())
		var parent: Node = node.get_parent()
		while parent != null:
			if parent is Control and parent.clip_contents:
				visible_rect = visible_rect.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		if not visible_rect.has_area():
			return
		result.append({"text": str(node.get("text")), "disabled": node.disabled,
			"class": node.get_class(), "pressed": node.button_pressed, "instanceId": node.get_instance_id(),
			"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y,
			"visibleRect": [visible_rect.position.x, visible_rect.position.y, visible_rect.size.x, visible_rect.size.y],
			"path": str(node.get_path()), "action": str(node.get_meta("action", "")),
			"command_id": str(node.get_meta("command_id", "")), "tooltip": str(node.get("tooltip_text")),
			"clipped": visible_rect != rect})
	for child in node.get_children():
		_qa_buttons(child, result)

func _qa_controls(node: Node, result: Array) -> void:
	if node is Control and node.is_visible_in_tree() and (node is BaseButton or node is Range or node is TextEdit or node is LineEdit or node is Label or node is ScrollContainer):
		var rect: Rect2 = node.get_global_rect()
		var visible_rect := rect.intersection(get_viewport().get_visible_rect())
		var parent := node.get_parent()
		while parent != null:
			if parent is Control and parent.clip_contents:
				visible_rect = visible_rect.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		var entry := {"class": node.get_class(), "name": str(node.name), "path": str(node.get_path()), "instanceId": node.get_instance_id(),
			"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y,
			"visibleRect": [visible_rect.position.x, visible_rect.position.y, visible_rect.size.x, visible_rect.size.y],
			"setting_id": str(node.get_meta("setting_id", ""))}
		if node is BaseButton:
			entry.merge({"text": str(node.get("text")), "pressed": node.button_pressed, "disabled": node.disabled,
				"action": str(node.get_meta("action", "")), "command_id": str(node.get_meta("command_id", "")), "tooltip": node.tooltip_text})
		elif node is Label or node is TextEdit or node is LineEdit:
			entry["text"] = str(node.get("text"))
		if node is Range:
			entry.merge({"value": node.value, "min_value": node.min_value, "max_value": node.max_value, "step": node.step})
		result.append(entry)
	for child in node.get_children():
		_qa_controls(child, result)

func _publish_qa() -> void:
	if not qa_mode or not OS.has_feature("web") or not OS.is_debug_build() or session == null or hud == null:
		return
	_qa_sequence += 1
	var buttons: Array = []
	_qa_buttons(hud, buttons)
	var controls: Array = []
	_qa_controls(hud, controls)
	var targets: Array = []
	for tile in session.world.tiles():
		if not bool(tile.get("solid", false)) and session.world.visible(tile):
			var point: Vector2 = view.project(tile)
			targets.append({"id": str(tile.id), "x": point.x, "y": point.y})
	var safe_rect: Rect2 = hud.safe_world_rect()
	var payload: Dictionary = {"snapshot": session.world.snapshot(), "moving": not motion.is_empty() or (native_movement != null and native_movement.is_moving()),
		"homeActive": home_active, "worldVisible": view.visible,
		"gameHudVisible": hud.is_game_interface_visible(), "hasActiveGame": has_active_game,
		"qaSequence": _qa_sequence,
		"pendingButton": pending_button,
		"paused": paused, "revision": session.revision, "message": status_message,
		"settings": settings.duplicate(true), "rolling": rolling, "overview": view.overview, "hintVisible": view.hint_visible,
		"ui": {"controls": controls, "settings": settings.duplicate(true), "modalOpen": hud.is_modal_open()},
		"scale": view.scale_factor, "origin": [view.origin.x, view.origin.y], "buttons": buttons,
		"progress": repository.data.mainline, "reviewing": reviewing, "strolling": strolling,
		"targets": targets, "safeCamera": safe_camera, "continuousInput": input_router.continuous,
		"safeRect": [safe_rect.position.x, safe_rect.position.y, safe_rect.size.x, safe_rect.size.y],
		"character": view.character_presentation(),
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"hudRegions": hud.layout_regions(),
		"native": {} if native_movement == null else native_movement.qa_state(),
		"render": view.render_statistics() if view.has_method("render_statistics") else {},
		"commands": session.world.commands(),
		"growthChoices": view.growth_choice_layout() if view.has_method("growth_choice_layout") else [],
		"context": {} if native_movement == null else _native_interaction_context(),
		"tiles": session.world.tiles(),
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

func _physics_process(delta: float) -> void:
	if _portrait_blocked: return
	if native_movement == null or session == null:
		return
	var context_open: bool = hud.has_method("is_context_open") and hud.is_context_open()
	native_movement.tick(minf(delta, 0.05), not _locked() and not home_active and not context_open)
	var moving: bool = native_movement.is_moving()
	_native_save_clock += delta
	if not paused and motion.is_empty() and ((_native_was_moving and not moving) or (moving and _native_save_clock >= 1.0)):
		_save()
		_native_save_clock = 0.0
		if _native_was_moving and not moving:
			_sync_hud()
	_native_was_moving = moving

func _advance_native_actions(delta: float) -> void:
	if not pending_button.is_empty():
		var intent := pending_button
		pending_button = ""
		_on_command(intent)
		return
	if not route.is_empty():
		native_movement.request_path(route)
		route.clear()
	if waiting_repair and session.world.together() and not native_movement.rejoining:
		waiting_repair = false
		_execute(Command.interact("repair"), "repair")
	elif bool(session.world.state.playing):
		beat_clock += delta
		if beat_clock >= 0.6:
			beat_clock = 0.0
			_execute(Command.interact("beat"), "beat")

func _on_native_support_changed(_who: String, _result: RefCounted) -> void:
	view.refresh_world(session.world, true)
	input_router.world_changed()
	audio.play("move")
	_save()
	_sync_hud()

func _native_action_duration(clip: String) -> float:
	return NativeActionPolicy.duration(clip, bool(settings.get("lowMotion", false)), PresentationProfiles.for_level(str(session.world.level.id)))

func _unhandled_input(event: InputEvent) -> void:
	# GUI gets first refusal; a focused button must not also trigger a world action.
	if native_movement == null or paused or home_active or not event is InputEventJoypadButton or not event.pressed:
		return
	var command := "primary" if event.button_index == JOY_BUTTON_A else "switch" if event.button_index == JOY_BUTTON_Y else "undo" if event.button_index == JOY_BUTTON_X else ""
	if not command.is_empty():
		_on_command(command)
		get_viewport().set_input_as_handled()

func _handle_native_pad_ui(event: InputEvent) -> bool:
	var context_open: bool = hud.has_method("is_context_open") and hud.is_context_open()
	if context_open and hud.has_method("handle_context_event"):
		if hud.handle_context_event(event):
			return true
	if not paused and event is InputEventJoypadMotion and absf(event.axis_value) > 0.2:
		audio.start()
	if paused and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		if hud.has_method("navigate_back"):
			hud.navigate_back()
		elif home_active:
			_show_home(false)
		else:
			hud.close_overlay()
		return true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if paused:
			if hud.has_method("navigate_back"):
				hud.navigate_back()
			elif not home_active:
				hud.close_overlay()
		else:
			if context_open:
				hud.close_context_choices()
			_on_command("settings")
		return true
	return false


func _native_interaction_context() -> Dictionary:
	if session == null or native_movement == null:
		return {}
	var body: CharacterBody3D = view.get_actor_body(session.world.actor())
	if body == null:
		return {}
	return NativeInteraction.context(session.world, _local_commands(), _command_states(), body.position, view.tile_position, PresentationProfiles.for_level(str(session.world.level.id)))

func _native_command_tile(command: Dictionary) -> Dictionary:
	return NativeInteraction.command_tile(session.world, command)

func _apply_native_hint(event: String) -> void:
	var next := HintNavigation.transition(_hint_tier, hud.is_hint_visible(), event)
	_hint_tier = int(next.tier)
	if next.visible:
		hud.show_hint(session.world, _hint_tier)
	else:
		hud.hide_hint()
