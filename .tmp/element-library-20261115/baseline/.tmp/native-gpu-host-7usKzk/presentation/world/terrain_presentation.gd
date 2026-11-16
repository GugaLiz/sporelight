class_name GardenTerrainPresentation
extends RefCounted

## Root boards connect the rule graph without becoming part of an island's
## masonry. Keep this presentation opt-in while other chapters retain theirs.
static func enabled(level: Dictionary) -> bool:
	return str(level.get("id", "")) == "1-1"

static func wall_depth(level: Dictionary, tile: Dictionary, neighbor: Dictionary, base: float) -> float:
	var adjacent := neighbor
	if enabled(level) and _authored_structure(level, tile) and _generated_root(level, neighbor):
		adjacent = {}
	var depth := maxf(0.0, (float(tile.h) - float(adjacent.h)) * 48.0) if not adjacent.is_empty() else maxf(12.0, base + float(tile.h) * 48.0)
	if enabled(level) and _generated_root(level, tile):
		return minf(depth, maxf(0.0, base))
	return depth

static func _authored_structure(level: Dictionary, tile: Dictionary) -> bool:
	var id := str(tile.get("id", ""))
	if id.is_empty() or id.begins_with("g:"):
		return false
	for authored in level.get("tiles", []):
		if str(authored.get("id", "")) == id:
			return true
	return false

static func _generated_root(level: Dictionary, tile: Dictionary) -> bool:
	return not tile.is_empty() and str(tile.get("id", "")).begins_with("g:") and not _authored_structure(level, tile)

## Pair identity is independent of array enumeration and travel direction.
## Existing stairs stay opaque throughout unrelated actions; only changed
## connections fade with the board that introduced or removed them.
static func connections(before_pairs: Array, after_pairs: Array, amount: float) -> Array:
	var before := _pair_map(before_pairs)
	var after := _pair_map(after_pairs)
	var identities: Array = before.keys()
	for key in after:
		if not before.has(key):
			identities.append(key)
	identities.sort()
	var result: Array = []
	var progress := clampf(amount, 0.0, 1.0)
	for key in identities:
		var pair: Array = after[key] if after.has(key) else before[key]
		var opacity := 1.0 if before.has(key) and after.has(key) else progress if after.has(key) else 1.0 - progress
		result.append({"pair": pair, "alpha": opacity})
	return result

static func _pair_map(pairs: Array) -> Dictionary:
	var result: Dictionary = {}
	for pair in pairs:
		if not pair is Array or pair.size() != 2 or not pair[0] is Dictionary or not pair[1] is Dictionary:
			continue
		var first: Dictionary = pair[0]
		var second: Dictionary = pair[1]
		var reversed := float(first.h) > float(second.h) or is_equal_approx(float(first.h), float(second.h)) and str(first.get("id", "")) > str(second.get("id", ""))
		var normalized: Array = [second, first] if reversed else [first, second]
		result[str(normalized[0].get("id", "")) + "|" + str(normalized[1].get("id", ""))] = normalized
	return result
