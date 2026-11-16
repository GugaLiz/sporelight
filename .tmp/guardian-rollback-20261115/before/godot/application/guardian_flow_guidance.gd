extends RefCounted
## Describe visible objects and the current local situation. The whole goal
## exists from the start; water and root building are independent preparations.

static func describe(world: Variant, world_tiles: Array = []) -> Dictionary:
	if world == null or str(world.level.id) != "3-4": return {}
	var board: Array = world_tiles if not world_tiles.is_empty() else world.tiles()
	var state: Dictionary = world.state
	var hero: Dictionary = world.point_for(str(state.actors.luvie), board)
	var buddy: Dictionary = world.point_for(str(state.actors.buddy), board)
	var result := {
		"phase":"prepare", "goal":"让石灯的光经过镜座，照到沉睡的花坛。", "target":"highslot",
		"near_core_luvie":world.near("f:-4:0","luvie",board),
		"near_core_buddy":world.near("f:-4:0","buddy",board),
		"hero_high":not hero.is_empty() and float(hero.h)>=2.0,
		"buddy_high":not buddy.is_empty() and float(buddy.h)>=2.0,
		"lift_raised":int(state.turns.lift)%2==1,
		"root_fixed":world.flag("root"), "water_current":int(state.turns.water)==1,
		"water_stored":world.flag("rain"), "light_current":world.beam_hits(-4,0),
		"inner_current":true, "together":world.together(board),
		"ready":world.ready(board), "completed":bool(state.completed)
	}
	if result.completed: return _phase(result,"complete","花坛苏醒了，两位一起留在花园里。","")
	if result.ready: return _phase(result,"care","光照着花坛，两位可以一起照料它了。","core")
	if result.light_current:
		if result.hero_high or result.buddy_high:
			return _phase(result,"return_lift" if result.lift_raised else "call_lift","光已经留在花坛上，沿原路回去会合。","lift" if result.lift_raised else "liftcall_high")
		return _phase(result,"reunion","光已经留在花坛上，两位回到花坛旁会合。","core")
	var mirror: Dictionary=state.items.mirror
	if str(mirror.tile)=="f:8:0" and str(mirror.get("holder",""))=="":
		return _phase(result,"reflect","镜子已经入座，看看光现在照向哪里。","highslot")
	if str(mirror.get("holder",""))=="luvie":
		if result.hero_high: return _phase(result,"place_mirror","空镜座就在高岸上。","highslot")
		if result.water_stored and result.root_fixed: return _phase(result,"carry_mirror","水池已蓄满，花台可以载镜子上高岸。","lift")
		return _phase(result,"prepare","镜子要乘花台上高岸，缺口和空水池都在眼前。","lift")
	return result

static func _phase(state: Dictionary, phase: String, goal: String, target: String) -> Dictionary:
	state.phase=phase; state.goal=goal; state.target=target
	return state

static func command_label(world: Variant, id: String, fallback: String) -> String:
	if world == null or str(world.level.id)!="3-4": return fallback
	match id:
		"valve:lift": return "降下升降台 ↓" if int(world.state.turns.lift)%2 else "升起升降台 ↑"
		"valve:water": return "关上引水闸" if int(world.state.turns.water)==1 else "打开引水闸"
		"call:lift": return "召回上层花台" if world.guardian_lift_call_station()=="f:7:0" else "召回下层花台"
		"repair": return "一起照料花坛 ✧"
	return fallback

static func gift_tooltip() -> String:
	return "根路、储水、接光与会合记录已保存。"
