extends SceneTree
## Compatibility only: compare each real operation with the pre-2-3 HEAD source.
## This suite preserves existing mechanics rather than defining new restrictions.
const World = preload("res://core/garden_world.gd")
const Session = preload("res://application/game_session.gd")
const Command = preload("res://contracts/game_command.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const BASELINE_COMMIT := "5059b55a0e38d7de68f5593185931c059986d677"
const BASELINE_SHA256 := "5791cbe0a30255ea0bee968ed0c0048511e1d484da67ff25008e6957836ca75b"
var baseline_script: GDScript
var checks := 0
var failures: Array[String] = []
var comparisons := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if not _load_baseline():
		_report()
		return
	_zero_beat_edit_compatibility()
	for song: Array in [
		["turn", "rise", "rest"], ["turn", "rest", "rise"],
		["rest", "turn", "rise"], ["rise", "turn", "rest"],
		["rise", "rest", "turn"], ["rest", "rise", "turn"]
	]:
		_permutation(song)
	_reset_preserves_discoveries()
	_undo_and_reload()
	_rest_is_not_a_new_goal_gate()
	_original_route()
	_report()

func _report() -> void:
	print(JSON.stringify({"suite": "native-rain-song-rules", "baselineCommit": BASELINE_COMMIT, "baselineSha256": BASELINE_SHA256, "checks": checks, "comparisons": comparisons, "passed": failures.is_empty(), "failures": failures, "gpuPixelsVerified": false, "scope": "Per-operation compatibility against checksum-verified pre-2-3 HEAD: results, commands, snapshots, geometry, readiness and undo availability; six phrases, original 27 commands, existing pause/edit/end/reset semantics and retained discoveries. No new mechanic restrictions or damaged-trial repair."}))
	quit(0 if failures.is_empty() else 1)

func _load_baseline() -> bool:
	# Immutable UTF-8 fixture exported from BASELINE_COMMIT with binary Git
	# stdout. Never compare current production source against itself: unrelated
	# feedback edits must not either invalidate or silently update this baseline.
	var source := FileAccess.get_file_as_string("res://tests/fixtures/garden_world_5059b55a.gd.txt").replace("\r\n", "\n")
	var matches_baseline := source.sha256_text() == BASELINE_SHA256
	_check(matches_baseline, "UTF-8 source exactly matches immutable HEAD checksum after newline normalization")
	if not matches_baseline: return false
	_check(source.begins_with("class_name GardenWorld"), "baseline is the actual GardenWorld source")
	if not source.begins_with("class_name GardenWorld"): return false
	# Remove only the global registration, retaining every rule and fork path.
	baseline_script = GDScript.new()
	baseline_script.source_code = source.substr(source.find("\n") + 1)
	var parse_result := baseline_script.reload()
	_check(parse_result == OK, "independent HEAD source compiles without a second global class registration")
	return parse_result == OK

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			if key == "trial" and value[key] is String and not str(value[key]).is_empty():
				result[key] = _canonical(JSON.parse_string(value[key]))
			else:
				result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_canonical(item))
		return result
	return value

func _same(actual: Variant, expected: Variant, label: String) -> void:
	_check(Snapshot.equivalent(_canonical(actual), _canonical(expected)), label)

func _observe(world: RefCounted) -> Dictionary:
	return {"snapshot": world.snapshot(), "commands": world.commands(), "tiles": world.tiles(), "ready": world.ready(), "together": world.together(), "canUndo": world.can_undo(), "northRoute": world.path_to("f:0:-4", "luvie")}

func _pair(saved: Dictionary = {}) -> Dictionary:
	var pair := {"current": World.new("2-3", saved), "baseline": baseline_script.new("2-3", saved)}
	_compare(pair, "initial compatible state")
	return pair

func _compare(pair: Dictionary, label: String) -> void:
	comparisons += 1
	_same(_observe(pair.current), _observe(pair.baseline), label + " matches HEAD state, commands and geometry")

func _act(pair: Dictionary, id: String, quiet := false) -> Dictionary:
	var actual: Dictionary = pair.current.act(id, quiet)
	var expected: Dictionary = pair.baseline.act(id, quiet)
	_same(actual, expected, id + " result matches HEAD")
	_compare(pair, id)
	return actual

