extends Node
class_name GardenAudioService

const SOUND_ALIASES := {"滴": "tap", "tick": "tap", "叮": "chime", "咚": "rest", "thump": "rest"}
const CUES := {
	"move": {"file": "soft-step", "cooldown": 0.13, "gain": 0.40},
	"tap": {"file": "leaf-tap", "cooldown": 0.08, "gain": 0.34},
	"turn": {"file": "leaf-turn", "cooldown": 0.18, "gain": 0.48},
	"rise": {"file": "leaf-rise", "cooldown": 0.18, "gain": 0.48},
	"rest": {"file": "leaf-rest", "cooldown": 0.18, "gain": 0.34},
	"latch": {"file": "soft-latch", "cooldown": 0.20, "gain": 0.50},
	"grow": {"file": "soft-grow", "cooldown": 0.12, "gain": 0.50},
	"collect": {"file": "soft-collect", "cooldown": 0.12, "gain": 0.52},
	"complete": {"file": "soft-complete", "cooldown": 0.40, "gain": 0.58},
	"chime": {"file": "soft-chime", "cooldown": 0.25, "gain": 0.38},
}
const AMBIENT_TRIM := 0.65
var _settings: Dictionary = {}
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _effects: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_cue_ms: Dictionary = {}
var _next_effect := 0
var _started := false
var _paused := false


func _ready() -> void:
	_music = _player("Music")
	_ambient = _player("Ambient")
	for index in 6:
		_effects.append(_player("Effect%s" % index))
	# Cache short cues at setup; interaction never imports a sound from disk.
	for cue in CUES.values():
		var resource := "res://assets/audio/%s.wav" % String(cue["file"])
		if ResourceLoader.exists(resource):
			_streams[String(cue["file"])] = load(resource)
	_music.stream = _loop_stream(["garden-dawn.ogg", "garden-dawn.wav", "music.wav"])
	_ambient.stream = _loop_stream(["garden-air.ogg", "garden-air.wav", "ambient.wav"])
	configure(_settings)


# Call from the first player gesture; do not autoplay from startup.
func start() -> void:
	if _music == null or _started:
		return
	_started = true
	if _music.stream != null:
		_music.play()
	if _ambient.stream != null:
		_ambient.play()
	_music.stream_paused = _paused
	_ambient.stream_paused = _paused


func configure(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	for key in ["bgm", "ambient", "sfx"]:
		_settings[key] = clampf(float(_settings.get(key, {"bgm": 0.35, "ambient": 0.25, "sfx": 0.6}[key])), 0.0, 1.0)
	if _music == null:
		return
	_music.volume_linear = float(_settings["bgm"])
	_ambient.volume_linear = float(_settings["ambient"]) * AMBIENT_TRIM
	for effect in _effects:
		effect.volume_linear = float(_settings["sfx"]) * float(effect.get_meta("cue_gain", 1.0))


func play(kind: String) -> bool:
	if not _started or _paused or _effects.is_empty() or float(_settings.get("sfx", 0.6)) <= 0.0:
		return false
	var cue_name := String(SOUND_ALIASES.get(kind, kind))
	if not CUES.has(cue_name):
		return false
	var cue: Dictionary = CUES[cue_name]
	var now := Time.get_ticks_msec()
	if _last_cue_ms.has(cue_name) and now - int(_last_cue_ms[cue_name]) < float(cue["cooldown"]) * 1000.0:
		return false
	var stream: AudioStream = _streams.get(String(cue["file"]))
	if stream == null:
		return false
	_last_cue_ms[cue_name] = now
	var effect := _effects[_next_effect % _effects.size()]
	_next_effect += 1
	effect.stop()
	effect.set_meta("cue_gain", float(cue["gain"]))
	effect.volume_linear = float(_settings["sfx"]) * float(cue["gain"])
	effect.stream = stream
	effect.play()
	return true


func pause(value: bool) -> void:
	_paused = value
	if _music == null:
		return
	_music.stream_paused = value
	_ambient.stream_paused = value
	if value:
		for effect in _effects:
			effect.stop()
		_last_cue_ms.clear()


func _player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	add_child(player)
	return player


func _loop_stream(candidates: Array) -> AudioStream:
	for filename in candidates:
		var resource := "res://assets/audio/%s" % String(filename)
		if not ResourceLoader.exists(resource):
			continue
		var stream: AudioStream = load(resource)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
			stream.loop_offset = 0.0
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			# Actual frame count accounts for stereo and sample encoding.
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		return stream
	return null
