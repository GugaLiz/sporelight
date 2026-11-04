class_name GardenCommandResult
extends RefCounted

var accepted: bool = false
var changed: bool = false
var message: String = ""
var before: Dictionary = {}
var after: Dictionary = {}
var revision: int = 0
var command: GardenCommand

func to_dictionary() -> Dictionary:
	return {
		"accepted": accepted, "changed": changed, "message": message,
		"before": before.duplicate(true), "after": after.duplicate(true),
		"revision": revision, "command": command.to_dictionary()
	}

