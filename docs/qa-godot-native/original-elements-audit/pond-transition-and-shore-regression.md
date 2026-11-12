# 池塘返岸、连续岸线与全景边界回归

日期：2026-11-11。此次未修改 `native_garden_stage.gd`，未启动 GPU。舞台和其他模块仍有并行改动，以下为直接执行对应测试得到的有界结果，最终整包源码绑定由集成者统一完成。

## 2-1 中水位返回低水位

`native_original_dressing_test.gd` 新增真实合法阀门动作的前后快照（来自 authored/2-1 fixture），验证回撤至低水位的 0、.25、.5、.75、.999、1 六个时刻：

- 过渡中 `_tile_map` 已有未来 `f:-4:4`，但 `_surfaces` 尚无真实岸面；原索引 7 的 fern 必须不创建，并记录在 `original_deferred_scenery`。
- 落稳后岸面实际回归，原 fern 同步恢复，底脚贴合该真实面。
- 中断过渡后 `clear_motion(false)` 同样恢复完整岸面与 fern。

集成者此前补充的“逻辑格和实体 surface 必须同时存在”判定，以及 props key 包含 terrain signature 的实现已通过该回归；此次没有再修改植被放置实现。最终运行没有 missing-support `ERROR` 或 `SCRIPT ERROR`。

## C08：岸线密集锯齿竖条

原 `_ribbon` 为每条短边分别构造矩形，转角两侧未共享端点，会出现缝隙和透明叠加。现改为闭合索引条带，每个原岸线顶点只有一对边缘顶点，相邻片段与末尾→首段使用同一索引。连接采用 miter，长度限制在半宽的两倍，防止锐角尖刺。保留原 **17 px 苔岸、10 px 浅岸、1.5 px 水线**，不删任何岸线层。

新增 `original_pond_ribbon.gdshader`，仅沿条带横向 UV 做轻微边缘羽化，原色值/透明度与草纹理保留。几何测试检查每个 join 的共享边使用次数为 2、所有三角形面积非零、闭合接缝、中心仍落在原岸线上、miter 长度上限及边使用次数不超过 2。此处只声明接缝结构已修正；C08 的最终画面状态需集成者重新查看 GPU 原图。

## 全景需纳入外围生态

当前舞台 `_calculate_overview_bounds` 只包含地块/地基，池岸、后岸灌木和青蛙可能在地块边界外。新接口 `OriginalPondEnvironment.presentation_bounds() -> Rect2` 返回**固定 native 等角相机 right/up 轴的世界投影矩形**，已含有机水面、岸线、草团、全部环境 Sprite 的画布边缘与青蛙轻微浮动裕量。

mesh AABB 与 billboard 矩形只在环境 refresh 重建时遍历一次；接口调用仅返回缓存矩形并叠加当前环境根的水高平移，不扫描节点或 mesh 顶点。

接入建议（仅由集成者改 stage）：在 `_calculate_overview_bounds` 最后算 middle 前，若 `_original_pond.visible` 且矩形有面积，执行 `low=low.min(rect.position)`、`high=high.max(rect.end)`。原普通镜头保持不变。首次进入 pond 关必须在 `_original_pond.refresh(self)` 后至少再计算一次 overview bounds，否则环境初次创建前调用得到的是空矩形；后续几何变化可随现有全景计算读取缓存。

## 定向结果

| 测试 | 检查数 | 最终结果 |
| --- | ---: | --- |
| native_original_dressing | 1,718（24 状态） | 通过 |
| native_original_pond | 28,534 | 通过 |
| native_mechanism_props | 267 | 通过 |
| native_motion_cache | 9,087 | 通过 |
| native_prop_alignment | 3,108（34 个动作） | 通过 |

合计 **42,714 项**，最终日志均未检出运行 `ERROR` / `SCRIPT ERROR`，详见 [pond-transition-regression](pond-transition-regression/checks-direct.json)。`native_mechanism_props` 原测试在落稳时继续读取已被 destination props 替换的旧 HeightPointer，导致四个端点断言失败；测试现每步重新取得当前 `_mark` 指针，过渡中仍要求原 node/mesh identity 不变，端点改验当前节点在树内且未待删除，原升降高度和角色根不动断言全部保留。这是对象生命周期取证修正，不是放宽位置容差。

这些 CPU 测试不证明当前 GPU 画面、人体姿态或正式包性能已通过。
