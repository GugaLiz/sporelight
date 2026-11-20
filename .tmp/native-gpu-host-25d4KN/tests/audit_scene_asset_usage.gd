extends SceneTree
## Read-only resource usage audit. Snapshots prepare art states, not route QA.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
const Cloud = preload("res://core/cloud_garden_world.gd")
const Assets = preload("res://elements/element_assets.gd")

class TracedStage:
	extends "res://presentation/native/native_garden_stage.gd"
	var audit_context := "bootstrap"
	var calls: Dictionary = {}
	func _texture(alias: String) -> Texture2D:
		if not calls.has(alias): calls[alias] = {}
		calls[alias][audit_context] = true
		return super._texture(alias)

var output := ""
var stage: Node2D
var seen: Dictionary = {}
var generated: Dictionary = {}
var states: Array = []
var context := ""
var current_level := ""
var current_visibility := true

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	_run.call_deferred()

func _texture_resource(texture: Texture2D, node_path: String, role: String) -> void:
	if texture == null: return
	if texture is AtlasTexture:
		_texture_resource(texture.atlas,node_path,role+"/atlas")
		return
	var path := texture.resource_path
	if path.begins_with("res://assets/"):
		if not seen.has(path): seen[path] = {"resource":path,"uses":{},"visibleUses":{},"nodes":{},"roles":{}}
		seen[path].uses[context] = true
		if current_visibility: seen[path].visibleUses[context] = true
		seen[path].nodes[current_level+":"+node_path] = true
		seen[path].roles[role] = true
	elif texture is ImageTexture:
		var key := current_level+":"+node_path
		if not generated.has(key): generated[key] = {"level":current_level,"node":node_path,"role":role,"canvas":texture.get_size(),"contexts":{}}
		generated[key].contexts[context] = true

func _material(material: Material, node_path: String) -> void:
	if material is BaseMaterial3D:
		for property: String in ["albedo_texture","normal_texture","roughness_texture","emission_texture"]:
			var value: Variant = material.get(property)
			if value is Texture2D: _texture_resource(value,node_path,"material/"+property)
	elif material is ShaderMaterial and material.shader != null:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(str(uniform.name))
			if value is Texture2D: _texture_resource(value,node_path,"shader/"+str(uniform.name))

func _scan(node: Node) -> void:
	current_visibility = bool(node.call("is_visible_in_tree")) if node.has_method("is_visible_in_tree") else true
	var node_path := str(stage.get_path_to(node))
	if node is Sprite3D: _texture_resource(node.texture,node_path,"sprite3d")
	elif node is AnimatedSprite3D and node.sprite_frames != null:
		# All source animation frames are reachable at runtime, even if this
		# prepared scene is paused on idle; actor audit owns their classification.
		for animation: String in node.sprite_frames.get_animation_names():
			for frame in range(node.sprite_frames.get_frame_count(animation)):
				_texture_resource(node.sprite_frames.get_frame_texture(animation,frame),node_path,"actor-frame/"+animation)
	elif node is MeshInstance3D:
		_material(node.material_override,node_path)
		if node.mesh != null:
			for surface in range(node.mesh.get_surface_count()):
				_material(node.get_active_material(surface),node_path)
	for child: Node in node.get_children(): _scan(child)

func _sample(id: String, snapshot: Dictionary, label: String) -> void:
	current_level = id
	context = id+":"+label
	stage.audit_context = context
	var world: RefCounted = Cloud.new(id,snapshot) if id.begins_with("cloud-") else World.new(id,snapshot)
	stage.set_world(world)
	stage.set_process(false)
	await process_frame
	_scan(stage)
	states.append({"level":id,"state":label,"completed":bool(world.state.completed)})

func _run() -> void:
	if output.is_empty(): push_error("--output required"); quit(2); return
	stage = TracedStage.new()
	root.add_child(stage)
	stage.set_process(false)
	var main: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for fixture: Dictionary in main.cases:
		if not str(fixture.name).begins_with("authored/"): continue
		var id := str(fixture.levelId)
		await _sample(id,{},"initial")
		var index := 0
		for step: Dictionary in fixture.steps:
			index += 1
			if str(step.command.kind) == "act" or index == fixture.steps.size():
				await _sample(id,step.snapshot,"step-%d-%s" % [index,str(step.command.get("value",""))])
		print("AUDIT ",id)
	var cloud: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for fixture: Dictionary in cloud.levels:
		var id := str(fixture.id)
		await _sample(id,{},"initial")
		var index := 0
		for step: Dictionary in fixture.steps:
			index += 1
			if str(step.command.kind) == "act" or index == fixture.steps.size():
				await _sample(id,step.snapshot,"step-%d-%s" % [index,str(step.command.get("value",""))])
		print("AUDIT ",id)
	var entries: Array = []
	for path: String in seen:
		var entry: Dictionary = seen[path]
		entry.uses = entry.uses.keys(); entry.visibleUses = entry.visibleUses.keys(); entry.nodes = entry.nodes.keys(); entry.roles = entry.roles.keys()
		entries.append(entry)
	var generated_entries: Array = []
	for key: String in generated:
		var entry: Dictionary = generated[key]
		entry.contexts = entry.contexts.keys()
		generated_entries.append(entry)
	var calls: Dictionary = {}
	for alias: String in stage.calls: calls[alias] = {"resource":Assets.resource_path(alias),"contexts":stage.calls[alias].keys()}
	var report := {"scope":"15 native level scenes and all authored action-state snapshots. Resource load calls are separate from textures bound to actual sprites/materials. Actor-frame reachability is included but classified by the separate actor audit. No geometry, rule state, saves or art modified; no GPU quality claim.","sampledStates":states,"boundResources":entries,"stageTextureCalls":calls,"generatedNodeTextures":generated_entries,"assetErrors":stage.asset_errors()}
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n"); file.close()
	print(JSON.stringify({"states":states.size(),"boundResources":entries.size(),"stageAliases":calls.size(),"generatedTextures":generated_entries.size(),"assetErrors":stage.asset_errors()}))
	stage.queue_free()
	await process_frame
	quit(0)
