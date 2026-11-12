extends SceneTree
const Guidance=preload("res://ui/fourth_garden_guidance.gd")
const World=preload("res://core/garden_world.gd")
const HUD=preload("res://ui/garden_hud.gd")
const MapView=preload("res://ui/chapter_map.gd")
const Ink=preload("res://ui/chapter_map_effects.gd")
const DetailArt=preload("res://ui/chapter_map_detail_art.gd")
var checks:=0
var failures: Array[String]=[]
var rows: Array=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var steps: Array=[]
	for entry: Dictionary in fixture.cases:
		if str(entry.name)=="authored/1-4":steps=entry.steps
	var states: Dictionary={"hold_lever":World.new("1-4").snapshot()}
	var flower_ready: Dictionary={}
	var prior: Dictionary=states.hold_lever
	for step: Dictionary in steps:
		var command: Dictionary=step.command
		if str(command.kind)=="act":
			match str(command.value):
				"use:hold":states.cross_arch=step.snapshot
				"use:latch":states.fix_latch=prior;states.find_bell=step.snapshot
				"take:bell":states.return_bell=step.snapshot
				"use:home":states.welcome=step.snapshot
				"repair":flower_ready=prior
		prior=step.snapshot
	states.restored=steps.back().snapshot
	check(states.size()==7,"authored route supplies every normal 1-4 teaching phase")
	var handoff: Dictionary=states.return_bell.duplicate(true)
	handoff.items.bell.holder="buddy"
	states.handoff_bell=handoff
	for expected: String in states:
		var world:=World.new("1-4",states[expected])
		var before: Dictionary=world.snapshot()
		check(Guidance.phase(world)==expected,"actual route phase "+expected)
		var messages: Array=[]
		for tier in range(3):
			var message:=Guidance.hint(world,tier);messages.append(message)
			check(not message.is_empty(),expected+" has tier "+str(tier))
			check(not message.contains("换手") and not message.contains("蹲"),expected+" uses current actor/standing semantics")
		check(messages[0]!=messages[1] and messages[1]!=messages[2],expected+" three levels offer distinct context and action")
		check(world.snapshot()==before,expected+" guidance never mutates state")
		rows.append({"phase":expected,"first":messages[0],"action":messages[2]})
	var initial_world:=World.new("1-4")
	var initial_progress:=Guidance.journey(initial_world)
	check(initial_world.together() and initial_progress.done==0 and not initial_progress.steps[2].done,"initial togetherness never marks flowerbed meeting")
	for pair: Array in [["find_bell",1],["return_bell",1],["welcome",2],["restored",4]]:
		var milestone:=World.new("1-4",states[pair[0]])
		var saved: Dictionary=milestone.snapshot()
		check(Guidance.journey(milestone).done==pair[1],str(pair[0])+" stage rail reads real milestone progress")
		check(milestone.snapshot()==saved,"stage rail never changes rules or tutorial saves")
	var together_at_flower:=World.new("1-4",flower_ready)
	check(Guidance.journey(together_at_flower).done==3,"both legally near the flowerbed marks meeting before active repair")
	var alternative:=World.new("1-4",states.welcome)
	alternative.state.flags.erase("latch")
	var alternative_journey:=Guidance.journey(alternative)
	check(alternative_journey.done==2 and alternative_journey.steps[0].label=="已到家门","alternate home route is acknowledged without demanding latch")
	var feedback:=HUD.new();root.add_child(feedback);feedback.set_process(false)
	var default_goal: String=Guidance.journey(initial_world).goal
	feedback.set_message(default_goal)
	feedback.update_state(initial_world,false,default_goal)
	check(feedback._message.text=="当前目标：固定归途","1-4 default intro uses current milestone")
	var finished:=World.new("1-4",states.restored)
	feedback.update_state(finished,false,default_goal)
	check(feedback._message.text=="花园已复苏","completed 1-4 never retains return-the-bell intro")
	var refreshes: int=feedback._message_refreshes
	feedback.update_state(finished,false,default_goal)
	check(feedback._message_refreshes==refreshes,"unchanged default milestone does not restart message animation or layout")
	feedback.set_message("这里暂时不能放下门铃。")
	feedback.update_state(finished,false,default_goal)
	check(feedback._message.text=="这里暂时不能放下门铃。","default milestone does not overwrite live action feedback")
	feedback.show_hint(finished,0);feedback.update_state(finished,false,default_goal)
	check(feedback.is_hint_visible(),"default milestone does not displace requested hint")
	feedback.hide_hint();feedback.set_message("鼹鼠：谢谢你们！")
	feedback._mole_message_active=true;feedback.update_state(finished,false,default_goal)
	check(feedback._mole_message_active and feedback._message.text=="鼹鼠：谢谢你们！","default milestone preserves active NPC dialogue")
	feedback._message_remaining=0;feedback.update_state(finished,false,default_goal)
	check(feedback._message.text=="花园已复苏","expired feedback allows accurate completed default")
	feedback.free()
	var at_home:=World.new("1-4")
	var home:=""
	for mark: Dictionary in at_home.level.marks:
		if str(mark.id)=="home":home=str(mark.tile)
	at_home.state.actors.luvie=home
	var before: Dictionary=at_home.snapshot()
	var conversation:=Guidance.new()
	check(conversation.poll(at_home,0,false).is_empty(),"action feedback/hint has priority over unsolicited speech")
	var greeting:=conversation.poll(at_home,0,true)
	check(greeting.get("text","")=="雨把我的门铃吹跑了……你们愿意帮我找找吗？","original lost-bell dialogue restored")
	check(float(greeting.get("seconds",0))==8,"original eight-second speech duration")
	check(conversation.poll(at_home,8,true).is_empty(),"staying nearby does not repeat greeting")
	at_home.state.actors.luvie="f:3:5"
	check(conversation.poll(at_home,0,true).get("hide",false),"leaving home hides the visit dialogue")
	at_home.state.actors.luvie=home
	check(conversation.poll(at_home,0,true).is_empty(),"reentry within twenty seconds respects cooldown")
	check(conversation.poll(at_home,12,true).is_empty(),"cooldown expiry while staying nearby does not repeat speech")
	at_home.state.actors.luvie="f:3:5";conversation.poll(at_home,0,true)
	at_home.state.actors.luvie=home
	check(conversation.poll(at_home,0,true).has("text"),"new visit after twenty-second cooldown permits greeting")
	check(at_home.snapshot()==before,"dialogue timings never enter puzzle saves")
	var physical_conversation:=Guidance.new()
	check(physical_conversation.poll(at_home,0,true,false).get("hide",false),"logical home does not greet when actual body is far")
	check(physical_conversation.poll(at_home,0,true,true).has("text"),"actual body approaching NPC permits greeting")
	check(physical_conversation.poll(at_home,0,true,false).get("hide",false),"same-tile physical departure hides NPC speech")
	var hud:=HUD.new();root.add_child(hud);hud.set_process(false)
	hud.update_state(at_home);hud._message_remaining=0
	hud.set_journey({"steps":[{"label":"花园复苏","done":false}],"done":0,"total":1})
	check(hud._journey_step_count==4 and hud._journey_labels.size()==4,"1-4 HUD restores four visible milestones within existing header")
	check(hud._journey_count.visible,"1-4 header shows readable progress")
	check(hud._journey_steps.visible==not hud._short_landscape,"small landscape shows current milestone instead of all four rows")
	hud.show_hint(at_home,2)
	check(hud._hint_label.text.contains(Guidance.hint(at_home,2)),"real HUD uses current staged 1-4 hint")
	hud._process(.1)
	check(hud.is_hint_visible(),"automatic conversation does not displace requested hint")
	hud.hide_hint();hud.set_dialogue_proximity(func() -> bool: return false);hud._process(.1)
	check(not hud._mole_message_active,"real HUD consumes actual NPC distance provider")
	hud.set_dialogue_proximity(func() -> bool: return true);hud._process(.1)
	check(hud._message.text.begins_with("鼹鼠：") and hud._mole_message_active,"real HUD renders the restored situational line")
	var elapsed: float=hud._mole_conversation.elapsed
	hud._locked=true;hud._process(5)
	check(is_equal_approx(hud._mole_conversation.elapsed,elapsed),"locked/paused gameplay does not advance visit clock")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390),Vector2i(568,320)]:
		root.size=dimensions;hud._layout()
		for frame in 4:await process_frame
		var small: bool=dimensions.y<=420
		check(hud._journey_steps.visible==not small,str(dimensions)+" shows desktop stages or compact current stage")
		check(hud._heading.get_global_rect().encloses(hud._journey_count.get_global_rect()),str(dimensions)+" progress stays inside existing title paper")
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(hud._heading.get_global_rect()),str(dimensions)+" stage header stays inside viewport")
		if not small:
			for label: Control in hud._journey_labels:
				check(hud._heading.get_global_rect().encloses(label.get_global_rect()),"desktop milestone fits title paper")
	root.size=Vector2i(1280,720)
	hud.free()
	var levels: Array=JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	var progress:={"records":{},"runs":{},"unlock_all":true}
	var map:=MapView.new();root.add_child(map);map.size=Vector2(1280,720)
	var features:={}
	for chapter: String in ["valley","pond","cave"]:
		map.configure(levels,progress,{"chapter":chapter})
		var ink: Control=map._living_ink;ink.set_process(false)
		check(ink.landmarks.size()==4,chapter+" has four original landmark positions")
		check(ink.mouse_filter==Control.MOUSE_FILTER_IGNORE,chapter+" living illustration cannot intercept touches")
		for item: Dictionary in ink.landmarks:
			check(Ink.FEATURES.has(item.id) and Ink.CAPTIONS.has(item.id),str(item.id)+" has a distinct mechanism vignette")
			features[Ink.FEATURES[item.id]]=true
		var initial: float=ink.clock
		ink._process(.1);check(ink.clock>initial,chapter+" visible unlocked map advances lightweight motion")
		map.apply_settings({"lowMotion":true});initial=ink.clock;ink._process(1)
		check(is_equal_approx(initial,ink.clock),chapter+" lowMotion freezes clock")
		map.apply_settings({"lowMotion":false,"particles":false})
		check(not ink.particles,chapter+" particles toggle honored")
		map.set_paused(true);ink._process(1)
		check(is_equal_approx(initial,ink.clock),chapter+" explicit pause freezes clock")
		map.set_paused(false);map.hide();ink._process(1)
		check(is_equal_approx(initial,ink.clock),chapter+" hidden map does not animate")
		map.show();map.show_overview()
		check(map._living_ink.paused,chapter+" overview freezes background effects")
		map.close_overview();check(not map._living_ink.paused,chapter+" returning to chapter restores motion policy")
	check(features.size()==12,"twelve mainline levels retain twelve distinct mechanism identities")
	for id: String in ["1-4","2-4","3-4"]:
		for unlocked: bool in [false,true]:
			map.configure(levels,{"records":{},"runs":{},"unlock_all":unlocked},{"level":id})
			var marker: Button=map._body.get_node("MapMarker_"+id)
			check(marker.get_rect()==Rect2(736,84,126,158),id+" fourth landmark retains original position and hit area")
			for state_name: String in ["normal","hover","pressed","hover_pressed","disabled"]:
				var surface:=marker.get_theme_stylebox(state_name) as StyleBoxFlat
				check(marker.position.y-surface.expand_margin_top>=134,id+" "+state_name+" feedback is configured below chapter heading")
			marker.grab_focus()
			var focused:=marker.get_theme_stylebox("normal") as StyleBoxFlat
			check(marker.position.y-focused.expand_margin_top>=134,id+" keyboard focus obeys same painted inset")
			marker.release_focus()
			check(marker.get_theme_stylebox("normal").border_color==Color("fff1b6"),id+" focus exit restores selected golden border")
	map.configure(levels,progress,{"chapter":"valley"})
	for id: String in DetailArt.ART:
		var art:=DetailArt.new();root.add_child(art);art.configure(id)
		check(not art._art.is_empty(),id+" selected paper card has original watercolor art")
		check(art.mouse_filter==Control.MOUSE_FILTER_IGNORE,id+" card illustration cannot act as an extra button")
		for item: Dictionary in art._art:
			check(is_instance_valid(item.texture) and Rect2(Vector2.ZERO,art.size).encloses(item.rect),id+" original image fits illustration bounds")
		art.free()
	check(progress=={"records":{},"runs":{},"unlock_all":true},"map illustration changes no progress or unlock record")
	map.free()
	print(JSON.stringify({"suite":"native-chapter-guidance","checks":checks,"passed":failures.is_empty(),"failures":failures,"rows":rows,"gpuVerified":false}))
	quit(0 if failures.is_empty() else 1)
