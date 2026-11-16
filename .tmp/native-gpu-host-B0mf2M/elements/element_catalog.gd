class_name GardenElementCatalog
extends RefCounted
## Read-only bridge between existing domain adapters and future editor documents.
## This catalog does not spawn props or implement replacement gameplay rules.
const Actors = preload("res://elements/actor_definitions.gd")
const Surfaces = preload("res://elements/surface_definitions.gd")
const Props = preload("res://elements/prop_definitions.gd")
const Assets = preload("res://elements/element_assets.gd")
const Original = preload("res://presentation/native/original_garden_dressing.gd")
const Profiles = preload("res://presentation/native/level_presentation_profiles.gd")
const World = preload("res://core/garden_world.gd")
static var _types: Dictionary = {}

static func _type(domain: String, renderer: String, owner: String = "GardenWorld", support_required: bool = true) -> Dictionary:
	return {"domain_ref":domain,"renderer":renderer,"state_owner":owner,"support_required":support_required,"factory_policy":"existing specialized adapter; no generic spawn"}

static func types() -> Dictionary:
	if not _types.is_empty(): return _types.duplicate(true)
	for who: String in World.ACTORS:
		_types["actor."+who] = _type("actors.actors."+who,"res://presentation/native/actor_visual_factory.gd")
	for key: String in Surfaces.definitions().elements:
		_types[key] = _type("surfaces.elements."+key,"res://presentation/native/native_surface.gd")
	for kind: String in ["fixed","module","bridge","lift","water"]:
		_types["surface."+kind] = _type("surfaces.elements.surface.moving-board" if kind=="module" else "surfaces.elements.surface.floor","res://presentation/native/native_surface.gd")
	_types["surface.generated-routes"] = _type("surfaces.elements.surface.root","res://presentation/native/native_surface.gd","GardenWorld.tiles()",false)
	for id: String in level_ids():
		var world := World.new(id)
		for mark: Dictionary in world.level.marks:
			var semantic := Props.semantic_for_mark(id,mark)
			_types["prop."+semantic] = _type("props.semantic_overrides / authored mark kind: "+semantic,"res://presentation/native/native_garden_stage.gd#_update_props")
		for module: Dictionary in world.level.modules:
			_types["module."+str(module.kind)] = _type("authored modules[].kind="+str(module.kind),"res://presentation/native/native_surface.gd")
		for item: String in world.state.items:
			_types["carry."+item] = _type("actors.carry / authored state.items."+item,"res://presentation/native/original_carry_art.gd")
	for alias: String in Assets.paths():
		_types["scenery."+alias] = _type("resources."+alias,"res://presentation/native/original_garden_dressing.gd","placement adapter",false)
	_types["scenery.procedural-sprite"] = _type("adapter-generated texture; source contains anchor and canvas","res://presentation/native/original_sanctuary_dressing.gd","sanctuary adapter",false)
	_types["prop.rock-obstacle"] = _type("source_level.walls","res://presentation/native/original_wall_props.gd","authored wall collision/terrain profile",false)
	_types["adapter.scenery"] = _type("level_presentation_profiles.gd:dressing","res://presentation/native/level_presentation_profiles.gd","placement adapter",false)
	_types["assembly.sanctuary"] = _type("source_level.sanctuary","res://presentation/native/original_sanctuary_dressing.gd","GardenWorld flags",false)
	_types["effect.collectible"] = _type("source_level.collectibles","res://presentation/native/native_garden_effects.gd")
	_types["effect.environment"] = _type("chapter environment","res://presentation/native/native_garden_effects.gd","visual clock + surface support",false)
	_types["effect.light-path"] = _type("world.rays()/lamp_ray()","res://presentation/native/rule_ray_presentation.gd / lightwell_dressing.gd","GardenWorld optical paths",false)
	_types["effect.shadow-projection"] = _type("world.projection()","res://presentation/native/shadow_dressing.gd","GardenWorld mode/frozen/items",false)
	return _types.duplicate(true)

static func definitions() -> Dictionary:
	return {"schema_version":1,"types":types(),"actors":Actors.definitions(),"surfaces":Surfaces.definitions(),"props":Props.definitions(),"resources":Assets.paths(),"contracts":{
		"instance":"stable level/category/authored identity; data references remain original",
		"appearance":"resource alias + domain definition; never puzzle conditions",
		"support":"fixed or moving tile identity; scenery must validate physical support",
		"state":"GardenWorld owns actor identity, carry, turns, growth and completion",
		"composition":"preserve specialized renderer adapters and authored layout profiles"}}

static func level_ids() -> Array:
	var result: Array = []
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json"))
	for level: Dictionary in data.levels: result.append(str(level.id))
	return result

static func _instance(level: String, category: String, identity: String, element: String, source: Variant, support: String = "", binding: String = "") -> Dictionary:
	return {"instance_id":level+"/"+category+"/"+identity,"category":category,"element_id":element,"source":source.duplicate(true) if source is Dictionary or source is Array else source,"support":{"tile":support,"policy":"actual-world-support" if not support.is_empty() else "adapter-owned"},"state_binding":binding}

