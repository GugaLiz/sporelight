# 当前 UI 与角色素材审计

2026-11-16。本次只审计当前 Godot 原生入口的实际引用和生成来源，没有修改运行时资源或声称画面已修复。机器清单见 [ui-actor-inventory.json](ui-actor-inventory.json)。

## 统计口径

从 `godot/ui/*.gd` 的直接资源路径、动态图像键、图鉴数据与 `actor-elements.json` 的实际 clip 帧数组展开。当前列出113个路径、91种不同字节内容，其中86条使用旧抠图或抠图派生资源。3条 UI 消费可直接重绑上轮已有重绘（`bloom`、`gold-lotus`、`icon-spore`）；loader logo 为原 logo 的派生副本，重绘源后机械导出即可。其余82条路径按SHA去重为61种母图候选；它们含与场景审计重复的道具，最终总数必须按路径／SHA合并，不相加。

## 角色与伙伴

- 游戏内主角53张PNG来自旧抠图或抠图派生，去重32种画面。`character-refined` 的manifest明确写着裁切／背景提取／合成，并不是AI重绘；`menu-walk` 是切分旧侧身手臂和腿再旋转合成，虽然文件名含menu，实际用于原生游戏侧走。
- clip为正面走（7种独立帧、8个播放位置）、背面走（12播放帧，存在对称和idle重复）、侧走（12帧、左右共用翻转）、12帧跳跃、5帧播种、interact／salute／三方向idle。重复字节组记录在JSON中；可以复用新画面回填相同旧帧，不能为了“全部重绘”凭空改变动作节奏。
- `buddy-ball.png` 另有1种旧checker抠图；用于双方滚动、伙伴程序化帽面、首页伙伴。正常伙伴身体、眼睛、叶与脚由代码绘制，不需要把整位伙伴重新变成一张静态卡片。
- 首页角色14帧及orb/firefly两张已有完整imagegen重绘，导入只做保留alpha的图集包装。它们不是本次旧抠图重绘候选。
- 53张主角文件必须成组保护各自脚点、姿态覆写、行走相位与fps，不能只替换idle而让走路切回旧边缘。地图选中标记直接使用 `character-refined/idle-front.png`，也要同步新图。

## 当前仍走旧图的 UI

- 首页：`menu-logo.png`、`menu-paper.png`。
- HUD：`panel-paper.png`、`button-green.png`、`icon-spore.png`。面板装饰以源像素矩形裁切，不能只画一个新面板却改变装饰位置。
- 地图：5种植物地标状态、terrain-steps、production light/moss，详情仍直接加载原scene道具图，包含金白莲。
- 图鉴：bloom、light、gallery vine/mushroom、bug、lily-open、production arch、cave-bloom。
- 地图详情：多种scene道具直接路径复用，其中icon-leaf仍有明显厚白纸边。
- Web loading shell：loader/logo.png来自旧menu-logo，hero/orb来自已有重绘，bg是完整插画。

以上大多数 `load/preload` 直接使用文件路径，绕过 `ElementAssets` 及 `element-theme.json`。只改世界alias会遗漏这些消费；新资源需统一入口或显式更新全部直接引用。既有7张scene重绘目前也没有自动作用到这些旧UI路径。

## 不误算的项目

完整不透明首页／章节插画、作为填充的矩形纸张纹理、程序化控件／渐变／伙伴／叶包都不是背景抠出的独立图素。只在visual manifest里登记却没有当前消费的旧portrait、未使用icon、旧book-scene/card-paper/reading-companion不会因目录存在而全部算作本次替换。

可视复核联系表：`ui-actor-unique.png`、`ui-cutout-unique.png`，均为只读原图的审阅缩略图，没有修改原素材。

```powershell
node tools/godot-migration/audit-ui-actor-assets.mjs --contact-sheets
```

本审计是静态消费链与来源／alpha检查，尚未声称所有图在某一次GPU画面同时可见，也不代替新资源接入后的真实渲染与交互验收。
