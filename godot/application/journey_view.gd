class_name GardenJourney
extends RefCounted
## Public goals describe intentions. Help is opt-in and never drives actions.

const GOALS := {
	"1-1": ["让缺口彼端的花床重新醒来。", "根台里的一节嫩芽，正在等你决定去向。", "芽节有限，可以收回后重新安排；先观察想去的地方。"],
	"1-2": ["为岩石另一侧的小花找到一条路。", "岩石挡住了直路，周围还留有空隙。", "根须从根尖连续生长，预算相同也可能走出不同的路。"],
	"1-3": ["让苔藓庭院与远岸相遇。", "石纹与岸边的缺口并不总在同一方向。", "转动庭院时，站在上面的人与出口会一起改变位置。"],
	"1-4": ["和伙伴一起，把门铃带回家。", "低拱和沉重的机关各自需要不同的帮手。", "有人保持机关时，另一位可以继续行动；门闩能让已接通的路稳定下来。"],
	"2-1": ["听听池塘需要哪一层水。", "池壁留下几道水线，不同高度有不同的生命。", "水位更高不一定更合适；浮台和岸边会随它改变关系。"],
	"2-2": ["把一束光送回花床。", "光照到镜叶会转向，碰到石壁会停下来。", "镜叶的位置和朝向共同决定光路；观察实际光束再试一次。"],
	"2-3": ["为雨滴排出一段能抵达的旋律。", "石台跟随每一拍变化，先后会改变结果。", "可以暂停、单步和重排；每次试奏都用来验证一个想法。"],
	"2-4": ["陪池塘的小生命完成一次相遇。", "花、庭院和微光生灵之间，还有等待发生的联系。", "先观察它们对环境的回应，再安排可以相遇的通路。"],
	"3-1": ["把暖光和伙伴一起带过暗处。", "低处通道、照孔和石窗透出的光各有不同。", "伙伴能进入的空间与你不同；一束光也能从另一侧帮助你。"],
	"3-2": ["让不同时刻的影子共同成为道路。", "日与月照出的轮廓，各自只覆盖一部分空隙。", "留影保存当时真实的形状，再观察另一种光照下的连接。"],
	"3-3": ["让有限的水，照顾整座花园。", "有些生命安定下来后，对水的需要会发生变化。", "观察根系是否已经稳定，再思考是否能把资源让给别处。"],
	"3-4": ["和伙伴唤醒沉睡的守护者。", "根、水和光之间需要保持连通。", "曾经点亮过还不够；准备会合时，再检查现在仍在起作用的连接。"],
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
	var steps: Array = [{"label": "花园复苏", "done": complete}]
	return {
		"steps": steps, "current": -1 if complete else 0,
		"done": 1 if complete else 0, "total": 1,
		"goal": str(entry[0]),
		"next": str(level.get("story", "")) if complete else str(entry[0])
	}

static func hint(world: Variant, tier: int = 0) -> Dictionary:
	var level: Dictionary = world.level
	var entry: Array = GOALS.get(str(level.get("id", "")), [str(level.get("rule", "慢慢探索这片花园。")), "观察身边物件的变化。", "尝试之后，可以撤销，再验证另一个想法。"])
	var stage := clampi(tier, 0, 2)
	if bool(world.state.get("completed", false)):
		return {"tier": stage, "title": "已经复苏的花园", "message": str(level.get("story", "留下慢慢看看，也可以前往下一片花园。"))}
	if stage == 0:
		return {"tier": stage, "title": "先看看这里", "message": str(entry[1])}
	if stage == 1:
		return {"tier": stage, "title": "想想它们的关系", "message": str(entry[2])}
	var explicit: Dictionary = world.hint() if world.has_method("hint") else {}
	return {"tier": stage, "title": "一个具体的方向", "message": str(explicit.get("message", entry[2]))}