static func for_world(world: RefCounted) -> Dictionary:
	var level: Dictionary = world.level
	var id := str(level.id)
	var instances: Array = []
	for who: String in World.ACTORS:
		var entry := _instance(id,"actor",who,"actor."+who,Actors.actor(who),str(world.state.actors[who]),"state.actors."+who)
		entry.skin_id = Actors.default_skin(who)
		instances.append(entry)
	for tile: Dictionary in level.tiles:
		instances.append(_instance(id,"terrain",str(tile.id),"surface.floor",tile,str(tile.id),"world.tiles()/visible()"))
	for mark: Dictionary in level.marks:
		var entry := _instance(id,"mark",str(mark.id),"prop."+Props.semantic_for_mark(id,mark),mark,str(mark.tile),"world.commands()/act():"+str(mark.id))
		entry.authored_kind = str(mark.kind)
		instances.append(entry)
	for module: Dictionary in level.modules:
		var anchor: Array = module.shape[0]
		for cell: Array in module.shape:
			if float(cell[0])==0.0 and float(cell[1])==0.0: anchor=cell;break
		instances.append(_instance(id,"module",str(module.id),"module."+str(module.kind),module,World.module_cell(str(module.id),anchor[0],anchor[1]),"state.turns."+str(module.id)+"; state.water; level adapter"))
	for root: Dictionary in level.roots:
		instances.append(_instance(id,"root",str(root.id),"surface.root",root,str(root.at),"state.growth."+str(root.id)))
	for item: String in world.state.items:
		var item_state: Dictionary = world.state.items[item]
		var holder := str(item_state.get("holder",""))
		var support := str(world.state.actors.get(holder,"")) if not holder.is_empty() else str(item_state.get("tile",""))
		var entry := _instance(id,"carry",item,"carry."+item,item_state,support,"state.items."+item)
		entry.item_id = item
		entry.lifecycle = "held" if not holder.is_empty() else "on-support" if not support.is_empty() else "removed-from-board"
		if entry.lifecycle=="held": entry.support.holder = holder
		elif entry.lifecycle=="removed-from-board": entry.support.policy = "removed-from-board"
		instances.append(entry)
	for item: Dictionary in level.collectibles:
		instances.append(_instance(id,"collectible",str(item.id),"effect.collectible",item,str(item.tile),"state.collected"))
	for wall: Array in level.get("walls",[]):
		instances.append(_instance(id,"obstacle",JSON.stringify(wall),"prop.rock-obstacle",wall,"","level.walls; authored wall geometry owns its base"))
	var authored_ids := {}
	for tile: Dictionary in level.tiles: authored_ids[str(tile.id)] = true
	for tile: Dictionary in world.tiles():
		if not authored_ids.has(str(tile.id)):
			instances.append(_instance(id,"runtime-terrain",str(tile.id),"surface."+str(tile.get("kind","floor")),tile,str(tile.id),"world.tiles(): derived from current state"))
	# Original SOURCE_PROPS is the live recipe only after the two authored
	# starter gardens. Do not mislabel their historical browser props as live.
	var scenery: Array = Original.SOURCE_PROPS.get(id,[]) if not id in ["1-1","1-2"] else []
	for index: int in scenery.size():
		var row: Array = scenery[index]
		var entry := _instance(id,"scenery-source","source-%d"%index,"scenery."+str(row[0]),row,"f:%d:%d"%[roundi(float(row[1])),roundi(float(row[2]))],"original_scenery_placement: actual support + reservations + visibility")
		entry.support.policy = "authored-candidate; resolved by placement adapter"
		instances.append(entry)
	var profile := Profiles.for_level(id)
	instances.append(_instance(id,"terrain-generator","state-routes","surface.generated-routes",{"script":"res://core/garden_world.gd","entry":"tiles","coverage":"fixed visibility, modules, root growth, lever/latch bridges, water/lift approaches, sun/moon memory"},"","state.growth/turns/flags/items/water/mode/frozen"))
	var dressing: Script = profile.get("dressing")
	instances.append(_instance(id,"scenery-generator","dressing","adapter.scenery",{"script":dressing.resource_path if dressing!=null else "","entry":"scenery","authored_layout":id in ["1-1","1-2"]},"","stage rebuild; deterministic support/occlusion placement"))
	instances.append(_instance(id,"effect","environment","effect.environment",{"renderer":"res://presentation/native/native_garden_effects.gd","chapter":level.chapter,"scope":"atmosphere, surface runoff, collectible halos; adapter selects actual effects"},"","stage visual clock; world support; state.collected"))
	if id in ["2-2","3-4","3-1"]:
		instances.append(_instance(id,"effect","light-path","effect.light-path",{"renderer":"res://presentation/native/rule_ray_presentation.gd" if id!="3-1" else "res://presentation/native/lightwell_dressing.gd","points":world.lamp_ray() if id=="3-1" else world.rays()},"","world.lamp_ray()" if id=="3-1" else "world.rays()"))
	if id=="3-2":
		instances.append(_instance(id,"effect","projection","effect.shadow-projection",{"sun":world.projection(0),"moon":world.projection(1)},"","state.mode/frozen/shadowMemory/items"))
	if level.has("sanctuary"):
		instances.append(_instance(id,"scene-assembly","sanctuary","assembly.sanctuary",{"authored":level.sanctuary,"renderer":"res://presentation/native/original_sanctuary_dressing.gd","components":["gate","fountain","mole-resident"]},"","level.sanctuary + world flags"))
	return {"schema_version":1,"document_kind":"sporelight-authored-elements","level_id":id,"source_level":level.duplicate(true),"initial_state":world.snapshot(),"instances":instances,"scenery_observation":{"status":"not-captured","scope":"call capture_scenery with a constructed stage"},"roundtrip_policy":"source_level is authoritative; instances are a derived read-only index"}

