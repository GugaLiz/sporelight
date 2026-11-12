# 普通行走 CPU 热路径审计（2026-11-10）

## 已实施范围

`native_movement.gd` 在一次 physics tick 的只读阶段共享同一份 `world.tiles()`。位置查询、合法邻接、伙伴距离判断和运行时姿态捕获使用核心查询接口已有的可选 tiles 参数。`session.revision` 或 world 对象变化会立即重建，tick 结束释放。没有跨帧缓存，没有缓存 `together()` 的布尔结果，没有修改核心规则、物理步进、速度、碰撞、跟随目标、坐标转换、存档内容或提交时机。

`native_garden_stage.gd` 仅在 `growth_choice_layout()` 对没有 roots 的关卡提前返回；这些关卡原本也没有可绘制根路径按钮，避免每次 redraw 为空结果执行全套 commands 查询。材质、shader 和 actor 方法属于其他并行子任务，不包含在本项变更中。

## 分层诊断结果

以下是诊断过程数据。期间存在浏览器验收、其他测试及构建工作，不属于安静环境性能承诺；调用次数和正确性可重复检验。严格隔离了 physics_frame 等待期间的渲染调用，避免将整帧工作误记到 motor。

| 指标 | 原查询方式 | tick 内共享 tiles |
| --- | ---: | ---: |
| 1-3 空闲 60 tick 的 tiles 次数 | 600 | 60 |
| 3-4 空闲 60 tick 的 tiles 次数 | 360 | 60 |
| 1-3 单程 3 格 / 90 tick 的 tiles 次数 | 1089–1098 | 194–196 |
| 3-4 单程 3 格 / 90 tick 的 tiles 次数 | 680–683 | 123 |
| 1-3 普通无跨格 tick 中位耗时 | 4.3–5.3 ms | 1.8–2.4 ms |
| 3-4 普通无跨格 tick 中位耗时 | 4.8–5.8 ms | 1.5–1.7 ms |

测试真实运行 CharacterBody3D，两个关卡各三次往返；结果核对实际支持格顺序、伙伴跟随、存档可还原与物理落脚。可用同源 `-- --baseline` 启用 UncachedMovement 对照：仅让可选 tiles 参数为空，以执行原来的每查询重建行为。

记录：[原始 motor 基线](baseline-tick-scoped.log)、[首次优化结果](optimized-tick-scoped.log)。`baseline.log` 是最早探索性记录，计数包含等待期间渲染，不用于上表。

## 完整应用链路发现

新的 `native_application_walk_performance_test.gd` 使用真实 main、motor、HUD、session 和 repository。声音仅替换为空实现。比较只有当前关卡和 15 个已开始关卡的存档；file 组在独立临时路径真实执行 JSON 序列化、临时文件写入、备份、读回及完整校验，不读取玩家存档。memory 组仍执行 `commit_run/stage_run` 归一化及一次完整 store 校验，仅用于区分问题，不能代替 file 组。

八组均通过实际行走终点及持久化一致性检查（24 项）。[完整原始记录](application-chain.log) 中各项时间为包含子调用的时间，不能相加视为互斥占比。

| 关卡 / 实际文件存档 | `_save` 中位 | 跨格 tick 中位 | `_sync_hud` 中位 |
| --- | ---: | ---: | ---: |
| 1-3 / 单关 | 23.175 ms | 33.117 ms | 4.378 ms |
| 1-3 / 15 关 | 88.717 ms | 105.356 ms | 3.118 ms |
| 3-4 / 单关 | 24.817 ms | 53.040 ms | 16.657 ms |
| 3-4 / 15 关 | 76.935 ms | 100.490 ms | 17.030 ms |

1-3 的 15 关文件组在 100 tick 中执行 8 次保存、39 次全库验证、593 次 snapshot 验证；保存累计 676 ms，占该组 tick CPU 总计 958 ms 的约 71%。3-4 对应为 5 次保存、24 次全库验证、365 次 snapshot 验证；保存 378/616 ms，约 61%。这证明只优化 motor 无法解决跨格停顿：完整持久化反复重验所有关卡是另一处主要成本。主任务负责后续 repository 优化，本子任务没有减少保存频率或绕过校验。

## 旧测试坐标修正

