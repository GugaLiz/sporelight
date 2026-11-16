class_name GardenMoleConversation
extends RefCounted

var _stage := ""
var _was_near := false
var _until := 0.0
var _next_greeting := 0.0
var _text := ""

static func dialogue(state: Dictionary) -> Dictionary:
	var flags: Array = state.get("flags", [])
	if state.get("completed", false):
		return {"stage": "restored", "text": "花开啦，连蝴蝶都来做客了。以后也常来坐坐呀。"}
	if "home" in flags:
		return {"stage": "welcome", "text": "谢谢你们！花门开了，带上小伙伴去喷泉边看看吧。"}
	if not str(state.get("items", {}).get("bell", {}).get("holder", "")).is_empty():
		return {"stage": "bell", "text": "咦，是我的小门铃！我认得这声轻轻的叮铃。"}
	if "latch" in flags:
		return {"stage": "latch", "text": "回来的路修好啦。门铃好像落在那边的石台上了……"}
	if "hold" in flags:
		return {"stage": "help", "text": "你们配合得真好！小拱道就拜托小苔灵啦。"}
	return {"stage": "lost", "text": "雨把我的门铃吹跑了……你们愿意帮我找找吗？"}

func update(state: Dictionary, near: bool, time: float) -> String:
	if not near:
		_was_near = false
		return ""
	var current := dialogue(state)
	if current.stage != _stage or not _was_near and time >= _next_greeting:
		_stage = current.stage
		_text = current.text
		_until = time + 8000
		_next_greeting = time + 20000
	_was_near = true
	return _text if time < _until else ""
