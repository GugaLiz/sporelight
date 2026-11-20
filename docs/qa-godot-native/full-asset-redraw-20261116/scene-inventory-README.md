# Scene resource inventory

2026-11-16. Native runtime resources before the full redraw task.

{"sceneResources":54,"oldCutoutResources":29,"alreadyRedrawnResources":13,"opaqueTextures":12}

Constructed 15 levels and 115 initial/authored-action snapshots with a TracedStage. Actual sprite/material bindings are separate from texture requests; every bound resource has per-level/state/node roles, alpha statistics and original SHA256. Carry-pouch compositing and the fountain stone-grain direct load are added with source evidence. Inactive cached nodes remain in raw uses; visibleUses/levels identify rendered-state reachability. This is resource usage/provenance, not GPU visual acceptance or a route playthrough.

## Old cutouts in use

| Alias | Canvas | Use | Required registration |
| --- | --- | --- | --- |
| berry-bush | 134 × 115 | 1-3, 1-4, 2-1, 2-2, 2-3, 2-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| blue-mushroom | 100 × 130 | 3-1, 3-2, 3-3, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| dew-parcel | 91 × 97 | 2-1, 3-3 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Dew plant ground state and carried parcel are separate assets; do not turn either into a new puzzle object. |
| dew-plant | 119 × 135 | 2-1, 3-3 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Dew plant ground state and carried parcel are separate assets; do not turn either into a new puzzle object. |
| fern | 126 × 114 | 1-1, 1-2, 1-3, 1-4, 2-1, 2-2, 2-3, 2-4, 3-1, 3-3, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| flower-gate-frame | 272 × 405 | 1-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage. Frame/seal are a registered pair split from light-tower; preserve transparent doorway/membrane mask and independent seal fade. |
| flower-gate-seal | 272 × 405 | 1-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage. Frame/seal are a registered pair split from light-tower; preserve transparent doorway/membrane mask and independent seal fade. |
| glow-flower | 182 × 272 | 3-1, 3-2, 3-3, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| light-tower | 272 × 405 | 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage. |
| lotus-pool | 342 × 200 | 2-1, 2-2, 2-3 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage. |
| pink-flowers | 130 × 124 | 1-1, 1-2, 1-3, 1-4, 2-1, 2-2, 2-3 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| red-mushroom | 113 × 142 | 1-1, 1-2, 1-3, 1-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| river-rock | 113 × 97 | 2-1, 2-2, 2-3, 2-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage. |
| small-pebbles | 117 × 50 | 1-1, 1-3, 1-4, 2-1, 2-2, 2-3, 2-4, 3-1, 3-2, 3-3, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| stone-lantern | 116 × 158 | 1-1, 1-2, 1-3, 1-4, 2-1, 2-2, 2-3, 2-4, 3-1, 3-2, 3-3, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage. |
| trailing-vine | 57 × 226 | 1-1, 1-2, 1-3, 1-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| violet-crystal | 86 × 111 | 3-1, 3-3, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| wood-lantern | 120 × 154 | 2-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| yellow-flowers | 106 × 112 | 1-1, 1-2, 1-3, 1-4, 2-1, 2-2 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| bush | 141 × 119 | 1-1, 1-3, 1-4, 2-1, 2-2, 2-3, 2-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| crystal | 88 × 102 | 2-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| flowers | 130 × 124 | 1-3, 1-4, 2-1, 2-2, 2-3, 2-4, 3-1, 3-2, 3-3, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| lilypad | 146 × 85 | 1-4, 2-1, 2-2, 2-3, 2-4, 3-2, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| rock | 122 × 146 | 1-2 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. Full hard-base footprint and navigation/depth alignment must be reviewed separately from foliage. |
| stairs | 142 × 147 | 1-1, 1-2, 1-3, 1-4, 2-1, 2-2, 2-3, 2-4, 3-1, 3-2, 3-3, 3-4 | Interior paint-source is sampled by PaintedStoneUV.sample using fixed 142x147 source pixels; preserve sampled tread/riser quadrilaterals, not only silhouette. |
| stone | 229 × 148 | 1-4 | Only interior grain is composited into the code-native fountain; source outer cutout edge is not displayed. Keep sampled stone face coverage; no geometry change. |
| bug | 256 × 256 | 2-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| light | 256 × 256 | 3-1 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |
| vine | 256 × 256 | 1-1, 1-2, 3-4 | Preserve logical canvas, alpha8 silhouette, root/foot anchor and source pixel-to-world scale. |

## Source evidence and exclusions

- garden-scenery extraction: scripts/prepare_garden_scenery.py. Original sheet crop + edge-connected neutral removal.
- grid-world extraction: scripts/prepare_grid_assets.py. Same removal process. stairs/stone are cutout SOURCE rasters used as interior surface/grain samples; their silhouette is not directly displayed.
- production extraction: scripts/prepare_assets.py. remove_checker and special glow alpha processing.
- stone grain is loaded directly in original_sanctuary_dressing.gd; a new theme alias alone will not replace this direct load.
- flowers and pink-flowers share the same source flower cluster, with slightly different source crops. flower-gate-frame/seal are registered layers derived from light-tower.
- 13 already-redrawn resources: the previous seven scene sprites plus six generated shadow/symbiosis state textures.
- Cloud architecture, plants, birds, lantern strings, drops and other native forms are code-authored SVG/mesh/shader assets. They are not old sheet cutouts.
- Unused directory candidates such as pebble-cluster, production/moss.png and grid-world/grass.png were not included simply because a manifest listed them.
- Actor frame resources and ball are handled by the separate UI/actor inventory; scene source paths are deduplicated by resource file.

## Reproduce

Run the pinned Godot console with: --headless --path godot --script res://tests/audit_scene_asset_usage.gd -- --output=<absolute scene-runtime-usage.json path>. Then node tools/godot-migration/audit-scene-assets.mjs enriches provenance/alpha and creates the contact sheet. Neither operation edits game art, save data or production behavior.
