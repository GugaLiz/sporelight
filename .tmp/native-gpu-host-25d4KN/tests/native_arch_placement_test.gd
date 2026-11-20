extends SceneTree
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var original_at := Vector3.ZERO
	for turn in range(4):
		var snapshot: Dictionary = World.new("1-3").snapshot()
		snapshot.turns.garden = turn
		var world := World.new("1-3", snapshot)
		stage.set_world(world)
		await process_frame
		var arch: Sprite3D = stage._props.get_node("OriginalScenery_13_arch")
		check(arch.position.is_equal_approx(Vector3(-4.44,.008,-.64)),"reviewed explicit placement is used without runtime search")
		check(is_equal_approx(arch.pixel_size,90.0*sqrt(2.0)/70.0/256.0),"approved 90px source scale remains")
		check(arch.offset.is_equal_approx(Vector2(-32,103.5)),"original front foot anchor remains")
		if turn == 0: original_at = arch.global_position
		check(arch.global_position.is_equal_approx(original_at),"fixed shore arch remains stable through all turns")
		# Independently reconstruct painted source plinths from the actual card.
		# Sampling the old radius again would miss the unsupported west column.
		var anchor := Vector2(arch.texture.get_width()*.5-arch.offset.x,arch.texture.get_height()*.5+arch.offset.y)
		for foot: Vector4 in [Vector4(72,188,30,15),Vector4(164,213,32,16)]:
			var minimum := Vector2(INF,INF)
			var maximum := Vector2(-INF,-INF)
			for corner: Vector2 in [Vector2(-foot.z,0),Vector2(0,-foot.w),Vector2(foot.z,0),Vector2(0,foot.w)]:
				var p := Vector2(foot.x,foot.y)+corner-anchor
				var ground := arch.global_position+Vector3(1,0,-1).normalized()*p.x*arch.pixel_size+Vector3(1,0,1).normalized()*p.y*arch.pixel_size*2
				minimum=minimum.min(Vector2(ground.x,ground.z)); maximum=maximum.max(Vector2(ground.x,ground.z))
			for ix in range(9):
				for iz in range(9):
					var point := Vector3(lerpf(minimum.x,maximum.x,ix/8.0),arch.global_position.y-.008,lerpf(minimum.y,maximum.y,iz/8.0))
					var logical: Vector3 = stage.logical_position(point)
					var tile_id := "f:%d:%d" % [roundi(logical.x),roundi(logical.z)]
					check(stage._surfaces.has(tile_id) and not bool(stage._tile_map.get(tile_id,{}).get("solid",false)) and absf(stage.support_height(point,tile_id)-point.y)<.012,"entire painted column has real same-height shore support")
		var rest: Vector3 = stage.tile_position_id("f:-5:-1")
		for who: String in ["luvie","buddy"]:
			check(stage.prop_point_clear(rest,who),"rest doorway clears actual "+who+" capsule and navigation margin")
		var before: Dictionary = world.snapshot()
		stage._props_signature=0
		stage.refresh_world(world,false)
		check(stage._props.get_node("OriginalScenery_13_arch").global_position.is_equal_approx(original_at),"forced rebuild preserves stable arch position")
		check(world.snapshot()==before,"placement does not change rule state or rest identity")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"native-arch-placement","checks":checks,"failures":failures,"gpuPixelsVerified":false}))
	quit(0 if failures.is_empty() else 1)
