class_name GardenInputRouter
extends RefCounted

const DIRECTIONS := {
	KEY_UP: "up", KEY_W: "up", KEY_RIGHT: "right", KEY_D: "right",
	KEY_DOWN: "down", KEY_S: "down", KEY_LEFT: "left", KEY_A: "left"
}
const OFFSETS := {"up": Vector2i(0, -1), "right": Vector2i(1, 0), "down": Vector2i(0, 1), "left": Vector2i(-1, 0)}
const BUFFER_SECONDS: float = 0.16

var continuous: bool = false
var held: Array[String] = []
var buffered_direction: String = ""
var buffer_remaining: float = 0.0
var _pressed_codes: Dictionary = {}
var _blocked_held: String = ""

func handle_key(event: InputEventKey) -> String:
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var direction: String = str(DIRECTIONS.get(code, ""))
	if direction.is_empty():
		return ""
	if not event.pressed:
		_pressed_codes.erase(code)
		if not direction in _pressed_codes.values():
			held.erase(direction)
			if _blocked_held == direction:
				_blocked_held = ""
		return ""
	# Echo must not rearm a held key after pause/focus loss, nor refresh a tap's lifetime.
	if event.echo:
		return ""
	_pressed_codes[code] = direction
	held.erase(direction)
	held.append(direction)
	_blocked_held = ""
	return direction

func buffer(direction: String) -> void:
	# One explicit intent, independent of the optional hold-to-walk setting.
	buffered_direction = direction
	buffer_remaining = BUFFER_SECONDS

func advance(delta: float) -> void:
	if buffered_direction.is_empty():
		return
	buffer_remaining = maxf(0.0, buffer_remaining - maxf(0.0, delta))
	if buffer_remaining <= 0.0:
		discard_buffer()

func discard_buffer() -> void:
	buffered_direction = ""
	buffer_remaining = 0.0

func suppress_held(direction: String) -> void:
	_blocked_held = direction

func world_changed() -> void:
	# A mechanism may have opened the formerly blocked neighboring tile.
	_blocked_held = ""

func take_next() -> String:
	if not buffered_direction.is_empty():
		var result: String = buffered_direction
		discard_buffer()
		return result
	if continuous and not held.is_empty() and held.back() != _blocked_held:
		return held.back()
	return ""

func clear() -> void:
	held.clear()
	_pressed_codes.clear()
	_blocked_held = ""
	discard_buffer()

