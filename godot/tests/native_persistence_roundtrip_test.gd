extends SceneTree
const Repository = preload("res://services/save_repository.gd")
const Factory = preload("res://core/world_factory.gd")
func validate(snapshot: Dictionary) -> Dictionary:
	return Factory.create(str(snapshot.get("levelId", ""))).normalize_saved(snapshot)
func _init() -> void:
	var repository := Repository.new("user://qa-native-offset-quantum.json")
	repository.snapshot_validator = validate
	var world: RefCounted = Factory.create("1-1")
	world.act("grow:root:down")
	world.state.actors.luvie = "g:root:0:1"
	world.state.actors.buddy = "g:root:0:1"
	var failures: Array = []
	var checks := 0
	for index in range(51):
		var offset := snappedf(float(index - 25) * 0.0173, 0.0001)
		world.state.runtime = {"version": 1, "poses": {
			"luvie": {"support": "g:root:0:1", "offset": [offset, 0.0002, 0.02], "facing": "front"},
			"buddy": {"support": "g:root:0:1", "offset": [-0.23, 0.0002, 0.2], "facing": "front"}}}
		var saved: Dictionary = repository.commit_run(world.snapshot())
		checks += 1
		if not saved.ok:
			failures.append({"offset": offset, "error": saved})
			continue
		var restored := Repository.new(repository.path)
		restored.snapshot_validator = validate
		var result: Dictionary = restored.load_store()
		checks += 1
		if not result.ok or restored.data.mainline.runs["1-1"].actors != world.state.actors:
			failures.append("logical positions changed")
			continue
		var actual: Dictionary = restored.data.mainline.runs["1-1"].runtime.poses
		for who: String in ["luvie", "buddy"]:
			checks += 1
			if actual[who].support != world.state.actors[who]:
				failures.append("support changed")
			for axis: int in range(3):
				checks += 1
				if roundi(float(actual[who].offset[axis]) * 10000) != roundi(float(world.state.runtime.poses[who].offset[axis]) * 10000):
					failures.append("position quantum changed")
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(repository.path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(repository.path + suffix))
	print(JSON.stringify({"suite": "native-real-offset-persistence", "checks": checks, "passed": failures.is_empty(), "failures": failures, "positionQuantum": 0.0001}))
	quit(0 if failures.is_empty() else 1)
