extends SceneTree
## Physical arrival/restoration around existing instruments; no synthetic paths.
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const Session = preload("res://application/game_session.gd")
const Movement = preload("res://application/native_movement.gd")
const Router = preload("res://application/input_router.gd")
const Picking = preload("res://presentation/native/native_prop_picking.gd")
var checks := 0
var failures: Array[String] = []
var visibility: Array = []
var stage: Node2D
var session: RefCounted
var movement: RefCounted
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	stage = Stage.new(); root.add_child(stage); stage.set_process(false)
	for id: String in ["1-3","2-1","3-2","3-3","3-4"]:
		session = Session.new(id)
		var marks: Array = session.world.level.marks.duplicate(true)
		for mark: Dictionary in marks:
			if not str(mark.kind) in ["turn","valve","lift"] or str(mark.id) == "mirrorA": continue
			session = Session.new(id)
			var small := bool(session.world.point_for(str(mark.tile)).get("small",false))
			if not small: session.world.state.actors.luvie = str(mark.tile)
			session.world.state.actors.buddy = str(mark.tile)
			session.world.state.follow = false
			session.world.state.erase("runtime")
			var saved: Dictionary = session.world.snapshot()
			stage.set_world(session.world)
			movement = Movement.new(); movement.setup(session,stage,Router.new())
			await physics_frame
			check(session.world.state.actors == saved.actors and session.world.state.turns == saved.turns,id+" restore keeps rule supports and mechanisms")
			for who: String in ["luvie","buddy"]:
				if small and who == "luvie": continue
				_validate(mark,who,"default")
				var body: CharacterBody3D = stage.get_actor_body(who)
				var tile: Dictionary = session.world.point_for(str(mark.tile))
				var center: Vector3 = stage.tile_position(tile)
				# Explicit manual positions, including the old exact centre, remain
				# authoritative in active gardens and completed saved memories.
				for completed: bool in [false,true]:
					session.world.state.completed = completed
					for offset: Vector3 in [Vector3.ZERO,Vector3(.04,0,-.08)]:
						body.position = center+offset+Vector3(0,.018,0)
						movement.capture(); movement.restore()
						check(Vector2(body.position.x-center.x-offset.x,body.position.z-center.z-offset.z).length()<.01,id+" "+who+" explicit pose preserved "+str(completed))
				session.world.state.completed = false; session.world.state.active = who
				body.position = center+Vector3(0,.018,0)
				movement.capture(); movement.request_path([str(mark.tile)])
				for frame in range(120):
					await physics_frame
					movement.tick(1.0/60)
					if frame>3 and not movement.is_moving(): break
				check(not movement.is_moving(),id+" "+who+" same-support click settles")
				var expected: Vector3 = stage.actor_rest_position(tile,who)
				check(Vector2(body.position.x-expected.x,body.position.z-expected.z).length()<.06,id+" "+who+" real motor reaches instrument stance")
				_validate(mark,who,"walked")
	await _four_turns()
	await _lift_steps()
	print(JSON.stringify({"suite":"native-instrument-stance","checks":checks,"failures":failures,"passed":failures.is_empty(),"visibility":visibility,"gpuPixelsVerified":false}))
	stage.free(); quit(0 if failures.is_empty() else 1)

func _validate(mark: Dictionary,who: String,phase: String,readability := true) -> void:
	var label := str(session.world.level.id)+"/"+str(mark.id)+"/"+who+"/"+phase
	var body: CharacterBody3D = stage.get_actor_body(who)
	var base: MeshInstance3D = stage._props_nodes["mark:"+str(mark.id)].get_node("InstrumentBase")
	var shape: CapsuleShape3D = body.get_node("Collision").shape
	check(Vector2(body.position.x-base.global_position.x,body.position.z-base.global_position.z).length()>.1995+shape.radius,label+" full capsule clears base actor="+str(body.position)+" base="+str(base.global_position))
	check(str(session.world.state.actors[who]) == str(mark.tile),label+" logical support unchanged")
	var supported := true
	var height: float = stage.support_height(body.position,str(mark.tile),who)
	for sector in range(24):
		var foot := body.position+Vector3(cos(TAU*sector/24),0,sin(TAU*sector/24))*shape.radius
		var hit := false
		for surface: Node3D in stage._surfaces.values():
			if not surface.is_visible_in_tree(): continue
			if phase.begins_with("lift") and not str(surface.tile_id).begins_with("m:lift:"): continue
			var local := surface.to_local(foot)
			if absf(local.x)>.5001 or absf(local.z)>.5001: continue
			if absf(float(surface.sample_height(foot))-height)<.025: hit = true; break
		if not hit: supported = false
	check(supported,label+" full capsule real flat support")
	if who == "luvie" and readability: _wheel_readability(base,label)
	if who == "buddy" and readability: _buddy_face_readability(body,label)

