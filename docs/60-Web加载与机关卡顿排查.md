# Web加载与机关卡顿排查

本文件记录上一轮`5411b226`版本；后续动作比例、持续行走与Web模板优化及当前预览见 [62号结果记录](62-动作比例与运行性能优化结果.md)。下文原始指标与未解决项保留为历史，不表示当前4222仍使用旧包。

2026-11-10。用户反馈正式4222入口在100%停留十几秒，进入游戏后仍明显卡顿。本次区分下载、启动编译、游玩逻辑与测试环境帧节奏；不以之前的通关/渲染验收代替性能验收。

## 已确认原因

1. **100%是下载完成。** 普通入口实测下载约0.9秒，随后有约24.7秒同步长任务，主线程无法更新加载画面。首次另一轮启动约41秒。WebGL调用计时确认，约20.46秒花在`getProgramParameter`等待着色器编译，最大单次3.71秒；323次纹理上传合计约35毫秒。未发现资源404、损坏或加载死锁，不能把大字体/图片体积直接当成这段等待的原因。
2. **机关动画重复生成整张道路表。** 原`set_motion`对每个surface及角色采样重复调用`point_for`，每次再执行`tiles()`深拷贝。复杂关3-4的70个surface放大了开销：60帧约18,480次查询、CPU约11.4–11.7秒。
3. **当前测量环境约32Hz。** 使用GTX1660Ti硬件ANGLE/D3D11；空白HTML帧间隔中位数也约31.3ms。普通首关空闲/行走约31.2ms，不能拿此环境宣称达到60fps，亦不能将所有32fps都归咎于游戏。

直接证据在[loading-startup](qa-godot-native/loading-startup/README.md)，包括普通入口、GL调用耗时和空白页对照。Godot官方说明Web使用Compatibility渲染，现代管线预编译不能直接套用；同步编译限制亦有[官方提案记录](https://github.com/godotengine/godot-proposals/issues/15346)。本项目结论以实际测量为准。

## 实际修复

- 一段动画期间只构造一次前、后快照的tile索引；运动采样复用索引。清理、重新进入及中途跨关时释放缓存。旋转圆弧、缓动、承载、根路生长和完成条件保持原算法。
- 最终源复测中，60帧降至120次查询、约170–189ms；120次角色采样不再重建道路表，约1.29ms。详见[CPU及几何对照](qa-godot-native/performance-motion-cache/README.md)。这是局部CPU测量，不等同于整机帧率提高相同倍数。
- 交付改用Web release构建；加载页明确写出“资源已加载完成，首次准备画面还需要一些时间”。没有删减素材或降低1-1画质。
- 尝试过减少未使用灯光槽、关闭未使用接收阴影分支，均未显示稳定的启动改善，已全部撤回。最终shader、素材、灯光及关卡规则与原验收版相同。

## 构建与保护

最终运行源摘要`5411b2264b38f7577f596a45d817b5800250ce39506caabc53ac227fc32f84bb`，488个文件。正式构建为`performance-final`（release），浏览器回归使用同源`performance-qa`（debug），两者分别记录。

[精确差异核对](qa-godot-native/loading-startup/final-delta.json)通过替换两个文件重建原`0e920…`摘要，证明运行源只改变`native_garden_stage.gd`的动画查询缓存及`loading-shell.html`的一句说明。核心规则、关卡定义、角色移动、交互、存档、shader与原图片未改。此前全关验收仍按其实际构建保留，不能将其直接标成此次新构建的重跑。

## 验收与限制

最终源验收结果：

- [7套无头检查](qa-godot-native/loading-startup/final-headless/checks.json)共9912项通过，运行源摘要稳定。全15关真实角色路线完成，包含19208个承载/接触采样。
- [浏览器触屏复验](qa-godot-native/all-level-adjustment/loading-startup/final-browser/checks.json)：1-2、3-4共107步、117次触点，零键盘路径辅助，无浏览器或Godot错误。
- [旋转中段](qa-godot-native/all-level-adjustment/loading-startup/final-motion/checks.json)与[升降中段](qa-godot-native/all-level-adjustment/loading-startup/final-lift-motion/checks.json)各两种尺寸通过；独立agent复看人物承载、落稳光束及伙伴跟随，无穿台或悬空。
- [最终release普通入口](qa-godot-native/loading-startup/final-normal/checks.json)关闭QA桥，实际进入首页后用真实输入进入1-1、生长、撤销、重复生长和走动。冷启动21.62秒，同浏览器刷新3.71秒；截图确认两次均实际生成根桥。第一次生长最大帧间隔4187.66ms，重复生长最大62.21ms；随后空闲/行走最大32.06/32.28ms。完成且无错误只代表流程正确，首次操作长停顿仍属性能未达标。
- [首次生长GL追踪](qa-godot-native/loading-startup/final-growth-profile/checks.json)独立复现约4.03秒长帧：对应的4.057秒主线程长任务中，两次`getProgramParameter`分别等待1.844秒与1.893秒，确认主要仍是首次shader编译等待。重复动作最大32.17ms。该插桩运行用于定位，不替代上一条未插桩时序。

本地原入口`http://localhost:4222/`现已提供`performance-final` release；端口与存档格式保持不变。

**首次WebGL编译的等待尚未完全消除，首次生长也仍有明显停顿。** 上述数字来自当前主机的隔离Chrome，不保证用户设备一致。最终保留的优化解决机关动画重复计算；本次不把原有渲染和路线检查通过解释成性能完全通过。后续应单独处理首次用到材质时的编译与启动准备，并继续以普通入口冷缓存、首个动作和重复动作分别验收；不能只把卡顿转移到加载页或依赖已缓存的浏览器报喜。
