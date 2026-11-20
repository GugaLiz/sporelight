extends SceneTree
## Explicit user-requested rule revision. Keep the historical fixture intact.
const World = preload("res://core/garden_world.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
const Flow = preload("res://application/guardian_flow_guidance.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func _run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var original: Dictionary
	for entry: Dictionary in data.cases:
		if entry.name=="authored/3-4": original=entry
	for inner: int in range(4):
		for water: int in range(4):
			var saved: Dictionary=original.steps[94].snapshot.duplicate(true)
			saved.turns.inner=inner; saved.turns.water=water
			var world:=World.new("3-4",saved)
			_check(Snapshot.equivalent(world.snapshot(),saved),"existing home save remains intact for angles %s/%s" % [inner,water])
			_check(world.ready() and Flow.describe(world).phase=="care","planting depends on supplied water and actual light/reunion, not remote angles")
			_check(world.act("repair").ok and world.state.completed,"all sixteen remote angle combinations allow local active care")
			var restored:=World.new("3-4",world.snapshot())
			_check(Snapshot.equivalent(restored.snapshot(),world.snapshot()),"completion and all original gift flags survive save/reload")
			_check(world.undo() and not world.state.completed and world.state.turns.inner==inner and world.state.turns.water==water,"undo returns exact original angles without revoking stored supply")
	for missing: String in ["root","rain","star","moon","light","buddy","near_core","active_hero"]:
		var saved: Dictionary=original.steps[94].snapshot.duplicate(true)
		match missing:
			"light": saved.turns.light=0
			"buddy": saved.actors.buddy="m:water:0:0"
			"near_core": saved.actors={"luvie":"f:8:0","buddy":"f:8:0"}
			"active_hero": saved.active="buddy"
			_: saved.flags.erase(missing)
		var world:=World.new("3-4",saved)
		var before: Dictionary=world.snapshot()
		_check(not world.act("repair").ok and Snapshot.equivalent(before,world.snapshot()),"cannot bypass actual prerequisite/local actor requirement: "+missing)
	for turn: int in range(4):
		var saved: Dictionary=original.steps[94].snapshot.duplicate(true)
		saved.turns.light=turn
		var world:=World.new("3-4",saved)
		var ray: Array=world.rays()
		var direction: Vector2i=[Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1)][turn]
		_check(ray.size()>1 and Vector2i(int(ray[1].x-ray[0].x),int(ray[1].z-ray[0].z))==direction,"lamp emits in actual direction "+str(turn))
		_check(world.beam_hits(-4,0)==(turn==1),"only geometrically correct reflection reaches the original core")
		_check(ray[0].x==8 and ray[0].z==4 and ray[0].h==2,"optical source stays on lamp pivot")
	var stored: Dictionary=original.steps[34].snapshot.duplicate(true)
	stored.active="luvie"; stored.actors.luvie="m:lift:0:0"; stored.turns.water=0
	var charged:=World.new("3-4",stored)
	_check(charged.flag("rain") and charged.act("valve:lift").ok,"filled reservoir powers ascent after intake rotates away")
	_check(charged.act("valve:lift").ok,"safe descent remains available")
	stored.flags.erase("rain")
	var empty:=World.new("3-4",stored)
	_check(not empty.act("valve:lift").ok,"empty reservoir cannot ascend")
	var returned:=World.new("3-4",original.steps[55].snapshot)
	_check(returned.has_path_to("f:-4:0","luvie") and Flow.describe(returned).phase=="reunion","actual existing return path is used without extra inner rotation")
	for index: int in original.steps.size():
		var world:=World.new("3-4",original.steps[index].snapshot)
		_check(Snapshot.equivalent(world.snapshot(),original.steps[index].snapshot),"historical save retained at original step "+str(index))
	print(JSON.stringify({"suite":"guardian-causality","checks":checks,"passed":failures.is_empty(),"failures":failures,"scope":"Explicit new remote-angle cultivation contract; unchanged old saves, core prerequisites, reservoir and actual directional rays. GPU and physical route separate."}))
	quit(0 if failures.is_empty() else 1)
