extends SceneTree
## Independent material samples at fixed points on a rigid board. External
## docking stairs may change; the board's own paving and masonry may not.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
var cases: Array = []
var stage: Node2D
var fresh: Node2D
var wall_pairs := 0

func _initialize() -> void: call_deferred("_run")
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

# Explicit quarter-turn table, independent of production texture helpers.
func _quarter(point: Vector3, turn: int) -> Vector3:
	match posmod(turn,4):
		1: return Vector3(-point.z,point.y,point.x)
		2: return Vector3(-point.x,point.y,-point.z)
		3: return Vector3(point.z,point.y,-point.x)
	return point

func _uv_at(part: MeshInstance3D, point: Vector3) -> Dictionary:
	if part == null or part.mesh == null: return {}
	var arrays: Array = part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index in range(0,vertices.size(),3):
		var a:=vertices[index]
		var ab:=vertices[index+1]-a
		var ac:=vertices[index+2]-a
		var ap:=point-a
		var normal:=ab.cross(ac)
		if normal.length_squared()<.0000000001 or absf(ap.dot(normal.normalized()))>.00001: continue
		var denominator:=ab.dot(ab)*ac.dot(ac)-ab.dot(ac)*ab.dot(ac)
		if absf(denominator)<.000000000001: continue
		var b:=(ap.dot(ab)*ac.dot(ac)-ap.dot(ac)*ab.dot(ac))/denominator
		var c:=(ap.dot(ac)*ab.dot(ab)-ap.dot(ab)*ab.dot(ac))/denominator
		if b < -.0001 or c < -.0001 or b+c > 1.0001: continue
		return {"uv":uvs[index]*(1-b-c)+uvs[index+1]*b+uvs[index+2]*c,"normal":normal.normalized()}
	return {}

func _samples(surface: Node3D, turn: int, label: String) -> Dictionary:
	var result: Dictionary={}
	var points: Array[Vector3]=[Vector3(.11,0,.07),Vector3(-.09,0,.12),Vector3(.08,0,-.13)]
	for index in points.size():
		var at:=_quarter(points[index],turn)
		var sample:=_uv_at(surface._top,at)
		_check(not sample.is_empty(),label+" central paving sample "+str(index)+" exists")
		if sample.is_empty(): continue
		# The zero-turn authored UV at this physical spot is x+.5,z+.5.
		_check(Vector2(sample.uv).distance_to(Vector2(points[index].x+.5,points[index].z+.5))<.00002,label+" paving remains fixed on board "+str(index))
		result["top"+str(index)]=sample.uv
	for index in range(4):
		var canonical:=_quarter(Vector3(.5,-.45,.13),index)
		var sample:=_uv_at(surface._sides,_quarter(canonical,turn))
		# A docked neighbor may legitimately remove this cut face.
		if not sample.is_empty():
			result["wall"+str(index)]=sample.uv
			var parts: PackedStringArray=str(surface.tile_id).split(":")
			if parts.size()==4 and parts[0]=="m":
				for module: Dictionary in stage.world.level.modules:
					if str(module.id)!=parts[1]:continue
					var horizontal: float=float(module.z)+int(parts[3])+canonical.z if index%2==0 else float(module.x)+int(parts[2])+canonical.x
					var original_height: float=float(module.get("low",module.h))*.65 if str(module.kind)=="lift" else float(module.h)*.65
					var expected:=Vector2(horizontal/4.5,-(original_height+canonical.y)/4.5)
					_check(Vector2(sample.uv).distance_to(expected)<.00002,label+" authored wall phase "+str(index))
	var material: Material=surface._sides.get_active_material(0) if surface._sides.mesh!=null else null
	if material is ShaderMaterial:
		_check(int(material.get_shader_parameter("texture_turn"))==posmod(turn,4),label+" masonry shader keeps authored face orientation")
	return result

func _compare_samples(a: Dictionary,b: Dictionary,label: String) -> void:
	for key: String in a:
		if not b.has(key): continue
		_check(Vector2(a[key]).distance_to(Vector2(b[key]))<.00002,label+" "+key+" unchanged")
		if key.begins_with("wall"): wall_pairs+=1

func _fingerprint(surface: Node3D) -> String:
	# Transform equality is approximate and checked separately: trig sampling
	# may contain signed zero / sub-micrometre endpoint rounding.
	var data: Array=[surface.rises,surface._body.get_child(0).shape.get_faces()]
	for part: MeshInstance3D in [surface._top,surface._sides,surface._ramps,surface._risers,surface._treads]:
		data.append(part.mesh.surface_get_arrays(0) if part.mesh!=null else [])
		var material: Material=part.get_active_material(0) if part.mesh!=null else null
		if material is ShaderMaterial: data.append(material.get_shader_parameter("texture_turn"))
	return var_to_bytes(data).hex_encode().sha256_text()

