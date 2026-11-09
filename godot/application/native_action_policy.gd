class_name NativeActionPolicy
extends RefCounted

## Presentation timing only: transaction validation/commit/cancel stay in main.
static func duration(clip: String, low_motion: bool, policy: Dictionary = {}) -> float:
	if clip.begins_with("take:") or clip.begins_with("drop:"):
		return 0.32
	if clip.begins_with("angle:") or clip.begins_with("observe:") or clip.begins_with("discover:"):
		return 0.24
	if clip.begins_with("grow:") or clip.begins_with("retract:"):
		if clip.begins_with("grow:") and not low_motion:
			return float(policy.get("growth_duration", 0.44))
		return 0.44
	if clip.begins_with("turn:") or clip.begins_with("valve:") or clip in ["rotate", "lift", "beat"]:
		return 0.62
	if clip == "repair":
		return 0.75
	return 0.36