## Optional headless inspection of actual sprites after native stage construction.
## Generated scenery IDs use provenance when available, else anchor+alias+ordinal.
## Persist these IDs in a future editor; do not use Godot auto-generated node names.
static func capture_scenery(document: Dictionary, stage: Node) -> void:
	var instances: Array = document.instances
	for index: int in range(instances.size()-1,-1,-1):
		if instances[index].category=="scenery-observed": instances.remove_at(index)
	var reverse := {}
	for alias: String in Assets.paths(): reverse[Assets.resource_path(alias)] = alias
	var occurrences := {}
	var count := 0
	for node: Node in stage._props.get_children():
		if not node is Sprite3D: continue
		var texture: Texture2D = node.texture
		if texture is AtlasTexture: texture = texture.atlas
		var alias := str(node.get_meta("original_scenery_alias",node.get_meta("dressing_alias",reverse.get(texture.resource_path if texture!=null else "","procedural-sprite"))))
		var support := str(node.get_meta("original_scenery_support",node.get_meta("dressing_support",node.get_meta("original_wall_support",""))))
		var p: Vector3 = node.position
		var identity := "%s/%s/%.5f,%.5f,%.5f"%[alias,support,p.x,p.y,p.z]
		if node.has_meta("original_wall_support"): identity = "wall/"+support+"/"+str(node.get_meta("original_wall_side"))
		elif int(node.get_meta("original_scenery_index",-1))>=0: identity = "source-"+str(node.get_meta("original_scenery_index"))
		var ordinal := int(occurrences.get(identity,0))
		occurrences[identity] = ordinal+1
		identity += "/%d"%ordinal
		var entry := _instance(str(document.level_id),"scenery-observed",identity,"scenery."+alias,{"alias":alias,"position":[p.x,p.y,p.z],"scale":[node.scale.x,node.scale.y,node.scale.z],"pixel_size":node.pixel_size,"offset":[node.offset.x,node.offset.y]},support,"dressing adapter; snapshot only, not gameplay state")
		if support.is_empty(): entry.support.policy = "authored-world-anchor; profile resolves height (no invented tile binding)"
		instances.append(entry)
		count += 1
	document.scenery_observation = {"status":"captured","state":"initial-state","sprite_count":count,"deferred":stage._props.get_meta("original_deferred_scenery",[]).duplicate(true),"scope":"direct scenery sprites; procedural meshes remain represented by renderer adapters"}

static func capture_authored_routes(document: Dictionary, reference: Dictionary) -> void:
	var id := str(document.level_id)
	var fixed := {}
	for tile: Dictionary in document.source_level.tiles: fixed[str(tile.id)] = true
	var observed := {}
	for entry: Dictionary in reference.get("cases",[]):
		if str(entry.get("name",""))!="authored/"+id: continue
		for step: int in entry.steps.size():
			var world := World.new(id,entry.steps[step].snapshot)
			for tile: Dictionary in world.tiles():
				if fixed.has(str(tile.id)): continue
				var key := JSON.stringify([tile.id,tile.x,tile.z,tile.h])
				if not observed.has(key):
					var row := _instance(id,"terrain-state-observation",key,"surface."+str(tile.get("kind","floor")),tile,str(tile.id),"world.tiles(): authored fixture snapshots")
					row.fixture_steps = []
					observed[key] = row
				observed[key].fixture_steps.append(step)
	for index: int in range(document.instances.size()-1,-1,-1):
		if document.instances[index].category=="terrain-state-observation": document.instances.remove_at(index)
	document.instances.append_array(observed.values())
	document.route_observation = {"source":"res://tests/fixtures/reference.json","case":"authored/"+id,"unique_dynamic_tile_poses":observed.size(),"scope":"recorded authored paths, not exhaustive reachable-state enumeration"}
