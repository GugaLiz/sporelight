# Native scene feedback review — 2026-11-12

The requested arch, fountain, wall/shore, bridge and latch changes pass the reviewed visual scope. This is not a claim that the whole project has no clipping: the existing 1-3 initial actor overlap remains open under GQ-003.

## Evidence and version binding

| Batch | Source identity | Actual images reviewed |
| --- | --- | ---: |
| `delivery-final/` | `c6c430378e24a5183f8cfcced8a23cbade03cb212e24c35b7776fb29a75e96e8`, 584 runtime files | 52/52 |
| `approach-clear-final-gpu/` | `b0066359b247ee276a5d9fdf6ebc2afb120030eadf0c3f34b6c1024c1f7bbbca`, 585 runtime files | 4/4 |
| `release-visual-binding/` | `a83286c3f7e3ef44aa7180788fdf9e7803cf19224fd329c3e27dda2b644fdb4f`, 585 runtime files | 4/4 |

Every image in these three batches was opened and visually inspected. PNG IHDR dimensions independently match 1280×720 or 844×390. All three native capture reports have `framebuffersSaved=true`, `sourceFilesStable=true`, `failures=[]` and `passed=true`.

The last four images directly cover final-source 1-4 repair-before and completed states in the normal camera at both sizes. Their twelve recorded related `.gd`/`.json` hashes match current disk bytes, including `native_prop_obstacles.gd`. See `source-binding.json` for per-file hashes and every reviewed image's SHA-256. Earlier batches recorded eleven related sources and did not record that obstacle module.

The 52-image basis is deliberately not relabelled as final-source evidence. After it, editor import added `native_arch_footprint.gd.uid`, the buddy's real same-tile standing point changed from `(.40,0,-.20)` to `(.44,0,.30)`, and contact escape changed to use the polygon's actual contact normal. Those are real byte/behavior changes. Ten of the basis's eleven recorded files remain byte-identical; `native_garden_stage.gd` differs. The last contact change kept visual dimensions, positions, anchors and default standing points unchanged. Final-source normal-camera evidence is the separate four-image batch.

## Visual findings

- 1-3's upper-left arch stays on the same fixed island through all four static turns. Its measured root moves from `(-4.84,.008,-.84)` to `(-4.44,.008,-.64)`. Width remains `1.81827461719513`; source offset `(-32,103.5)` and depth testing remain unchanged.
- The final 1-4 fountain has its full front basin outline above the ground, with aligned upper/lower basin and water arcs. Width remains `1.81221362948418`; sprite Y remains `.657999992370605`, offset remains `(0,176)`, and depth testing remains enabled. The actual basin center is `(-8.65,-1.75)`; the front-foot sprite root is approximately `(-8.15714264,.658,-1.25714290)`. Sprite-root coordinates are not the basin center.
- At final buddy standing point `(.44,0,.30)`, both faces are distinguishable before and after flower opening in both normal-camera sizes. The flowerbed's right stem remains beside the cap and does not cover the eyes/face. The mole and golden lotus remain visible.
- Latch-before and latch-after expose the raised brass grip and horizontal green locked grip beside the player and spore halo. The small plaque lettering is tiny at 844×390; this review does not claim every letter is comfortably readable.
- Closed wall/shore, opened home stair, held bridge and prepared bridge midpoint show the intended attached terrain silhouettes. Prepared midpoints are visual samples, not proof of the complete motion lifecycle.

Two earlier flowerbed candidates were explicitly rejected for hiding the buddy's face; their original images and logs remain in `core-front-candidate/` and `core-front-second/`. Intermediate `after/` and `after-final/` remain intermediate evidence, not delivery evidence.

## Checks and limits

Strict mechanism checks pass 539 assertions with `failures=[]`, including registered hard bases, exact planner/collider footprint agreement, mesh bounds, layer/mask, anti-entry height, latch contact and cues. Logs remain in `mechanism-delivery-final/` and `mechanism-approach-final/`. These CPU checks state `gpuPixelsVerified=false` and do not replace the GPU review.

Rendering used native Windows/OpenGL compatibility on NVIDIA GeForce RTX 4090 D. The runtime logger's assertions are clean, but startup stderr consistently contains `ERROR: Failed to read the root certificate store.` This environmental startup error is preserved and prevents a claim of completely clean startup.

These captures use prepared snapshots and presentation interpolation with default settings. They do not establish browser rendering, real user input, full gameplay completion, complete transitions or performance. The parent agent owns and separately records the final actual physical routes and delivery binding.

The 1-3 initial hero/buddy zero-offset overlap and intermittent lower-body stripes are visible in the original `before/` evidence as well as the 52-image basis. The parent confirmed that initial placement is unchanged. It remains an open baseline issue, not a fixed item in this delivery.
