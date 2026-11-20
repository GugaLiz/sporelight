extends SceneTree
const Revision2=preload("res://tests/fixtures/guardian_revision2_world.gd")
const Production=preload("res://core/garden_world.gd")
const Candidate=preload("res://tests/fixtures/guardian_rollback_candidate_world.gd")
const Repository=preload("res://services/save_repository.gd")
const Snapshot=preload("res://contracts/snapshot_data.gd")
var World:Script
var checks:=0
var failures:Array[String]=[]
var states:Array[Dictionary]=[]
func _initialize()->void:
	World=Candidate if "--candidate" in OS.get_cmdline_user_args() else Production
	create_timer(30).timeout.connect(func()->void: push_error("rollback suite timeout");quit(2))
	_run.call_deferred()
func _check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func _record(w:RefCounted)->void: states.append(w.snapshot())
func _act(w:RefCounted,id:String)->void:
	_check(w.act(id).ok,"real revision2 action "+id)
	_record(w)
func _walk(w:RefCounted,target:String)->void:
	_check(w.has_path_to(target),"real revision2 route "+target)
	for id:String in w.path_to(target):
		_check(w.move(id).ok,"real revision2 step "+id)
		_record(w)
func _water(w:RefCounted)->void:
	_act(w,"switch");_walk(w,"m:water:0:0");_act(w,"valve:water")
	_act(w,"valve:water");_walk(w,"f:-3:0");_act(w,"switch")
func _bridge(w:RefCounted)->void:
	_walk(w,"f:1:-4");_act(w,"take:mirror")
	for x:int in range(2,5):
		_act(w,"grow:root:right");_walk(w,"g:root:%d:-4"%x)
func _migrate(saved:Dictionary,label:String)->Dictionary:
	_check(Revision2.new("3-4").normalize_saved(saved).ok,"source revision2 really valid: "+label)
	var outcome:Dictionary=World.new("3-4").normalize_saved(saved)
	_check(outcome.ok,"rollback accepts valid source: "+label)
	if not outcome.ok:return {}
	var result:Dictionary=outcome.snapshot
	_check(not result.has("layoutRevision") and not result.has("runtime"),"obsolete revision/physical offsets cleared")
	_check(result.flags==saved.flags and result.growth==saved.growth and result.collected==saved.collected and result.completed==saved.completed,"earned progress/completion preserved")
	_check(result.items.mirror.angle==saved.items.mirror.angle and result.items.mirror.get("holder","")==saved.items.mirror.get("holder",""),"mirror ownership/orientation preserved")
	var archive:Dictionary=result.guardianRevision2Recovery.snapshot
	var expected:=saved.duplicate(true);expected.erase("guardianRevision2Recovery")
	_check(Snapshot.equivalent(archive,expected) and not archive.has("guardianRevision2Recovery"),"one nonrecursive original revision2 snapshot retained")
	var w:RefCounted=World.new("3-4",result)
	_check(Snapshot.equivalent(w.snapshot(),result),"migrated snapshot roundtrip exact")
	_check(Snapshot.equivalent(w.normalize_saved(result).snapshot,result),"repeated normalization does not remap or overwrite archive")
	for who:String in ["luvie","buddy"]:
		var p:Dictionary=w.point_for(str(result.actors[who]))
		_check(not p.is_empty() and not p.get("solid",false) and not (who=="luvie" and p.get("small",false)),"old body support valid")
	if Revision2.new("3-4",saved).beam_hits(-4,0):
		_check(w.state.turns.light==1 and w.beam_hits(-4,0),"current real illumination preserved using old north lamp")
	return result
func _support_map(w:RefCounted)->Dictionary:
	var result:Dictionary={}
	for tile:Dictionary in w.tiles():
		result[tile.id]=[tile.x,tile.z,tile.h,bool(tile.get("solid",false)),bool(tile.get("small",false))]
	return result