func _module_ids(world: RefCounted,module_id: String) -> Array[String]:
	var result: Array[String]=[]
	# A stationary bank may own an overlapped cell in one orientation; retain
	# every authored module identity and sample it whenever it becomes visible.
	for module: Dictionary in world.level.modules:
		if str(module.id)!=module_id: continue
		for cell: Array in module.shape: result.append("m:"+module_id+":"+str(int(cell[0]))+":"+str(int(cell[1])))
	return result

func _structural_members(world: RefCounted,module: Dictionary) -> Array[String]:
	var ids:=_module_ids(world,str(module.id))
	# This leaf is genuinely not built before receiving dew, unlike the
	# guardian tiles merely masked by a coincident fixed bank during dedup.
	if str(world.level.id)=="3-3" and str(module.id)=="lift" and not world.flag("root"):
		ids.erase("m:lift:-1:0")
	return ids

func _prepared_world(level_id: String,module: Dictionary) -> RefCounted:
	if level_id=="2-1" and str(module.id)=="float":
		# The original dew item must first be collected and returned: its dry
		# bank disappears at water1, so a cold snapshot cannot simply be raised.
		var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
		for entry: Dictionary in fixture.cases:
			if str(entry.name)!="authored/2-1":continue
			var previous: Dictionary=entry.initial.snapshot
			for step: Dictionary in entry.steps:
				if str(step.command.value)=="valve:water":return World.new(level_id,previous)
				previous=step.snapshot
	return World.new(level_id)

func _structure(level_id: String,module: Dictionary,turn: int,root_ready: bool=false) -> void:
	var first: RefCounted=_prepared_world(level_id,module)
	if root_ready:first.state.flags.append("root")
	first.state.turns[str(module.id)]=turn
	var last: RefCounted=first.fork(first.snapshot())
	last.state.turns[str(module.id)]=(turn+1)%4 if str(module.kind)=="rotate" else 1
	if str(module.id)=="float":last.state.water=1
	var before: Dictionary=first.snapshot().duplicate(true)
	var after: Dictionary=last.snapshot().duplicate(true)
	_check(first.fork(before).snapshot()==before and last.fork(after).snapshot()==after,level_id+" structural prepared saves remain valid after movement")
	var members:=_structural_members(first,module)
	var source_ids: Array[String]=[]
	var fixed: Dictionary={}
	for tile: Dictionary in first.tiles():
		source_ids.append(str(tile.id))
		if str(tile.get("kind","fixed"))=="fixed":fixed[str(tile.id)]=Vector3(float(tile.x),float(tile.h)*.65,float(tile.z))
	stage.clear_motion(false);stage.set_world(first)
	var label:=level_id+"/"+str(module.id)+" structure "+str(turn)
	for progress: float in [0.0,.001,.25,.5,.9999]:
		stage.set_motion(before,after,progress,"turn:"+str(module.id))
		var actual: Array[String]=[]
		for id: String in stage._surfaces:
			if id.begins_with("m:"+str(module.id)+":"): actual.append(id)
		actual.sort();members.sort()
		_check(actual==members,label+" every real leaf retained at "+str(progress))
		for id: String in members:
			if not stage._surfaces.has(id):continue
			var surface: Node3D=stage._surfaces[id]
			var supplemental:=not source_ids.has(id)
			_check(surface.visible==(progress>0 or not supplemental),label+" departure bank owns coincident first frame "+id+"/"+str(progress))
			_check(surface._body.collision_layer==(0 if supplemental else 1),label+" supplemental visual never adds free support "+id+"/"+str(progress))
			var parts:=id.split(":")
			var local:=Vector2i(int(parts[2]),int(parts[3]))
			for index in range(4):
				var axis3:=_quarter(Vector3(1,0,0),index)
				var neighbor:=local+Vector2i(int(axis3.x),int(axis3.z))
				var neighbor_id:="m:"+str(module.id)+":"+str(neighbor.x)+":"+str(neighbor.y)
				var point:=_quarter(_quarter(Vector3(.5,-.45,.13),index),turn if str(module.kind)=="rotate" else 0)
				var wall:=_uv_at(surface._sides,point)
				_check(wall.is_empty()==members.has(neighbor_id),label+" complete outline without internal cut wall "+id+"/"+str(index)+"/"+str(progress))
		for id: String in fixed:
			_check(stage._surfaces.has(id),label+" keeps stationary departure bank "+id)
			if stage._surfaces.has(id):_check(stage._surfaces[id].position.distance_to(fixed[id])<.00001,label+" departure bank never follows rotating leaf "+id)
		_check(stage._tiles==last.tiles(),label+" interpolated visual leaves never enter rule board")
		_check(first.snapshot()==before and last.snapshot()==after,label+" animation never changes puzzle snapshots")
	stage.set_motion(before,after,1.0,"turn:"+str(module.id))
	var settled_ids: Array[String]=[]
	var occupied: Dictionary={}
	for tile: Dictionary in last.tiles():
		settled_ids.append(str(tile.id))
		var position_key:=Vector3(float(tile.x),float(tile.h),float(tile.z))
		_check(not occupied.has(position_key),label+" settled board has one geometry owner per coordinate")
		occupied[position_key]=true
	settled_ids.sort()
	var rendered: Array=stage._surfaces.keys();rendered.sort()
	_check(rendered==settled_ids,label+" no supplemental collision or terrain remains after docking")
	if level_id=="3-3" and str(module.id)=="lift" and not root_ready:
		_check(not stage._surfaces.has("m:lift:-1:0"),"3-3 conditional lift leaf remains absent without root")
	if root_ready:
		_check(stage._surfaces.has("m:lift:-1:0"),"3-3 root-completed lift retains its real ninth leaf")
	stage.clear_motion(false)

