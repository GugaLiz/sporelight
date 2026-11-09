extends SceneTree
const Repository = preload("res://services/save_repository.gd")
const Factory = preload("res://core/world_factory.gd")
var checks := 0
var failures := 0
func verify(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func validate(snapshot: Dictionary) -> Dictionary:
	return Factory.create(str(snapshot.get("levelId", ""))).normalize_saved(snapshot)
func _init() -> void:
	var repository := Repository.new("user://qa-native-cloud-store.json")
	repository.snapshot_validator = validate
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	var legacy := {"version": 1, "runs": {}, "memories": {}, "completed": [], "discoveries": {}}
	for fixture: Dictionary in fixtures.levels:
		var final: Dictionary = fixture.steps.back().snapshot
		legacy.runs[fixture.id] = final
		legacy.memories[fixture.id] = final
		legacy.completed.append(fixture.id)
		legacy.discoveries[fixture.id] = final.found
	var preview: Dictionary = repository.preview_import_json(JSON.stringify({"format": "sporelight.legacy-export", "version": 1, "keys": {"sporelight.cloud-gardens.v1": JSON.stringify(legacy)}}))
	verify(preview.get("ok", false), "cloud legacy preview")
	if not preview.get("ok", false):
		quit(1)
		return
	for fixture: Dictionary in fixtures.levels:
		verify(preview.data.mainline.runs.has(fixture.id), "cloud run decoded")
		verify(preview.data.mainline.memories.has(fixture.id), "cloud memory decoded")
		verify(preview.data.mainline.records[fixture.id].collected == 2, "cloud discovery score")
		verify(preview.data.mainline.runs[fixture.id].completed, "cloud repaired retained")
	verify(repository.data.mainline.runs.is_empty(), "preview is read only")
	verify(repository.import_json(JSON.stringify({"format": "sporelight.legacy-export", "version": 1, "keys": {"sporelight.cloud-gardens.v1": JSON.stringify(legacy)}})).ok, "cloud legacy import")
	var loaded := Repository.new("user://qa-native-cloud-store.json")
	loaded.snapshot_validator = validate
	verify(loaded.load_store().ok, "cloud save reload")
	for fixture: Dictionary in fixtures.levels:
		verify(loaded.data.mainline.runs.has(fixture.id), "cloud reload run")
	var first: RefCounted = Factory.create("cloud-1")
	verify(loaded.stage_run(first.snapshot()).ok, "new cloud run stages")
	var before: Dictionary = loaded.data.mainline.runs["cloud-1"].duplicate(true)
	loaded._adopt_retained_cloud(loaded.data)
	verify(loaded.data.mainline.runs["cloud-1"] == before, "retained legacy cannot overwrite native play")
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists("user://qa-native-cloud-store.json" + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://qa-native-cloud-store.json" + suffix))
	# Discoveries are permanent across undo/replay, independent of completion.
	var retained := Repository.new("user://qa-native-cloud-discoveries.json")
	retained.snapshot_validator = validate
	var partial := {"version": 1, "runs": {}, "memories": {}, "completed": [], "discoveries": {"cloud-1": ["wind"]}}
	var partial_result: Dictionary = retained.preview_import_json(JSON.stringify({"format": "sporelight.legacy-export", "version": 1, "keys": {"sporelight.cloud-gardens.v1": JSON.stringify(partial)}}))
	verify(partial_result.ok and "wind" in partial_result.data.cloud_discoveries.get("cloud-1", []), "uncompleted legacy discoveries retained")
	retained.data = partial_result.data
	var run: RefCounted = Factory.create("cloud-1")
	run.state.observations = ["letter"]
	run.state.collected = ["letter"]
	verify(retained.stage_run(run.snapshot()).ok, "stage new discovery")
	verify(retained.data.cloud_discoveries["cloud-1"].size() == 2, "merge permanent discoveries")
	verify(retained.stage_run(Factory.create("cloud-1").snapshot()).ok, "stage replay")
	verify(retained.data.cloud_discoveries["cloud-1"].size() == 2, "replay never erases discoveries")
	var touch_settings: Dictionary = retained.data.settings.duplicate(true)
	touch_settings.touchControls = true
	verify(retained.save_settings(touch_settings).ok, "save touch preference")
	var reread := Repository.new(retained.path)
	reread.snapshot_validator = validate
	verify(reread.load_store().ok and reread.data.settings.touchControls, "reload touch preference")
	var old_store: Dictionary = Repository.empty_store()
	old_store.erase("cloud_discoveries")
	old_store.legacy_raw["sporelight.cloud-gardens.v1"] = JSON.stringify(partial)
	var backup := FileAccess.open(retained.path + ".bak", FileAccess.WRITE)
	backup.store_string(JSON.stringify(old_store))
	backup.close()
	var primary := FileAccess.open(retained.path, FileAccess.WRITE)
	primary.store_string("invalid primary")
	primary.close()
	var recovered := Repository.new(retained.path)
	recovered.snapshot_validator = validate
	var recovery: Dictionary = recovered.load_store()
	verify(recovery.ok and recovery.get("recovered", false) and "wind" in recovered.data.cloud_discoveries.get("cloud-1", []), "backup cloud discoveries migrate")
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(retained.path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(retained.path + suffix))
	print("Cloud save: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
