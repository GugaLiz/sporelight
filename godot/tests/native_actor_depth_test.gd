extends SceneTree
const FirstGarden = preload("res://presentation/native/first_garden_profile.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var world := World.new("1-1")
	world.act("grow:root:right")
	world.act("grow:root:down")
	stage.set_world(world)
	await process_frame
	stage.set_paused(true)
	for who: String in ["luvie", "buddy"]:
		var body: CharacterBody3D = stage.get_actor_body(who)
		var art: AnimatedSprite3D = body.get_node("Visual/Art")
		body.get_node("Visual/AnimationPlayer").stop()
		stage.actor_visual_root(who).scale = Vector3.ONE
		for lane in [2, 3, 4]:
			world.state.actors[who] = "f:%d:-1" % lane
			for distance: float in [0.61, 0.76, 0.91, 1.06, 1.21]:
				body.position = stage.physical_position(Vector3(lane, 0, -distance))
				body.position.y = stage.support_height(body.position, world.state.actors[who]) + 0.018
				for facing: String in ["front", "back", "left", "right"]:
					stage.update_actor_visual(who, Vector3.ZERO, facing)
					var foot: Vector3 = stage.actor_visual_root(who).global_position
					var head := art.to_global(Vector3(0, 1, 0))
					_check(Vector2(head.x - foot.x, head.z - foot.z).length() < 0.0001, "upright card cannot lean into rear risers")
					var expected := stage.world_to_screen(foot + stage._camera.global_basis.y)
					_check(stage.world_to_screen(head).distance_to(expected) < 0.01, "vertical depth correction preserves projected artwork height")
					_check(absf(foot.y - stage.support_height(foot, world.state.actors[who])) < 0.0001, "foot anchor stays on actual tread")
					_check(not art.no_depth_test and art.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS, "foreground still occludes actor through real depth")
					var before := art.basis
					for repeat in range(5): stage.update_actor_visual(who, Vector3.ZERO, facing)
					_check(art.basis.is_equal_approx(before), "pose updates never accumulate projection compensation")
	for spec: Vector3 in [FirstGarden.EAST, FirstGarden.REAR, FirstGarden.SOUTH]:
		_check((spec.y - spec.x) / spec.z >= 0.1499, "treads preserve the authored minimum usable depth")
	_check_stride(stage)
	stage.set_world(World.new("1-3"))
	for who: String in ["luvie", "buddy"]:
		stage.update_actor_visual(who, Vector3.ZERO)
		_check(stage.get_actor_body(who).get_node("Visual/Art").billboard == BaseMaterial3D.BILLBOARD_ENABLED, "unverified other levels retain established rendering")
	print(JSON.stringify({"suite":"actor-depth-clearance", "checks":checks, "passed":failures.is_empty(), "failures":failures}))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_stride(stage: Node) -> void:
	for who: String in ["luvie", "buddy"]:
		for flight in range(3):
			var world := World.new("1-1")
			world.act("grow:root:down" if flight == 2 else "grow:root:right")
			stage.set_world(world)
			var body: CharacterBody3D = stage.get_actor_body(who)
			for direction: float in [-1.0, 1.0]:
				var previous := INF
				for sample in range(91):
					var distance := 0.25 + (sample if direction > 0 else 90 - sample) * 0.015
					var logical := Vector3(distance, 0, 0) if flight == 0 else Vector3(3, 0, -distance) if flight == 1 else Vector3(0, 0, distance)
					var id := "g:root:1:0" if flight == 0 else "f:3:%d" % int(roundf(-distance)) if flight == 1 else "g:root:0:1"
					if flight == 0 and distance < 0.5: id = "f:0:0"
					if flight == 0 and distance > 1.5: id = "f:2:0"
					if flight == 2 and distance < 0.5: id = "f:0:0"
					if flight == 2 and distance > 1.5: id = "f:0:2"
					world.state.actors[who] = id
					body.position = stage.physical_position(logical)
					var ground: float = stage.support_height(body.position, id)
					body.position.y = ground + 0.018
					var velocity := (Vector3.RIGHT if flight == 0 else Vector3.FORWARD if flight == 1 else Vector3.BACK) * direction * 2.0
					stage.update_actor_visual(who, velocity)
					var sole: float = stage.actor_visual_root(who).global_position.y
					_check(sole >= ground - 0.00001 and sole <= ground + 0.1084, "moving sole stays within one riser above actual terrain")
					if is_finite(previous): _check(absf(sole - previous) < 0.041, "continuous traversal avoids a full-riser vertical jump: %s flight=%d direction=%s distance=%s previous=%s sole=%s" % [who, flight, direction, distance, previous, sole])
					previous = sole
					_check(absf(body.get_node("Shadow").global_position.y - ground - 0.012) < 0.00001, "shadow remains on real tread during lifted stride")
					stage.update_actor_visual(who, Vector3.ZERO)
					_check(absf(stage.actor_visual_root(who).global_position.y - ground) < 0.00001, "stopping restores exact tread contact")
	_check(is_equal_approx(stage.stair_pace(Vector3.ZERO, Vector2.RIGHT), 1.0), "flat ground keeps ordinary walking speed")
	for at: Vector3 in [Vector3(1, 0, 0), Vector3(3, 0, -0.8), Vector3(0, 0, 1)]:
		var direction := Vector2.RIGHT if at.x == 1 else Vector2.DOWN
		_check(is_equal_approx(stage.stair_pace(stage.physical_position(at), direction), 0.62), "climbing and descending use measured stair pace")
		_check(is_equal_approx(stage.stair_pace(stage.physical_position(at), direction.orthogonal()), 1.0), "walking along a tread retains normal speed")