func _rotation(level_id: String,module: Dictionary) -> void:
	var world:=World.new(level_id)
	var module_id:=str(module.id)
	world.state.turns[module_id]=0
	stage.clear_motion(false); stage.set_world(world)
	var ids:=_module_ids(world,module_id)
	var original: Dictionary={}
	var originals: Dictionary={}
	var snapshot: Dictionary=world.snapshot().duplicate(true)
	for id: String in ids:
		if not stage._surfaces.has(id): continue
		original[id]=_fingerprint(stage._surfaces[id])
		originals[id]=_samples(stage._surfaces[id],0,level_id+"/"+id+" zero")
	for turn in range(4):
		var before: Dictionary=world.snapshot().duplicate(true)
		world.state.turns[module_id]=(turn+1)%4
		var after: Dictionary=world.snapshot().duplicate(true)
		var label:=level_id+"/"+module_id+" "+str(turn)+"->"+str((turn+1)%4)
		stage.set_motion(before,after,.9999,"turn:"+module_id)
		var almost: Dictionary={}
		var positions: Dictionary={}
		for id: String in ids:
			if not stage._surfaces.has(id): continue
			almost[id]=_samples(stage._surfaces[id],turn,label+" almost "+id)
			if not originals.has(id): originals[id]=almost[id]
			positions[id]=stage._surfaces[id].to_global(_quarter(Vector3(.11,0,.07),turn))
		stage.set_motion(before,after,1.0,"turn:"+module_id)
		fresh.clear_motion(false); fresh.set_world(World.new(level_id,after))
		for id: String in ids:
			if not stage._surfaces.has(id): continue
			var surface: Node3D=stage._surfaces[id]
			var settled:=_samples(surface,(turn+1)%4,label+" docked "+id)
			if originals.has(id): _compare_samples(originals[id],settled,label+" original identity "+id)
			else: originals[id]=settled
			if almost.has(id):
				_compare_samples(almost[id],settled,label+" final-frame continuity "+id)
				_check(surface.to_global(_quarter(Vector3(.11,0,.07),turn+1)).distance_to(positions[id])<.0001,label+" actual paint point position continuous "+id)
			_check(fresh._surfaces.has(id),label+" fresh load has same board "+id)
			if fresh._surfaces.has(id):
				_check(_fingerprint(surface)==_fingerprint(fresh._surfaces[id]),label+" history-independent mesh UV collision "+id)
				_check(surface.position.is_equal_approx(fresh._surfaces[id].position) and surface.rotation.is_equal_approx(fresh._surfaces[id].rotation),label+" fresh load transform "+id)
		stage.clear_motion(false)
		# Undo/cancel restores the previously saved state, not a cached paint.
		stage.set_world(World.new(level_id,before))
		for id: String in ids:
			if stage._surfaces.has(id) and originals.has(id): _compare_samples(originals[id],_samples(stage._surfaces[id],turn,label+" undo "+id),label+" undo identity "+id)
		stage.set_motion(before,after,.5,"turn:"+module_id)
		stage.clear_motion(false);stage.set_world(World.new(level_id,before))
		for id: String in ids:
			if stage._surfaces.has(id) and originals.has(id): _compare_samples(originals[id],_samples(stage._surfaces[id],turn,label+" cancel "+id),label+" cancel identity "+id)
		stage.set_world(world)
	for id: String in ids:
		if stage._surfaces.has(id) and original.has(id): _check(_fingerprint(stage._surfaces[id])==original[id],level_id+"/"+id+" four turns recover exact mesh UV collision")
	_check(originals.size()==ids.size(),level_id+"/"+module_id+" every authored cell sampled across four orientations")
	_check(world.snapshot()==snapshot,level_id+"/"+module_id+" four visual transitions leave original rules")
	cases.append({"level":level_id,"module":module_id,"kind":"rotate","turns":4,"cells":ids.size()})

