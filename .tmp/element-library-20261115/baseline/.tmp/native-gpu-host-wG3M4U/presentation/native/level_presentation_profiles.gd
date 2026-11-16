class_name LevelPresentationProfiles
extends RefCounted

## Opt in per level. Unknown levels keep the established native fallback.
## No domain rules, objective predicates or save coordinates belong here.
const FIRST_GARDEN := {
	"terrain": preload("res://presentation/native/first_garden_profile.gd"),
	"dressing": preload("res://presentation/native/first_garden_dressing.gd"),
	"full_width_traversal": true,
	"physical_stair_steps": true,
	"smooth_stair_soles": true,
	"vertical_actor_depth": true,
	"integrated_props": true,
	"prop_shadows": true,
	"interaction_ring": true,
	"growth_reveal": true,
	"growth_duration": 0.68,
	"root_prompt": "选择生长方向",
	"seedbed_growth_choices": true,
	"root_labels": {"grow:root:right": "向东生长 · 1节", "grow:root:down": "向南生长 · 1节", "retract:root": "收回根路"}
}

const SECOND_GARDEN := {
	"terrain": preload("res://presentation/native/second_garden_profile.gd"),
	"dressing": preload("res://presentation/native/second_garden_dressing.gd"),
	"full_width_traversal": true,
	"physical_stair_steps": true,
	"smooth_stair_soles": true,
	"vertical_actor_depth": true,
	"integrated_props": true,
	"prop_shadows": true,
	"interaction_ring": true,
	"growth_reveal": true,
	"path_growth_reveal": true,
	"path_root_progress": true
}

## Shared real treads retain each garden's rule coordinates and narrow lanes.
const CHAPTER_GARDEN := {
	"dressing": preload("res://presentation/native/chapter_garden_dressing.gd"),
	"vertical_actor_depth": true,
	"integrated_props": true,
	"prop_shadows": true,
	"interaction_ring": true,
	"physical_stair_steps": true,
	"smooth_stair_soles": true,
	"growth_reveal": true,
	"path_growth_reveal": true
}

const CHAPTER_LEVELS := [
	"1-3", "1-4", "2-1", "2-2", "2-3", "2-4",
	"3-1", "3-2", "3-3", "3-4", "cloud-1", "cloud-2", "cloud-3"
]

static func for_level(id: String) -> Dictionary:
	match id:
		"1-1": return FIRST_GARDEN
		"1-2": return SECOND_GARDEN
	if id in CHAPTER_LEVELS: return CHAPTER_GARDEN
	return {}
