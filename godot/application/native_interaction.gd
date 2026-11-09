class_name NativeInteraction
extends RefCounted

## Pure proximity/grouping policy. Availability remains owned by domain queries;
## this module never executes an action or mutates a command supplied by callers.
static func context(world: RefCounted, commands: Array, availability: Dictionary, actor_position: Vector3, tile_position: Callable, policy: Dictionary = {}) -> Dictionary:
	var groups := {}
	for command: Dictionary in commands:
		var id := str(command.id)
		var target: Dictionary = command_tile(world, command)
		if target.is_empty():
			continue
		var location: Vector3 = tile_position.call(target)
		var distance := Vector2(location.x - actor_position.x, location.z - actor_position.z).length()
		if distance > 1.65:
			continue
		var key := str(target.id)
		if not groups.has(key):
			groups[key] = {"tile": target, "distance": distance, "choices": []}
		var entry: Dictionary = command.duplicate(true)
		entry["disabled"] = not bool(availability.get(id, {}).get("available", false))
		entry["reason"] = str(availability.get(id, {}).get("reason", ""))
		groups[key].choices.append(entry)
	if groups.is_empty():
		return {}
	var sorted: Array = groups.values()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Nearby observation does not steal the main action from a mechanism.
		var a_observe := str(a.choices[0].id).begins_with("observe:") or str(a.choices[0].id).begins_with("discover:")
		var b_observe := str(b.choices[0].id).begins_with("observe:") or str(b.choices[0].id).begins_with("discover:")
		return float(a.distance) + (0.35 if a_observe else 0.0) < float(b.distance) + (0.35 if b_observe else 0.0)
	)
	var selected: Dictionary = sorted[0]
	var choices: Array = selected.choices
	var root_action := false
	for command: Dictionary in choices:
		if str(command.id).begins_with("grow:") or str(command.id).begins_with("retract:"):
			root_action = true
	var label := "安排根路" if root_action else str(choices[0].label) if choices.size() == 1 else "选择操作"
	if root_action and policy.has("root_prompt"):
		label = str(policy.root_prompt) if choices.size() > 1 else "收回根路" if str(choices[0].id).begins_with("retract:") else str(policy.root_prompt)
		var labels: Dictionary = policy.get("root_labels", {})
		for choice: Dictionary in choices:
			choice.label = str(labels.get(str(choice.id), choice.label))
	return {"id": str(choices[0].id) if choices.size() == 1 and not root_action else "context", "label": label, "choices": choices, "tile": selected.tile}


static func command_tile(world: RefCounted, command: Dictionary) -> Dictionary:
	var id := str(command.id)
	var parts := id.split(":")
	var target := str(command.get("target", ""))
	if not target.is_empty():
		var tile: Dictionary = world.point_for(target)
		if not tile.is_empty():
			return tile
		for mark: Dictionary in world.level.marks:
			if str(mark.id) == target:
				return world.point_for(str(mark.tile))
	if id.begins_with("grow:") or id.begins_with("retract:"):
		for root: Dictionary in world.level.roots:
			if str(root.id) == str(parts[1]):
				return world.point_for(str(root.at))
	if id.begins_with("take:") or id.begins_with("angle:"):
		var item: Dictionary = world.state.items.get(str(parts[1]), {})
		return world.point() if item.get("holder", "") == world.actor() else world.point_for(str(item.get("tile", "")))
	if id.begins_with("drop:"):
		return world.point_for(":".join(parts.slice(2)))
	for mark: Dictionary in world.level.marks:
		if id == "repair" and mark.kind == "core":
			return world.point_for(str(mark.tile))
		if id == "freeze" and str(mark.id) == "freeze":
			return world.point_for(str(mark.tile))
		if (id.begins_with("swap:") or id in ["play", "beat", "resetSong"]) and mark.kind == "song":
			return world.point_for(str(mark.tile))
		if parts.size() >= 2 and str(mark.id) == str(parts[1]):
			return world.point_for(str(mark.tile))
	if id.begins_with("turn:") and parts.size() >= 2:
		for module: Dictionary in world.level.modules:
			if str(module.id) == str(parts[1]):
				return world.point_for(world.module_cell(str(module.id)))
	return world.point()

