extends RefCounted
## Candidate scenery sizes referenced to the approved first garden, in world
## units. Source alpha >= 64; detached flower clusters count as one plant.
## Runtime never scans PNG pixels. Tests verify the measured source metadata.
const SOURCES := {
	"fern": {"size": Vector2i(126, 114), "body": Rect2i(0, 0, 126, 114), "base_x": Vector2i(8, 101), "width": 0.44},
	"pink-flowers": {"size": Vector2i(130, 124), "body": Rect2i(0, 0, 130, 124), "base_x": Vector2i(0, 130), "width": 0.34},
	"blue-flowers": {"size": Vector2i(112, 118), "body": Rect2i(0, 0, 112, 118), "base_x": Vector2i(11, 90), "width": 0.30},
	"yellow-flowers": {"size": Vector2i(106, 112), "body": Rect2i(0, 0, 106, 112), "base_x": Vector2i(6, 106), "width": 0.28},
	"red-mushroom": {"size": Vector2i(113, 142), "body": Rect2i(0, 0, 113, 142), "base_x": Vector2i(19, 98), "width": 0.27},
	"blue-mushroom": {"size": Vector2i(100, 130), "body": Rect2i(0, 0, 100, 130), "base_x": Vector2i(18, 83), "width": 0.27},
	"stone-lantern": {"size": Vector2i(116, 158), "body": Rect2i(0, 0, 116, 158), "base_x": Vector2i(0, 116), "width": 0.43},
	"wood-lantern": {"size": Vector2i(120, 154), "body": Rect2i(0, 0, 120, 154), "base_x": Vector2i(0, 65), "width": 0.40},
	"trailing-vine": {"size": Vector2i(57, 226), "body": Rect2i(0, 0, 57, 226), "base_x": Vector2i(18, 43), "width": 0.23}
}

static func nominal_width(alias: String) -> float:
	var source: Dictionary = SOURCES[alias]
	return float(source.width) * source.size.x / source.body.size.x

static func footprint_radius(alias: String) -> float:
	var source: Dictionary = SOURCES[alias]
	# Conservative square around the lower 20% of the source silhouette,
	# projected along both isometric ground axes, including asymmetric feet.
	var half := float(source.size.x) * 0.5
	var reach := maxf(half - source.base_x.x, source.base_x.y - half)
	return nominal_width(alias) * reach / source.size.x / sqrt(2.0) + 0.01

static func flat_footprint(stage: Node, at: Vector3, support: String, alias: String) -> bool:
	var radius := footprint_radius(alias)
	var centre: Vector3 = stage.tile_position(stage._tile_map[support])
	# Chapter scenery is on unscaled fixed tiles. Second-garden edge props use
	# its outer x=-1 or x=5 tiles, never the physically widened x=4 stair tile.
	if absf(at.x - centre.x) + radius > 0.49 or absf(at.z - centre.z) + radius > 0.49: return false
	var height: float = stage.support_height(at, support)
	for x: float in [-radius, 0.0, radius]:
		for z: float in [-radius, 0.0, radius]:
			if absf(stage.support_height(at + Vector3(x, 0, z), support) - height) > 0.008: return false
	return true
