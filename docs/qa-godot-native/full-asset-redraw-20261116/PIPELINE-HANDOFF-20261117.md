# 全量重绘候选包装交接

2026-11-17。本报告只覆盖母图机械包装、来源核对和像素原图审阅；没有激活运行主题、导入Godot或切换服务。后续运行时验收由父任务统一执行。

## 冻结结果

- `assets/images/full-asset-redraw-20261116/config.json` 配置78个去重输出：45项非角色、33项角色。角色图集裁片与注册由角色代理维护，本批没有覆盖其锁定字段。
- `godot/assets/images/full-asset-redraw-20261116/` 78张同逻辑画布PNG及mipmap导入参数已导出。
- `manifest.json`、`theme.proposed.json`、`bitmap-redraw.proposed.json` 已生成；此前7项运行主题覆盖保留。**候选未激活**。
- 全78项 `--check` 通过：原图／母图／输出SHA、连续alpha、原逻辑尺寸、mipmap参数、alias/direct-source覆盖、既有覆盖和受保护生产源哈希。
- 具体计数与逐项高度、脚点误差见 [pipeline-handoff-20261117.json](pipeline-handoff-20261117.json)。图像统计不代替GPU、硬底座支撑或动画验收。

## 实际看图发现与处理

1. 新塔的洞口与旧切图mask略有差异，原mask会切拱圈石边并漏掉右洞左缘的青绿膜。已按新注册图重新登记两洞抗锯齿多边形，frame/seal使用同一塔母图和变换。当前暖／深底可见门洞清空，柱基和石圈保留；真实开闭过程仍须GPU复核。
2. 原`bug`生成稿含平直的灰白雾区，已明确否决。候选改用`bug-v2`，看图仅保留虫体、触角和半透明翅，未见矩形光雾。
3. 地图开花、花蕾、洞窟、休眠、池塘五态从同一新母图编辑，全部使用同一union crop和等比变换。休眠态前石环没有因短bbox被单独放大；alpha8高度86%是植株形态不同，不能等同基座缩小。
4. 图鉴`gallery-arch`与上轮`arch`同造型，复用上一轮已注册PNG作1:1包装；`gallery-lily`与莲池同造型，共用本轮`lotus-pool`母图，分别适配逻辑画布。
5. `lotus-pool`按高度注册会超画布，等比contain后可见高约99%。UI绿按钮contain后约94.2%，纸面板约99.4%；这些候选保持长宽比，没有为了填满画布硬拉。
6. `vine`原图上方含大量白色抠图残片。新图alpha8高度只有旧bbox的约68%，但花盆／嫩芽主体与脚点在原图对照中接近；不能按污染bbox重新放大。
7. 已查看UI原图／新图、暖底／深底五页：中文Logo“微光苔原”和英文“Sporelight”正确；纸框、按钮、叶图标、图鉴蘑菇／藤桥、地图苔藓／花坛／阶梯轮廓更连续，未发现剩余矩形背景或破字。

审阅图片：`tower-review/`、`nonactor-review/`、`ui-review/`、`final-state-review/`。`tower-review`保留旧mask中间稿，不作为最终门洞依据；最终门洞在`nonactor-review/contact-01.png`。

## 复现与下一步

```powershell
node tools/godot-migration/prepare-full-nonactor-registration.mjs
node tools/godot-migration/export-full-asset-redraw.mjs --config=assets/images/full-asset-redraw-20261116/config.json
node tools/godot-migration/export-full-asset-redraw.mjs --config=assets/images/full-asset-redraw-20261116/config.json --check
```

非角色准备脚本只修改非actor配置，保留角色代理的锁定registration/master_rect。父任务之后统一`--apply-theme`、loader机械同步、Godot import、GPU和release导出；本批不提前重写保护基线或更新4222。
