# 全量素材重绘的机械导出

`export-full-asset-redraw.mjs` 只包装已由 ImageGen 生成的透明母图，不生成新视觉、不抠背景、不硬切alpha，也不修改玩法。配置示例为 `full-asset-redraw.config.example.json`，示例不会自行运行或接入游戏。

```powershell
node tools/godot-migration/export-full-asset-redraw.mjs --config=assets/images/full-asset-redraw-20261116/config.json
node tools/godot-migration/export-full-asset-redraw.mjs --config=assets/images/full-asset-redraw-20261116/config.json --check
# 素材与proposed主题可检查后，显式激活；合并保留此前7项主题及其他未修改槽。
node tools/godot-migration/export-full-asset-redraw.mjs --config=assets/images/full-asset-redraw-20261116/config.json --apply-theme
node tools/godot-migration/export-full-asset-redraw.mjs --config=assets/images/full-asset-redraw-20261116/config.json --check --expect-applied
```

默认只写新的同逻辑画布PNG、`.import`、来源/测量manifest、`theme.proposed.json`及`bitmap-redraw.proposed.json`。只有 `--apply-theme` 写运行主题和bitmap源映射；两份配置先暂存，写入失败会回滚已替换文件，不主动保留半套映射。不会导入、构建、启动游戏或更新服务。`--only=id1,id2` 分批处理，之前已导出项保留。母图必须先复制到仓库，原文件与母图不得作为输出被覆盖。

## 显式注册

- `contain`（默认）：按原图alpha8矩形中可容纳的单一缩放比例，以底部中心对齐；`anchor:[0.5,1]` 可改为相对锚点，`crop` / `target` 是显式像素矩形。它保留长宽比，不保证新花叶/基座已与原图一致。
- `height`：保持原alpha8可见高度和底部根点，单一缩放；新形状变宽而超出逻辑画布会报错，不自动压扁或缩小整件物体。
- `anchors`：`points:[{"master":[x,y],"logical":[x,y]}, ...]` 至少两点，计算不含旋转的等比缩放/平移；按最终整数采样检查点误差，默认不得超过1逻辑像素，可显式设 `max_point_error`。石门、盆沿等须用完整硬脚，不用叶冠或光晕。
- `scale`：明确 `scale`、`master_anchor:[x,y]`、`logical_anchor:[x,y]`；用于已测定主体或角色脚点，不按光晕bbox放大。
- `shared`：`{"mode":"shared","entry":"bloom"}`。引用配置中较早的状态，共用同一采样变换；母图和逻辑画布都必须一致。花坛两态/同一角色多帧应使用已确认的统一基座/脚锚，不能每帧按bbox重新缩放而漂移。

两柱/基座不能用单一等比变换对齐时，先审查重绘构图或更新明确测量定义并独立验收。工具会报点误差，不通过横纵拉伸把它隐藏。母图可见alpha8不得被裁掉；登记后超出画布会失败。

连贯动作母图可指定 `master_rect:[left,top,width,height]`，或 `cell:{column:0,row:0,width:256,height:256,origin:[0,0],gap:[0,0]}`。只做已绘制帧的矩形拆分，不能用旧肢体/光流补帧。注册坐标均相对于选中cell，manifest保留整张母图SHA和明确cell像素矩形。动画多帧使用共同尺度与脚锚时，首帧可按 `scale` 明确全cell `crop:[0,0,w,h]`，后续 `shared` 引用它，避免每帧alpha bbox不同导致大小/脚点抖动。

已知多层图素可以登记显式 `alpha_mask:{mode:"inside"或"outside",polygons:[[[x,y],...]],antialias_scale:4}`，在同一新母图和共用注册变换上生成抗锯齿遮罩层。例如花门tower是完整新画、frame扣去原门洞、seal仅保留门洞。遮罩坐标是已审查的原逻辑像素，不能自动追踪旧锯齿或在每帧阈值抠图；洞口与实体门柱仍需真实GPU复核。

## 资源与保护

`aliases` 必须在当前ElementAssets资源库中存在，且原图字节和逻辑画布与每个槽一致。同一源图供多个世界/UI别名时，可把多个别名放进一个entry。`source_paths:["res://assets/images/旧图.png"]` 登记直接路径消费者的替换，写入候选bitmap源映射；它们也必须与entry原图同字节/画布。两个裁剪不同的原图可以共用母图，但应有各自的原图、注册和逻辑输出。

UI的直接 `load/preload` 需先接入 `ElementAssets.texture_for_source()`，仅有JSON映射不会改变尚未接入的消费者。特殊直接绑定亦可登记 `bindings:[{"path":"godot/ui/example.gd"}]`；`--expect-applied` 检查源码包含输出资源路径（或显式 `contains`），不替换代码文本。源映射目标默认为 `godot/content/bitmap-redraw.json`，可用配置 `source_map_path` / `proposed_source_map` 修改，schema为 `{schema_version:1,source_overrides:{旧res路径:新res路径}}`。

首次导出保存生产GDScript/Shader/场景/内容定义哈希，后续导出及检查拒绝悄然更改规则、几何、角色、UI等源文件；`element-theme.json`、`bitmap-redraw.json` 和新PNG/导入缓存除外。应在必要的消费者接入编辑完成后建立这份基线。输出SHA、源/母图SHA、alpha8/128、连续alpha、原画布、mipmap参数和旧主题/源映射覆盖均单独验证。它们不代替真实GPU画面、完整硬底座反投影、运动生命周期或动画步态验证。

Actor SpriteFrames 可替换其资源别名，但必须保留每帧画布、站立/滚动像素比例、姿态脚锚、裁片和clip相位。程序化伙伴没有可抠图PNG；不能把它误记成已被新图片替换。图集/裁剪使用原图像素坐标时，母图输出必须保留对应区域；把不同大小的高分辨母图直接装入主题会被拒绝。

## 生成记录与看图

`sync-full-redraw-config.mjs` 读取 `generated-jobs.json`，同步母图路径、generation id和提示词记录，不生成/导出/激活图片。动画任务可有 `outputs:[{id:"actor-walk-1",master_rect:[...],registration:{...}},...]`；同一旧字节组的多个alias必须落到同一明确帧，冲突会报错。显式registration会锁定以保护手工脚锚。

`review-full-redraw-contact.mjs` 按manifest输出原图/新图、暖底/深底4列联系表，使用逻辑PNG原始像素，不缩放图素。默认每页6项，可 `--rows=2` 或 `--only=id1,id2`；每项注明实际alpha8高度比与记录的脚点误差。实际GPU比例、完整硬底座和动画仍须另外看图。