`native_movement_test.gd` 曾将 1-1 东岛的目标物理 X 写死为 4，但当前已批准的 `first_garden_profile` 给东岛增加 0.65 的物理间距。未缓存对照同样到达物理约 4.65、逻辑约 4.0，只有该旧断言失败。已将目标坐标改为 `stage.tile_position(world.point_for("f:4:0"))`，保留 0.09 容差；45 项现均通过，2392 个物理采样的最大落脚误差 0.11318。[未缓存诊断](uncached-movement-diagnostic.log)。

## 完整路径回归

[routes/checks.json](routes/checks.json) 为 `passed=true, stable=true`：原生 movement 45 项及完整 authored 路径 1826 项全部通过。15 个关卡（1-1 至 3-4、cloud-1 至 cloud-3）全部由真实身体完成，包含 19208 个物理采样；最大身体与地形间距 0.11891，最大视觉接触误差 0.10833。[逐关记录](routes/native_route_test.log)。

主任务后续 normalizer、actor 与浏览器导出验收应关联各自最终源；不能将本页诊断耗时当作浏览器 GPU 帧率结论。

## 主任务 normalizer 接入复核

主任务随后将 `main._normalize_snapshot` 委托给纯领域 normalization 缓存，保留原来的文件验证链和保存时机。本 Harness 使用继承该生产服务的 CountedNormalizer，只记录 `_normalize_uncached` 实际调用次数，结果如下：

| 实际文件组 | repository snapshot 验证调用（仍完整执行） | 实际领域 normalization |
| --- | ---: | ---: |
| 1-3 / 单关 | 47 | 16 |
| 1-3 / 15 关 | 593 | 30 |
| 3-4 / 单关 | 29 | 8 |
| 3-4 / 15 关 | 365 | 22 |

[normalizer-validation/checks.json](normalizer-validation/checks.json) 在源 `0558eb340009e24be4bafb4ea0266b7ebf6f737bcfa1fa9a6eaae98d4ac5b39a` 上 `passed=true, stable=true`：应用链 24 项、新 motor 性能与查询生命周期 88 项通过。后者同时验证同 tick 提交后的缓存失效、world 替换失效、输入数组不被后续查询修改、tick 外直接域变化不被旧缓存遮蔽，以及实际路径支持格顺序。

这一轮有 `-j4` 引擎编译并行运行，时间数据只作诊断，调用计数是本轮明确验收结论；干净环境性能测量由主任务安排。

## 交互上下文查询范围

`NativeInteraction.context` 为一个非空命令列表创建一次 tiles，然后将其传给 `command_tile` 的可选参数。两个接口原有参数保持兼容，独立调用仍查询当前世界；没有跨调用保留缓存。排序、距离、禁用原因、伙伴位置和主操作规则保持原样。

新 `native_interaction_query_test.gd` 对 15 关的 115 个初始或动作后状态，比较 scope 查询与强制每次 `point_for` 重建 tiles 的完整上下文结果，并验证世界快照与传入 board 未变化。旧实现实测总计 381 次 tiles；scope 实现 105 次（10 个空命令状态零次，105 个非空状态各一次），调用方提供 board 时全部零次。

[interaction-validation/checks.json](interaction-validation/checks.json) 为 `passed=true, stable=true`：新 query 测试 575 项、现有 interaction priority 27 项及 HUD 186 项，共 788 项通过。[修改前计数](interaction-baseline.log)、[等价性与修改后计数](interaction-validation/native_interaction_query_test.log)。`uncachedTiles` 对照会额外包含新 context 的一次 board 构造，因此总降幅采用修改前独立日志的 381，而不是该对照列的数字。

## 15 关逐帧表现补充审计与修复

新增 `native_presentation_cpu_audit_test.gd` 分别同步测量每关 60 次 `_process`、`growth_choice_layout`、水流更新、真实 authored 动作的运动帧和光线对齐策略；3-1 另使用真实 motor 跨格，仅计其回调内的 refresh。初次审计 46 项通过，定位到两处原先遗漏的重复计算，得到授权后修复。

| 关卡 | 60 次 `_process` 的 tiles 次数（前→后） | 修复后 60 次根按钮布局的 tiles 次数 |
| --- | ---: | ---: |
| 1-1 | 0→0 | 60 |
| 1-2 | 0→0 | 60 |
| 1-3 | 0→0 | 0 |
| 1-4 | 0→0 | 0 |
| 2-1 | 0→0 | 0 |
| 2-2 | 0→0 | 0 |
| 2-3 | 0→0 | 0 |
| 2-4 | 0→0 | 0 |
| 3-1 | 0→0 | 0 |
| 3-2 | 0→0 | 0 |
| 3-3 | 0→0 | 60 |
| 3-4 | 120→0 | 60 |
| cloud-1 | 0→0 | 0 |
| cloud-2 | 0→0 | 0 |
| cloud-3 | 0→0 | 0 |

