extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Factory = preload("res://core/world_factory.gd")
const Ratios = preload("res://presentation/native/original_prop_ratios.gd")
var rows: Array = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var stage := Stage.new(); root.add_child(stage); stage.set_process(false)
	var refs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var cloud: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cloud-reference.json"))
	for id: String in ["1-1","1-2","1-3","1-4","2-1","2-2","2-3","2-4","3-1","3-2","3-3","3-4","cloud-1","cloud-2","cloud-3"]:
		var done: Dictionary = {}
		for entry: Dictionary in refs.cases:
			if str(entry.name)=="authored/"+id: done=entry.steps.back().snapshot
		for entry: Dictionary in cloud.levels:
			if str(entry.id)==id: done=entry.steps.back().snapshot
		for state: Dictionary in [{},done]:
			stage.set_world(Factory.create(id,state))
			stage.refresh_world(stage.world,false)
			var row := {"level":id,"completed":stage.world.state.completed,"roots":[],"cloud":[],"collectibles":[]}
			for key: String in stage._props_nodes:
				var node: Node3D = stage._props_nodes[key]
				if not node.has_meta("tile_id"): continue
				var tile := str(node.get_meta("tile_id"))
				var point: Vector3 = stage.tile_position_id(tile)
				var item := {"id":key,"tile":tile,"root":str(node.global_position),"center_delta":str(node.global_position-point),"cards":[]}
				for child in node.get_children():
					if child is Sprite3D:
						item.cards.append({"name":str(child.name),"position":str(child.position),"billboard":child.billboard,"offset":str(child.offset),"width":child.texture.get_width()*child.pixel_size,"normal":str(child.global_basis.z.normalized())})
				var base: Node3D = node.get_node_or_null("InstrumentBase")
				if base != null:
					item.base_root_distance=Vector2(base.position.x,base.position.z).length()
					item.base_gap=base.global_position.y-.06-stage.support_height(base.global_position,tile)
					item.actor_distances={}
					for who: String in ["luvie","buddy"]:
						var body: Node3D = stage.get_actor_body(who)
						item.actor_distances[who]=Vector2(body.position.x-base.global_position.x,body.position.z-base.global_position.z).length()
				if key=="mark:core" and not id.begins_with("cloud"):
					var layout := Ratios.core_layout(stage,node)
					item.core_shift=str(layout.shift); item.footprint_supported=Ratios._supported_footprint(stage,node,layout.width,layout.shift)
				row.roots.append(item)
			for node in stage._props.get_children():
				if not node.has_meta("original_kind"): continue
				var card: Sprite3D = node.get_child(0)
				var entry := {"kind":node.get_meta("original_kind"),"root":str(node.global_position),"card":str(card.global_position),"sourceFoot":card.get_meta("source_foot",0),"foot_support":false}
				for surface: Node3D in stage._surfaces.values():
					var local: Vector3 = surface.to_local(card.global_position)
					if absf(local.x)<=.5 and absf(local.z)<=.5 and absf(float(surface.sample_height(card.global_position))-card.global_position.y)<.025: entry.foot_support=true
				row.cloud.append(entry)
			for key: String in stage._garden_effects.collectibles:
				var e: Dictionary=stage._garden_effects.collectibles[key]
				row.collectibles.append({"id":key,"entry":str(e)})
			rows.append(row)
	print(JSON.stringify({"rows":rows}))
	stage.free(); quit()
