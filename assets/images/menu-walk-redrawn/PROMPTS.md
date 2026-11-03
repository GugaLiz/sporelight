# Side-view redraw provenance

Generated with the built-in imagegen tool, at the user's explicit request to redraw if cutout repairs were insufficient. Identity reference: `assets/images/material/char.png`. Original references are preserved. No CLI/API fallback used.

## Walk-cycle prompt

Redraw a production transparent WALK CYCLE spritesheet for the EXACT girl in the attached character reference. Match original sculpted 3D storybook look and identity: brown bob, big brown eyes, tall curled red mushroom hat with cream dots, GREEN LEAF cape and mushroom brooch, ivory scalloped dress, brown ankle boots. Exactly EIGHT complete full body sprites in a regular 4 column x 2 row grid, equal cells, generous gutters. True transparent background; NO checkerboard, text, labels, drop shadows or scenery. Every sprite strictly LEFT SIDE PROFILE, entire body/shoulders/arms/hips face left, consistent head shape, scale and lighting. Sequential full walk cycle: near foot forward contact, near down/far toe off, passing far foot beneath bent knee, far forward reach, opposite contact, opposite down, opposite passing, opposite reach. Supporting boot sole flat on ground, swing boot lifts via knee and ankle articulation, rounded toes always point left; never sliced or detached feet. Gentle modest stride, natural opposite arm swing, stable hat and hip registration. Same ground baseline within each cell. Each pose a single clean opaque coherent character with clean antialiased alpha edges, no blur, no ghosting, no pasted frontal torso. Preserve face, hat, leaf cape and dress details faithfully.

## Matching idle prompt

Create ONE clean full-body LEFT SIDE PROFILE neutral standing sprite matching exactly the same red mushroom-hatted girl in this walk-cycle reference. Preserve face, mushroom hat, green leaf cape, scalloped ivory dress, brown boots and sculpted storybook 3D style. Both feet relaxed on same ground line, both boot soles FLAT horizontal, toes pointing LEFT, arms resting naturally beside the side-view torso, no walking, no raised foot. Entire person faces LEFT. Center figure with generous margins, full hat and shoes visible. TRUE transparent alpha background, no scenery, floor, halo, cast shadow, backdrop, checkerboard or text. Clean smooth continuous silhouette without white fringe or ragged edges. Same body proportions as reference. Intended as idle pose between these walking frames.

## Packaging

The generated transparent PNGs are saved here as `source-sheet.png` and `source-idle.png`. `scripts/import_menu_redraw.py` extracts the eight cells and registers them on 512×512 canvases with foot baseline 472. This packaging preserves generated alpha and never cuts, rotates, or blends body parts.