func _go(pair: Dictionary, tile: String) -> void:
	var route: Array = pair.current.path_to(tile)
	_same(route, pair.baseline.path_to(tile), "path to " + tile + " matches HEAD")
	_check(not route.is_empty() or str(pair.current.state.actors[pair.current.actor()]) == tile, "legal route exists to " + tile)
	for step: String in route:
		var actual: Dictionary = pair.current.move(step)
		_same(actual, pair.baseline.move(step), "step result to " + step + " matches HEAD")
		_check(actual.ok, "legal step to " + step)
		_compare(pair, "move " + step)

func _aboard() -> Dictionary:
	var pair := _pair()
	_same(pair.current.state.song, ["turn", "rise", "rest"], "fresh default is the original valid phrase")
	_go(pair, "m:stage:0:0")
	_check(_act(pair, "switch").ok, "switch to pianist while passenger stays aboard")
	_go(pair, "f:-4:0")
	return pair

func _arrange(pair: Dictionary, song: Array) -> void:
	for index in range(song.size()):
		var at: int = pair.current.state.song.find(song[index])
		while at > index:
			_check(_act(pair, "swap:" + str(at - 1)).ok, "adjacent edits preserve the original phrase controls")
			at -= 1
	_same(pair.current.state.song, song, "chosen permutation is retained")

func _reload(pair: Dictionary) -> void:
	pair.current = World.new("2-3", pair.current.snapshot())
	pair.baseline = baseline_script.new("2-3", pair.baseline.snapshot())
	_compare(pair, "legal snapshot reload")

func _zero_beat_edit_compatibility() -> void:
	var pair := _aboard()
	var original: Dictionary = pair.current.snapshot()
	_check(_act(pair, "play").ok and pair.current.state.playing, "original start records a zero-beat trial")
	_check(_act(pair, "play").ok and not pair.current.state.playing, "original pause before the first beat")
	_check(_act(pair, "swap:0").ok, "original zero-beat paused trial permits editing")
	_check(_act(pair, "swap:1").ok, "original second adjacent edit remains available")
	_reload(pair)
	_check(_act(pair, "resetSong").ok, "original zero-beat reset remains available")
	_same(pair.current.snapshot(), original, "reset preserves the original trial-origin phrase behavior")
	_check(_act(pair, "swap:0").ok, "original reset allows subsequent editing")

func _permutation(song: Array) -> void:
	var pair := _aboard()
	_arrange(pair, song)
	var original: Dictionary = pair.current.snapshot()
	var label := "%s/%s/%s" % song
	for index in range(3):
		var before: Dictionary = pair.current.snapshot()
		var result := _act(pair, "beat")
		_check(result.ok and int(pair.current.state.beat) == index + 1, label + " consumes the original next beat")
		if str(song[index]) == "rest":
			_same(pair.current.state.turns, before.turns, label + " rest preserves orientation")
			_same(pair.current.state.flags, before.flags, label + " rest preserves elevation and latch")
		elif str(song[index]) == "turn" and "raised" in before.flags:
			_same(pair.current.state.turns, before.turns, label + " raised turn retains the original mechanical stop")
			_check(str(result.message).contains("限位"), label + " blocked turn remains an accepted consumed beat")
	_check(pair.current.has_path_to("f:0:-4", "luvie") == (song.find("turn") < song.find("rise")), label + " retains original causal reachability")
	_check(not pair.current.flag("latch") and not pair.current.ready(), label + " rehearsal does not itself fix the bridge or win")
	# Existing end controls are intentionally retained, including play's toggle
	# and the following beat's accepted completed-phrase stop.
	_check(_act(pair, "play").ok and pair.current.state.playing, label + " original end play toggles playback")
	_check(_act(pair, "beat", true).ok and not pair.current.state.playing, label + " original internal beat stops an exhausted phrase")
	_check(_act(pair, "beat").ok, label + " original manual exhausted beat remains an accepted response")
	_check(_act(pair, "resetSong").ok, label + " original reset remains available")
	_same(pair.current.snapshot(), original, label + " reset restores the actual chosen rehearsal origin")

