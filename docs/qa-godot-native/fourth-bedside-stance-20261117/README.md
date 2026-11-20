# 1-4 花坛侧面双人站位

2026-11-17。用户新图显示小苔灵为主动角色、同行开启、两人挤在可见花坛旁，旧入口没有种植提示。本批站位修复与角色提示分开实施，父任务统一最终源码和发布。

## 复现与原因

- 从已归铃的内存状态开始，小苔灵实际带露薇从家门走到 `f:-8:1`，没有传送人物。旧版落稳后小苔灵 `(-7.9984,.6509,.6498)`、露薇 `(-7.9883,.6508,.6815)`，水平仅0.0333m；继续60帧仍不分开，明显小于两角色胶囊半径之和0.29m。
- 普通同行停点在花坛硬基内，被拒绝后回退到同一个canonical prop waypoint。两角色碰撞只遮挡地形（mask1、角色layer2），所以不会互相推出。问题是持续物理共点，不能仅当作一次正常前后遮挡。
- 本次native渲染使用单个AnimatedSprite3D离散帧，未引用旧2D的WalkBlendSurface；新侧走联系表的单格也无双帽。因此没有证据把用户截图中疑似双帽细节归为该混帧器。原生复现确认了身体重叠，但不声称逐像素复现用户图中的每个重影细节。
- 旧基线图和原始位置在 `../fourth-overlap-diagnostic-20261117/`。其诊断脚本不改生产源和用户保存。

## 最小改动

只在 `native_garden_stage.gd::actor_rest_offset` 的1-4 `f:-8:1` 分支登记已有同高支撑上的两处真实停靠点：露薇偏移 `(-.44,0,-.44)`，小苔灵 `(+.44,0,-.44)`。先用现有local-target、硬物clear及segment-clear验证候选，再用真实电机走入。既有点击、跟随和无runtime默认恢复共用此位置，不改变地形、尺寸、深度或角色碰撞策略。

初次左右相反的候选虽然身体分开，却让矮伙伴过多藏在花坛石基后，已人工否决。当前将高露薇放左、矮伙伴放右，伙伴脸和身体可读；露薇脸位于花冠上方，正常下半身局部遮挡仍保留。旧runtime内保存的主动人物位置不强制改写，跟随者沿原路真实分开。

## 验证

新增 `native_fourth_bedside_stance_test.gd`，50项无窗口检查通过，覆盖双方领队、换手、旧重叠runtime、真实无传送分离、脚底接触和硬基clear，以及开启原同行后走入原core范围、主动种植完成。真实GPU同样50项通过，6张1841×907完整原图在 `gpu-final/`，原始记录为该目录 `checks.json`。

最终GPU物理距离：小苔灵领队0.844m、露薇领队0.861m、用户旧runtime落稳分离0.443m、原core会合0.745m。两角色实际站在既有台面；旧runtime起始点仍保留，随后由电机走开。

原switch仍会关闭follow。本测试明确再按原follow，未偷改换手能力或让小苔灵直接repair；本次角色提示流程由父任务另一子任务负责。一次候选GPU被窗口失焦通知打断路径，其失败保留在 `gpu-swapped-candidate/`；测试根Window随后设置unfocusable，最终复跑正常。无窗口首轮把换手后follow错误视为继续开启的测试假设，也保留在 `initial-candidate-follow-assumption.json`。

```powershell
<Godot> --headless --path godot --script res://tests/native_fourth_bedside_stance_test.gd
<Godot> --path godot --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/native_fourth_bedside_stance_test.gd -- --capture-output=<绝对目录>
```

本批GPU仍是当前本机原生渲染，不是用户浏览器逐帧录屏或全15关测试。
