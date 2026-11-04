class_name GardenJourney
extends RefCounted

static func describe(world: RefCounted) -> Dictionary:
	var state: Dictionary = world.state
	var steps: Array = []
	match str(world.level.id):
		"1-1", "1-2":
			_add(steps, state, "接通根路", world.connected())
		"1-3":
			_add(steps, state, "转庭接北岸", world.has_path_to("f:0:-4", "luvie"))
		"1-4":
			_add(steps, state, "固定归途", world.flag("latch"))
			_add(steps, state, "归还门铃", world.flag("home"))
		"2-1":
			_add(steps, state, "清露养睡莲", world.flag("care"))
			_add(steps, state, "中水位靠岸", state.water == 1)
		"2-2":
			_add(steps, state, "镜叶入槽", state.items.mirrorB.get("tile", "") == "f:1:0")
			_add(steps, state, "光照花床", world.beam_hits(4, 0))
		"2-3":
			_add(steps, state, "转庭后升台", world.flag("raised") and state.turns.stage == 1)
			_add(steps, state, "固定便道", world.flag("latch"))
		"2-4":
			_add(steps, state, "种下蜜花", world.flag("plant"))
			_add(steps, state, "载光虫授粉", world.flag("pollinated"))
		"3-1":
			_add(steps, state, "照亮石窗", world.flag("window"))
			_add(steps, state, "随身带暖灯", not str(state.items.lamp.get("holder", "")).is_empty())
		"3-2":
			_add(steps, state, "安放日月柱", state.items.sunPost.get("tile", "") == "f:0:0" and state.items.moonPost.get("tile", "") == "f:3:-1")
			_add(steps, state, "两段影路相接", world.ready() and world.has_path_to("f:3:4", "luvie"))
		"3-3":
			_add(steps, state, "藤根学会蓄水", world.flag("root"))
			_add(steps, state, "分水托起花台", state.turns.water == 1 and state.turns.lift == 1)
		"3-4":
			_add(steps, state, "固定叶阶", world.flag("root"))
			_add(steps, state, "水托花台", world.flag("rain") and state.turns.water == 1)
			_add(steps, state, "光回到家", world.flag("star") and world.beam_hits(-4, 0))
			_add(steps, state, "接通归途", state.turns.inner == 1)
	var core: Dictionary = {}
	for mark in world.level.marks:
		if str(mark.kind) == "core":
			core = mark
			break
	var prerequisites: bool = _all_done(steps)
	_add(steps, state, "两位到花床" if world.level.get("dual", false) else "抵达花床",
		prerequisites and world.near(str(core.get("tile", "")), "luvie") and world.together())
	_add(steps, state, "种下微光", bool(state.completed))
	var current: int = -1
	var done: int = 0
	for index in steps.size():
		if steps[index].done:
			done += 1
		elif current < 0:
			current = index
	var next: String
	if bool(state.completed):
		next = str(world.level.story)
	elif world.ready() and prerequisites:
		if not world.near(str(core.get("tile", "")), "luvie"):
			next = "道路已准备好，带着伙伴前往核心花床。"
		elif world.together():
			next = "花床已准备好，点击「一起种下微光」完成修复。"
		else:
			next = "伙伴还没到身边。开启同行等它跟上，或换手带它回来。"
	else:
		next = str(world.hint().get("message", ""))
	return {"steps": steps, "current": current, "done": done, "total": steps.size(), "next": next}

static func _add(steps: Array, state: Dictionary, label: String, complete: bool) -> void:
	steps.append({"label": label, "done": bool(state.completed) or complete})

static func _all_done(steps: Array) -> bool:
	for step in steps:
		if not step.done:
			return false
	return true