func _reset_preserves_discoveries() -> void:
	var pair := _aboard()
	var origin: Dictionary = pair.current.snapshot()
	_check(_act(pair, "beat").ok, "discovery recovery begins an original trial")
	_go(pair, "f:-5:-1")
	_check(_act(pair, "observe:rest").ok, "trial records an optional observation")
	var found: Array = pair.current.state.collected.duplicate()
	var observations: Array = pair.current.state.observations.duplicate()
	_check(found.size() > origin.collected.size() and observations.has("rest"), "new optional discoveries exist")
	_reload(pair)
	_check(_act(pair, "resetSong").ok, "legal reloaded rehearsal resets")
	_same(pair.current.state.actors, origin.actors, "original reset restores passengers")
	_same(pair.current.state.turns, origin.turns, "original reset restores platform orientation")
	_same(pair.current.state.flags, origin.flags, "original reset restores elevation and flags")
	_same(pair.current.state.collected, found, "original reset retains new collections")
	_same(pair.current.state.observations, observations, "original reset retains observations")
	var restored: Dictionary = pair.current.snapshot()
	_check(_act(pair, "resetSong").ok, "original repeated reset remains harmless")
	_same(pair.current.snapshot(), restored, "reset does not duplicate discoveries")

func _session_pair(saved: Dictionary) -> Dictionary:
	var current := Session.new("2-3", saved)
	var baseline := Session.new("2-3", saved)
	baseline.world = baseline_script.new("2-3", saved)
	return {"current": current, "baseline": baseline}

func _session_apply(pair: Dictionary, command: RefCounted) -> RefCounted:
	var actual: RefCounted = pair.current.apply(command)
	var expected: RefCounted = pair.baseline.apply(command)
	_same({"accepted": actual.accepted, "changed": actual.changed, "message": actual.message, "before": actual.before, "after": actual.after, "revision": actual.revision}, {"accepted": expected.accepted, "changed": expected.changed, "message": expected.message, "before": expected.before, "after": expected.after, "revision": expected.revision}, "session operation matches HEAD semantics")
	_compare({"current": pair.current.world, "baseline": pair.baseline.world}, "session operation")
	return actual

func _undo_and_reload() -> void:
	var worlds := _aboard()
	var pair := _session_pair(worlds.current.snapshot())
	_check(_session_apply(pair, Command.interact("play")).accepted, "session starts original automatic rehearsal")
	var started: Dictionary = pair.current.world.snapshot()
	_check(_session_apply(pair, Command.interact("beat")).accepted, "original automatic internal beat is permitted")
	_check(_session_apply(pair, Command.undo_action()).accepted, "undo restores pre-beat trial")
	started.playing = false
	_same(pair.current.world.snapshot(), started, "original undo explicitly pauses rehearsal")
	_check(_session_apply(pair, Command.interact("swap:0")).accepted, "original undo to zero beats permits editing")
	pair = _session_pair(pair.current.world.snapshot())
	_check(not _session_apply(pair, Command.undo_action()).accepted, "reload invents no undo history")
	_check(_session_apply(pair, Command.interact("resetSong")).accepted, "original reloaded trial resets")
	_check(_session_apply(pair, Command.interact("swap:0")).accepted, "original reset restores editing")
	_check(_session_apply(pair, Command.undo_action()).accepted, "undo reverses the new edit")
	_same(pair.current.world.state.song, ["turn", "rise", "rest"], "undo restores the original phrase")

func _rest_is_not_a_new_goal_gate() -> void:
	var pair := _aboard()
	_check(_act(pair, "beat").ok and _act(pair, "beat").ok, "original two spatial actions establish north landing")
	_check(_act(pair, "switch").ok, "switch to passenger")
	_go(pair, "f:0:-4")
	_check(_act(pair, "use:latch").ok, "original latch action creates reunion route")
	_check(_act(pair, "switch").ok, "switch back to pianist")
	_go(pair, "f:1:-4")
	_check(_act(pair, "switch").ok, "return to gardener")
	_check(int(pair.current.state.beat) == 2 and pair.current.ready(), "original rest is not a new goal gate")
	_check(_act(pair, "repair").ok and pair.current.state.completed, "original latch/together completion remains valid")

func _original_route() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in fixture.cases:
		if str(entry.name) != "authored/2-3": continue
		var pair := _pair(entry.initial.snapshot)
		_check(entry.steps.size() == 27, "original route retains all 27 atomic commands")
		for step: Dictionary in entry.steps:
			if str(step.command.kind) == "move":
				var actual: Dictionary = pair.current.move(str(step.command.value))
				_same(actual, pair.baseline.move(str(step.command.value)), "original route movement result matches HEAD")
				_check(actual.ok, "original route movement accepted")
				_compare(pair, "original route movement")
			else:
				_check(_act(pair, str(step.command.value)).ok, "original route action accepted")
			_same(pair.current.snapshot(), step.snapshot, "frozen original route snapshot unchanged")
		_check(pair.current.state.completed, "original route still completes")
		return
	_check(false, "original authored 2-3 fixture exists")
