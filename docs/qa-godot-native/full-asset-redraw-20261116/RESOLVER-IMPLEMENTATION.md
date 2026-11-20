# 原图身份共用解析接入

2026-11-16。本批只接通实际资源消费；未完成的重绘映射保持原图fallback，不宣称所有素材已经重绘。

## 配置与优先级

`godot/content/bitmap-redraw.json`：

```json
{"schema_version":1,"source_overrides":{"res://assets/images/旧图.png":"res://assets/images/新版图.png"}}
```

初始为空。`ElementAssets` 将原图路径视为资源身份：显式 `element-theme.json` 同源覆盖 → 默认 `bitmap-redraw.json` → 原图。`resource_path(alias)`、`texture(alias)` 和 `texture_for_source(original_path)` 采用同一结果。多个alias引用同一张原图时保持同一新图（如spore/icon-spore），主题提出冲突替换会整批拒绝。

source map只接受存在的项目图片路径与Texture2D，同画布、规范路径，事务任一项不合法则全部不改；不放开尺寸校验，不循环追随目标映射。`reset_theme()`只清显式主题，保留配置的基础重绘；`reset_bitmap_redraw()`供隔离测试／开发恢复基础原图。资源与revision缓存随映射变化失效。

## 已接通的消费

- `menu_cover.gd`：logo与首页主按钮。
- `menu_vignette.gd`：首页背景、整套人物帧、伙伴帽面球、orb与firefly。
- `garden_hud.gd`：图鉴、纸纹、装饰等共用 `_texture`，收集计数使用动态共用spore。
- `game_hud_skin.gd`：面板装饰、主按钮、spore计数；按钮样式缓存包含资源revision。
- `chapter_map.gd`：地标5状态、地图人物与插画／卡片。
- `chapter_map_detail_art.gd`：细节卡全部场景道具原图。
- 游戏内actor clip别名本来走 `ElementAssets`，因此新的bitmap源映射也覆盖角色帧；不更改fps、pose、collision或存档。

`godot/ui/` 中未留下直接图片 `load/preload`，它们全部经同一解析入口。既有程序化控件、伙伴绘制和独立美术状态保持。

## Web加载页

加载页发生在PCK下载之前，无法调用GDScript。`sync-loading-assets.py` 因此读取同一source map和theme资源关系，以相同优先级找实际源图；用原来的缩图导出产生loader/logo.png等公开文件。新logo仅需生成一次，首页与加载页共用其来源。新目标也必须同原画布，并限制在Godot图片目录内。

本次只修改导出解析，不执行导出。`--check` 遇到现有loader/orb.png字节差异，已用HEAD原脚本独立复现，同样失败，日志在 `resolver-headless/loader-baseline-check.log`；待最终资源生成后统一重新导出并核对，不修改oracle掩盖差异。

## 验证

[5套597项](resolver-headless/checks.json)通过：resolver27、HUD182、原资源177、缓存77、主题集成134。新增27项包含原路径fallback、alias/direct缓存统一、同源spore一致、覆盖优先级、事务拒绝与真实HUD/map/detail纹理绑定。原资源与集成fixture显式先清默认bitmap map，以保持其原资源库比较语义；实际交付配置另外验证。

这些是headless资源／UI绑定检查，不代表GPU美术、浏览器点击或最终全部映射已经验收。生产源码已通知主代理稳定，后续只由素材管线补映射和新图。
