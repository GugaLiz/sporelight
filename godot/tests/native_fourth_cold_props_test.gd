extends SceneTree
const Stage := preload("res://presentation/native/native_garden_stage.gd")
const World := preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _run() -> void:
	for cold: bool in [true,false]:
		var stage := Stage.new()
		root.add_child(stage)
		if not cold: stage.set_world(World.new("1-1"))
		var world := World.new("1-4")
		stage.set_world(world)
		var initial: Dictionary = {}
		for node: Node in stage._props.find_children("*","Sprite3D",true,false):
			if node.billboard != BaseMaterial3D.BILLBOARD_DISABLED: continue
			if node.name != "MoleResident" and not str(node.name).begins_with("OriginalSanctuaryGate") and str(node.name) != "arch": continue
			initial[str(stage._props.get_path_to(node))] = node.basis
			var right: Vector3 = stage._camera.global_basis.x.normalized()
			var up: Vector3 = stage._camera.global_basis.y.normalized()
			_check(absf(node.basis.x.dot(right)-1.0)<.001,"cold=%s %s full projected width before any movement" % [cold,node.name])
			_check(absf(node.basis.y.dot(up)-1.0)<.001,"cold=%s %s full projected height before any movement" % [cold,node.name])
		_check(initial.has("MoleResident"),"resident checked on first set_world")
		_check(initial.size() >= 2,"window/gate and resident both checked")
		# A real collectible state update rebuilds these props, as in the report.
		world.state.collected.append("spore-0")
		stage.refresh_world(world,true)
		for key: String in initial:
			var prop := stage._props.get_node_or_null(key) as Sprite3D
			_check(prop != null and prop.basis.is_equal_approx(initial[key]),"pickup rebuild preserves initial shape / "+key)
		stage.queue_free()
		await process_frame
	print(JSON.stringify({"suite":"native-fourth-cold-props","checks":checks,"passed":failures.is_empty(),"failures":failures,"scope":"Fresh stage and warm switch to 1-4, before any tick; projected prop basis and legitimate collection rebuild. No save mutation."}))
	quit(0 if failures.is_empty() else 1)
