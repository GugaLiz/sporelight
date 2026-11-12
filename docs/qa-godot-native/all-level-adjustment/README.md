# 全关卡调整验收证据

对应 [调整计划](../../58-全关卡分阶段调整与验收计划.md)、[实际改动与验收说明](../../59-全关卡表现调整与自主验收.md)。

## 候选与最终版本

- 改前：`b2786fabf6dd9982a0af42d776c6e8494be48e45c55e39a4ba1fda6de171f802`。`baseline-gpu/` 保存15关×两尺寸×四状态的120张截图。
- 第一候选：`c19706e29bc4ca4e18395b1594db4f2353f75556015615515b7abd069cd9417e`。`candidate-gpu/` 同样120张；`candidate-motion/` 保留末关中段提前出光的真实问题证据。`candidate-headless/` 的23套检查均通过，但期间继续修源使stable=false，因此不作为冻结版验收。
- 完整矩阵版本：`6f83b6936f427a5a41d90faf4713528a3b98ed15e4340d6632402b3c14512522`。`final-headless/`23套143436项通过、stable=true；`final-reference/`12组6820项通过；`final-gpu/`120个状态通过；`final-motion/`与`final-lift-motion/`覆盖末关转光庭和2-1升降的两尺寸中段。
- 样式版本：`eaf75d3b05341720f3cac3ce1bfe7cf2a0c1642db18a8abc2d9925393cdec4a4`。相对完整矩阵版本仅3行日/月柱文字描边与颜色，见 [精确差异](final-label-delta.json)。`final-label-headless/`4套96533项通过且stable=true。`final-style-gpu/`补验3-2两尺寸8态。桌面14条路线及首关通过；触屏11/14通过，保留3-1、cloud-2/3菜单入口失败证据。
- 最终交互版本：`0e920007a200c6bc248c7eec777932b8edbfb985dd831984bcbecd12748889f6`。相对样式版仅`native_interaction.gd`改动，见 [交互差异证明](final-interaction-delta.json)。`final-interaction-headless/`8套945项通过且stable=true（两个HUD入口重复执行同套186项）。只修附近操作的菜单可达性，不改领域规则、物理、移动或渲染；原矩阵证据按实际构建分别保留。

## 验证职责

无头测试验证真实网格/碰撞、角色运动、事务、状态与恢复；GPU状态采样从隔离存档恢复关键状态后截图，不冒充连续通关。浏览器真实输入另跑鼠标/键盘与模拟触屏。两类证据分别记录，人工评审再判断接地、材质、遮挡和状态表达。

[protected-contracts.json](protected-contracts.json) 核对核心规则、首关参数与素材保护范围。
[presentation-review.md](presentation-review.md) 是地形渲染agent的独立代码及画面复审；机关专项另有独立复审记录。

截图及联系图按仓库规则留在本地，不随默认Git提交；检查JSON、日志与脚本可追溯。最终预览由本地 `level-adjustment-accepted` 构建提供，不代表已发布或Windows打包。

## 最终结果

本轮验收通过，结构化记录见[final-summary.json](final-summary.json)，独立输入评审见[browser-review.md](browser-review.md)。最终运行源与Web构建均为`0e920007a200c6bc248c7eec777932b8edbfb985dd831984bcbecd12748889f6`，本地[正式预览](http://localhost:4222/)使用`level-adjustment-accepted`。

| 范围 | 结果与证据 |
| --- | --- |
| 全关实体与规则 | 矩阵版23套143436项、15条真实角色路线通过；另64个非首关主线参考案例及云庭规则6820项通过 |
| 渲染 | 矩阵版15关×两尺寸×四态共120张GPU图通过；转光庭/升降两尺寸中段及样式版3-2补图通过 |
| 桌面操作 | 样式版14关完整路线通过；最终交互版首关专门流程通过 |
| 最终14关横屏 | [accepted-browser-touch](accepted-browser-touch/checks.json)：14/14通过，466步、516次触屏点击，无方向键回退和浏览器错误 |
| 最终首关横屏 | [accepted-first-garden-touch-safe-target](accepted-first-garden-touch-safe-target/checks.json)：主线与可选探索、回收/撤销和重载通过；3次真实方向键路径回退，无浏览器错误 |
| 交互代码回归 | 8套945项执行断言通过；单文件差异证明、保护清单及独立复查通过 |

先前触屏失败保留；已由最终菜单修复和测试热区预检分别解决。14关触屏操作未用方向键回退，不等于真机认证；首关属于触屏/方向键混合验证，菜单显露工具可使用滚动辅助。未穷尽全部设备、全部操作序列或复杂终态性能。
