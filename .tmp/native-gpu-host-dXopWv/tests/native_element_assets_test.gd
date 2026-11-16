extends SceneTree
const Assets = preload("res://elements/element_assets.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _run() -> void:
	Assets.reset_theme()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/visual-assets.json"))
	for entry: Dictionary in manifest.entries:
		check(Assets.resource_path(entry.id) == entry.resource, "default resource preserved: " + str(entry.id))
	var before := Assets.revision()
	check(not Assets.apply_theme({"schema_version":1,"resource_overrides":{"missing-alias":"res://assets/images/production/flower.png"}}).ok, "unknown alias rejected")
	check(Assets.revision() == before, "rejected theme is atomic")
	check(not Assets.apply_theme({"schema_version":1,"resource_overrides":{"flower":"res://missing.png"}}).ok, "missing replacement rejected")
	check(not Assets.apply_theme({"schema_version":1,"resource_overrides":{"flower":"res://core/garden_world.gd"}}).ok, "non-texture rejected")
	var original := Assets.texture("flower")
	var bloom_path := Assets.resource_path("bloom")
	check(Assets.apply_theme({"schema_version":1,"resource_overrides":{"flower":bloom_path}}).ok, "compatible flower state asset replaces shared slot")
	check(Assets.texture("flower").resource_path == bloom_path and Assets.texture("flower") != original, "replacement bypasses stale alias cache")
	check(Assets.resource_path("bloom") == bloom_path, "other slot unchanged")
	check(Assets.revision() > before, "theme change invalidates consumer caches")
	Assets.reset_theme()
	check(Assets.texture("flower").resource_path == original.resource_path, "default restoration works")
	check(Assets.texture("unknown") == null, "missing alias remains explicit")
	print(JSON.stringify({"suite":"element-assets","checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
