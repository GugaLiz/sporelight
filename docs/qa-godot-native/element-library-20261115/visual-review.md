# 元素库抽取 GPU 回归记录 · 2026-11-15

## 实际覆盖

- 当前代码：12 个新建关卡场景（1-1～3-4）+ 5 个历史完成状态的准备快照（1-4、2-2、3-2、3-3、3-4）+ 3-2 伙伴换肤与恢复，共 19 张。
- 冻结抽取前副本：相同 12 个新建场景 + 相同 5 个准备快照，共 17 张。副本路径为 `.tmp/element-library-20261115/baseline/godot`；单独导入资源缓存，未拿旧截图充当本次证据。
- 真 GPU：Godot 4.7.2、OpenGL Compatibility、NVIDIA GeForce RTX 4090 D。每张 1280×720，同时核验真实 3D SubViewport 尺寸和非透明世界像素。64×64 的不可聚焦、屏幕外宿主窗口不作为截图来源。
- 当前 112 个、基线 101 个生产源文件分别记录 SHA-256，捕获前后完全一致；两份最终 report 均 `passed=true`、`sourceFilesStable=true`，无脚本/渲染错误。

## 对比与观图

17 组相同场景逐像素比较：每张改变 **0～23 / 921600** 个像素（最大约 0.00250%）。2-1 冷场景、2-2 冷场景、3-3 准备完成态完全相同。其余差异保留原始统计，未设阈值抹除；差异呈零散小点，不将其声称为绝对相同或擅自认定原因。

已查看 12 关冷场景总览，以及 1-1、2-2、3-2、3-4 并排图和全部五关准备状态图。在这些画面中，角色及伙伴、道路/楼梯、花坛、石灯/反射镜、日月石、旋转模块的位置、尺寸、画面构成与冻结基线一致，未见因本次元素抽取新增的比例变化、缺件或模型位移。该结论不代表消除基线已有的设计问题。

- [12 关冷场景总览](all-cold.jpg)
- [4 关基线/当前并排](key-comparison.jpg)
- [5 关准备状态并排](prepared-comparison.jpg)
- [逐像素原始统计](pixel-diff.json)

## 换肤证明

3-2 中将伙伴外观临时换成已有主角帧的 0.7 比例版本，只用于验证 renderer 可替换，不发布这套试验外观。实际 GPU 中伙伴外观发生变化；断言确认世界快照、物理身体位置、碰撞形状保持不变。恢复 `buddy.original` 后整张截图与该关冷场景 **921600 个像素完全相同**。

[原伙伴 → 试验皮肤 → 恢复原伙伴](companion-skin.jpg)

## 已复现的既存测试失败

- 冻结基线 `native_movement_test.gd`：同样在 cloud-2 的共享运动器合法边测试失败，44/45 通过；2392 次地面采样、最大误差 0.11318 与当前一致。[基线日志](baseline-movement.log)
- 冻结基线 `rule_reference.gd`：同样在 authored/1-1 初始 tiles 数量 expected 16 / got 19 失败。[基线日志](baseline-rule-reference.log)

上述结果用于区分本次回归与原有测试/夹具问题，没有通过重写旧 fixture 掩盖失败。

## 证据边界与复现

这里是原生场景渲染和外观替换验收，不含 HUD/Web/音频/性能；相机为原关卡入场 framing，画面外元素不在单张截图覆盖范围。五个完成状态直接加载历史 snapshot，**不是完整操作通关录像**。玩法路线、能力与存档验收由独立规则/物理测试承担。

捕获脚本：`godot/tests/native_element_library_capture.gd`；对比脚本：`godot/tests/compare_element_library_captures.py`。冻结场景时先按最终相机刷新 actor depth，再停动画，避免旧相机轴造成假视觉差异。每轮 GPU 串行运行。早期捕获曾正确拦截生产文件仍在变化的轮次，最终目录已由稳定轮次重采。

```text
node tools/godot-migration/capture-native-background.mjs --script=res://tests/native_element_library_capture.gd --output=docs/qa-godot-native/element-library-20261115/current --source-sha=element-library-final-20261115
python godot/tests/compare_element_library_captures.py docs/qa-godot-native/element-library-20261115
```

最终机器报告：[当前](current/report.json)、[冻结基线](baseline/report.json)。实际逐文件哈希见报告 `initialSources/finalSources`；`sourceSha` 为这次采集的说明标签，不当作 Git commit。
