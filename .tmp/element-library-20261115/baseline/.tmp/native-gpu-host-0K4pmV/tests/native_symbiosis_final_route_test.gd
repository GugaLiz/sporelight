extends SceneTree
## Prepared rule boundaries, independent expected corridor coordinates.
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
var fixture: Dictionary = {}

func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _world(stable: bool, high: int, water: int) -> RefCounted:
	var saved: Dictionary = fixture.steps[38 if stable else 37].snapshot.duplicate(true)
	saved.turns.lift = high
	saved.turns.water = water
	saved.actors = {"luvie":"m:lift:0:0","buddy":"m:lift:0:0"}
	saved.follow = false
	saved.erase("runtime")
	return World.new("3-3", saved)

func _corridor(world: RefCounted) -> Array:
	var result: Array = []
	for tile: Dictionary in world.tiles():
		if is_equal_approx(float(tile.h),2.0) and is_equal_approx(float(tile.z),2.0) and int(tile.x) in range(5):
			result.append([int(tile.x),int(tile.z),float(tile.h)])
	result.sort_custom(func(a: Array,b: Array) -> bool: return a[0]<b[0])
	return result

func _matrix() -> void:
	var expected: Array = [[0,2,2.0],[1,2,2.0],[2,2,2.0],[3,2,2.0],[4,2,2.0]]
	for stable: bool in [false,true]:
		for high: int in [0,1]:
			for water: int in range(4):
				var world := _world(stable,high,water)
				var label := "root=%s lift=%d water=%d" % [stable,high,water]
				var open: bool = stable and high==1
				_check(world.symbiosis_final_route_open()==open,label+" helper matches independent predicate")
				_check(world.ready()==open,label+" readiness shares final route state")
				_check(_corridor(world)==(expected if open else []),label+" exactly five gaps or no final route")
				_check(not world.path_to("f:0:4").is_empty()==open,label+" endpoint reachability follows route")
				var shore: Dictionary = world.point_for("f:0:3")
				_check(shore.get("kind","fixed")=="fixed" and is_equal_approx(float(shore.h),2.0),label+" permanent shore stays fixed high ground")
				_check(world.tiles().filter(func(t: Dictionary) -> bool: return str(t.id)=="f:0:3").size()==1,label+" shore has a single rendered owner")
				world.state.actors.buddy="f:0:3"
				_check(world.point_for("f:0:3").get("kind","fixed")=="fixed",label+" occupying permanent shore never changes its kind")
				var normalized: Dictionary = world.normalize_saved(world.snapshot())
				_check(bool(normalized.get("ok",false)),label+" prepared saved state normalizes")
				var restored := World.new("3-3",world.snapshot())
				_check(restored.state.turns.water==water and restored.state.turns.lift==high and _corridor(restored)==(expected if open else []),label+" reload preserves progress and corridor")
	_check(not World.new("3-4").symbiosis_final_route_open(),"helper is local to 3-3")

func _descent() -> void:
	for water: int in range(4):
		for occupant: String in ["luvie","buddy","item"]:
			var world := _world(true,1,water)
			if occupant=="item": world.state.items.dew={"tile":"f:2:2","angle":0}
			else:
				world.state.actors[occupant]="f:2:2"
				world.state.active="buddy" if occupant=="luvie" else "luvie"
			var before: Dictionary=world.snapshot().duplicate(true)
			_check(not world.act("valve:lift").ok and world.snapshot()==before,"occupied corridor blocks normal descent %s water%d" % [occupant,water])
			_check(not world.act("valve:lift",true).ok and world.snapshot()==before,"occupied corridor blocks quiet descent %s water%d" % [occupant,water])
		var safe := _world(true,1,water)
		var before: Dictionary = safe.snapshot().duplicate(true)
		_check(safe.act("valve:lift").ok and _corridor(safe).is_empty(),"safe descent allowed for water%d" % water)
		_check(safe.undo() and safe.snapshot()==before and _corridor(safe).size()==5,"undo restores exact high route for water%d" % water)
		var low := _world(true,0,water)
		var low_before: Dictionary = low.snapshot().duplicate(true)
		var lifted: bool=low.act("valve:lift").ok
		_check(lifted==(water in [0,1]),"existing powered ascent retained for water%d" % water)
		if not lifted: _check(low.snapshot()==low_before,"unpowered ascent does not mutate progress")
		var shore_safe := _world(true,1,water)
		shore_safe.state.actors.buddy="f:0:3"
		_check(shore_safe.act("valve:lift").ok and shore_safe.point_for("f:0:3").get("kind","fixed")=="fixed","permanent shore occupant survives descent water%d" % water)

func _run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if str(entry.name)=="authored/3-3": fixture=entry
	_check(fixture.steps.size()==59,"historical 59-intention fixture remains unchanged")
	_matrix()
	_descent()
	print(JSON.stringify({"suite":"symbiosis-final-route","checks":checks,"failures":failures,"passed":failures.is_empty(),"scope":"Prepared root/lift/water, occupied descent, undo and save boundaries; real travel is a separate GPU suite."}))
	quit(0 if failures.is_empty() else 1)
