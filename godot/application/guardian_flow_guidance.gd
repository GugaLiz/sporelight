extends RefCounted
## Current intentions and object names, never commands or puzzle solutions.
## Historical gifts remain distinct from the live connections needed at home.

static func describe(world: Variant, world_tiles: Array = []) -> Dictionary:
	if world == null or str(world.level.id) != "3-4": return {}
	var board: Array = world_tiles if not world_tiles.is_empty() else world.tiles()
	var state: Dictionary = world.state
	var active := str(state.get("active", "luvie"))
	var hero: Dictionary = world.point_for(str(state.actors.luvie), board)
	var buddy: Dictionary = world.point_for(str(state.actors.buddy), board)
	var result := {
		"phase": "", "goal": "", "target": "",
		"near_core_luvie": world.near("f:-4:0", "luvie", board),
		"near_core_buddy": world.near("f:-4:0", "buddy", board),
		"hero_high": not hero.is_empty() and float(hero.h) >= 2.0,
		"buddy_high": not buddy.is_empty() and float(buddy.h) >= 2.0,
		"lift_raised": int(state.turns.get("lift", 0)) % 2 == 1,
		"root_fixed": world.flag("root"),
		"water_current": int(state.turns.get("water", 0)) == 1,
		"water_stored": world.flag("rain"),
		"light_current": world.beam_hits(-4, 0),
		"inner_current": int(state.turns.get("inner", 0)) == 1,
		"together": world.together(board),
		"ready": world.ready(board),
		"completed": bool(state.get("completed", false))
	}
	if result.completed:
		return _phase(result, "complete", "守护者已苏醒，花园恢复了生机。", "")
	if not result.root_fixed:
		return _phase(result, "root", "接通根路，让露薇能把镜子带向高处。", "root")
	if not world.flag("rain"):
		return _phase(result, "water", "让小苔灵接通水渠，灌满升降台储水罐。", "water")
	if not world.flag("star"):
		var mirror: Dictionary = state.items.get("mirror", {})
		if str(mirror.get("tile", "")) != "f:8:0" or not str(mirror.get("holder", "")).is_empty():
			var goal := "切换露薇，把镜子运上高处。" if active == "buddy" else "把镜子运上高处，放进岸边的镜座。"
			return _phase(result, "mirror", goal, "highslot")
		var goal := "切换露薇，调整灯台和镜子接光。" if active == "buddy" else "调整灯台和镜子，让光照到起点花坛。"
		return _phase(result, "light", goal, "light")
	if not result.light_current:
		return _phase(result, "restore_light", "花坛的光断了，重新接好灯台与镜子。", "light")
	if result.hero_high or result.buddy_high:
		if result.lift_raised:
			var goal := "光已送达，乘升降台返回起点花坛。" if result.hero_high else "伙伴还在高处，让它乘升降台返回。"
			if result.hero_high and not result.buddy_high and active == "buddy":
				goal = "切换露薇，乘升降台返回起点花坛。"
			elif result.buddy_high and not result.hero_high and active == "luvie":
				goal = "切换小苔灵，乘升降台返回花坛。"
			return _phase(result, "return_lift", goal, "lift")
		var rescue := "升降台在下层，让小苔灵升台接人。" if result.hero_high else "伙伴还在高处，让露薇升台接它。"
		if result.hero_high and result.buddy_high:
			rescue = "两人留在高处，撤销降台后再一起乘台。"
		return _phase(result, "rescue_lift", rescue, "lift")
	if not result.near_core_luvie:
		if not world.has_path_to("f:-4:0", "luvie"):
			return _phase(result, "return_inner", "转动中央庭院，接上返回花坛的路。", "inner")
		return _phase(result, "reunion", "归途已经接好，让露薇回到起点花坛。", "core")
	if not result.near_core_buddy:
		if not world.has_path_to("f:-4:0", "buddy"):
			return _phase(result, "return_companion", "接回伙伴脚下的路，再回花坛会合。", "water" if str(state.actors.buddy).begins_with("m:water:") else "inner")
		return _phase(result, "reunion", "露薇已回到花坛，接小苔灵回来会合。", "core")
	if not result.together:
		return _phase(result, "reunion", "两人都在花坛附近，再靠近彼此会合。", "core")
	if result.ready:
		return _phase(result, "care", "两人已会合，让露薇照料花坛。", "core")
	return _phase(result, "reunion", "两人在花坛旁会合，一起照料它。", "core")

static func _phase(state: Dictionary, phase: String, goal: String, target: String) -> Dictionary:
	state.phase = phase
	state.goal = goal
	state.target = target
	return state

static func command_label(world: Variant, id: String, fallback: String) -> String:
	if world == null or str(world.level.id) != "3-4": return fallback
	match id:
		"valve:lift": return "降下升降台 ↓" if int(world.state.turns.get("lift", 0)) % 2 else "升起升降台 ↑"
		"turn:inner": return "转动中央庭院 ↻"
		"turn:light": return "转动灯台 ↻"
		"valve:water": return "转动引水台 ↻"
		"repair": return "一起照料花坛 ✧"
	return fallback

static func gift_tooltip() -> String:
	return "根路接通、首次供水、首次接光、花坛会合，各得到两份赠礼；无需另找收藏。"
