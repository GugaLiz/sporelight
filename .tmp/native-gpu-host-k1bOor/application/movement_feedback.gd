extends RefCounted
## Read-only explanations shared by click, keyboard and touch movement.
static func blocked(world: RefCounted, target: String, fallback: String) -> String:
	if str(world.level.id) != "1-4": return fallback
	var tile: Dictionary = world.point_for(target)
	if world.actor() == "luvie" and bool(tile.get("small", false)):
		return "低拱只有小苔灵能通过。" + ("露薇可沿已固定的归途绕行。" if world.flag("latch") else "切换小苔灵来探索这边吧。")
	if not tile.is_empty() and float(tile.x) <= -6 and not world.flag("home"):
		return "花门还没有打开，先让露薇把门铃归还鼹鼠。"
	if not world.flag("latch"):
		if str(world.state.actors.buddy) == "f:3:5":
			return "这边没有直连道路。小苔灵正守住踏板，露薇可沿南侧道路前往门闩。"
		if world.lever_held():
			return "露薇正保持重杆。让小苔灵穿过低拱，留意另一头的轻踏板。"
		return "这边还没有接通的道路。露薇能扳重杆，小苔灵能穿低拱。"
	return fallback
