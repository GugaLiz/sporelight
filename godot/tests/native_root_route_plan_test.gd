extends SceneTree
const World = preload("res://core/garden_world.gd")
const Plan = preload("res://application/root_route_plan.gd")
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func _initialize() -> void:
	for route: Array in [["up","right","right","down"],["down","right","right","up"]]:
		var world := World.new("1-2")
		var initial: Dictionary = world.snapshot()
		var plan := Plan.new(world)
		check(not plan.ready(), "empty route cannot grow")
		check(not plan.append("grow:root:right"), "rock blocks straight route in draft")
		for i in range(route.size()):
			check(plan.append("grow:root:"+route[i]), "authored next step is draftable")
			check(world.snapshot() == initial, "draft never changes the live world or budget")
			check(plan.ready() == (i == 3), "only a complete four-segment connected route is confirmable")
		check(not plan.append("grow:root:right"), "draft cannot spend a fifth seed")
		plan.trim(2)
		check(plan.targets.size() == 2 and plan.preview.budget() == 2 and not plan.ready(), "undo restores draft budget and available continuation")
		check(plan.append("grow:root:"+route[2]) and plan.append("grow:root:"+route[3]) and plan.ready(), "trimmed route can be edited back to completion")
		plan.trim(0)
		check(plan.targets.is_empty() and world.snapshot() == initial, "discarding draft preserves the original garden")
	var partial := World.new("1-2")
	partial.act("grow:root:up")
	partial.act("grow:root:right")
	var before := partial.snapshot()
	var remaining := Plan.new(partial)
	check(not remaining.ready(), "partly grown bridge still requires a draft")
	check(remaining.append("grow:root:right") and not remaining.ready(), "remaining draft cannot confirm before shore")
	check(remaining.append("grow:root:down") and remaining.ready(), "undo or interrupted growth can resume remaining seeds")
	remaining.trim(0)
	check(partial.snapshot() == before and remaining.targets.is_empty(), "discarding remaining draft preserves grown roots")
	print(JSON.stringify({"suite":"root-route-plan", "checks":checks,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