func _buddy_face_readability(body: CharacterBody3D,label: String) -> void:
	# BuddyCanvas has a 112px foot anchor, draws at y=107, and eyes at
	# (+/-4.5,-13) scaled by 92/48. These are facial landmarks, not an
	# opaque-rectangle substitute for the GPU-rendered companion texture.
	var art: AnimatedSprite3D = body.get_node("Visual/Art")
	var face := Transform3D(stage._camera.global_basis.orthonormalized().scaled(art.global_basis.get_scale()),art.global_position)
	var clear := 0
	var clear_props := 0
	var hero: AnimatedSprite3D = stage.get_actor_body("luvie").get_node("Visual/Art")
	for x: float in [-4.5,0,4.5]:
		var point := face.origin+face.basis*Vector3(x*92.0/48.0,5.0+13.0*92.0/48.0,0)*art.pixel_size
		var screen: Vector2 = stage.world_to_screen(point)
		var origin: Vector3 = stage._camera.project_ray_origin(screen)
		var direction: Vector3 = stage._camera.project_ray_normal(screen)
		if not Picking._art_occludes(stage,null,origin,direction,origin.distance_to(point)): clear += 1
		hero.visible = false
		if not Picking._art_occludes(stage,null,origin,direction,origin.distance_to(point)): clear_props += 1
		hero.visible = true
	visibility.append({"label":label,"buddyFaceLandmarks":clear,"buddyFaceClearProps":clear_props})
	# A landmark ray is diagnostic, not a whole-face alpha measurement.
	# The reviewed water pose permits one partly covered point. Light's
	# optional two-passenger pose must retain a facial landmark; the actual
	# GPU image decides whether the expression remains recognisable. Never
	# push either body onto a departing edge to satisfy three clear rays.
	var required := 1 if label.begins_with("3-4/light/") else 2 if label.begins_with("3-3/turn/") else 3
	check(clear >= required,label+" companion face is not fully occluded at sampled landmarks (GPU review required)")

func _lift_steps() -> void:
	for id: String in ["3-3","3-4"]:
		session = Session.new(id)
		var mark: Dictionary
		for candidate: Dictionary in session.world.level.marks:
			if str(candidate.id) == "lift": mark = candidate
		session.world.state.actors.luvie = str(mark.tile)
		session.world.state.actors.buddy = str(mark.tile)
		session.world.state.follow = false; session.world.state.erase("runtime")
		stage.set_world(session.world)
		movement = Movement.new(); movement.setup(session,stage,Router.new())
		await physics_frame
		for direction in range(2):
			var before: Dictionary = session.world.snapshot()
			session.world.state.turns.lift = 1-direction
			var after: Dictionary = session.world.snapshot()
			movement.begin_mechanism(before,after)
			for progress: float in [0,.25,.5,.75,1.0]:
				stage.set_motion(before,after,progress,"valve:lift")
				movement.advance_mechanism(progress)
				for who: String in ["luvie","buddy"]:
					stage.update_actor_visual(who,Vector3.ZERO,"front")
					_validate(mark,who,"lift"+str(direction)+"/"+str(progress),false)
			stage.clear_motion(false); movement.finish_mechanism()

