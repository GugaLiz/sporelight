# Flower gate registered-layer reference

The current native gate and decorative light tower share one 272 × 405 logical canvas. Source art is `godot/assets/images/garden-scenery/light-tower.png`; the frame and seal were split from this exact raster by `scripts/prepare_garden_scenery.py`.

The two original membrane polygons, in that canvas, are:

```json
{
  "left": [[83,235],[98,211],[113,203],[127,226],[128,296],[111,310],[85,302]],
  "right": [[158,228],[170,212],[185,220],[192,244],[191,290],[171,306],[158,295]]
}
```

The frame is the full tower with those two membrane interiors transparent; the seal contains only those membrane interiors. Both retain the whole canvas, including transparent margins. `OriginalSanctuaryDressing.scenery` assigns the same world position, pixel size and `offset=(0,202)` to both; seal render priority is one. The seal disappears after the existing `home` flag, while the frame keeps its normal depth and full masonry base.

For redrawing, generate the complete tower once using the existing picture as the geometry reference, retaining both pillars, roof, gold finial, flowers and full base. Register that master once to the logical canvas, then derive the two membrane layers with one reviewed antialiased mask. Do not generate three independent towers or fit each state's overall alpha bounds separately. If the new aperture contours differ, review the mask against the new painted masonry before exporting; a polygon must not cut into the pillars or leave cyan fragments in the open state.

Olive-background inspection previews are saved beside this file as `light-tower-against-olive.png`, `flower-gate-frame-against-olive.png`, and `flower-gate-seal-against-olive.png`. These previews only reveal alpha boundaries for inspection; they are not game assets.

# Shared source-consumer repair

`original_sanctuary_dressing.gd:_stone_grain()` now reads `ElementAssets.texture("stone")` rather than directly loading the old raster path. Its generated fountain texture invalidates on the shared asset revision, retaining warm-cache reuse. The native-presentation audit found no other direct old bitmap load bypass in the current stage path; legacy `presentation/world/garden_view.gd` is the optional legacy renderer, outside the current native scene runtime.

The new `native_fountain_theme_test.gd` replaces the stone slot with a same-canvas test texture, checks actual fountain pixel changes and one-time raster invalidation, restores identical original pixels, and compares pose, foot, full base outline, scale, depth and rule state. This test plus the existing cache and sanctuary suites passed 294 checks; see `scene-theme-headless/checks.json`. No rule, geometry or UV sampling coordinate changed.
