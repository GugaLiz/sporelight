class_name GardenInputRouter
extends RefCounted

const DIRECTIONS := {
	KEY_UP: "up", KEY_W: "up", KEY_RIGHT: "right", KEY_D: "right",
	KEY_DOWN: "down", KEY_S: "down", KEY_LEFT: "left", KEY_A: "left"
}
const OFFSETS := {"up": Vector2i(0, -1), "right": Vector2i(1, 0), "down": Vector2i(0, 1), "left": Vector2i(-1, 0)}
const BUFFER_SECONDS: float = 0.16

var continuous: bool = true
var held: Array[String] = []
var buffered_direction: String = ""
var buffer_remaining: float = 0.0
var _pressed_codes: Dictionary = {}
var _blocked_held: String = ""
var _pad_neutral_required := false

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
	# Keep a deliberate direction change while the current segment completes.
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
	_pad_neutral_required = true

func movement_vector() -> Vector2:
	var result := Vector2.ZERO
	for direction: String in held:
		var offset: Vector2i = OFFSETS[direction]
		result += Vector2(offset)
	if InputMap.has_action("native_pad_left"):
		var pad := Input.get_vector("native_pad_left", "native_pad_right", "native_pad_up", "native_pad_down", 0.2)
		if _pad_neutral_required:
			if pad.is_zero_approx():
				_pad_neutral_required = false
		else:
			result += pad
	return result.normalized() if result.length_squared() > 1.0 else result

static func install_native_actions() -> void:
	# Exported projects can have keyboard-only default UI bindings. Explicitly
	# map the same pad vocabulary to GUI navigation before world shortcuts.
	for definition: Array in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B], ["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT], ["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN]]:
		var action := str(definition[0])
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ui_button := InputEventJoypadButton.new()
		ui_button.button_index = int(definition[1])
		if not InputMap.action_has_event(action, ui_button):
			InputMap.action_add_event(action, ui_button)
	for definition: Array in [["native_pad_left", JOY_AXIS_LEFT_X, -1.0], ["native_pad_right", JOY_AXIS_LEFT_X, 1.0], ["native_pad_up", JOY_AXIS_LEFT_Y, -1.0], ["native_pad_down", JOY_AXIS_LEFT_Y, 1.0]]:
		if not InputMap.has_action(str(definition[0])):
			InputMap.add_action(str(definition[0]), 0.2)
			var axis := InputEventJoypadMotion.new()
			axis.axis = int(definition[1])
			axis.axis_value = float(definition[2])
			InputMap.action_add_event(str(definition[0]), axis)
		var ui_action := str({"native_pad_left": "ui_left", "native_pad_right": "ui_right", "native_pad_up": "ui_up", "native_pad_down": "ui_down"}[str(definition[0])])
		var ui_axis := InputEventJoypadMotion.new()
		ui_axis.axis = int(definition[1])
		ui_axis.axis_value = float(definition[2])
		if not InputMap.action_has_event(ui_action, ui_axis):
			InputMap.action_add_event(ui_action, ui_axis)
	for definition: Array in [["native_interact", JOY_BUTTON_A], ["native_switch", JOY_BUTTON_Y], ["native_undo", JOY_BUTTON_X], ["native_pause", JOY_BUTTON_START]]:
		if not InputMap.has_action(str(definition[0])):
			InputMap.add_action(str(definition[0]))
			var button := InputEventJoypadButton.new()
			button.button_index = int(definition[1])
			InputMap.action_add_event(str(definition[0]), button)

