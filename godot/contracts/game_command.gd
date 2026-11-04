class_name GardenCommand
extends RefCounted

enum Kind { MOVE, INTERACT, UNDO }

var kind: Kind
var value: String

func _init(command_kind: Kind = Kind.INTERACT, command_value: String = "") -> void:
	kind = command_kind
	value = command_value

static func move_to(tile_id: String) -> GardenCommand:
	return GardenCommand.new(Kind.MOVE, tile_id)

static func interact(action_id: String) -> GardenCommand:
	return GardenCommand.new(Kind.INTERACT, action_id)

static func undo_action() -> GardenCommand:
	return GardenCommand.new(Kind.UNDO)

func to_dictionary() -> Dictionary:
	return {"kind": Kind.keys()[kind].to_lower(), "value": value}

