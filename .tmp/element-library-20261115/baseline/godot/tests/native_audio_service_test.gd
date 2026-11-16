extends SceneTree

# Exercise the actual service and imported audio, never AudioStub.
const AudioService = preload("res://services/audio_service.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func _wait_wall_msec(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _dispose_audio(audio: Node) -> void:
	# Stop mixer playback and release imported streams before freeing the fixture.
	# Quitting in the same frame as queue_free leaves the paused fixture alive.
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	audio._streams.clear()
	await _wait_wall_msec(150)
	audio.queue_free()
	await process_frame
	await _wait_wall_msec(150)


func _run() -> void:
	var audio := AudioService.new()
	root.add_child(audio)
	_check(audio.get_child_count() == 8, "one music, one ambience and six bounded effect voices")
	_check(not audio._started and not audio._music.playing and not audio._ambient.playing, "setup does not autoplay")
	_check(not audio.play("tap"), "cues require first gesture")
	_check(audio._music.stream is AudioStreamOggVorbis, "compressed original score is selected")
	_check(audio._ambient.stream is AudioStreamOggVorbis, "non-pitched ambience is selected")
	_check(is_equal_approx(audio._music.stream.get_length(), 112.0), "score contains both complete 14-bar phrases")
	_check(is_equal_approx(audio._ambient.stream.get_length(), 32.0), "air layer contains the full separate period")
	_check(audio._music.stream.loop and audio._ambient.stream.loop, "both imported Ogg tracks loop")
	_check(audio._streams.size() == 10, "all ten short cues are cached before interaction")
	audio.start()
	_check(audio._started and audio._music.playing and audio._ambient.playing, "first gesture starts both loops")
	audio._music.seek(17.0)
	audio.start()
	_check(audio.get_child_count() == 8 and audio._music.get_playback_position() >= 16.9, "repeated start neither creates players nor restarts score")
	_check(audio.play("tap"), "tap cue plays")
	var voices := audio._next_effect
	_check(not audio.play("tick") and not audio.play("滴") and audio._next_effect == voices, "aliases share the same coalescing cooldown")
	_check(audio.play("turn"), "a different semantic cue remains available")
	_check(not audio.play("unknown") and audio._next_effect == voices + 1, "unknown cue never steals a voice")
	await _wait_wall_msec(100)
	_check(audio.play("tap"), "cue is available again after its short cooldown")
	audio.pause(true)
	var position := audio._music.get_playback_position()
	_check(audio._music.stream_paused and audio._ambient.stream_paused, "pause retains both loop transports")
	for effect in audio._effects:
		_check(not effect.playing, "pause clears transient cue tails")
	_check(not audio.play("grow"), "paused gameplay remains silent")
	audio.configure({"bgm": 2.0, "ambient": -1.0, "sfx": 0.0})
	_check(is_equal_approx(audio._music.volume_linear, 1.0) and is_zero_approx(audio._ambient.volume_linear), "settings clamp all loop levels")
	_check(audio._music.stream_paused and audio._music.get_playback_position() >= position - 0.05, "configure does not unpause or restart loops")
	audio.start()
	_check(audio._music.stream_paused, "a repeated gesture cannot bypass pause")
	audio.pause(false)
	voices = audio._next_effect
	_check(not audio.play("move") and audio._next_effect == voices, "muted effects do not consume a voice")
	audio.configure({"bgm": 0.35, "ambient": 0.25, "sfx": 0.6})
	_check(is_equal_approx(audio._ambient.volume_linear, 0.1625), "air stays below the independent ambient setting")
	_check(audio.play("move") and not audio.play("move"), "simultaneous character footsteps coalesce")
	audio._music.seek(111.95)
	await _wait_wall_msec(250)
	_check(audio._music.playing, "score continues playing across the Ogg loop boundary")
	_check(audio._music.get_playback_position() < 1.0, "score transport wraps to its opening phrase")
	await _dispose_audio(audio)
	var prepaused := AudioService.new()
	prepaused.pause(true)
	root.add_child(prepaused)
	prepaused.start()
	_check(prepaused._music.stream_paused, "start also respects a pause requested before ready")
	await _dispose_audio(prepaused)
	print(JSON.stringify({"suite": "native_audio_service", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
