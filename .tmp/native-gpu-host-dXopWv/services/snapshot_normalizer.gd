extends RefCounted
## Pure domain normalization for the fixed, packaged level definitions.
## Persistence still validates every record and every read-back. Only identical
## snapshot values can reuse a successful normalization; callers own all copies.
const Factory = preload("res://core/world_factory.gd")
const Repository = preload("res://services/save_repository.gd")
const ENTRIES_PER_LEVEL := 4
const MAX_SAFE_JSON_INTEGER := 9007199254740991
var _entries: Dictionary = {}

func normalize(snapshot: Dictionary) -> Dictionary:
	var id := str(snapshot.get("levelId", ""))
	if not id in Repository.LEVEL_IDS:
		return {"ok": false}
	var entries: Array = _entries.get(id, [])
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		# JSON round-trips represent integers as floats. The rule normalizers
		# accept both, while booleans/strings and every nested value stay distinct.
		if _cache_equivalent(snapshot, entry.input):
			entries.remove_at(index)
			entries.push_front(entry)
			return entry.result.duplicate(true)
	var result := _normalize_uncached(id, snapshot)
	if bool(result.get("ok", false)):
		entries.push_front({"input": snapshot.duplicate(true), "result": result.duplicate(true)})
		if entries.size() > ENTRIES_PER_LEVEL: entries.pop_back()
		_entries[id] = entries
	return result

static func _cache_equivalent(left: Variant, right: Variant) -> bool:
	# Converting two int64 values to float can merge distinct values above
	# 2^53 (and change a normalized turn's modulo). Keep integers exact and
	# conservatively miss unsafe mixed numeric types instead of guessing.
	if left is int and right is int: return left == right
	if left is float and right is float: return left == right
	if (left is int and right is float) or (left is float and right is int):
		var integer: int = left if left is int else right
		if integer < -MAX_SAFE_JSON_INTEGER or integer > MAX_SAFE_JSON_INTEGER: return false
		return float(left) == float(right)
	if typeof(left) != typeof(right): return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key: Variant in left:
			if not right.has(key) or not _cache_equivalent(left[key], right[key]): return false
		return true
	if left is Array:
		if left.size() != right.size(): return false
		for index: int in left.size():
			if not _cache_equivalent(left[index], right[index]): return false
		return true
	return left == right

func _normalize_uncached(id: String, snapshot: Dictionary) -> Dictionary:
	return Factory.create(id).normalize_saved(snapshot)

func clear() -> void:
	_entries.clear()
