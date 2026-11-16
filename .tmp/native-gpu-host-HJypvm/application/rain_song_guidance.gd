extends RefCounted
## Read-only piano notation. This module never selects, hides or runs actions.

const NAMES := {"turn": "转庭", "rise": "升台", "rest": "歇一拍"}

static func applies(world: Variant) -> bool:
	return world != null and str(world.level.id) == "2-3"

static func has_trial(world: Variant) -> bool:
	return applies(world) and not str(world.state.get("trial", "")).is_empty()

static func is_song_action(id: String) -> bool:
	return id in ["play", "beat", "resetSong"] or id.begins_with("swap:")

static func note(world: Variant, index: int) -> String:
	var song: Array = world.state.get("song", [])
	return str(NAMES.get(str(song[index]), "动作")) if index >= 0 and index < song.size() else ""

static func progress(world: Variant) -> String:
	var beat := clampi(int(world.state.get("beat", 0)), 0, 3)
	return "已执行 %d/3 · %s" % [beat, "试奏中" if bool(world.state.get("playing", false)) else "未播放"]

static func sequence(world: Variant) -> String:
	var labels: Array[String] = []
	var beat := clampi(int(world.state.get("beat", 0)), 0, 3)
	for index in range(3):
		labels.append("%s%d %s" % ["✓" if index < beat else "", index + 1, note(world, index)])
	return "   ".join(labels)

static func last_effect(world: Variant) -> String:
	var beat := clampi(int(world.state.get("beat", 0)), 0, 3)
	if beat == 0: return "尚无执行记录。"
	var last := str(world.state.song[beat - 1])
	var raised_before := false
	var trial: Variant = JSON.parse_string(str(world.state.trial)) if has_trial(world) else null
	if trial is Dictionary: raised_before = "raised" in trial.get("flags", [])
	for index in range(beat - 1):
		if str(world.state.song[index]) == "rise": raised_before = true
	var result := "保持原位" if last == "rest" else "花台已升起" if last == "rise" else "高处限位，花台未转动" if raised_before else "花台已转动90°"
	return "第%d拍 · %s：%s。" % [beat, str(NAMES.get(last, "动作")), result]

static func summary(world: Variant) -> String:
	return sequence(world) + "\n" + progress(world) + "\n" + last_effect(world)
