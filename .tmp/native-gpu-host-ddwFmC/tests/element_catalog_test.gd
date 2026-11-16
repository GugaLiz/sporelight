extends SceneTree
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	if not FileAccess.file_exists("res://elements/element_catalog.gd") or not FileAccess.file_exists("res://elements/element_document.gd"):
		print("FAIL: reusable catalog/document API not implemented")
		quit(1)
		return
	var catalog = load("res://elements/element_catalog.gd")
	var documents = load("res://elements/element_document.gd")
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	_check(levels.size()==12,"twelve authored levels")
	var definitions: Dictionary = catalog.definitions()
	_check(definitions.has("actors") and definitions.has("surfaces") and definitions.has("props") and definitions.has("resources"),"all reusable domains exposed")
	var seen := {}
	for level: Dictionary in levels:
		var world := World.new(level.id)
		var before := world.snapshot()
		var document: Dictionary = catalog.for_world(world)
		_check(world.snapshot()==before,level.id+" inventory is read only")
		_check(document.source_level==level and document.initial_state==before,level.id+" retains full authored level and state")
		var counts := {}
		for instance: Dictionary in document.instances:
			_check(not seen.has(instance.instance_id),"unique stable ID "+instance.instance_id)
			seen[instance.instance_id] = true
			counts[instance.category] = int(counts.get(instance.category,0))+1
			_check(instance.has("support") and instance.has("state_binding") and instance.has("source"),instance.instance_id+" support/state/provenance")
			_check(definitions.types.has(instance.element_id),instance.instance_id+" type resolves")
		_check(counts.get("actor",0)==2,level.id+" both actors")
		_check(counts.get("terrain",0)==level.tiles.size(),level.id+" every authored tile")
		_check(counts.get("mark",0)==level.marks.size(),level.id+" every semantic mark")
		_check(counts.get("module",0)==level.modules.size(),level.id+" every moving module")
		_check(counts.get("root",0)==level.roots.size(),level.id+" every growth anchor")
		_check(counts.get("carry",0)==world.state.items.size(),level.id+" carry items from actual initial rule state")
		_check(counts.get("collectible",0)==level.collectibles.size(),level.id+" every authored collectible")
		var imported: Dictionary = documents.decode(documents.encode(document))
		_check(imported.ok and imported.level==level,level.id+" JSON roundtrip retains gameplay payload")
		_check(documents.encode(catalog.for_world(world))==documents.encode(document),level.id+" stable repeated export")
		var malformed := document.duplicate(true)
		malformed.instances.append(malformed.instances[0].duplicate(true))
		_check(not documents.validate(malformed).ok,level.id+" duplicate IDs rejected")
		malformed = document.duplicate(true)
		malformed.instances[0].element_id = "actor.unknown"
		_check(not documents.validate(malformed).ok,level.id+" unknown element types rejected")
		malformed = document.duplicate(true)
		malformed.instances[0].support.tile = "f:999:999"
		_check(not documents.validate(malformed).ok,level.id+" unknown supports rejected")
		malformed = document.duplicate(true)
		malformed.instances[0].support.tile = ""
		_check(not documents.validate(malformed).ok,level.id+" missing actor support rejected")
		if level.id=="2-3":
			_check(document.instances.any(func(x: Dictionary)->bool: return x.category=="mark" and x.source.id=="stage" and x.element_id=="prop.passenger-deck"),"flower-kind passenger deck is not planter")
		if level.id=="3-2":
			_check(document.instances.any(func(x: Dictionary)->bool: return x.element_id=="prop.shadow-memory"),"shadow memory semantic override")
	_check(not documents.decode("not json").ok,"invalid JSON rejected")
	_check(not documents.validate({"schema_version":99}).ok,"unknown schema rejected")
	# Exported item attachment follows the holder; source/save coordinates stay empty.
	var held_world := World.new("3-1")
	held_world.state.items.lamp.holder = "luvie"
	held_world.state.items.lamp.tile = ""
	var held: Dictionary = catalog.for_world(held_world)
	var carry_index := -1
	for i: int in held.instances.size():
		if held.instances[i].category=="carry": carry_index=i;break
	_check(carry_index>=0,"held item present")
	_check(held.instances[carry_index].support.tile==held_world.state.actors.luvie and held.instances[carry_index].support.holder=="luvie","held item binds to holder support")
	_check(documents.decode(documents.encode(held)).ok,"held item roundtrip")
	var invalid := held.duplicate(true)
	invalid.instances[carry_index].support.holder = "buddy"
	_check(not documents.validate(invalid).ok,"false carry holder rejected")
	invalid = held.duplicate(true)
	invalid.instances[carry_index].support.tile = ""
	_check(not documents.validate(invalid).ok,"held item cannot remove support")
	invalid = held.duplicate(true)
	invalid.instances[carry_index].lifecycle = "removed-from-board"
	invalid.instances[carry_index].support = {"tile":"","policy":"removed-from-board"}
	_check(not documents.validate(invalid).ok,"held item cannot masquerade as consumed")
	var consumed_world := World.new("2-1")
	consumed_world.state.items.dew.tile = ""
	consumed_world.state.flags.append("care")
	var consumed: Dictionary = catalog.for_world(consumed_world)
	for i: int in consumed.instances.size():
		if consumed.instances[i].category=="carry": carry_index=i;break
	_check(consumed.instances[carry_index].lifecycle=="removed-from-board","consumed lifecycle explicit")
	_check(documents.decode(documents.encode(consumed)).ok,"consumed item roundtrip")
	invalid = consumed.duplicate(true)
	invalid.initial_state.items.dew.tile = "f:0:4"
	_check(not documents.validate(invalid).ok,"consumed state must match source item")
	invalid = consumed.duplicate(true)
	invalid.instances[carry_index].lifecycle = "on-support"
	_check(not documents.validate(invalid).ok,"missing support cannot bypass lifecycle")
	invalid = consumed.duplicate(true)
	invalid.instances[0].support = {"tile":"","policy":"removed-from-board"}
	invalid.instances[0].lifecycle = "removed-from-board"
	_check(not documents.validate(invalid).ok,"actor cannot use removed carry exception")
	print(JSON.stringify({"suite":"element-catalog","checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
