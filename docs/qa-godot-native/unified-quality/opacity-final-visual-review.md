# 山谷与池塘硬体不透明及完成清场独立复核

## 结论与来源

**本次分配的 1-X / 2-X 硬体透明返修范围通过最终定向复核。** e83 的 64 张机制状态原图通过；其 32 张完成清场/全景原图中，1-4 门框整卡淡化被独立否决；随后 2ced 修正创建语义后，1-4 与 2-2 的 16 张定向原图通过。没有覆盖或删除前两次失败证据，也不将自动采集成功等同人工画面通过。

| 批次 | 源码 SHA-256 / 文件数 | 本人实际看图范围 | 结论 |
| --- | --- | --- | --- |
| [opaque-level-states](opaque-level-states/checks.json) | `e83f8ced7dec84a22ccfcef508bc619cfb948d7ea983c782c1914c58f299320f` / 580 | 1-1～1-4、2-1～2-4，1280×720 与 844×390，arrival / mechanism / before-completion / restored-completion，64 张 | 指定硬体、双人可读性及此前问题复验通过 |
| [opaque-placement](opaque-placement/checks.json) 与 [1-2 second-return](opaque-placement-second-return/checks.json) | 同 e83 | 上述八关双尺寸，仅 completed-clear / overview，32 张；1-2 取 second-return | 除 1-4 门框淡化外通过；该中间批次不能整体放行 |
| [structure-placement](structure-placement/checks.json) | `2cedf0cc20e4faf656fbee130e36de63bf7a8995b89e6bf98ef29e0f9adf6f01` / 580 | 仅 1-4、2-2，双尺寸 arrival / completed / completed-clear / overview，16 张 | 门框返修及相关不透明回归通过 |

合计 **112 张完整 PNG 原图**，逐图 SHA、尺寸、批次与源码见 [清单](opacity-reviewed-images.json)。本报告未重看 structure-placement 的 3-4 / 云庭；这些由其他评审负责。未额外启动 GPU，未改生产代码。

## 逐关观察

| 关卡 | 双尺寸状态图与完成清场/全景观察 |
| --- | --- |
| 1-1 | 已认可首关例外保留；完成后真实移开，开花与石床仍保持完成态；全景包含原岛体。未从此推导任意自由站位都无遮挡。 |
| 1-2 | 原根路、岩石、窄床及双人可辨；完成后沿原 `g:root:3:1` 返回清场，开花与整床可见，全景包含远岛。不新增地块，也不将返回描述为新增 `f:3:1` 或 `f:4:2`。首轮东侧清场候选失败保留于 opaque-placement，采用同源码 second-return 的有效返回证据。 |
| 1-3 | 照料前伙伴不再藏入主角；完成清场后花床及两处远岛在全景完整，拱门与地面层次清楚。 |
| 1-4 | 照料前后双人脸部可辨，阶段提示随 3/4、4/4 正确更新；e83 清场暴露门框淡化，2ced 后实体框体与基脚恢复清晰，未产生新的默认脸部遮挡。完成全景包含整座花园。 |
| 2-1 | 机制小石坛保持实体，双人和操作标识可辨；完成清场保持高水位，低岸按原规则隐藏，全景覆盖花园。高床局部挡下半身属于正常深度关系。 |
| 2-2 | 镜、岩石、石灯和光路可辨；完成清场时前景石块局部挡住下半身，两人面部仍清楚，硬物无整卡淡化。2ced 定向四状态回归未见新脸部遮挡。 |
| 2-3 | 固定源岸小坛与 SongBase 分离，舞台圆形控制标记可辨；升起的舞台正常遮住后方源岸坛。完成清场花床完整，永久返路在全景可见。 |
| 2-4 | 此前失败的终岛石灯在照料前、完成、清场保持实体，从灯脚到灯罩不再整卡淡化；双人脸部仍可辨，蕨类、远船与源岸保留。 |

## 两次否决与本轮闭环

1. [c52 失败报告](reviewed-main-visual-review.md) 中 2-4 硬石灯淡化：e83 的 [桌面照料前](opaque-level-states/1280x720/2-4/before-completion.png)、[桌面完成](opaque-level-states/1280x720/2-4/restored-completion.png)、[小屏照料前](opaque-level-states/844x390/2-4/before-completion.png)、[小屏完成](opaque-level-states/844x390/2-4/restored-completion.png) 均已不透明，且没有靠遮住脸来换取实体感。该问题在所验姿态关闭。
2. e83 [1-4 桌面清场](opaque-placement/1280x720/1-4/completed-clear.png)、[小屏清场](opaque-placement/844x390/1-4/completed-clear.png) 中，`OriginalSanctuaryGateFrame` 从装饰顶到底脚一起幽灵化。它是 `flower-gate-frame` 建筑框体，并非光封层或云庭灯塔；不能因普通景观白名单已修而忽略独立创建路径。2ced [桌面清场](structure-placement/1280x720/1-4/completed-clear.png)、[小屏清场](structure-placement/844x390/1-4/completed-clear.png) 保留完整框体、基脚与正常深度，两人脸清楚；同批 arrival / completed / overview 一并复核。该问题在所验姿态关闭。
3. [a205 失败报告](independent-final-review.md) 的 A/B/C/D 在 e83 相应状态仍维持 c52 已确认的改善：伙伴分离、小坛旁站与固定源岸、1-4 进度提示，没有观察到这些问题复发。

## 证据边界

- opaque-level-states 是准备/恢复状态，mechanism 仅为机制关键帧，不是完整起/中/止输入证据。placement 的完成状态由 QA 准备，随后恢复控制、清场行走、全景切换使用真实控件；不因此声称从初态实际玩通每关。
- e83/2ced 的此次差异是硬体遮挡语义与 alpha；本报告只确认原图观察。完整路线、胶囊碰撞、未解阻断、撤销/读档、动态接岸与性能须引用各自源码对应专项证据，不能由截图替代。
- 1-4 小横屏 mechanism 中远处非当前伙伴部分受底部 HUD 遮挡，是先前已登记的镜头边界；本次完成态全景确认全园可纳入，但并非同一个机制姿态，不用它冒充该姿态的补证。
- 2-2 完成截图仍保留“把一束光送回花床。”的通用文字。本次只验不透明与默认可见性，不将该文字视为已验收的全关完成后提示改进。
- 本批为 debug Web 图像证据；不覆盖正式包资源核对、设备触控与 GQ-011 性能问题，不宣称任意自由移动姿态全时无遮挡。