func _four_turns() -> void:
	for id: String in ["1-3","3-3","3-4"]:
		var initial := Session.new(id)
		for mark: Dictionary in initial.world.level.marks:
			var module := preload("res://presentation/native/mechanism_props.gd")._rotating_module(initial.world,str(mark.tile))
			if module.is_empty(): continue
			var small := bool(initial.world.point_for(str(mark.tile)).get("small",false))
			session = Session.new(id)
			if not small: session.world.state.actors.luvie = str(mark.tile)
			session.world.state.actors.buddy = str(mark.tile)
			session.world.state.follow = false; session.world.state.erase("runtime")
			stage.set_world(session.world)
			movement = Movement.new(); movement.setup(session,stage,Router.new())
			await physics_frame
			for turn in range(4):
				var before: Dictionary = session.world.snapshot()
				# Sample the existing rotation transaction even when a particular
				# puzzle requires another flag before the command can be issued.
				session.world.state.turns[module] = (int(session.world.state.turns.get(module,0))+1)%4
				var after: Dictionary = session.world.snapshot()
				movement.begin_mechanism(before,after)
				for progress: float in [0,.25,.5,.75,1.0]:
					stage.set_motion(before,after,progress,"turn:"+module)
					movement.advance_mechanism(progress)
					for who: String in ["luvie","buddy"]:
						if small and who == "luvie": continue
						stage.update_actor_visual(who,Vector3.ZERO,"front")
						_validate(mark,who,"turn"+str(turn)+"/"+str(progress),progress==0 or progress==1)
				stage.clear_motion(false); movement.finish_mechanism()
				for who: String in ["luvie","buddy"]:
					if small and who == "luvie": continue
					_validate(mark,who,"settled"+str(turn))

func _wheel_readability(base: MeshInstance3D,label: String) -> void:
	var wheel: MeshInstance3D = base.get_parent().get_node("InstrumentWheel")
	var hero: AnimatedSprite3D = stage.get_actor_body("luvie").get_node("Visual/Art")
	# Sample the real mesh triangles; test the current opaque hero image on
	# the camera ray, rather than assuming a floor gap makes the control visible.
	var visible := 0
	var faces := wheel.mesh.get_faces()
	for index in range(0,faces.size(),3):
		var point := wheel.to_global((faces[index]+faces[index+1]+faces[index+2])/3.0)
		var screen: Vector2 = stage.world_to_screen(point)
		var origin: Vector3 = stage._camera.project_ray_origin(screen)
		var direction: Vector3 = stage._camera.project_ray_normal(screen)
		if Picking._opaque_distance(hero,stage._camera,origin,direction)>origin.distance_to(point)-.01: visible += 1
	var fraction := float(visible)/(faces.size()/3)
	visibility.append({"label":label,"wheel":fraction})
	# Light's departing west edge requires an inset stance. Its operational
	# glyph must be clear; a partly covered rim is acceptable and must never
	# be 'fixed' by putting the passenger back across the protected edge.
	var inset_light := label.begins_with("3-4/light/")
	var inset_water := label.begins_with("3-3/turn/")
	# Water's opposite inset avoids the foreground high terrace. The GPU
	# review permits a partly covered rim, with all five glyph rays still clear.
	check(fraction>(.5 if inset_light else .70 if inset_water else .90),label+" wheel remains legible with safe stance")
	var symbol: Label3D = base.get_parent().get_node("MotionKind")
	var clear_glyph := 0
	for offset: Vector2 in [Vector2.ZERO,Vector2(-.035,0),Vector2(.035,0),Vector2(0,-.035),Vector2(0,.035)]:
		var point := symbol.to_global(Vector3(offset.x,offset.y,0))
		var screen: Vector2 = stage.world_to_screen(point)
		var origin: Vector3 = stage._camera.project_ray_origin(screen)
		var direction: Vector3 = stage._camera.project_ray_normal(screen)
		if Picking._opaque_distance(hero,stage._camera,origin,direction)>origin.distance_to(point)-.01: clear_glyph += 1
	check(clear_glyph==5,label+" central action glyph and four adjacent points clear hero")
	var stem: MeshInstance3D = base.get_parent().get_node("InstrumentStem")
	visible = 0
	for y: float in [.12,.20,.28,.36,.44]:
		var point := stem.global_position+Vector3(0,y-.28,0)
		var screen: Vector2 = stage.world_to_screen(point)
		var origin: Vector3 = stage._camera.project_ray_origin(screen)
		var direction: Vector3 = stage._camera.project_ray_normal(screen)
		if Picking._opaque_distance(hero,stage._camera,origin,direction)>origin.distance_to(point)-.01: visible += 1
	check(visible>=4,label+" at least four of five stem points clear opaque hero")
