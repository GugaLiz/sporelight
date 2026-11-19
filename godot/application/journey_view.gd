class_name GardenJourney
extends RefCounted
## Public goals describe intentions. Help is opt-in and never drives actions.
const GuardianFlow := preload("res://application/guardian_flow_guidance.gd")

const GOALS := {
	"1-1": ["让缺口彼端的花床重新醒来。", "点根台旁的＋选择方向，石板就会生长；再点对岸地面走过去，最后到花坛旁互动。", "E 打开附近操作；选方向后立即生长，无需再次确认。Z 撤销上一步，收回根路需在操作面板中选择。"],
	"1-2": ["为岩石另一侧的小花找到一条路。", "岩石挡住了直路。先在岩石上侧或下侧选一个＋；长出一节后，点击新石板走上去，再继续选方向。", "四节根路逐节生长，每次先走到已建末端；最后一节接向对岸。Z 可撤销一步，微光与休息都不影响接桥。"],
	"1-3": ["让苔藓庭院与远岸相遇。", "沿已接通的石板走上庭院，到中心把手旁按 E 转动；休息后可直接用方向键走开。", "转动庭院时，站在上面的人与出口会一起改变位置。"],
	"1-4": ["和伙伴一起，把门铃带回家。", "低拱和沉重的机关各自需要不同的帮手。", "有人保持机关时，另一位可以继续行动；门闩能让已接通的路稳定下来。"],
	"2-1": ["听听池塘需要哪一层水。", "池壁留下几道水线，不同高度有不同的生命。", "水位更高不一定更合适；浮台和岸边会随它改变关系。"],
	"2-2": ["把一束光送回花床。", "光照到镜叶会转向，碰到石壁会停下来。", "镜叶的位置和朝向共同决定光路；观察实际光束再试一次。"],
	"2-3": ["为雨滴排出一段能抵达的旋律。", "石台跟随每一拍变化，先后会改变结果。", "可以暂停、单步和重排；每次试奏都用来验证一个想法。"],
	"2-4": ["陪池塘的小生命完成一次相遇。", "花、庭院和微光生灵之间，还有等待发生的联系。", "先观察它们对环境的回应，再安排可以相遇的通路。"],
	"3-1": ["把暖光和伙伴一起带过暗处。", "低处通道、照孔和石窗透出的光各有不同。", "伙伴能进入的空间与你不同；一束光也能从另一侧帮助你。"],
	"3-2": ["让不同时刻的影子共同成为道路。", "日与月照出的轮廓，各自只覆盖一部分空隙。", "留影保存当时真实的形状，再观察另一种光照下的连接。"],
	"3-3": ["让清露与藤根，唤醒远岸的花园。", "根碗里的清露与花台的高度，都会改变花园的回应。", "根系蓄水后，留意高处是否出现新的连接；水轮仍影响花台上升的动力。"],
	"3-4": ["和伙伴唤醒沉睡的守护者。", "根路通向远岸，清水为升降台蓄力，光唤醒花坛。", "储水罐灌满后不会流失；让光留在花坛上，再和伙伴回来照料。"],
	"cloud-1": ["把花种带到风中的塔庭。", "转桥两端连接着不同的庭院。", "桥的朝向改变目的地，携带的物件也会随你一起前往。"],
	"cloud-2": ["让高处的花院重新得到清水。", "花台会靠岸，也能改变高度。", "在可靠的停靠处登台，再观察另一高度能连接哪里。"],
	"cloud-3": ["和伙伴一起，让星灯成为归途。", "门、压板和桥相互牵连。", "伙伴可以保持机关；已经固定的门闩也许能让它重新加入你。"]
}

static func describe(world: Variant) -> Dictionary:
	var state: Dictionary = world.state
	var level: Dictionary = world.level
	var id := str(level.get("id", ""))
	var entry: Array = GOALS.get(id, [str(level.get("rule", "慢慢探索这片花园。")), "先观察身边的变化。", "尝试一个动作，再看看它改变了什么。"])
	var complete := bool(state.get("completed", false))
	# 3-4 now communicates the current journey in the existing objective row.
	# Its opt-in hint tiers below retain their authored discovery/solution split.
	var goal := str(GuardianFlow.describe(world).goal) if id == "3-4" else str(entry[0])
	var steps: Array = [{"label": "花园复苏", "done": complete}]
	if id == "2-1":
		var cared: bool = world.flag("care")
		var dew: Dictionary = state.get("items",{}).get("dew",{})
		steps = [{"label":"带回清露","done":complete or cared or bool(dew.get("picked",false))}, {"label":"照料睡莲","done":complete or cared}, {"label":"花园复苏","done":complete}]
	if id in ["1-1", "1-2"] and world.has_method("point"):
		var built: int = state.get("growth",{}).get("root",[]).size()
		var budget: int = int(level.roots[0].get("budget",1))
		var core: Dictionary = world.point_for(str(level.get("core","")))
		if core.is_empty():
			for mark: Dictionary in level.get("marks",[]):
				if str(mark.kind) == "core": core = world.point_for(str(mark.tile))
		var active_tile: Dictionary = world.point()
		var arrived := complete or (not core.is_empty() and absf(float(active_tile.x)-float(core.x)) + absf(float(active_tile.z)-float(core.z)) <= 1)
		steps = [{"label":"接通根路", "done":complete or built >= budget}, {"label":"抵达花床", "done":arrived}, {"label":"种下微光", "done":complete}]
	var done := 0
	for step: Dictionary in steps:
		if bool(step.done): done += 1
	return {
		"steps": steps, "current": -1 if complete else done,
		"done": done, "total": steps.size(),
		"goal": goal,
		"next": str(level.get("story", "")) if complete else goal
	}

static func hint(world: Variant, tier: int = 0) -> Dictionary:
	var level: Dictionary = world.level
	var entry: Array = GOALS.get(str(level.get("id", "")), [str(level.get("rule", "慢慢探索这片花园。")), "观察身边物件的变化。", "尝试之后，可以撤销，再验证另一个想法。"])
	var stage := clampi(tier, 0, 2)
	if bool(world.state.get("completed", false)):
		return {"tier": stage, "title": "已经复苏的花园", "message": str(level.get("story", "留下慢慢看看，也可以前往下一片花园。"))}
	if str(level.get("id", "")) == "2-1" and stage == 0 and not world.flag("care"):
		return {"tier":stage,"title":"清露与微光","message":"发光水滴是清露，需要露薇走近后主动接住；已收集的微光不能替代清露。"}
	if stage == 0:
		return {"tier": stage, "title": "先看看这里", "message": str(entry[1])}
	if stage == 1:
		return {"tier": stage, "title": "想想它们的关系", "message": str(entry[2])}
	var explicit: Dictionary = world.hint() if world.has_method("hint") else {}
	return {"tier": stage, "title": "一个具体的方向", "message": str(explicit.get("message", entry[2]))}
