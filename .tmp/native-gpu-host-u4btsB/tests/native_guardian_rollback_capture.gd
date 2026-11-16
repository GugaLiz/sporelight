extends "res://tests/native_guardian_capture.gd"
## The restored authored route runs in the non-focusable GPU test host.
func _start() -> bool:
	var settled: bool = await super._start()
	app.view._resize()
	app._update_layout()
	return settled

func _capture(label: String) -> void:
	await super._capture(label)
	_check(app.view._viewport.size == dimensions, label + " native viewport matches output")
	var pixels: Image = app.view._viewport.get_texture().get_image()
	var visible := 0
	for y in range(0, pixels.get_height(), 20):
		for x in range(0, pixels.get_width(), 20):
			if pixels.get_pixel(x, y).a > .1: visible += 1
	_check(visible > 40, label + " actual world pixels are present")
