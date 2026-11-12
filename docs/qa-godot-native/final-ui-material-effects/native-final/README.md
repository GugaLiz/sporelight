# Frozen native integration acceptance

- Result: True; source stable: True.
- Source SHA-256: `a004245d0253d107e0dfb194187347aab37d9c27835eba80a0c01043f1f7e11f` (536 files).
- 31 suite executions; 338,868 check executions. Excluding the duplicate UI alias: 338,686 checks across 30 test programs.
- All 15 full physical routes completed; 477 authored actions, 19,270 physical samples.
- No runtime files, tests, or golden data were changed during this final batch.

| Suite | Checks | Result |
| --- | ---: | --- |
| service_save_test | 87 | PASS |
| service_snapshot_normalizer_test | 2,120 | PASS |
| service_hud_test | 182 | PASS |
| service_button_test | 100 | PASS |
| service_modal_lifecycle_test | 262 | PASS |
| service_home_navigation_test | 381 | PASS |
| native_chapter_map_test | 286 | PASS |
| native_chapter_presentation_test | 362 | PASS |
| native_cloud_bridge_motion_test | 3,666 | PASS |
| native_cloud_save_test | 29 | PASS |
| native_first_garden_material_test | 19,189 | PASS |
| native_game_hud_skin_test | 66 | PASS |
| native_garden_effects_test | 2,113 | PASS |
| native_generic_stair_movement_test | 35 | PASS |
| native_generic_stairs_test | 2,208 | PASS |
| native_island_foundations_test | 3,793 | PASS |
| native_motion_cache_test | 9,147 | PASS |
| native_motion_terrain_test | 83,520 | PASS |
| native_overview_hud_test | 136 | PASS |
| native_persistence_roundtrip_test | 510 | PASS |
| native_persistence_test | 22 | PASS |
| native_root_route_plan_test | 40 | PASS |
| native_root_weaving_hud_test | 43 | PASS |
| native_route_test | 1,826 | PASS |
| native_second_garden_test | 139 | PASS |
| native_stair_lifecycle_test | 28,905 | PASS |
| native_surface_alignment_test | 74,371 | PASS |
| native_ui_test | 182 | PASS |
| native_visibility_water_query_test | 9,120 | PASS |
| native_water_render_test | 43 | PASS |
| native_world_render_test | 95,985 | PASS |

Limits:

- Headless assertions do not certify GPU pixels, pointer/touch, or audible audio.
- 31 suite executions include service_hud_test alias rerunning native_ui_test (182 checks); unique test programs: 30.
- Selected native integration coverage; not the unrestricted legacy rule_reference suite.