func _translation(level_id: String,module: Dictionary) -> void:
	var world: RefCounted=_prepared_world(level_id,module)
	var module_id:=str(module.id)
	world.state.turns[module_id]=0
	var before: Dictionary=world.snapshot().duplicate(true)
	stage.clear_motion(false);stage.set_world(world)
	var ids:=_module_ids(world,module_id)
	var original: Dictionary={}
	for id: String in ids:
		if stage._surfaces.has(id): original[id]=_samples(stage._surfaces[id],0,level_id+"/"+id+" departure")
	world.state.turns[module_id]=1
	if module_id=="float": world.state.water=1
	var after: Dictionary=world.snapshot().duplicate(true)
	stage.set_motion(before,after,.9999,"valve:"+module_id)
	var almost: Dictionary={}
	for id: String in ids:
		if stage._surfaces.has(id): almost[id]=_samples(stage._surfaces[id],0,level_id+"/"+id+" translated almost")
	stage.set_motion(before,after,1.0,"valve:"+module_id)
	for id: String in ids:
		if not stage._surfaces.has(id): continue
		var settled:=_samples(stage._surfaces[id],0,level_id+"/"+id+" translated")
		if original.has(id): _compare_samples(original[id],settled,level_id+"/"+id+" translation paint anchored")
		if almost.has(id): _compare_samples(almost[id],settled,level_id+"/"+id+" translation last frame")
	_check(world.snapshot()==after,level_id+"/"+module_id+" presentation preserves translated snapshot")
	cases.append({"level":level_id,"module":module_id,"kind":str(module.kind),"cells":ids.size()})

func _first_garden() -> void:
	var world:=World.new("1-1")
	stage.clear_motion(false);stage.set_world(world)
	var before: Dictionary={}
	for id: String in stage._surfaces: before[id]=_fingerprint(stage._surfaces[id])
	stage.set_world(World.new("3-4"));stage.set_world(world)
	for id: String in before: _check(_fingerprint(stage._surfaces[id])==before[id],"1-1 authored surface unaffected by module material cache "+id)

func _run() -> void:
	stage=Stage.new();fresh=Stage.new()
	root.add_child(stage);root.add_child(fresh)
	stage.set_process(false);fresh.set_process(false)
	var definitions: Array=JSON.parse_string(FileAccess.get_file_as_string("res://content/levels.json")).levels
	for definition: Dictionary in definitions:
		for module: Dictionary in definition.get("modules",[]):
			if str(module.kind)=="rotate":
				_rotation(str(definition.id),module)
				for turn in range(4):_structure(str(definition.id),module,turn)
			elif str(module.kind) in ["slide","lift"]:
				_translation(str(definition.id),module)
				_structure(str(definition.id),module,0)
				if str(definition.id)=="3-3" and str(module.id)=="lift":_structure("3-3",module,0,true)
	_first_garden()
	_check(cases.filter(func(entry: Dictionary)->bool:return entry.kind=="rotate").size()==6,"all six authored rotating modules covered")
	_check(wall_pairs>100,"masonry comparisons cover actual exposed faces")
	print(JSON.stringify({"suite":"native-surface-identity","passed":failures.is_empty(),"checks":checks,"wallPairs":wall_pairs,"cases":cases,"failures":failures,"gpuPixelsVerified":false,"scope":"Independent barycentric mesh UV samples and rigid physical point continuity. Prepared orientations and load/undo; no claim of legal full journeys or GPU pixel acceptance."}))
	stage.queue_free();fresh.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
