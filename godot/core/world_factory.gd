extends RefCounted

const MainlineWorld = preload("res://core/garden_world.gd")
const CloudWorld = preload("res://core/cloud_garden_world.gd")

static func create(level_id: String = "1-1", saved: Dictionary = {}) -> RefCounted:
	return CloudWorld.new(level_id, saved) if level_id.begins_with("cloud-") else MainlineWorld.new(level_id, saved)
