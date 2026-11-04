extends RefCounted
class_name GardenSaveRepository

const FORMAT := "sporelight.godot"
const VERSION := 1
const LEGACY_KEYS := ["sporelight.save.v2", "sporelight.garden2.v1", "sporelight.cloud-gardens.v1", "sporelight.save.v1"]
const LEVEL_IDS := ["1-1", "1-2", "1-3", "1-4", "2-1", "2-2", "2-3", "2-4", "3-1", "3-2", "3-3", "3-4"]

var path: String
var data: Dictionary
var snapshot_validator: Callable
var _totals: Dictionary = {}


func _init(store_path: String = "user://sporelight-godot.v1.json") -> void:
	path = store_path
	data = empty_store()


static func default_settings() -> Dictionary:
	return {"bgm": 0.35, "sfx": 0.6, "ambient": 0.25, "quality": "standard", "dynamicLight": true, "particles": true, "lowMotion": false, "vibration": false, "fullscreen": false, "language": "zh-CN", "continuousInput": false, "safeCamera": false}


static func empty_store() -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "content_version": 2,
		"player": {"name": "露薇", "has_named": false}, "settings": default_settings(),
		"mainline": {"last_level": "1-1", "runs": {}, "memories": {}, "records": {}},
		"gallery": {}, "legacy_raw": {}, "import_fingerprints": []}


