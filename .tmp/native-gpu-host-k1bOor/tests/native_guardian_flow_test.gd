extends "res://tests/native_ui_test.gd"
## Flow presentation is read-only; validate historical flags against live state.
const World = preload("res://core/garden_world.gd")
const Flow = preload("res://application/guardian_flow_guidance.gd")
const Interaction = preload("res://application/native_interaction.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
var fixture: Dictionary = {}
var records: Array = []

func _world(index: int) -> RefCounted:
	return World.new("3-4", fixture.steps[index].snapshot)

func _expect(world: RefCounted, phase: String, phrase: String, label: String) -> Dictionary:
	var before: Dictionary = world.snapshot().duplicate(true)
	var commands: Array = world.commands().duplicate(true)
	var state: Dictionary = Flow.describe(world)
	_check(str(state.phase) == phase, label + "/current-phase")
	_check(str(state.goal).contains(phrase), label + "/direct-current-intention")
	_check(not str(state.goal).contains("90") and not str(state.goal).contains("三节") and not str(state.goal).contains("f:"), label + "/no-solution-angle-or-coordinates")
	_check(str(Journey.describe(world).goal) == str(state.goal), label + "/existing-objective-row-uses-flow")
	_check(Snapshot.equivalent(before, world.snapshot()) and commands == world.commands(), label + "/presentation-never-changes-world-or-commands")
	records.append({"case": label, "state": state})
	return state

func _display_commands(world: RefCounted) -> void:
	var original: Array = world.commands().duplicate(true)
	var availability := {}
	for command: Dictionary in original: availability[str(command.id)] = {"available": true}
	var board: Array = world.tiles()
	var actor: Dictionary = world.point_for(str(world.state.actors[world.actor()]), board)
	var locate := func(tile: Dictionary) -> Vector3: return Vector3(float(tile.x), float(tile.h) * .65, float(tile.z))
	var context: Dictionary = Interaction.context(world, original, availability, locate.call(actor), locate, {}, board)
	for choice: Dictionary in context.get("choices", []):
		var source: Array = original.filter(func(command: Dictionary) -> bool: return str(command.id) == str(choice.id))
		_check(source.size() == 1, "display-label maps an existing original command")
		if source.is_empty(): continue
		_check(str(choice.label) == Flow.command_label(world, str(choice.id), str(source[0].label)), "nearby context uses a concrete object name")
		_check(not choice.disabled and str(choice.reason).is_empty(), "renaming preserves supplied availability")
	_check(original == world.commands(), "renaming does not mutate caller commands")

func _readonly_replay() -> void:
	for index in range(fixture.steps.size()):
		var world: RefCounted = _world(index)
		var before: Dictionary = world.snapshot().duplicate(true)
		var commands: Array = world.commands().duplicate(true)
		Flow.describe(world)
		Journey.describe(world)
		for command: Dictionary in commands: Flow.command_label(world, str(command.id), str(command.label))
		for tier in range(3): Journey.hint(world, tier)
		_check(Snapshot.equivalent(before, world.snapshot()), "original state " + str(index) + " remains unchanged")
		_check(commands == world.commands(), "original actions " + str(index) + " remain unchanged")
		if not bool(world.state.completed):
			_check(str(Journey.hint(world, 0).message) == "根路通向远岸，清水为升降台蓄力，光唤醒花坛。" and str(Journey.hint(world, 1).message) == "储水罐灌满后不会流失；让光留在花坛上，再和伙伴回来照料。", "current causal broad hints " + str(index) + " describe stored water and live light")
	for id: String in ["1-1", "2-3", "3-2", "3-3"]:
		var world := World.new(id)
		var before: Dictionary = world.snapshot().duplicate(true)
		_check(Flow.describe(world).is_empty(), id + "/no-guardian-state")
		_check(str(Journey.describe(world).goal) == str(Journey.GOALS[id][0]), id + "/original-default-goal")
		for command: Dictionary in world.commands():
			_check(Flow.command_label(world, str(command.id), str(command.label)) == str(command.label), id + "/original-command-label")
		_check(Snapshot.equivalent(before, world.snapshot()), id + "/world-unchanged")

func _hud_cases() -> void:
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(844,390),Vector2i(568,320)]:
		var outer := SubViewport.new()
		outer.size = dimensions
		root.add_child(outer)
		var hud := HUD.new()
		outer.add_child(hud)
		for index in [48,55,80,94,95]:
			var world: RefCounted = _world(index)
			var expected: Dictionary = Flow.describe(world)
			hud.update_state(world)
			hud.set_journey(Journey.describe(world))
			await _settle()
			await _settle()
			var label := str(dimensions) + "/step-" + str(index)
			_check(hud._rule.visible and hud._rule.text == str(expected.goal), label + "/current-goal-remains-visible-on-small-screen")
			_check(hud._heading.get_global_rect().grow(1).encloses(hud._rule.get_global_rect()), label + "/objective-contained-in-existing-heading")
			_check(hud._collection_count.text == "赠礼 %d / 8" % world.state.collected.size(), label + "/actual-original-gift-count-labelled")
			_check(hud._collection_count.tooltip_text.contains("各得到两份赠礼") and not hud._score.text.contains("沿途"), label + "/gift-source-is-not-map-collectibles")
			_check(not hud._journey_steps.visible and not hud._journey_count.visible, label + "/no-new-checklist-panel")
			_check(hud.safe_world_rect().size.y >= dimensions.y * .3, label + "/world-area-retained")
			var stable_rect: Rect2 = hud._heading.get_global_rect()
			for repeat in range(5):
				hud.update_state(world)
				hud.set_journey(Journey.describe(world))
				await process_frame
			_check(stable_rect == hud._heading.get_global_rect(), label + "/repeated-state-does-not-jitter-layout")
		var ordinary := World.new("3-3")
		hud.update_state(ordinary)
		hud.set_journey(Journey.describe(ordinary))
		await _settle()
		_check(not hud._collection_count.text.contains("赠礼") and hud._score.text.contains("沿途微光"), str(dimensions) + "/other-level-collection-label-restored")
		_check(hud._rule.visible == (dimensions.y > 500), str(dimensions) + "/other-level-small-screen-layout-retained")
		outer.queue_free()
		await process_frame

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for entry: Dictionary in data.cases:
		if entry.name == "authored/3-4": fixture = entry
	_check(not fixture.is_empty(), "original guardian reference exists")
	if fixture.is_empty(): quit(1); return
	_expect(World.new("3-4"), "root", "接通根路", "cold")
	_expect(_world(20), "water", "小苔灵接通水渠", "mirror-ready-but-water-missing")
	_expect(_world(34), "mirror", "切换露薇", "water-supplied-companion-still-active")
	var mirror_hero: Dictionary = fixture.steps[34].snapshot.duplicate(true)
	mirror_hero.active = "luvie"
	_expect(World.new("3-4", mirror_hero), "mirror", "放进岸边的镜座", "water-supplied-hero-already-active")
	_expect(_world(36), "mirror", "放进岸边的镜座", "raised-with-mirror")
	_expect(_world(48), "return_lift", "乘升降台返回", "screenshot-high-bank")
	_expect(_world(55), "reunion", "露薇回到起点花坛", "after-lowering-with-existing-return-route")
	_expect(_world(68), "reunion", "露薇回到起点花坛", "inner-joined")
	var hero_home: Dictionary = _expect(_world(80), "reunion", "接小苔灵回来", "hero-home")
	_check(hero_home.near_core_luvie and not hero_home.near_core_buddy, "current individual arrival is not historical moon")
	var both_home: Dictionary = _expect(_world(94), "care", "照料花坛", "both-home")
	_check(both_home.ready and both_home.together and both_home.light_current, "care only when actual conditions hold")
	_expect(_world(95), "complete", "已苏醒", "completed")
	for condition: String in ["inner", "water", "light"]:
		var saved: Dictionary = fixture.steps[94].snapshot.duplicate(true)
		saved.turns[condition] = 0
		var world := World.new("3-4", saved)
		var required := condition == "light"
		var state: Dictionary = _expect(world, "restore_light" if required else "care", "光断了" if required else "照料花坛", "causal-current-" + condition)
		_check(world.flag("moon") and world.state.collected.size() == 8 and bool(state.ready) == not required, "only live light remains a cultivation condition; stored water and road angle have their own roles: " + condition)
	var low_lift: Dictionary = fixture.steps[48].snapshot.duplicate(true)
	low_lift.turns.lift = 0
	_expect(World.new("3-4", low_lift), "rescue_lift", "小苔灵升台接人", "high-hero-low-lift")
	var dry_return: Dictionary = fixture.steps[54].snapshot.duplicate(true)
	dry_return.turns.water = 0
	var dry_world := World.new("3-4", dry_return)
	var dry_state: Dictionary = _expect(dry_world, "return_lift", "乘升降台返回", "high-lift-safe-descent-with-reservoir-filled")
	_check(not dry_state.water_current and bool(dry_world.act("valve:lift").ok), "missing-current-water does not suppress original safe descent")
	var high_buddy: Dictionary = fixture.steps[48].snapshot.duplicate(true)
	high_buddy.actors = {"luvie":"f:-4:0","buddy":"f:8:2"}
	_expect(World.new("3-4", high_buddy), "return_lift", "切换小苔灵", "buddy-high-hero-active")
	var waiting_buddy: Dictionary = fixture.steps[48].snapshot.duplicate(true)
	waiting_buddy.active = "buddy"
	_expect(World.new("3-4", waiting_buddy), "return_lift", "切换露薇", "hero-high-companion-active")
	var light_buddy: Dictionary = fixture.steps[48].snapshot.duplicate(true)
	light_buddy.flags.erase("star")
	light_buddy.turns.light = 0
	light_buddy.active = "buddy"
	_expect(World.new("3-4", light_buddy), "light", "切换露薇", "placed-mirror-companion-active")
	for index in [34,54,68,80,94]: _display_commands(_world(index))
	_check(Flow.command_label(_world(34), "valve:lift", "old") == "升起升降台 ↑", "low lift names ascent")
	_check(Flow.command_label(_world(54), "valve:lift", "old") == "降下升降台 ↓", "high lift names descent")
	_readonly_replay()
	await _hud_cases()
	print(JSON.stringify({"suite":"guardian-flow","checks":_checks,"passed":_failures.is_empty(),"failures":_failures,"records":records,"scope":"Pure current-intention presentation, unchanged original snapshots/actions, real native HUD layout. Not GPU appearance, physical return, browser or performance acceptance."}))
	quit(0 if _failures.is_empty() else 1)
