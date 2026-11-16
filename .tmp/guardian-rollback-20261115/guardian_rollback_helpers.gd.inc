func _guardian_revision2_definition() -> Dictionary:
	# Validation-only description of the rejected layout. It is never selected
	# by gameplay and cannot be activated by an arbitrary saved-state field.
	var definition := level.duplicate(true)
	definition.tiles = definition.tiles.filter(func(tile: Dictionary) -> bool: return not tile.get("small", false))
	for tile: Dictionary in definition.tiles:
		if tile.id == "f:8:-1": tile.solid = true
	for p: Vector2i in [Vector2i(-4,2),Vector2i(-4,3),Vector2i(-3,3),Vector2i(-2,3),Vector2i(-1,3),Vector2i(0,3),Vector2i(1,3),Vector2i(2,3)]:
		_add(definition.tiles,p.x,p.y,0,"fixed",true)
	_add(definition.tiles,4,-3,0,"fixed")
	_add(definition.tiles,4,-2,0,"fixed")
	_add(definition.tiles,8,2,2,"fixed")
	definition.walls = [[8,-1]]
	for module: Dictionary in definition.modules:
		match str(module.id):
			"inner": module.kind = "fixed"
			"water":
				module.kind = "fixed"; module.x = 4; module.z = 3
				module.shape = []
				for x: int in range(-1,2):
					for z: int in range(-1,2): module.shape.append([x,z])
			"light":
				module.kind = "fixed"; module.z = 3
				module.shape = [[0,0],[0,-1]]
				module.erase("axis"); module.erase("distance")
	return definition

func _guardian_rollback_revision2(saved: Dictionary) -> Dictionary:
	var source: RefCounted = get_script().new("3-4")
	source._validating_guardian_revision2 = true
	source.level = _guardian_revision2_definition()
	# Reuse the unchanged strict snapshot validator against the actual rejected
	# board, including bodies, items, root-chain topology and finite local poses.
	if not source._restore(saved,source.snapshot()): return {}
	source.state.turns.inner = 0
	source.state.turns.light = 0
	source.state.turns.water = 1 if int(source.state.turns.water)==1 else 0
	var source_board: Array = source.tiles()
	var result: Dictionary = source.snapshot()
	var lit_before: bool = source.beam_hits(-4,0)
	result.erase("layoutRevision")
	result.erase("runtime")
	result.turns.inner = 0
	result.turns.light = 1 if lit_before else 0
	var restored: RefCounted = get_script().new("3-4")
	restored.state = result
	var old_board: Array = restored.tiles()
	for who: String in ACTORS:
		var id := str(result.actors[who])
		result.actors[who] = _guardian_rollback_support(id,who,source_board,old_board,result)
		if str(result.actors[who]).is_empty(): return {}
	for item: Dictionary in result.items.values():
		if str(item.tile).is_empty(): continue
		item.tile = _guardian_rollback_support(str(item.tile),"item",source_board,old_board,result)
		if str(item.tile).is_empty(): return {}
	# The rejected version allowed empty platform calls from both shores.
	# Restore an empty platform at the occupied shore rather than stranding a
	# valid save in the older version, which has no shore-call command.
	var occupied := false
	var high := false
	for who: String in ACTORS:
		var id := str(result.actors[who])
		occupied = occupied or id.begins_with("m:lift:")
		var point: Dictionary = restored.point_for(id)
		high = high or (not point.is_empty() and float(point.h)>=2.0)
	if not occupied: result.turns.lift = 1 if high else 0
	# Docking removes the opposite landing. Keep a grounded item on the same
	# shore instead of leaving its saved support attached to that landing.
	var docked_board: Array = restored.tiles()
	for item: Dictionary in result.items.values():
		var id := str(item.tile)
		if id.is_empty() or not _find_tile(id,docked_board).is_empty(): continue
		item.tile = _guardian_rollback_support(id,"item",old_board,docked_board,result)
		if str(item.tile).is_empty(): return {}
	# Archive the first revision-2 bytes in the saved snapshot. Ordinary saves
	# preserve this field; repeated normalization cannot nest or overwrite it.
	var recovery := saved.duplicate(true)
	recovery.erase("guardianRevision2Recovery")
	result.guardianRevision2Recovery = {"format":1,"sourceLayoutRevision":2,"snapshot":recovery}
	return result

func _guardian_rollback_support(id: String, who: String, source_board: Array, old_board: Array, result: Dictionary) -> String:
	var origin := _find_tile(id,source_board)
	if origin.is_empty(): return ""
	var bridge_ready: bool = "root" in result.flags
	var frontier: String = str(result.growth.root.back()) if not result.growth.root.is_empty() else "f:1:-4"
	# Before the root bridge, revision 2 let the small companion reach the
	# lift from its adjacent water court. That connection never existed here.
	if who in ACTORS and not bridge_ready and (id.begins_with("m:lift:") or float(origin.h)>=2.0 or (float(origin.x)>=3 and float(origin.z)<2)):
		return "m:water:0:0" if who=="buddy" else frontier
	if id.begins_with("m:water:"): return "m:water:0:0"
	if id.begins_with("m:light:"): return "f:8:1"
	if origin.get("small",false) and float(origin.z)==3 and float(origin.x)>-4: return "f:-4:3"
	var same := _find_tile(id,old_board)
	if not same.is_empty() and not same.get("solid",false) and not (who=="luvie" and same.get("small",false)): return id
	# Recognized removed source supports may move only to a legal same-height
	# old shore. Invalid IDs were already rejected against the revision-2 graph.
	var best := ""
	var distance := INF
	for tile: Dictionary in old_board:
		if tile.get("solid",false) or (who=="luvie" and tile.get("small",false)) or float(tile.h)!=float(origin.h): continue
		var candidate := _distance(origin,tile)
		if candidate < distance:
			distance = candidate; best = str(tile.id)
	return best

