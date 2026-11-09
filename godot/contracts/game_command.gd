class_name GardenCommand
extends RefCounted

enum Kind { MOVE, INTERACT, UNDO, ACTOR_MOVE }

var kind: Kind
var value: String
var actor_id: String = ""

func _init(command_kind: Kind = Kind.INTERACT, command_value: String = "") -> void:
	kind = command_kind
	value = command_value

static func move_to(tile_id: String) -> GardenCommand:
	return GardenCommand.new(Kind.MOVE, tile_id)

static func interact(action_id: String) -> GardenCommand:
	return GardenCommand.new(Kind.INTERACT, action_id)

static func move_actor(who: String, tile_id: String) -> GardenCommand:
	var result := GardenCommand.new(Kind.ACTOR_MOVE, tile_id)
	result.actor_id = who
	return result

static func undo_action() -> GardenCommand:
	return GardenCommand.new(Kind.UNDO)

func to_dictionary() -> Dictionary:
	var result := {"kind": Kind.keys()[kind].to_lower(), "value": value}
	if not actor_id.is_empty():
		result["actor"] = actor_id
	return result

