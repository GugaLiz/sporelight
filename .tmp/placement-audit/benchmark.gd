extends SceneTree
const Stage=preload("res://presentation/native/native_garden_stage.gd")
const World=preload("res://core/garden_world.gd")
const D=preload("res://presentation/native/original_garden_dressing.gd")
const P=preload("res://presentation/native/original_scenery_placement.gd")
func _initialize():call_deferred("run")
func solve(stage):
	var ctx=P.prepare(stage)
	for entry in D.SOURCE_PROPS[str(stage.world.level.id)]:
		var authored=Vector3(entry[1],entry[3],entry[2]);var support="f:%d:%d"%[roundi(authored.x),roundi(authored.z)]
		if not stage._tile_map.has(support) or not stage._surfaces.has(support):continue
		P.place(stage,authored,entry[0],D.canvas_width(entry[4]),D.SOURCE_PROPS[str(stage.world.level.id)].find(entry),ctx)
func run():
	var stage=Stage.new();root.add_child(stage);var rows=[]
	for id in ["1-3","1-4","2-1","2-2","2-3","2-4","3-1","3-2","3-3","3-4"]:
		stage.set_world(World.new(id));await process_frame
		P._contexts.clear();P._placements.clear()
		var started=Time.get_ticks_usec();solve(stage);var cold=Time.get_ticks_usec()-started
		var searches=P.searches;var warm=[]
		for repeat in range(10):
			started=Time.get_ticks_usec();solve(stage);warm.append(Time.get_ticks_usec()-started)
		var forced=[]
		for repeat in range(5):
			stage._props_signature=0
			started=Time.get_ticks_usec();stage.refresh_world(stage.world);forced.append(Time.get_ticks_usec()-started);await process_frame
		warm.sort();forced.sort()
		rows.append({"level":id,"solverColdMs":cold/1000.0,"solverWarmMedianMs":warm[5]/1000.0,"solverWarmMaxMs":warm.back()/1000.0,"forcedPropsWarmMedianMs":forced[2]/1000.0,"forcedPropsWarmMaxMs":forced.back()/1000.0,"warmNewSearches":P.searches-searches})
	FileAccess.open("res://../.tmp/placement-audit/benchmark.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"CPU headless solver and forced full props rebuild timings; no GPU or frame-rate claim","samples":rows},"  "))
	print(JSON.stringify(rows));stage.queue_free();await process_frame;quit()
