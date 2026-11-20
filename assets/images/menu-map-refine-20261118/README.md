# 选关地图坐姿角色

2026-11-18，使用内置 `image_gen`，透明背景；非 CLI/API fallback。成品 `map-sitting.png` 为1280×1280 RGBA，原透明边缘保留，未做阈值抠图。同步消费副本在 `godot/assets/images/menu-map-refine-20261118/map-sitting.png`。

身份参考：`godot/assets/images/full-asset-redraw-20261116/actor-idle-front.png`、`godot/assets/images/cover-identity-20261118/attention-0.png`。角色用于已通关且选中的关卡节点，花瓣、石坑和发光虫分别由现有花朵资源及Godot原生绘制承载。坐姿臀点为完整画布的(.49,.75)，对应花瓣座点；没有增加可行走支撑。

生成原件：`C:/Users/liuli/.codex/generated_images/01a1e357-7aba-7553-a912-f4cb92c970e5/exec-51cc3416-4745-46a2-b601-1065c01daae3.png`。项目引用只使用仓库副本。

最终完整提示词：

```text
Use case: identity-preserve. Asset type: one transparent game character sprite for a small illustrated level map. Input 1 is the exact front idle character identity, input 2 is the same identity in quarter view. Redraw ONLY that exact mushroom girl in a seated pose, three-quarter facing gently right, looking curiously toward a tiny firefly that will be added by game code. She is perched naturally as if sitting on a broad flower petal: hips sitting level, torso upright, knees bent, both little brown boots dangling down together, one hand resting near the seat and the other loosely extended, calm closed-mouth smile. Preserve the same face, brown bob and bangs, huge red mushroom cap with cream spots, cream petal dress, sage green shoulder cape, red berry clasp, brown boots, same head/body proportions and painterly soft storybook rendering. No actual flower, no base, no ground, no bugs, no background, no text, no circles, no floor shadow. Entire hat, hands and boots fully inside image with generous transparent margins, one character only. This is a new sitting posture of the existing character, not a different design or baby. Genuine transparent alpha, clean soft antialiased boundary, polished game sprite.
```

实际GPU与浏览器验收见 `docs/119-首页入口与插画选关布局修复.md`。
