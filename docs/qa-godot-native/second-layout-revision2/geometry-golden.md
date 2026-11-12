# 1-2 布局 revision 2：几何基线审查

本次仅适配删除固定 `f:3:1`、`f:4:2` 后的几何验收，不修改 runtime、关卡内容、世界规则或 1-1 基线。原七个 socket、四节预算与 `second_garden_profile.gd` 保持原定义。

## 两份基线的责任

- `godot/tests/fixtures/native-surface-support-baseline.json`：历史原件，SHA-256 固定为 `86116d40e268ef77d54289d17a0bde31bf19110d688234b8e6310656f297dce1`。1-1 继续逐 mesh / collision 与它比较；1-2 剩余旧格也必须继续比较它。
- `godot/tests/fixtures/native-surface-second-layout-revision2.json`：只包含 1-2 revision 2。上路及下路各 0–4 节，初始空路共用，合计九种拓扑。包含完整 geometry hash 与逐状态旧格差异审查记录。

测试不因新基线存在而跳过旧格对照。`second_layout_revision2_geometry_guard.gd` 对九种拓扑共比较 117 个旧剩余 surface 实例：97 个完全一致，20 个仅发生下面已审查的边面变化。旧基线没有下路状态，因此下路固定格对照旧初始状态；下路新增根台接受同样薄板约束，并列入新基线。

## 允许且实际观察到的变化

方向编号沿用 stage：0 北、1 东、2 南、3 西。

| 保留格 | 删除邻居导致新增的边 | 侧面 / 碰撞新增三角 | 沿口新增三角 | 顶面、阶梯踏面、立面 |
| --- | --- | --- | --- | --- |
| `f:4:1` | 西侧 `f:3:1`、南侧 `f:4:2` | 各 26，合计 52 | 52 | 全部与旧 hash 一致 |
| `f:5:2` | 西侧 `f:4:2` | 26 | 26 | 全部与旧 hash 一致 |
| `g:root:3:0`（上路第 3/4 节状态） | 南侧 `f:3:1` | 26 | 0；根台侧边没有沿口 | 全部与旧 hash 一致 |

审查不只接受 hash 差异：测试在独立参考 Surface 上补回两个旧邻居的暴露面条件，确认该参考 Surface 完整 hash 等于历史原件，再逐三角验证当前 Surface 保留全部旧三角。新增侧面/碰撞只能位于对应边的局部坐标 `±0.5`，新增沿口只能位于 `±0.502`；不允许其他位置变化。

## 新末节及下路根台

新 `g:root:3:1` 是第四节接岸根台，分别覆盖上下两种完整路线。测试验证：

- 使用原 authored terrace profile，`thin_plate=true`。
- 所有结构顶点位于 `[-0.20, 0]`，底面闭合，无延伸至地基的柱体。
- 3×3 支撑点采样全部为高度 0。
- 所有可见结构三角与实际碰撞三角集合一致。
- 下路新增的 `g:root:1:2`、`g:root:2:2`、`g:root:3:2` 同样通过上述约束。

这些断言只证明几何保持和薄板合同。0–3 节无法跨岸、第四节实际可通行由主 agent 的真实移动专项另验，不能由 geometry golden 代替。

## 明确捕获与复核流程

在仓库根目录执行：

```powershell
& "$env:USERPROFILE/.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script res://tests/native_surface_alignment_test.gd -- --capture-second-layout-revision2
```

该命令只构造 1-2 九种状态，执行旧格/边面/薄板对照，通过 11,432 项后输出独立 `.candidate.json`。它不会访问写入旧 baseline，也不会捕获 1-1。旧 `--capture-baseline` 开关已明确拒绝执行，防止整批覆盖。

查看候选文件的 `legacyComparison`，确认所有 changed fields、方向、三角数与上表一致，`levelId` 为 `1-2`、`layoutRevision` 为 2、states 数为 9，才晋升文件：

```powershell
Copy-Item -LiteralPath 'godot/tests/fixtures/native-surface-second-layout-revision2.candidate.json' -Destination 'godot/tests/fixtures/native-surface-second-layout-revision2.json'
Remove-Item -LiteralPath 'godot/tests/fixtures/native-surface-second-layout-revision2.candidate.json'
& "$env:USERPROFILE/.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe" --headless --path godot --script res://tests/native_surface_alignment_test.gd
```

正常验收同时校验旧文件 SHA、1-1 原 hash、新基线九种拓扑、全部旧格对照、新增边面三角、原 profile 文件 SHA，以及其余关卡既有真实阶梯与接缝合同。本轮未运行 GPU。

本轮最终结果：捕获候选 **11,432 / 11,432** 通过；晋升后的完整 `native-surface-alignment` **85,871 / 85,871** 通过，覆盖 72 种拓扑、47 处接缝、4,984 个真实阶梯踏面三角。候选临时文件已删除，历史原件 SHA 未变化。