func _run()->void:
	# Generate authentic inputs with the frozen revision-2 domain implementation.
	for water_first:bool in [true,false]:
		var w:=Revision2.new("3-4");_record(w)
		if water_first:_water(w);_bridge(w)
		else:_bridge(w);_water(w)
		_walk(w,"m:lift:0:0");_act(w,"valve:lift");_walk(w,"f:7:0")
		_act(w,"drop:mirror:f:8:0");_act(w,"angle:mirror")
		_walk(w,"m:lift:0:0");_act(w,"valve:lift");_walk(w,"f:-4:0");_act(w,"repair")
	for index:int in range(states.size()):
		var saved:=states[index].duplicate(true)
		saved.runtime={"version":1,"poses":{}}
		for who:String in ["luvie","buddy"]: saved.runtime.poses[who]={"support":saved.actors[who],"offset":[.12,0,-.08],"yaw":.6}
		_migrate(saved,"actual route "+str(index))
	# Reconstructed validation-only supports and optics must match real v2.
	for saved:Dictionary in states:
		var genuine:=Revision2.new("3-4",saved)
		var validator:RefCounted=World.new("3-4")
		validator._validating_guardian_revision2=true
		validator.level=validator._guardian_revision2_definition()
		validator.state=genuine.snapshot()
		_check(Snapshot.equivalent(_support_map(validator),_support_map(genuine)),"validation geometry matches frozen revision2")
		_check(Snapshot.equivalent({"rays":validator.rays()},{"rays":genuine.rays()}),"validation light matches frozen revision2")
	# Every legal support in both an unbuilt and completed-bridge layout.
	for seed:Dictionary in [states[0],states.back()]:
		for raised:int in [0,1]:
			var basis:=seed.duplicate(true);basis.completed=false;basis.turns.lift=raised
			var source:=Revision2.new("3-4",basis)
			for tile:Dictionary in source.tiles():
				if tile.get("solid",false):continue
				for who:String in ["luvie","buddy"]:
					if who=="luvie" and tile.get("small",false):continue
					var saved:=basis.duplicate(true);saved.actors[who]=tile.id
					_migrate(saved,"support "+str(tile.id)+"/"+who+"/"+str(raised))
	# Grounded mirror supports remain legal after an empty lift is docked.
	for raised:int in [0,1]:
		var item_basis:Dictionary=states.back().duplicate(true);item_basis.completed=false;item_basis.turns.lift=raised
		var item_source:=Revision2.new("3-4",item_basis)
		for tile:Dictionary in item_source.tiles():
			var saved:=item_basis.duplicate(true);saved.items.mirror.tile=tile.id;saved.items.mirror.erase("holder")
			_migrate(saved,"grounded mirror "+str(tile.id)+"/"+str(raised))
	var nested:Dictionary=states[0].duplicate(true)
	nested.guardianRevision2Recovery={"snapshot":{"sentinel":"older nested value"}}
	_migrate(nested,"incoming recovery stripped before first archive")
	var high:Dictionary=states.back().duplicate(true);high.completed=false;high.actors.luvie="f:7:0";high.turns.lift=0
	var recovered:=_migrate(high,"empty lift below high traveller")
	_check(not recovered.is_empty() and recovered.turns.lift==1,"empty lift restored at high occupied shore")
	if not recovered.is_empty():
		var w:RefCounted=World.new("3-4",recovered)
		_check(w.has_path_to("m:lift:0:0","luvie"),"high traveller can physically reach restored platform")
	var low:Dictionary=states.back().duplicate(true);low.completed=false;low.turns.lift=1
	var lowered:=_migrate(low,"empty lift above low travellers")
	_check(not lowered.is_empty() and lowered.turns.lift==0,"empty lift restored at low occupied shore")
	var water_only:=Revision2.new("3-4");water_only.state.active="buddy";water_only.state.actors.buddy="m:water:0:0"
	_check(water_only.act("valve:water").ok,"water-first source opens gate")
	var early:=water_only.snapshot();early.actors.buddy="m:lift:0:0"
	var early_back:=_migrate(early,"water-first companion on lift before root")
	_check(not early_back.is_empty() and "rain" in early_back.flags and not "root" in early_back.flags and early_back.actors.buddy=="m:water:0:0","water-first progress retained on accessible old water court")
	for bad:String in ["version1","version3","unknown_support","bad_growth","hero_small","invalid_pose","wrong_item"]:
		var saved:=states[0].duplicate(true)
		match bad:
			"version1":saved.layoutRevision=1
			"version3":saved.layoutRevision=3
			"unknown_support":saved.actors.buddy="f:100:100"
			"bad_growth":saved.growth.root=["g:root:40:40"]
			"hero_small":saved.actors.luvie="m:water:0:0"
			"invalid_pose":saved.runtime={"version":1,"poses":{"luvie":{"support":saved.actors.luvie,"offset":[3,0,0]}}}
			"wrong_item":saved.items.mirror.tile="f:-4:8"
		_check(not World.new("3-4").normalize_saved(saved).ok,"reject unsupported/corrupt source: "+bad)
	var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry:Dictionary in reference.cases:
		if entry.name=="authored/3-4":
			for step:Dictionary in entry.steps:
				var result:Dictionary=World.new("3-4").normalize_saved(step.snapshot)
				_check(result.ok and Snapshot.equivalent(result.snapshot,step.snapshot),"old 96 snapshots remain exact without archive")
	for id:String in ["1-1","1-2","1-3","1-4","2-1","2-2","2-3","2-4","3-1","3-2","3-3"]:
		var original:Dictionary=Production.new(id).snapshot()
		_check(Snapshot.equivalent(World.new(id,original).snapshot(),original),"other level cold/save unchanged "+id)
	# Real repository readback must keep the original source after repeated saves.
	var repo:=Repository.new("user://tests/guardian-rollback-%d.json"%Time.get_ticks_usec())
	repo.configure_levels([{ "id":"3-4", "total":8 }])
	repo.snapshot_validator=func(saved:Dictionary)->Dictionary:return World.new("3-4").normalize_saved(saved)
	_check(repo.commit_run(high).ok,"repository commits source through rollback normalizer")
	var first_archive:Dictionary=repo.data.mainline.runs["3-4"].guardianRevision2Recovery.duplicate(true)
	for iteration:int in range(3):
		var w:RefCounted=World.new("3-4",repo.data.mainline.runs["3-4"])
		_check(w.act("switch").ok and repo.commit_run(w.snapshot()).ok,"ordinary save after migration")
	_check(Snapshot.equivalent(repo.data.mainline.runs["3-4"].guardianRevision2Recovery,first_archive),"rolling saves do not overwrite one-time recovery")
	_check(repo.load_store().ok and Snapshot.equivalent(repo.data.mainline.runs["3-4"].guardianRevision2Recovery,first_archive),"recovery survives real disk readback")
	for suffix:String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(repo.path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(repo.path+suffix))
	print(JSON.stringify({"suite":"guardian-rollback-migration","checks":checks,"passed":failures.is_empty(),"failures":failures,"candidate":"--candidate" in OS.get_cmdline_user_args(),"scope":"Frozen revision2 real routes/support matrix, rollback safety, unchanged old saves, persistent one-time recovery."}))
	quit(0 if failures.is_empty() else 1)
