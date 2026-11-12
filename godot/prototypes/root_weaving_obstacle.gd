extends RefCounted

# Compatibility entry for older prototype references; both versions share art.
static func build(stage: Node, wall: Array) -> void:
	preload("res://presentation/native/isolated_rock_spire.gd").build(stage, wall)
