extends SceneTree

const Repository := preload("res://services/save_repository.gd")
const World := preload("res://core/garden_world.gd")
var _checks := 0
var _failures: Array[String] = []
var _paths: Array[String] = []


func _initialize() -> void:
	create_timer(20).timeout.connect(func() -> void:
		_failures.append("Suite timed out after a runtime exception")
		_finish())
	var test_path := "user://tests/service-save-%s.json" % Time.get_ticks_usec()
	var repository := Repository.new(test_path)
	_expect(Repository.json_equivalent({"value": 1}, {"value": 1.0}), "JSON numeric int/float roundtrip is semantically equal")
	_expect(not Repository.json_equivalent({"value": true}, {"value": 1}), "JSON equivalence keeps boolean and number distinct")
	_paths.append(test_path)
	repository.configure_levels([{"id": "1-1", "total": 3}, {"id": "1-3", "total": 4}])
	_expect(repository.load_store().ok, "New isolated store loads without browser migration")
	_expect(repository.data.settings.bgm == 0.35 and repository.data.settings.sfx == 0.6 and repository.data.settings.ambient == 0.25, "Default volume matches the frozen browser implementation")
	_expect(repository.data.settings.continuousInput and repository.data.settings.inputSettingsRevision == 1 and not repository.data.settings.safeCamera, "Normal hold-to-walk defaults on without enabling safe-camera framing")
	var initial := _snapshot(false)
	if not _expect_ok(repository.commit_run(initial), "A valid active run persists"):
		_finish()
		return
	_expect(repository.data.mainline.memories.is_empty(), "Active runs do not manufacture memories")
	var completed := _snapshot(true)
	completed.collected = ["spore-0", "spore-1", "spore-2"]
	if not _expect_ok(repository.commit_run(completed), "Completed snapshot persists"):
		_finish()
		return
	_expect(repository.data.mainline.records["1-1"].stars == 3, "Completed collection receives three stars")
	var weaker := _snapshot(true)
	if not _expect_ok(repository.commit_run(weaker), "A weaker replay remains playable"):
		_finish()
		return
	_expect(repository.data.mainline.records["1-1"].collected == 3, "Weaker replay retains the best collection")
	var previous := repository.export_json()
	_expect(not repository.import_json("{broken").ok, "Broken JSON is rejected")
	_expect(repository.export_json() == previous, "Rejected import does not modify in-memory data")
	var reread := Repository.new(test_path)
	reread.configure_levels([{"id": "1-1", "total": 3}])
	_expect(reread.load_store().ok and reread.data.mainline.records["1-1"].collected == 3, "Persisted best score survives a fresh repository")
	var legacy := {"format": "sporelight.legacy-export", "version": 1, "keys": {
		"sporelight.save.v2": JSON.stringify({"version": 2, "playerName": "测试旅人", "hasNamed": true, "levels": {"1-3": {"completed": true, "bestStars": 2, "bestCollected": 2}}}),
		"sporelight.garden2.v1": JSON.stringify({"version": 1, "lastLevel": "1-1", "records": {"1-1": {"completed": true, "stars": 1, "collected": 1}}}),
		"sporelight.cloud-gardens.v1": "opaque-cloud-data-retained"}}
	var legacy_text := JSON.stringify(legacy)
	var preview := repository.preview_import_json(legacy_text)
	_expect(preview.ok and repository.export_json() == previous, "Import preview leaves current data unchanged")
	if not _expect_ok(repository.import_json(legacy_text), "Explicit legacy bundle imports"):
		_finish()
		return
	_expect(repository.data.mainline.records["1-1"].collected == 3, "Imported lower score cannot lower the current best")
	_expect(repository.data.mainline.records["1-3"].completed, "Old score fallback imports a missing mainline record")
	_expect(not repository.data.mainline.memories.has("1-3"), "A completion record alone does not fabricate a revisit snapshot")
	_expect(repository.data.legacy_raw["sporelight.cloud-gardens.v1"] == "opaque-cloud-data-retained", "Independent cloud data is retained verbatim")
	_expect(repository.import_json(legacy_text).get("duplicate", false), "Repeated import is idempotent")
	_expect(repository.import_json(JSON.stringify(legacy, "\t")).get("duplicate", false), "Whitespace changes do not repeat the same import")
	var bad_record := {"keys": {"sporelight.garden2.v1": JSON.stringify({"version": 1, "records": {"1-1": {"completed": true, "stars": "three", "collected": 1}}})}}
	previous = repository.export_json()
	_expect(not repository.import_json(JSON.stringify(bad_record)).ok and repository.export_json() == previous, "Malformed legacy scores cannot replace valid progress")
	var old_fallback := {"keys": {"sporelight.save.v1": JSON.stringify({"version": 1, "playerName": "旧旅人", "hasNamed": true, "levels": {"1-3": {"completed": true, "bestStars": 1, "bestCollected": 1}}})}}
	_expect(repository.import_json(JSON.stringify(old_fallback)).ok and repository.data.mainline.records["1-3"].collected == 2, "Oldest save fallback preserves a newer better record")
	var invalid := repository.data.duplicate(true)
	invalid.mainline.runs["1-1"].actors.luvie = ""
	previous = repository.export_json()
	_expect(not repository.persist(invalid).ok and repository.export_json() == previous, "Invalid snapshot cannot replace the store")
	repository.snapshot_validator = func(_snapshot_value: Dictionary) -> bool: return false
	_expect(not repository.commit_run(initial).ok and repository.export_json() == previous, "Rule-level rejection cannot replace valid progress")
	repository.snapshot_validator = Callable()
	var blocked := test_path + ".blocked"
	var blocker := FileAccess.open(blocked, FileAccess.WRITE)
	blocker.store_string("This test file intentionally blocks a directory.")
	blocker.close()
	_paths.append(blocked)
	var unavailable := Repository.new(blocked + "/save.json")
	_expect(not unavailable.commit_run(initial).ok, "Storage write failure is reported")
	_expect(unavailable.data.mainline.runs.has("1-1"), "A failed disk commit still retains valid progress in memory")
	var later := initial.duplicate(true)
	later.actors.luvie = "f:-1:0"
	_expect_ok(unavailable.stage_run(later), "Later progress can stage without retrying inaccessible storage")
	var rescued: Dictionary = JSON.parse_string(unavailable.export_json())
	_expect(rescued.mainline.runs["1-1"].actors.luvie == "f:-1:0", "Export after storage failure includes the latest staged position")
	_expect(not unavailable.save_settings({"bgm": 0.1, "sfx": 0.2, "ambient": 0.3}).ok and unavailable.data.settings.bgm == 0.1, "Unsaved settings remain active and exportable in memory")
	var corrupt := FileAccess.open(test_path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var recovered := Repository.new(test_path)
	var recovery := recovered.load_store()
	_expect(recovery.ok and recovery.get("recovered", false), "Corrupt primary recovers from the last valid backup")
	_expect(recovered.persist().ok and FileAccess.file_exists(test_path + ".corrupt"), "Saving recovered data retains the corrupt original without replacing its good backup")
	var real_path := test_path + ".real-world"
	_paths.append(real_path)
	var real_repository := Repository.new(real_path)
	real_repository.configure_levels([{"id": "1-3", "total": 4}])
	real_repository.snapshot_validator = _validate_real_snapshot
	var world := World.new("1-3")
	var real_result := real_repository.commit_run(world.snapshot())
	_expect_ok(real_result, "A complete real-world snapshot persists with rule-level validation")
	var real_loaded := Repository.new(real_path)
	real_loaded.configure_levels([{"id": "1-3", "total": 4}])
	real_loaded.snapshot_validator = _validate_real_snapshot
	var real_load_result := real_loaded.load_store()
	_expect_ok(real_load_result, "A real-world JSON roundtrip passes rule-level validation")
	_expect(Repository.json_equivalent(real_loaded.data.mainline.runs.get("1-3", {}), world.snapshot()), "Loaded real-world state retains JSON-equivalent rule data")
	var normalizing := Repository.new(test_path + ".normalizing")
	normalizing.snapshot_validator = func(value: Dictionary) -> Dictionary:
		value["discovered"] = ["legacy-default-restored"]
		return {"ok": true, "snapshot": value}
	_expect_ok(normalizing.stage_run(initial), "Dictionary validators can normalize an accepted old snapshot")
	_expect(normalizing.data.mainline.runs["1-1"].get("discovered", []) == ["legacy-default-restored"], "Staged progress consumes the validator's normalized snapshot")
	var normalize_import := Repository.new(test_path + ".normalized-import")
	normalize_import.snapshot_validator = normalizing.snapshot_validator
	var source_export := Repository.empty_store()
	source_export.settings.erase("continuousInput")
	source_export.settings.erase("safeCamera")
	source_export.settings.erase("inputSettingsRevision")
	source_export.mainline.runs["1-1"] = initial.duplicate(true)
	var normalize_preview := normalize_import.preview_import_json(JSON.stringify(source_export))
	_expect(normalize_preview.ok and normalize_preview.data.mainline.runs["1-1"].get("discovered", []) == ["legacy-default-restored"], "New-format import consumes normalized snapshot values")
	_expect(normalize_preview.ok and normalize_preview.data.settings.continuousInput and normalize_preview.data.settings.inputSettingsRevision == 1 and not normalize_preview.data.settings.safeCamera, "Earlier preview stores receive normal hold-to-walk without enabling the camera option")
	var isolated_settings := Repository.new(test_path + ".settings")
	_paths.append(test_path + ".settings")
	_expect_ok(isolated_settings.save_settings({"continuousInput": true, "safeCamera": false}), "Continuous input can persist independently from safe-camera framing")
	_expect(isolated_settings.data.settings.continuousInput and not isolated_settings.data.settings.safeCamera, "Independent experience choices remain separate")
	var legacy_snapshot_import := {"keys": {"sporelight.garden2.v1": JSON.stringify({"version": 1, "runs": {"1-1": initial}})}}
	var legacy_normalize_preview := normalize_import.preview_import_json(JSON.stringify(legacy_snapshot_import))
	_expect(legacy_normalize_preview.ok and legacy_normalize_preview.data.mainline.runs["1-1"].get("discovered", []) == ["legacy-default-restored"], "Legacy import consumes normalized snapshot values")
	_input_settings_cases(repository.data.duplicate(true), test_path)
	_finish()


func _input_settings_cases(source: Dictionary, test_path: String) -> void:
	for camera: bool in [false, true]:
		var old := source.duplicate(true)
		old.settings.erase("inputSettingsRevision")
		old.settings.continuousInput = false
		old.settings.safeCamera = camera
		old.settings.bgm = 0.17
		old.settings.lowMotion = true
		old.settings.quality = "hd"
		var expected := old.duplicate(true)
		expected.settings.continuousInput = true
		expected.settings.inputSettingsRevision = 1
		var path := test_path + (".old-camera-on" if camera else ".old-camera-off")
		_paths.append(path)
		_write_test_file(path, JSON.stringify(old))
		var loaded := Repository.new(path)
		_expect_ok(loaded.load_store(), "An unmarked old false setting loads")
		_expect(Repository.json_equivalent(expected, loaded.data), "Old-default correction changes only continuous input and its revision, preserving full progress and the existing camera choice")
		_expect_ok(loaded.persist(), "The corrected input revision can persist")
		var reread := Repository.new(path)
		_expect_ok(reread.load_store(), "The corrected store reloads")
		_expect(Repository.json_equivalent(expected, reread.data), "Correction is stable on a second load")
		var choice: Dictionary = reread.data.settings.duplicate(true)
		choice.continuousInput = false
		_expect_ok(reread.save_settings(choice), "A player may explicitly select single-step after the correction")
		expected.settings.continuousInput = false
		var opted_out := Repository.new(path)
		_expect_ok(opted_out.load_store(), "A revised explicit false setting reloads")
		_expect(Repository.json_equivalent(expected, opted_out.data), "The revision preserves a later explicit false and all unrelated settings and progress")
		var export_path := path + ".import"
		_paths.append(export_path)
		var importing := Repository.new(export_path)
		var before := importing.export_json()
		var preview := importing.preview_import_json(JSON.stringify(old))
		_expect(preview.ok and preview.data.settings.continuousInput and preview.data.settings.inputSettingsRevision == 1, "Old-format current-schema import preview corrects an explicit legacy false")
		_expect(importing.export_json() == before, "Input correction during preview does not modify the destination")
		_expect_ok(importing.import_json(JSON.stringify(old)), "An old false setting imports with its original progress")
		_expect(Repository.json_equivalent(importing.data.mainline, old.mainline) and Repository.json_equivalent(importing.data.settings, preview.data.settings), "Import preserves complete mainline progress and independently normalizes input settings")
		var import_read := Repository.new(export_path)
		_expect_ok(import_read.load_store(), "Imported correction survives disk roundtrip")
		_expect(import_read.data.settings.continuousInput and import_read.data.settings.safeCamera == camera, "Imported continuous walking never changes either camera preference")
		var explicit_preview := importing.preview_import_json(opted_out.export_json())
		_expect(explicit_preview.ok and not explicit_preview.data.settings.continuousInput and explicit_preview.data.settings.inputSettingsRevision == 1, "An exported revised opt-out remains false when imported")
		_expect_ok(importing.import_json(opted_out.export_json()), "An explicit revised opt-out imports")
		var explicit_read := Repository.new(export_path)
		_expect_ok(explicit_read.load_store(), "An imported revised opt-out reloads")
		_expect(not explicit_read.data.settings.continuousInput and explicit_read.data.settings.safeCamera == camera, "Import and reload preserve the explicit single-step choice without camera coupling")
		var backup_path := path + ".backup"
		_paths.append(backup_path)
		_write_test_file(backup_path, "{broken")
		_write_test_file(backup_path + ".bak", JSON.stringify(old))
		var backup := Repository.new(backup_path)
		var recovery := backup.load_store()
		_expect(recovery.ok and recovery.get("recovered", false), "A corrupt primary may recover an unmarked old backup")
		expected.settings.continuousInput = true
		_expect(Repository.json_equivalent(expected, backup.data), "Backup recovery applies the same one-time correction and preserves everything else")
	var direct_path := test_path + ".explicit-settings"
	_paths.append(direct_path)
	var direct := Repository.new(direct_path)
	_expect_ok(direct.save_settings({"continuousInput": false, "safeCamera": false}), "An explicit settings action carries the current revision even without a supplied marker")
	var direct_read := Repository.new(direct_path)
	_expect_ok(direct_read.load_store(), "An explicit settings action reloads")
	_expect(not direct_read.data.settings.continuousInput and direct_read.data.settings.inputSettingsRevision == 1 and not direct_read.data.settings.safeCamera, "Settings normalization distinguishes a fresh explicit false from an unmarked old default")
	var malformed := source.duplicate(true)
	malformed.settings.inputSettingsRevision = "1"
	var stable := direct_read.export_json()
	_expect(not direct_read.preview_import_json(JSON.stringify(malformed)).ok and direct_read.export_json() == stable, "A malformed revision cannot replace valid settings")


func _write_test_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _finish() -> void:
	for target in _paths:
		for suffix in ["", ".tmp", ".bak", ".corrupt"]:
			if FileAccess.file_exists(target + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(target + suffix))
	print(JSON.stringify({"suite": "service_save", "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _expect_ok(result: Dictionary, description: String) -> bool:
	var ok: bool = result.get("ok", false)
	_expect(ok, description + (" (%s)" % result.get("error", "unknown_error") if not ok else ""))
	return ok


func _validate_real_snapshot(snapshot_value: Dictionary) -> bool:
	var restored := World.new(String(snapshot_value.levelId), snapshot_value)
	return Repository.json_equivalent(restored.snapshot(), snapshot_value)


func _snapshot(completed: bool) -> Dictionary:
	return {"designVersion": 2, "levelId": "1-1", "active": "luvie", "actors": {"luvie": "f:0:0", "buddy": "f:0:0"}, "growth": {}, "turns": {}, "items": {}, "flags": [], "collected": [], "observations": [], "completed": completed}


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error(description)
