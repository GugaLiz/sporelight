extends Node
class_name GardenAudioService

const SOUND_ALIASES := {"滴": "tick", "叮": "chime", "咚": "thump"}
var _settings: Dictionary = {}
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _effects: Array[AudioStreamPlayer] = []
var _next_effect := 0
var _started := false


func _ready() -> void:
	_music = _player("Music")
	_ambient = _player("Ambient")
	for index in 6:
		_effects.append(_player("Effect%s" % index))
	configure(_settings)


# Call from the first player gesture; do not autoplay from startup.
func start() -> void:
	if _music == null:
		return
	if not _started:
		_started = true
		_play_loop(_music, "music")
		_play_loop(_ambient, "ambient")
	pause(false)


func configure(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	if _music == null:
		return
	_music.volume_linear = clampf(float(_settings.get("bgm", 0.35)), 0, 1)
	_ambient.volume_linear = clampf(float(_settings.get("ambient", 0.25)), 0, 1)
	for effect in _effects:
		effect.volume_linear = clampf(float(_settings.get("sfx", 0.6)), 0, 1)


func play(kind: String) -> void:
	if not _started or _effects.is_empty():
		return
	var name := String(SOUND_ALIASES.get(kind, kind))
	var resource := "res://assets/audio/%s.wav" % name
	if not ResourceLoader.exists(resource):
		return
	var effect := _effects[_next_effect % _effects.size()]
	_next_effect += 1
	effect.stream = load(resource)
	effect.play()


func pause(value: bool) -> void:
	if _music == null:
		return
	_music.stream_paused = value
	_ambient.stream_paused = value
	for effect in _effects:
		effect.stream_paused = value


func _player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	add_child(player)
	return player


func _play_loop(player: AudioStreamPlayer, sound: String) -> void:
	var resource := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(resource):
		return
	var stream: AudioStreamWAV = load(resource)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	player.stream = stream
	player.play()
