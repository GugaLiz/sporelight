extends RefCounted
## Bottoms are local to a rigid island, not to the lowest tile in the level.
## Supply the complete geometry snapshot (including invisible tiles). During
## motion the stage supplies its departure snapshot and moves that mesh whole.
const BASE_THICKNESS := 0.67
const HEIGHT_UNIT := 0.65
const THIN_KINDS := ["root", "bridge", "shadow"]

static func bottoms(tiles: Array) -> Dictionary:
	var result := {}
	var pending: Array[Dictionary] = []
	var modules := {}
	for tile: Dictionary in tiles:
		var kind := str(tile.get("kind", "fixed"))
		if kind in THIN_KINDS or str(tile.id).begins_with("g:"):
			result[str(tile.id)] = float(tile.h) * HEIGHT_UNIT - 0.20
		elif kind == "module":
			var key := str(tile.get("module", str(tile.id).get_slice(":", 1)))
			if not modules.has(key): modules[key] = []
			modules[key].append(tile)
		else:
			pending.append(tile)
	for group: Array in modules.values(): _assign(group, result)
	while not pending.is_empty():
		var group: Array[Dictionary] = [pending.pop_back()]
		var index := 0
		while index < group.size():
			var tile: Dictionary = group[index]
			for candidate_index in range(pending.size() - 1, -1, -1):
				var candidate: Dictionary = pending[candidate_index]
				if _family(tile) != _family(candidate): continue
				var dx := absf(float(tile.x) - float(candidate.x))
				var dz := absf(float(tile.z) - float(candidate.z))
				if (is_zero_approx(dx) and is_equal_approx(dz, 1.0)) or (is_zero_approx(dz) and is_equal_approx(dx, 1.0)):
					group.append(candidate)
					pending.remove_at(candidate_index)
			index += 1
		_assign(group, result)
	return result

static func _family(tile: Dictionary) -> String:
	var kind := str(tile.get("kind", "fixed"))
	# Cloud lift cells have no module ID. Gates are temporary connectors;
	# neither may merge fixed banks when they happen to dock/open beside them.
	return kind if kind in ["lift", "gate"] else "fixed"

static func _assign(group: Array, result: Dictionary) -> void:
	var minimum := INF
	for tile: Dictionary in group: minimum = minf(minimum, float(tile.h) * HEIGHT_UNIT)
	for tile: Dictionary in group: result[str(tile.id)] = minimum - BASE_THICKNESS
