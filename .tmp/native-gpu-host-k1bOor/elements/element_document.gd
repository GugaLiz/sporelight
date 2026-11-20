class_name GardenElementDocument
extends RefCounted
const Catalog = preload("res://elements/element_catalog.gd")
## Lossless authored-level interchange. Derived instance rows are an index,
## not a second source of gameplay truth and not an executable editor scene.
static func encode(document: Dictionary) -> String:
	return JSON.stringify(document,"  ",true)+"\n"

static func validate(document: Dictionary) -> Dictionary:
	if document.get("schema_version")!=1 or document.get("document_kind")!="sporelight-authored-elements": return {"ok":false,"error":"unsupported_document_schema"}
	if not document.get("level_id") is String or not document.get("source_level") is Dictionary: return {"ok":false,"error":"missing_source_level"}
	var level: Dictionary = document.source_level
	if level.get("id")!=document.level_id: return {"ok":false,"error":"level_identity_mismatch"}
	for key: String in ["tiles","marks","modules","roots","collectibles"]:
		if not level.get(key) is Array: return {"ok":false,"error":"invalid_level_collection:"+key}
	if not document.get("instances") is Array or not document.get("initial_state") is Dictionary: return {"ok":false,"error":"missing_instance_index_or_state"}
	if document.initial_state.get("levelId")!=document.level_id: return {"ok":false,"error":"snapshot_identity_mismatch"}
	var definitions := Catalog.types()
	var supports := {}
	for tile: Variant in level.tiles:
		if not tile is Dictionary or not tile.get("id") is String: return {"ok":false,"error":"invalid_authored_tile"}
		supports[str(tile.id)] = true
	for module: Variant in level.modules:
		if not module is Dictionary or not module.get("shape") is Array or module.shape.is_empty() or not module.get("id") is String: return {"ok":false,"error":"invalid_authored_module"}
		for cell: Variant in module.shape:
			if not cell is Array or cell.size()!=2: return {"ok":false,"error":"invalid_module_cell"}
			for coordinate: Variant in cell:
				if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate)!=floor(float(coordinate)): return {"ok":false,"error":"invalid_module_coordinate"}
			supports["m:%s:%d:%d"%[str(module.id),int(cell[0]),int(cell[1])]] = true
	for row: Variant in document.instances:
		if row is Dictionary and row.get("category","") in ["runtime-terrain","terrain-state-observation"] and row.get("source") is Dictionary and row.source.get("id") is String:
			supports[str(row.source.id)] = true
	var ids := {}
	for row: Variant in document.instances:
		if not row is Dictionary: return {"ok":false,"error":"invalid_instance"}
		for field: String in ["instance_id","category","element_id","state_binding"]:
			if not row.get(field) is String: return {"ok":false,"error":"invalid_instance_field:"+field}
		if not row.instance_id.begins_with(str(document.level_id)+"/") or ids.has(row.instance_id): return {"ok":false,"error":"duplicate_or_wrong_level_instance"}
		if not row.get("support") is Dictionary or not row.support.get("tile") is String or not row.has("source"): return {"ok":false,"error":"missing_instance_support_or_source"}
		if not definitions.has(row.element_id): return {"ok":false,"error":"unknown_element_type:"+str(row.element_id)}
		var binding: String = row.support.tile
		var removed_carry := false
		if row.category=="carry":
			var item_id := str(row.get("item_id",""))
			var items: Variant = document.initial_state.get("items",{})
			if not items is Dictionary or not items.has(item_id) or not items[item_id] is Dictionary or row.source!=items[item_id] or row.element_id!="carry."+item_id: return {"ok":false,"error":"carry_state_mismatch"}
			var item: Dictionary = items[item_id]
			var holder := str(item.get("holder",""))
			var tile := str(item.get("tile",""))
			var lifecycle := str(row.get("lifecycle",""))
			if not holder.is_empty():
				var actors: Variant = document.initial_state.get("actors",{})
				if not actors is Dictionary or not holder in ["luvie","buddy"] or not actors.has(holder) or lifecycle!="held" or tile!="" or row.support.get("holder")!=holder or binding!=actors[holder]: return {"ok":false,"error":"invalid_held_support"}
			elif tile.is_empty():
				if lifecycle!="removed-from-board" or not binding.is_empty() or row.support.get("policy")!="removed-from-board": return {"ok":false,"error":"invalid_removed_carry"}
				removed_carry = true
			elif lifecycle!="on-support" or binding!=tile: return {"ok":false,"error":"invalid_grounded_carry"}
		if binding.is_empty():
			if bool(definitions[row.element_id].support_required) and not removed_carry: return {"ok":false,"error":"required_support_missing:"+str(row.instance_id)}
			if not removed_carry and not row.support.get("policy","") in ["adapter-owned","authored-world-anchor; profile resolves height (no invented tile binding)"]: return {"ok":false,"error":"missing_support_policy"}
		elif not supports.has(binding): return {"ok":false,"error":"unknown_support:"+binding}
		ids[row.instance_id] = true
	return {"ok":true}

static func decode(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text)!=OK: return {"ok":false,"error":"invalid_document_json"}
	var parsed: Variant = parser.data
	if not parsed is Dictionary: return {"ok":false,"error":"invalid_document_json"}
	var result := validate(parsed)
	if not result.ok: return result
	return {"ok":true,"level":parsed.source_level.duplicate(true),"document":parsed}