**3-1 探索可见性：** 两次真实跨格刷新分别构造 151、146 份 tiles，却没有重建地形；`visible()` 对各 tile 重复派生整个世界占该刷新绝大部分时间。现在 `visible(tile, world_tiles=[])` 只增加可选只读参数，原可见性条件逐字保留。刷新链及光线裁剪共享当前 `_tiles`；没有缓存可见性布尔结果，独立 hit_test 仍执行原来的 fresh 查询。最终两次刷新都只生成 **1 份 tiles**。并行负载下耗时由 173–237 ms 降到不同复测中的 10–32 ms，时间仅作诊断。

**3-4 水流固定端点：** 原先每帧对同一个固定接收点查询前后世界，造成 2 次 tiles。现在运动使用已有前后快照索引；静止时只有 world 的全部非 runtime 状态与 refresh 时深拷贝状态完全相等，才借用已有 `_tile_map`，否则保留原 point_for 回退。模块公式、圆弧、缓动、滴水、启停与对齐条件不变。`_process`、直接 water 更新、运动帧以及动作完成后 `_process` 的 60 帧计数全部 **120→0**。先前 motion 文档将残余查询归因于光线，现已更正；所有关卡的 RuleRayPresentation 对齐策略本身均为零 tiles 查询。

完整前后分项数据见 [presentation-comparison.json](presentation-comparison.json)，包含微秒数和计数。初次优化 [5 套检查](presentation-optimized/checks.json) 共 **16842 项**通过，其中新增 visibility/water 等价性 **9120 项**：3-1 每个 authored 状态、3-4 每个 authored 动作、五个运动进度、正向/逆向、clear/undo、直接状态变化失效及外部世界回退均覆盖。随后将 hit_test 恢复为严格独立查询，冻结源为 `90f268f20f659639c83adec3eb5b6fea2dc6f5954a8c7d4433f9501ce6e79670`；该源上的新等价性和 15 关审计再次通过。

`presentation-final/checks.json` 中默认 `rule_reference` 在已批准重做的 1-1 首状态遇到历史 JS 夹具差异（16 vs 19 tiles）；没有更改原夹具或放宽比较。与此前验收一致，1-2 至 3-4 另逐关跑完整原始 reference，1-1 用当前真实物理路径验证。

最终冻结源上的 [reference 汇总](presentation-reference/summary.json) 全部通过：11 关、64 cases、1761 commands、5347 checks。随后 [presentation-final-routes/checks.json](presentation-final-routes/checks.json) 为 `passed=true, stable=true`，云关原规则 1473 项和全部 15 关真实物理路线 1826 项通过；19208 个物理采样、最大身体间距 0.11891、最大视觉接触误差 0.10833，与修复前一致。该轮包含最终 hit_test scope 与水端点失效保护，渲染和移动实现随后保持不变。

## 最后代码复核：int64 缓存键边界

只读复核发现：通用 `Repository.json_equivalent` 将数值转成 float 比较，不能直接充当纯归一化缓存的所有键比较。例如 native int64 的 `9007199254740992` 与 `9007199254740993` 转成 float 会合并，但域规则对 turns 做整数 modulo 后分别得到 0 与 1。已按授权仅在 `snapshot_normalizer.gd` 增加独立的递归缓存比较：int/int 精确；安全整数范围内 int/float 保留 JSON roundtrip 命中；超范围混合数值保守 cache miss；bool、字典、数组及缺键/null 保持严格区分。通用 repository、领域规则和保存时机没有改动。

补充正负 `2^53 ±`、int64 最大值及相邻值、嵌套容器、bool、真实大整数旋转归一化的测试。最终源为 `b8980c780eb1a91621bce0775c207b2348a63a10e676f30d2fc8974025532f1f`；[normalizer-int64-final/checks.json](normalizer-int64-final/checks.json) 的三套定向回归为 normalizer 2120 项、save 87 项、cloud save 29 项，共 2236 项。此前全关真实路线与渲染等价性结果保留其明确的 `90f268…` 源记录；最后改动仅修正异常大整数输入的缓存命中条件，不声称那些重测试在新源上重新执行。
