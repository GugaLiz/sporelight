# 场景素材重绘提示词

2026-11-16，使用内置 `imagegen`，每个资源独立调用并要求真实透明背景。参考图均为本项目既有造型；母图与游戏导出图保存于仓库，运行时通过公共主题槽引用。

## arch

参考：`godot/assets/images/grid-world/arch.png`

Image 1 is the exact SHAPE AND COMPOSITION reference for a Sporelight game sprite. Redraw this SAME overgrown stone arch from scratch as a polished high-resolution hand-painted storybook game asset. Keep identical isometric camera, top plane, two thick rectangular feet, open archway (genuinely transparent opening), warm peach stone blocks, muted teal mossy side, draping ivy and tiny ivory flowers. Keep the full object centered on a square transparent canvas with the same visible extent and empty margins as reference (visible x about 15%-85%, y 4%-94%). Preserve silhouette, arch opening and bottom ground polygon positions precisely, no new pedestal. Clean organic edges with subpixel alpha antialiasing; remove all rough cutout residue, white outlines, pale halos, speckled isolated pixels and beige background. No cast shadow outside its feet, no border, no text, no scenery. Clean painted edges, subtle detailed stone and leaves, soft warm light upper left. Output one complete isolated asset, true RGBA transparency, not a checkerboard image. This must fit as a replacement of the existing art, not a scene redesign.

## ivory-lotus

参考：`godot/assets/images/garden-scenery/ivory-lotus.png`

Image 1 is the shape/composition/color reference for a small Sporelight game plant sprite. Redraw the SAME upright ivory lotus flower: one pale cream pointed layered bloom above a short green stem, two broad green leaves spreading left and right, a small dark green leaf at the root, warm buttery soft light. Keep near-frontal three-quarter view and silhouette/root location like reference: full plant visible, narrow transparent margin, no pot or soil platform. A refined hand-painted storybook asset with smooth organic alpha-antialiased petal and leaf edges, gentle internal shading, readable simple silhouette at small size. Remove all checkerboard/background and cutout outlines; background truly transparent INCLUDING between leaves. No white sticker stroke, no separate sparkles, no grey fringe, no shadow outside plant, no words. One complete isolated transparent game plant; closely preserve reference shape and leaf spread.

## blue-flowers

参考：`godot/assets/images/garden-scenery/blue-flowers.png`

Image 1 is the exact shape and color reference for a Sporelight game prop. Redraw the SAME cluster of blue bellflowers as a clean high-resolution hand-painted storybook game sprite. Preserve three arching olive green stems, large drooping sky-blue bell at upper right, medium bell at left and small bell low on right, small blue bud near center, long pointed green leaves at the base. Preserve the complete silhouette, frontal three-quarter angle, root at bottom center and similar canvas margins. Refined soft painted shading and thin natural details, readable at small game size. Genuine transparent background between every stem/leaf, no white/beige/checkerboard background, no sticker outline, no cutout fringe or pixel specks, no shadow plane, no text. Smooth subpixel antialiased alpha edges with no grey or white halo. One isolated complete plant.

## gold-lotus

参考：`godot/assets/images/garden-scenery/gold-lotus.png`

Image 1 is the EXACT SHAPE reference for a Sporelight in-game pale glowing lotus. Redraw it cleanly as a premium hand-painted storybook transparent sprite: a single upright pointed ivory/cream lotus with warm gold center, thin straight green stem, left and right broad spreading green leaves and the same small root leaves. Retain exact pose, visible shape, leaf spread, camera angle, height-to-width ratio and bottom-center root of the reference. Full flower, no cutoffs. True transparent background, also between petals/stem/leaves; remove any checkerboard, pale matte and cutout residue. Smooth refined antialiased organic edges, soft luminous center without a hard outline, no isolated sparkles, no sticker border, no ground or shadow, no extra props. Warm soft painted colors matching the reference.

## spore

参考：`godot/assets/images/material-ready/icon-spore.png`

Image 1 is the shape and palette reference for a collectible light mote in Sporelight. Redraw the same warm amber circular seed-light token with two delicate ivory sprouting leaves centered inside, a small upper-right satellite bead and a small lower-left satellite bead, subtle other tiny lower-right bead. Full isolated hand-painted fantasy game collectible, clean refined circular form, readable at 24-40 pixels. Preserve reference's horizontally wide composition and relative circle/body size. Gently luminous amber glass center, thin soft golden rim, tiny internal highlight dots. REMOVE the thick ivory sticker-like cutout border and the rough floating diamond on the left. Smooth continuous antialiased alpha edges, true transparent background, no paper silhouette, no beige/white matte, no square glow box, no text. Keep a restrained smooth warm halo close to the circular edge only.

## bloom

参考：`godot/assets/images/production/bloom.png`

Image 1 is an EXACT geometry and composition reference for a Sporelight terminal flowerbed sprite. Redraw THE SAME object from scratch with premium smooth hand-painted storybook edges: one soft coral-pink five-petal open flower with yellow stamen heart, small green shoots on left and right, growing on a square warm peach stone flowerbed with moss/grass top and small daisies. Match reference isometric projection, symmetric diamond-like square stone base, identical base corners, height, block depth and center root; base must occupy x 6%-94%, y 38%-90% of square transparent canvas; main flower centered at x50% y30%. Keep outline and proportions faithful. Soft warm upper-left light, muted sage foliage and subtle stone brick grain. No thick outlines, no white cutout fringes, no floating sparkles, no extra scene or new platform, no characters/text. True alpha background including spaces between shoots; smooth subpixel anti-aliased edges without pale halo. One isolated whole sprite with same square canvas composition and bottom base anchor as reference.

## flower（未完成花蕾态）

编辑目标：本批新生成的 bloom 母图。辅助参考：`godot/assets/images/production/flower.png`。

Image 1 (new pink flowerbed) is the EDIT TARGET. Image 2 (old bud flowerbed) is only a reference for the closed green bud shape. In image 1 change ONLY the central open pink flower above its root into a closed upright green lotus bud, like image 2. Preserve every stone block, square base outline, brick seams, base perspective, moss, daisies, side stems, base feet, all transparent margins and their positions EXACTLY unchanged from image 1. Keep the two side stems and all small leaves/daisies unchanged. Central closed green bud should occupy the same root position and fit the old bud's relative height/width, with pointed layered sage green sepals and warm upper left lighting. No pink open petals remain. Keep the high quality smooth painted style and antialiased alpha edge. True transparent background. No new objects, words, sparkles or ground/shadow. This is the unfinished state of the EXACT SAME flowerbed, so the stone base must stay pixel-aligned with image 1.

