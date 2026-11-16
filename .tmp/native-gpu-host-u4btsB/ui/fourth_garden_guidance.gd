extends RefCounted
## Original moleDialogue.ts story, with guidance for the current native rules.
## Visit timing is presentation-only; no tutorial flags enter a save.
var elapsed := 0.0
var last_stage := ""
var was_near := false
var next_greeting := 0.0

static func journey(world: Variant) -> Dictionary:
	var complete: bool=bool(world.state.get("completed",false))
	var home: bool=world.flag("home")
	var latch: bool=world.flag("latch")
	var core:=""
	for mark: Dictionary in world.level.get("marks",[]):
		if str(mark.get("kind",""))=="core": core=str(mark.tile);break
	var at_flower: bool=complete or (home and not core.is_empty() and world.near(core,"luvie") and world.near(core,"buddy") and world.together())
	var steps: Array=[
		{"label":"已到家门" if home and not latch else "固定归途","done":latch or home or complete},
		{"label":"归还门铃","done":home or complete},
		{"label":"两位到花床","done":at_flower},
		{"label":"种下微光","done":complete}
	]
	var done:=0;var current:=-1
	for index in steps.size():
		if steps[index].done:done+=1
		elif current<0:current=index
	return {"steps":steps,"current":current,"done":done,"total":4,"goal":"和伙伴一起，把门铃带回家。","next":"花园已复苏" if complete else str(steps[current].label)}

static func phase(world: Variant) -> String:
	if bool(world.state.get("completed",false)): return "restored"
	if world.flag("home"): return "welcome"
	if world.flag("latch"):
		var holder := str(world.state.items.bell.get("holder",""))
		return "return_bell" if holder=="luvie" else "handoff_bell" if holder=="buddy" else "find_bell"
	if str(world.state.actors.buddy)=="f:3:5": return "fix_latch"
	if world.lever_held(): return "cross_arch"
	return "hold_lever"

static func hint(world: Variant,tier: int) -> String:
	var lines: Array
	match phase(world):
		"hold_lever": lines=["雨把小门铃吹到了内庭。先看看重杆与低拱，谁能帮谁打开一段路？","露薇能扳住重杆，小苔灵能穿低拱。保持重杆时让露薇留在握点，另一位仍可行动。","让露薇走近外庭重杆并操作，再操控小苔灵过临时桥、穿低拱，到内庭的轻踏板。露薇移动会松手，先等伙伴站稳。"]
		"cross_arch": lines=["露薇把桥稳稳留住了。低拱另一头，有一块等待小脚步的石板。","小苔灵踩住轻踏板会打开南门；让它留在那里，露薇才有机会固定归途。","保持露薇的位置，操控小苔灵沿桥穿低拱，走到内庭轻踏板。站稳后再让露薇从南门过去。"]
		"fix_latch": lines=["轻踏板已经有人守着。现在，该让归途不再依靠谁的力气。","小苔灵留在踏板上维持南门；露薇固定门闩后，伙伴就可以离开。","操控露薇沿南门进入内庭，走近门闩并操作。先让小苔灵继续等候；门闩固定后不必再保持重杆。"]
		"find_bell": lines=["回家的路安定了，石台上还缺一声轻轻的叮铃。","门铃需要由露薇带给鼹鼠；沿途微光可以以后再找，不是开门的条件。","让露薇走到门铃所在的内庭石台，拾起门铃，再回鼹鼠家门操作。若曾放下门铃，就回到放下它的石台。"]
		"handoff_bell": lines=["小门铃已经找到了，让露薇把这声问候送到家门吧。","鼹鼠家门需要露薇归还门铃；物件可以先放在安全台面上交接。","让小苔灵在露薇可到达的固定石台放下门铃，再操控露薇拾起，带到鼹鼠家门操作。"]
		"return_bell": lines=["叶包里传来轻轻的铃声，鼹鼠一定认得它。","归还门铃会打开花门。回家门交还，不用把门铃放到花床上。","让露薇带着门铃走近鼹鼠家门，操作归还门铃；花门打开后再和小苔灵一起进去。"]
		"welcome": lines=["花门开了，喷泉把最后一段归途照得很亮。别忘了回头等一等伙伴。","门闩已固定，可以邀请伙伴同行；两位在内庭花床附近会合后，仍需主动播种。","接上小苔灵，穿过鼹鼠旁的花门到喷泉前花床。两位靠近后操作「一起种下微光」，完成修复。"]
		_: lines=["花开啦，连蝴蝶都来做客了。以后也常来坐坐呀。","归途、门铃和伙伴都回到了这里，可以留下慢慢看看。",str(world.level.get("story","这座小花园已经安定下来。"))]
	return str(lines[clampi(tier,0,2)])

static func conversation(world: Variant) -> Dictionary:
	if bool(world.state.get("completed",false)): return {"stage":"restored","text":"花开啦，连蝴蝶都来做客了。以后也常来坐坐呀。"}
	if world.flag("home"): return {"stage":"welcome","text":"谢谢你们！花门开了，带上小伙伴去喷泉边看看吧。"}
	if not str(world.state.items.bell.get("holder","")).is_empty(): return {"stage":"bell","text":"咦，是我的小门铃！我认得这声轻轻的叮铃。"}
	if world.flag("latch"): return {"stage":"latch","text":"回来的路修好啦。门铃好像落在那边的石台上了……"}
	if world.lever_held(): return {"stage":"help","text":"你们配合得真好！小拱道就拜托小苔灵啦。"}
	return {"stage":"lost","text":"雨把我的门铃吹跑了……你们愿意帮我找找吗？"}

static func near_home(world: Variant) -> bool:
	if world==null or str(world.level.id)!="1-4": return false
	for mark: Dictionary in world.level.get("marks",[]):
		if str(mark.id)=="home": return world.near(str(mark.tile))
	return false

func poll(world: Variant,delta: float,can_speak: bool,physical_near: Variant=null) -> Dictionary:
	elapsed+=maxf(0,delta)
	# The live HUD supplies actual body/NPC proximity. Logical proximity is
	# retained for rule-only callers that do not have a rendered stage.
	var nearby: bool=near_home(world) if physical_near==null else bool(physical_near)
	if not nearby:
		was_near=false
		return {"hide":true}
	var line:=conversation(world)
	var may_greet: bool=str(line.stage)!=last_stage or (not was_near and elapsed>=next_greeting)
	was_near=true
	if can_speak and may_greet:
		last_stage=str(line.stage);next_greeting=elapsed+20
		return {"text":str(line.text),"seconds":8.0}
	return {}