static func json_equivalent(left: Variant, right: Variant) -> bool:
	# JSON has one numeric type; Godot's Dictionary comparison distinguishes
	# native int values from numbers parsed as float. Preserve every other type.
	if left is int or left is float:
		return (right is int or right is float) and float(left) == float(right)
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not json_equivalent(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not json_equivalent(left[index], right[index]):
				return false
		return true
	return left == right


func configure_levels(levels: Array) -> void:
	_totals.clear()
	for level in levels:
		if level is Dictionary and LEVEL_IDS.has(level.get("id", "")):
			_totals[String(level.id)] = int(level.get("total", 0))


func load_store() -> Dictionary:
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			return _recover_backup("missing_primary")
		data = empty_store()
		return {"ok": true, "data": data.duplicate(true), "created": true}
	var parsed := _read_valid_store(path)
	if parsed.ok:
		data = parsed.data
		return {"ok": true, "data": data.duplicate(true), "created": false}
	if FileAccess.file_exists(path + ".bak"):
		return _recover_backup(String(parsed.get("error", "invalid_primary")))
	return {"ok": false, "error": parsed.get("error", "invalid_store"), "data": data.duplicate(true)}


func persist(candidate: Dictionary = {}) -> Dictionary:
	var next := data.duplicate(true) if candidate.is_empty() else candidate.duplicate(true)
	var validation := _validate_store(next)
	if not validation.ok:
		return validation
	var absolute := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		return _failure("create_directory_failed", directory_error)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("open_temporary_failed", FileAccess.get_open_error())
	file.store_string(JSON.stringify(next, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure("write_failed", write_error)
	var verified := _read_valid_store(temporary)
	if not verified.ok or not json_equivalent(verified.get("data"), next):
		return _failure("temporary_verification_failed")
	if FileAccess.file_exists(path):
		# A recovered corrupt primary must never overwrite its valid backup.
		var previous := _read_valid_store(path)
		var backup_target := path + ".bak" if previous.ok else path + ".corrupt"
		var backup_error := DirAccess.copy_absolute(absolute, ProjectSettings.globalize_path(backup_target))
		if backup_error != OK:
			return _failure("backup_failed", backup_error)
		var remove_error := DirAccess.remove_absolute(absolute)
		if remove_error != OK:
			return _failure("replace_failed", remove_error)
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
	if rename_error != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path + ".bak"), absolute)
		return _failure("commit_failed", rename_error)
	var reread := _read_valid_store(path)
	if not reread.ok or not json_equivalent(reread.get("data"), next):
		return _failure("commit_verification_failed")
	data = next
	return {"ok": true, "data": data.duplicate(true)}


func commit_run(snapshot: Dictionary) -> Dictionary:
	var staged := stage_run(snapshot)
	if not staged.ok:
		return staged
	return persist()


# Preserve valid progress in memory even when storage is unavailable, so an
# explicit export includes everything the player has done since the failure.
func stage_run(snapshot: Dictionary) -> Dictionary:
	var checked := _validate_snapshot(snapshot)
	if not checked.ok:
		return checked
	var normalized: Dictionary = checked.snapshot
	var id := String(normalized.levelId)
	var candidate := data.duplicate(true)
	candidate.mainline.last_level = id
	candidate.mainline.runs[id] = normalized.duplicate(true)
	if normalized.get("completed", false):
		candidate.mainline.memories[id] = normalized.duplicate(true)
		var count: int = normalized.get("collected", []).size()
		var total: int = int(_totals.get(id, maxi(1, count)))
		var stars := 3 if count >= total else (2 if count >= ceili(total / 2.0) else 1)
		var old: Dictionary = candidate.mainline.records.get(id, {})
		candidate.mainline.records[id] = {"completed": true, "collected": maxi(int(old.get("collected", 0)), count), "stars": maxi(int(old.get("stars", 0)), stars)}
	data = candidate
	return {"ok": true, "data": data.duplicate(true), "staged": true}


func save_settings(settings: Dictionary) -> Dictionary:
	var candidate := data.duplicate(true)
	candidate.settings = _normalize_settings(settings)
	data = candidate
	return persist()


func export_json() -> String:
	return JSON.stringify(data, "\t")


func export_file(target: String) -> Dictionary:
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return _failure("export_open_failed", FileAccess.get_open_error())
	file.store_string(export_json())
	file.flush()
	var error := file.get_error()
	file.close()
	return {"ok": true} if error == OK else _failure("export_write_failed", error)


func import_file(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _failure("import_open_failed", FileAccess.get_open_error())
	var text := file.get_as_text()
	file.close()
	return import_json(text)


func preview_import_file(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _failure("import_open_failed", FileAccess.get_open_error())
	var text := file.get_as_text()
	file.close()
	return preview_import_json(text)


func download_web_export() -> Dictionary:
	if not OS.has_feature("web"):
		return _failure("web_only")
	JavaScriptBridge.download_buffer(export_json().to_utf8_buffer(), "sporelight-save.json", "application/json")
	return {"ok": true}


func import_json(text: String) -> Dictionary:
	var preview := preview_import_json(text)
	if not preview.ok:
		return preview
	if preview.get("duplicate", false):
		return {"ok": true, "duplicate": true, "data": data.duplicate(true)}
	return persist(preview.data)


func preview_import_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return _failure("invalid_json")
	var source: Dictionary = json.data
	if not ["", FORMAT, "sporelight.legacy-export"].has(source.get("format", "")):
		return _failure("unsupported_import_format")
	if source.get("format", "") == "sporelight.legacy-export" and source.get("version", 0) != 1:
		return _failure("unsupported_legacy_export_version")
	var fingerprint := JSON.stringify(source).sha256_text()
	if data.import_fingerprints.has(fingerprint):
		return {"ok": true, "duplicate": true, "data": data.duplicate(true)}
	var candidate: Dictionary
	if source.get("format", "") == FORMAT:
		var validation := _validate_store(source)
		if not validation.ok:
			return validation
		candidate = _merge_store(data, source)
	else:
		var imported := _import_legacy(source)
		if not imported.ok:
			return imported
		candidate = imported.data
	candidate.import_fingerprints.append(fingerprint)
	var validation := _validate_store(candidate)
	if not validation.ok:
		return validation
	return {"ok": true, "data": candidate, "duplicate": false}


# Explicit user action only. Never called from the constructor or load_store().
func read_web_legacy_preview() -> Dictionary:
	if not OS.has_feature("web"):
		return _failure("web_only")
	var script := "JSON.stringify({format:'sporelight.legacy-export',version:1,keys:Object.fromEntries(['sporelight.save.v2','sporelight.garden2.v1','sporelight.cloud-gardens.v1','sporelight.save.v1'].map(k=>[k,localStorage.getItem(k)]))})"
	var result: Variant = JavaScriptBridge.eval(script, true)
	if not result is String:
		return _failure("browser_storage_unavailable")
	return preview_import_json(result)


func _import_legacy(source: Dictionary) -> Dictionary:
	var raw_value: Variant = source.get("keys", source)
	if not raw_value is Dictionary:
		return _failure("invalid_legacy_keys")
	var raw: Dictionary = raw_value
	var candidate := data.duplicate(true)
	var parsed: Dictionary = {}
	var found := false
	for key in LEGACY_KEYS:
		if not raw.has(key) or raw[key] == null:
			continue
		found = true
		var value: Variant = raw[key]
		var original := String(value) if value is String else JSON.stringify(value)
		candidate.legacy_raw[key] = original
		if key == "sporelight.cloud-gardens.v1":
			continue
		var json := JSON.new()
		if json.parse(original) != OK or not json.data is Dictionary:
			return _failure("invalid_legacy_data:" + key)
		parsed[key] = json.data
	if not found:
		return _failure("no_supported_legacy_keys")
	var old: Dictionary = parsed.get("sporelight.save.v2", parsed.get("sporelight.save.v1", {}))
	if parsed.has("sporelight.save.v2") or parsed.has("sporelight.save.v1"):
		if parsed.has("sporelight.save.v2") and old.get("version", 0) != 2:
			return _failure("invalid_legacy_save_version")
		if not old.get("levels", {}) is Dictionary or not old.get("settings", {}) is Dictionary:
			return _failure("invalid_legacy_save")
		if not old.get("playerName", "露薇") is String or not old.get("hasNamed", false) is bool:
			return _failure("invalid_legacy_player")
		candidate.player = {"name": String(old.get("playerName", "露薇")), "has_named": old.get("hasNamed", false) == true}
		candidate.settings = _normalize_settings(old.get("settings", {}))
		if not old.get("gallery", {}) is Dictionary:
			return _failure("invalid_legacy_gallery")
		for entry in old.get("gallery", {}):
			if old.gallery[entry] == true:
				candidate.gallery[entry] = true
	var garden: Dictionary = parsed.get("sporelight.garden2.v1", {})
	if parsed.has("sporelight.garden2.v1"):
		if garden.get("version", 0) != 1:
			return _failure("unsupported_legacy_garden_version")
		for field in ["runs", "memories", "records"]:
			if not garden.get(field, {}) is Dictionary:
				return _failure("invalid_legacy_" + field)
		for field in ["runs", "memories"]:
			for id in garden.get(field, {}):
				if not LEVEL_IDS.has(id):
					continue
				var snapshot: Variant = garden[field][id]
				if not snapshot is Dictionary:
					return _failure("invalid_legacy_snapshot")
				var validation := _validate_snapshot(snapshot, String(id))
				if not validation.ok:
					return validation
				snapshot = validation.snapshot
				if field == "memories" and not snapshot.get("completed", false):
					return _failure("incomplete_memory")
				candidate.mainline[field][id] = snapshot.duplicate(true)
				if snapshot.get("completed", false) and not candidate.mainline.memories.has(id):
					candidate.mainline.memories[id] = snapshot.duplicate(true)
		for id in garden.get("records", {}):
			if LEVEL_IDS.has(id):
				var record: Variant = garden.records[id]
				if not record is Dictionary or not _valid_legacy_record(record):
					return _failure("invalid_legacy_record")
				_merge_record(candidate.mainline.records, String(id), _legacy_record(record, String(id)))
		if LEVEL_IDS.has(garden.get("lastLevel", "")):
			candidate.mainline.last_level = garden.lastLevel
	elif LEVEL_IDS.has(old.get("lastLevel", "")):
		candidate.mainline.last_level = old.lastLevel
	for id in old.get("levels", {}):
		if LEVEL_IDS.has(id) and not candidate.mainline.records.has(id):
			var legacy: Variant = old.levels[id]
			if not legacy is Dictionary:
				return _failure("invalid_legacy_level_record")
			var record := {"completed": legacy.get("completed", false), "stars": legacy.get("bestStars", 0), "collected": legacy.get("bestCollected", 0)}
			if not _valid_legacy_record(record):
				return _failure("invalid_legacy_level_record_values")
			candidate.mainline.records[id] = _legacy_record(record, String(id))
	return {"ok": true, "data": candidate}


func _legacy_record(record: Dictionary, id: String) -> Dictionary:
	return {"completed": record.get("completed", false) == true, "stars": clampi(int(record.get("stars", 0)), 0, 3), "collected": clampi(int(record.get("collected", 0)), 0, int(_totals.get(id, 999)))}


func _valid_legacy_record(record: Dictionary) -> bool:
	return record.get("completed", false) is bool and _whole_number(record.get("stars", 0), 0, 3) and _whole_number(record.get("collected", 0), 0, 999)


func _merge_store(current: Dictionary, imported: Dictionary) -> Dictionary:
	var result := current.duplicate(true)
	result.player = imported.player.duplicate(true)
	result.settings = imported.settings.duplicate(true)
	result.gallery.merge(imported.gallery, true)
	result.legacy_raw.merge(imported.legacy_raw, true)
	result.mainline.last_level = imported.mainline.last_level
	for field in ["runs", "memories"]:
		result.mainline[field].merge(imported.mainline[field], true)
	for id in imported.mainline.records:
		_merge_record(result.mainline.records, String(id), imported.mainline.records[id])
	return result


func _merge_record(records: Dictionary, id: String, record: Dictionary) -> void:
	var existing: Dictionary = records.get(id, {})
	records[id] = {"completed": bool(existing.get("completed", false)) or bool(record.get("completed", false)), "stars": maxi(int(existing.get("stars", 0)), int(record.get("stars", 0))), "collected": maxi(int(existing.get("collected", 0)), int(record.get("collected", 0)))}


func _normalize_settings(raw: Variant) -> Dictionary:
	var result := default_settings()
	if not raw is Dictionary:
		return result
	for key in ["bgm", "sfx", "ambient"]:
		if raw.get(key) is float or raw.get(key) is int:
			result[key] = clampf(float(raw[key]), 0, 1)
	for key in ["dynamicLight", "particles", "lowMotion", "vibration", "fullscreen", "continuousInput", "safeCamera"]:
		if raw.get(key) is bool:
			result[key] = raw[key]
	if ["soft", "standard", "hd"].has(raw.get("quality", "")):
		result.quality = raw.quality
	if ["zh-CN", "zh-TW", "en"].has(raw.get("language", "")):
		result.language = raw.language
	return result


func _validate_store(value: Dictionary) -> Dictionary:
	if value.get("format", "") != FORMAT or value.get("version", 0) != VERSION or value.get("content_version", 0) != 2:
		return _failure("unsupported_store_version")
	for field in ["player", "settings", "mainline", "gallery", "legacy_raw"]:
		if not value.get(field) is Dictionary:
			return _failure("invalid_field:" + field)
	if not value.get("import_fingerprints") is Array:
		return _failure("invalid_import_history")
	for fingerprint in value.import_fingerprints:
		if not fingerprint is String:
			return _failure("invalid_import_fingerprint")
	if not value.player.get("name") is String or not value.player.get("has_named") is bool:
		return _failure("invalid_player")
	for key in ["bgm", "sfx", "ambient"]:
		var volume: Variant = value.settings.get(key)
		if not (volume is int or volume is float) or not is_finite(float(volume)) or float(volume) < 0 or float(volume) > 1:
			return _failure("invalid_volume")
	for key in ["dynamicLight", "particles", "lowMotion", "vibration", "fullscreen"]:
		if not value.settings.get(key) is bool:
			return _failure("invalid_setting:" + key)
	for key in ["continuousInput", "safeCamera"]:
		# Early preview stores did not have the two independent experiment flags.
		if not value.settings.has(key):
			value.settings[key] = false
		elif not value.settings[key] is bool:
			return _failure("invalid_setting:" + key)
	if not ["soft", "standard", "hd"].has(value.settings.get("quality", "")) or not ["zh-CN", "zh-TW", "en"].has(value.settings.get("language", "")):
		return _failure("invalid_setting_variant")
	var mainline: Dictionary = value.mainline
	if not LEVEL_IDS.has(mainline.get("last_level", "")):
		return _failure("invalid_last_level")
	for field in ["runs", "memories", "records"]:
		if not mainline.get(field) is Dictionary:
			return _failure("invalid_field:" + field)
	for field in ["runs", "memories"]:
		for id in mainline[field]:
			var snapshot: Variant = mainline[field][id]
			if not snapshot is Dictionary:
				return _failure("invalid_snapshot")
			var validation := _validate_snapshot(snapshot, String(id))
			if not validation.ok:
				return validation
			snapshot = validation.snapshot
			mainline[field][id] = snapshot
			if field == "memories" and not snapshot.get("completed", false):
				return _failure("incomplete_memory")
	for id in mainline.records:
		if not LEVEL_IDS.has(id) or not mainline.records[id] is Dictionary:
			return _failure("invalid_record")
		var record: Dictionary = mainline.records[id]
		if not record.get("completed") is bool or not _whole_number(record.get("stars"), 0, 3) or not _whole_number(record.get("collected"), 0, int(_totals.get(id, 999))):
			return _failure("invalid_record_values")
	for key in value.legacy_raw:
		if not LEGACY_KEYS.has(key) or not value.legacy_raw[key] is String:
			return _failure("invalid_legacy_raw")
	return {"ok": true}


func _validate_snapshot(snapshot: Dictionary, expected_id: String = "") -> Dictionary:
	var id := String(snapshot.get("levelId", ""))
	if snapshot.get("designVersion", 0) != 2 or not LEVEL_IDS.has(id) or (not expected_id.is_empty() and expected_id != id):
		return _failure("invalid_snapshot_version_or_level")
	if not snapshot.get("actors") is Dictionary or not ["luvie", "buddy"].has(snapshot.get("active", "")):
		return _failure("invalid_snapshot_actor")
	for actor in ["luvie", "buddy"]:
		if not snapshot.actors.get(actor) is String or snapshot.actors[actor].is_empty():
			return _failure("invalid_snapshot_position")
	for field in ["growth", "turns", "items"]:
		if not snapshot.get(field) is Dictionary:
			return _failure("invalid_snapshot_" + field)
	for field in ["flags", "collected", "observations"]:
		if not snapshot.get(field) is Array:
			return _failure("invalid_snapshot_" + field)
		for entry in snapshot[field]:
			if not entry is String:
				return _failure("invalid_snapshot_list_item")
	if not snapshot.get("completed") is bool:
		return _failure("invalid_snapshot_completion")
	if snapshot_validator.is_valid():
		var result: Variant = snapshot_validator.call(snapshot.duplicate(true))
		var accepted: bool = result if result is bool else (bool(result.get("ok", false)) if result is Dictionary else false)
		if not accepted:
			return _failure("snapshot_rule_validation_failed")
		if result is Dictionary and result.has("snapshot"):
			if not result.snapshot is Dictionary or result.snapshot.get("levelId") != id:
				return _failure("invalid_normalized_snapshot")
			return {"ok": true, "snapshot": result.snapshot.duplicate(true)}
	return {"ok": true, "snapshot": snapshot.duplicate(true)}


func _read_valid_store(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _failure("read_failed", FileAccess.get_open_error())
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return _failure("invalid_json")
	var validation := _validate_store(json.data)
	return {"ok": true, "data": json.data} if validation.ok else validation


func _recover_backup(reason: String) -> Dictionary:
	var backup := _read_valid_store(path + ".bak")
	if not backup.ok:
		return _failure("primary_and_backup_invalid:" + reason)
	data = backup.data
	return {"ok": true, "data": data.duplicate(true), "recovered": true, "warning": reason}


func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


func _failure(reason: String, code: int = FAILED) -> Dictionary:
	return {"ok": false, "error": reason, "code": code}
