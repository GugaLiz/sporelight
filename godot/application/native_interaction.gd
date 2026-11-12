class_name NativeInteraction
extends RefCounted

## Pure proximity/grouping policy. Availability remains owned by domain queries;
## this module never executes an action or mutates a command supplied by callers.
static func context(world: RefCounted, commands: Array, availability: Dictionary, actor_position: Vector3, tile_position: Callable, policy: Dictionary = {}, world_tiles: Array = []) -> Dictionary:
	if commands.is_empty(): return {}
	if world_tiles.is_empty(): world_tiles = world.tiles()
	var groups := {}
	for command: Dictionary in commands:
		var id := str(command.id)
		var target: Dictionary = command_tile(world, command, world_tiles)
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
	# A settled mechanism must not hide a legal nearby substantive action.
	# Optional observations alone keep the original focus and its denial reason.
	if not selected.choices.any(func(choice: Dictionary) -> bool: return not bool(choice.disabled)):
		for group: Dictionary in sorted:
			if group.choices.any(func(choice: Dictionary) -> bool: return not bool(choice.disabled) and not str(choice.id).begins_with("observe:") and not str(choice.id).begins_with("discover:")):
				selected = group
				break
	var choices: Array = selected.choices.duplicate(true)
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
	if root_action and bool(policy.get("path_root_progress", false)):
		# Keep committed progress visible on short screens where the objective
		# row is hidden. The choices and their domain availability stay intact.
		for choice: Dictionary in choices:
			var parts := str(choice.id).split(":")
			if parts.size() < 2 or not parts[0] in ["grow", "retract"]:
				continue
			for root: Dictionary in world.level.get("roots", []):
				if str(root.id) == parts[1]:
					label = "根路 %d/%d" % [world.state.get("growth", {}).get(root.id, []).size(), int(root.budget)]
			break
	# A single nearby pet/action must not bypass the menu and hide another
	# reachable object. Keep the focused group first and retain blocked reasons.
	for group: Dictionary in sorted:
		if str(group.tile.id) != str(selected.tile.id):
			choices.append_array(group.choices)
	if sorted.size() > 1 and not root_action:
		label = "选择附近操作"
	return {"id": str(choices[0].id) if choices.size() == 1 and not root_action else "context", "label": label, "choices": choices, "tile": selected.tile}


static func command_tile(world: RefCounted, command: Dictionary, world_tiles: Array = []) -> Dictionary:
	# A context owns one read-only derived board. Standalone callers keep the
	# same fresh-query behavior, without a cache surviving an action or pose.
	if world_tiles.is_empty(): world_tiles = world.tiles()
	var id := str(command.id)
	var parts := id.split(":")
	var target := str(command.get("target", ""))
	if not target.is_empty():
		var tile: Dictionary = world.point_for(target, world_tiles)
		if not tile.is_empty():
			return tile
		for mark: Dictionary in world.level.marks:
			if str(mark.id) == target:
				return world.point_for(str(mark.tile), world_tiles)
	if id.begins_with("grow:") or id.begins_with("retract:"):
		for root: Dictionary in world.level.roots:
			if str(root.id) == str(parts[1]):
				return world.point_for(str(root.at), world_tiles)
	if id.begins_with("take:") or id.begins_with("angle:"):
		var item: Dictionary = world.state.items.get(str(parts[1]), {})
		return world.point_for(str(world.state.actors[world.actor()]), world_tiles) if item.get("holder", "") == world.actor() else world.point_for(str(item.get("tile", "")), world_tiles)
	if id.begins_with("drop:"):
		return world.point_for(":".join(parts.slice(2)), world_tiles)
	for mark: Dictionary in world.level.marks:
		if id == "repair" and mark.kind == "core":
			return world.point_for(str(mark.tile), world_tiles)
		if id == "freeze" and str(mark.id) == "freeze":
			return world.point_for(str(mark.tile), world_tiles)
		if (id.begins_with("swap:") or id in ["play", "beat", "resetSong"]) and mark.kind == "song":
			return world.point_for(str(mark.tile), world_tiles)
		if parts.size() >= 2 and str(mark.id) == str(parts[1]):
			return world.point_for(str(mark.tile), world_tiles)
	if id.begins_with("turn:") and parts.size() >= 2:
		for module: Dictionary in world.level.modules:
			if str(module.id) == str(parts[1]):
				return world.point_for(world.module_cell(str(module.id)), world_tiles)
	return world.point_for(str(world.state.actors[world.actor()]), world_tiles)

