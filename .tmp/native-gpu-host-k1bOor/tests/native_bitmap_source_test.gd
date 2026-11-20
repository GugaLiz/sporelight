extends SceneTree
## Bitmap identity is shared by aliases, direct UI paths and loader packaging.
const Assets = preload("res://elements/element_assets.gd")
const HUD = preload("res://ui/garden_hud.gd")
const Map = preload("res://ui/chapter_map.gd")
const Detail = preload("res://ui/chapter_map_detail_art.gd")
const FLOWER := "res://assets/images/production/flower.png"
const BLOOM := "res://assets/images/production/bloom.png"
const SPORE := "res://assets/images/material-ready/icon-spore.png"
const NEW_SPORE := "res://assets/images/scene-redraw-20261116/spore.png"
const GOLD := "res://assets/images/garden-scenery/gold-lotus.png"
const NEW_GOLD := "res://assets/images/scene-redraw-20261116/gold-lotus.png"
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _run() -> void:
	var configured: Dictionary = Assets.bitmap_redraw_paths()
	var theme: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.THEME_PATH))
	Assets.reset_theme()
	Assets.reset_bitmap_redraw()
	check(Assets.texture_for_source(FLOWER) == Assets.texture("flower"), "unmapped UI source shares cached world texture")
	check(Assets.texture("missing") == null, "unknown alias remains explicit")
	var revision := Assets.revision()
	check(Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":{FLOWER:BLOOM,SPORE:NEW_SPORE,GOLD:NEW_GOLD}}).ok, "same-canvas bitmap set accepted")
	check(Assets.revision() > revision, "bitmap change invalidates visual caches")
	check(Assets.texture_for_source(FLOWER).resource_path == BLOOM and Assets.texture("flower").resource_path == BLOOM, "alias and direct flower source resolve identical redraw")
	check(Assets.texture("spore") == Assets.texture("icon-spore") and Assets.texture("spore") == Assets.texture_for_source(SPORE), "world collectible and UI counter share one redraw")
	var before: Dictionary = Assets.bitmap_redraw_paths()
	revision = Assets.revision()
	check(not Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":{FLOWER:BLOOM,SPORE:"res://assets/images/missing.png"}}).ok, "missing bitmap rejects the whole transaction")
	check(Assets.bitmap_redraw_paths() == before and Assets.revision() == revision, "failed transaction preserves all bindings and cache revision")
	check(not Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":{FLOWER:SPORE}}).ok, "different canvas rejected before changing anchors")
	check(not Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":{FLOWER:"res://core/garden_world.gd"}}).ok, "non-image path rejected")
	check(not Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":{"res://assets/images/missing.png":BLOOM}}).ok, "missing original rejected")
	check(not Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":{"res://assets/images/../images/production/flower.png":BLOOM}}).ok, "noncanonical source rejected")
	check(Assets.apply_theme({"schema_version":1,"resource_overrides":{"flower":FLOWER}}).ok, "explicit theme can override default redraw")
	check(Assets.texture_for_source(FLOWER).resource_path == FLOWER, "UI follows explicit theme precedence")
	Assets.reset_theme()
	check(Assets.texture_for_source(FLOWER).resource_path == BLOOM, "theme reset restores configured bitmap set")
	check(Assets.apply_theme({"schema_version":1,"resource_overrides":{"spore":NEW_SPORE}}).ok, "single alias theme accepted")
	check(Assets.resource_path("icon-spore") == NEW_SPORE, "theme also reaches the same-source UI alias")
	revision = Assets.revision()
	check(not Assets.apply_theme({"schema_version":1,"resource_overrides":{"spore":NEW_SPORE,"icon-spore":SPORE}}).ok, "conflicting same-source alias themes rejected")
	check(Assets.revision() == revision and Assets.resource_path("icon-spore") == NEW_SPORE, "conflicting theme is atomic")
	Assets.reset_theme()
	var hud := HUD.new()
	root.add_child(hud)
	hud.setup()
	check(hud._collection_icon.texture == Assets.texture("spore"), "real HUD counter consumes the redirected bitmap")
	check(hud._texture(FLOWER) == Assets.texture("flower"), "gallery loader consumes the redirected bitmap")
	var map := Map.new()
	root.add_child(map)
	var picture: TextureRect = map._picture(map,"production/flower.png",Rect2(0,0,80,80))
	check(picture.texture == Assets.texture("flower"), "chapter-map pictures consume the redirected bitmap")
	var detail := Detail.new()
	root.add_child(detail)
	detail.configure("3-4")
	check(detail._art.back().texture == Assets.texture_for_source(GOLD), "map mechanism detail consumes redirected scene art")
	var source_without_alias := "res://assets/images/scene-redraw-20261116/bloom.png"
	var alternate := "res://assets/images/scene-redraw-20261116/flower.png"
	check(Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":{source_without_alias:alternate}}).ok, "registered alias is not required for a real UI bitmap source")
	check(Assets.texture_for_source(source_without_alias).resource_path == alternate, "direct source resolves without an alias")
	hud.queue_free(); map.queue_free(); detail.queue_free()
	await process_frame
	Assets.reset_bitmap_redraw()
	check(Assets.texture_for_source(FLOWER).resource_path == FLOWER, "bitmap reset restores original fallback")
	check(Assets.apply_bitmap_redraw({"schema_version":1,"source_overrides":configured}).ok and Assets.apply_theme(theme).ok, "restore shipped mappings after isolated checks")
	print(JSON.stringify({"suite":"bitmap-source-resolution","checks":checks,"failures":failures,"passed":failures.is_empty(),"scope":"Headless shared bitmap resolver and actual UI texture bindings, not visual or pointer acceptance."}))
	quit(0 if failures.is_empty() else 1)
