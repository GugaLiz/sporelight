# 山谷与池塘返修候选独立原图复核

## 批次与结论

绑定 [reviewed-level-states 采集记录](reviewed-level-states/checks.json) 的 debug 源码 `c52aa7298f8175b51f025884d9dd0395ce4a3bb5cd88fcae6a5bac310ec30013`，580 文件。实际逐张查看 1-1～1-4、2-1～2-4，两种尺寸 1280×720 / 844×390，每关 arrival / mechanism / before-completion / restored-completion，合计 **64 张完整原图**。未以拼图替代原图，未启动额外 GPU，未修改生产代码。

**本批暂不整体放行：此前 A/B/C/D 在相应截图中改善并通过局部复核，但 2-4 终岛硬石灯仍整卡半透明。** 自动采集 `passed=true` 不覆盖该视觉问题。[此前 a205 否决报告](independent-final-review.md) 原样保留；两批结果不能相互覆盖。逐图 SHA 见 [本批清单](reviewed-main-images-c52.json)。

本批是准备并恢复的状态图，不是实际输入通关；mechanism 是关键结果快照，并非完整运动起/中/止。路径、连续碰撞、动态生命周期与正式发布另需绑定各自证据。

## 逐关结果

每格结论均查看了桌面和小横屏对应原图。

| 关卡 | arrival / mechanism | before-completion / restored-completion |
| --- | --- | --- |
| 1-1 | 已认可基线保留，未见本轮新增变化 | 保留原首关例外；不从此推导所有自由站位零遮挡 |
| 1-2 | 根路、岩石和三节/剩一节状态清楚；小屏远岛下缘部分在 HUD 后 | 双人脸部可辨，床与人物分开，窄床原例外保留 |
| 1-3 | 原拱门、植物、旋转牌与高低台可辨 | **旧 A 关闭于本范围**：照料前伙伴不再与主角重叠，完成后仍清楚 |
| 1-4 | 阶段提示与原机关状态相符；小屏 mechanism 的远处非当前伙伴仍部分在 HUD 后，需全景补证 | **旧 B/D 关闭于本范围**：两人脸部、身体可辨；3/4 为种下微光，4/4 为花园已复苏 |
| 2-1 | **旧 C 局部关闭**：小石坛在双人后侧，石基不再淡化或置于人物脚下，控制牌与伙伴可辨 | **旧 B 关闭于本范围**：伙伴在前侧可见，主角脸和上身清楚；高石基正常挡住主角部分下半身 |
| 2-2 | 镜面、岩石、光路和双人可辨；未见本轮新问题 | 延续 75 号认可的正常局部下半身深度遮挡，脸部与伙伴清楚 |
| 2-3 | 固定源岸小坛和 SongBase 分开；舞台上保留圆形控制标识，人物不再踩在石坛中 | 双人、核心床与永久返路可辨；移动舞台能正常挡住其后方源岸坛，是真实层次关系 |
| 2-4 | **旧 C 局部关闭**：初态人物避开小坛，船上两人与石坛分开，石基不再淡化 | 双人脸部与核心床可辨，**但终岛原石灯整体淡化，仍须返修** |

## 已关闭的旧图问题

- A：1-3 照料前伙伴此前几乎完全藏在主角中。本批 [桌面](reviewed-level-states/1280x720/1-3/before-completion.png) 与 [小横屏](reviewed-level-states/844x390/1-3/before-completion.png) 显示两个角色面部和主体分开；完成状态也维持可辨。
- B：1-4 与 2-1 的默认照料伙伴此前仅露帽或消失。本批 [1-4 桌面](reviewed-level-states/1280x720/1-4/before-completion.png)、[1-4 小横屏](reviewed-level-states/844x390/1-4/restored-completion.png)、[2-1 桌面](reviewed-level-states/1280x720/2-1/before-completion.png)、[2-1 小横屏](reviewed-level-states/844x390/2-1/restored-completion.png) 均可辨双人。身体局部被高石基遮住与实体穿入不同，后者仍需物理证据。
- C：2-1 中央小坛、2-3 舞台坛、2-4 船坛的原问题分别采取旁站、源岸固定、船上旁站。本批 [2-1 小坛](reviewed-level-states/1280x720/2-1/mechanism.png)、[2-3 舞台](reviewed-level-states/1280x720/2-3/mechanism.png)、[2-4 船上](reviewed-level-states/1280x720/2-4/mechanism.png) 不再出现人体踩在淡化石坛中的画面。此结论仅涉及小石坛，不能外推为所有硬景观不透明。
- D：1-4 默认底部目标由阶段驱动，照料前显示“当前目标：种下微光”，完成显示“花园已复苏”，与左上 3/4、4/4 对应。两个尺寸均未再保留过时归铃目标。

## 2-3 源岸摆位专项观察

[桌面初态](reviewed-level-states/1280x720/2-3/arrival.png) 和 [小屏初态](reviewed-level-states/844x390/2-3/arrival.png) 可同时看到浅色 SongBase 与右后方石坛，两者底面和轮廓分开；未见石坛压在琴键上或人物站在石坛中。原石坛和 SongBase 的材质风格不同，但本批没有因新摆位产生不合理尺寸或重叠。

[桌面机制态](reviewed-level-states/1280x720/2-3/mechanism.png) 和 [小屏机制态](reviewed-level-states/844x390/2-3/mechanism.png) 的舞台中心有圆形叶纹控制标记，主角站在旁侧，标记轮廓可见。小屏细节较细，圆形操作点仍可辨；不据此声称新手无需提示即可理解整套旋律。升起后的舞台侧墙正常遮挡后方固定石坛，不能误判为坛随舞台消失。四朝向两臂、固定坛不随升转、动作途中碰撞与原玩法可达性必须由机制专项另验。

## 待修正：2-4 硬石灯整卡淡化

本批 [桌面照料前](reviewed-level-states/1280x720/2-4/before-completion.png)、[桌面完成](reviewed-level-states/1280x720/2-4/restored-completion.png)、[小屏照料前](reviewed-level-states/844x390/2-4/before-completion.png)、[小屏完成](reviewed-level-states/844x390/2-4/restored-completion.png) 中，伙伴左侧石灯从基座到灯罩一起呈半透明；桌面大约位于 (550,450)，小屏大约 (377,225)。它不是光晕或自由叶冠，仍属于 GQ-016 硬体视觉/占地语义范围。

只读源码核对：`native_prop_obstacles.gd` 的 HARD_SCENERY 包括 stone-lantern；`native_garden_stage.gd::_update_occlusion()` 只对 core_planter 强制 alpha=1，其他进入遮挡组的硬景观仍可降到 0.60/0.3。该证据支持“硬体仍整卡淡化”，不等于证明灯脚实体可穿。应保留尺寸、实际硬底座及正常深度，采用物体语义或合法摆位修正，并重看这四张及涉及的其他硬景观。

## 仍需补齐的证据

1. 上述石灯修正后的同源图像与相关 CPU/实际路径回归；不得覆盖本批失败原图。
2. 完成后清场、普通/全景、动态起中止，以及小屏远处非当前伙伴被 HUD 遮住的全景补证。
3. 本报告不覆盖 3-X / 云庭 / 地图；不覆盖最终 4222 资源核对、正式构建或性能 GQ-011。
