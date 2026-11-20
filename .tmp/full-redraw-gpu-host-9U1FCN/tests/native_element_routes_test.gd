extends "res://tests/native_route_test.gd"
## Keep historical intentions immutable, add the actual walks required by the
## already accepted frontier rule (GQ-022). No body/state injection or new route.
func _replay(id: String, steps: Array, initial: Dictionary) -> void:
	var expanded: Array = []
	var previous := initial
	var added_walks := 0
	for step: Dictionary in steps:
		var command: Dictionary = step.command
		if str(command.kind)=="act" and str(command.value).begins_with("grow:"):
			var root_id := str(command.value).get_slice(":",1)
			var path: Array = previous.get("growth",{}).get(root_id,[])
			if not path.is_empty():
				var at_frontier: Dictionary = previous.duplicate(true)
				at_frontier.actors.luvie = str(path.back())
				expanded.append({"command":{"kind":"move","value":str(path.back())},"snapshot":at_frontier})
				added_walks += 1
		expanded.append(step)
		previous = step.snapshot
	await super._replay(id,expanded,initial)
	routes.back().originalIntentions = steps.size()
	routes.back().addedFrontierWalks = added_walks
