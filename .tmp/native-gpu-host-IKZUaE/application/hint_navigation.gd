class_name HintNavigation
extends RefCounted

const TIERS := 3

## A reducer, not a second state store: HUD owns visibility, application owns tier.
## Hint wording and task progress remain in GardenJourney/domain rules.
static func transition(tier: int, visible: bool, event: String) -> Dictionary:
	match event:
		"toggle": visible = not visible
		"next":
			if visible: tier = (tier + 1) % TIERS
		"reset":
			tier = 0
			visible = false
	return {"tier": clampi(tier, 0, TIERS - 1), "visible": visible}
