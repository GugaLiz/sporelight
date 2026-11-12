# 加载与卡顿排查证据

对应[文档60](../../60-Web加载与机关卡顿排查.md)。全部使用隔离浏览器，不读取用户旅程。

| 目录/文件 | 用途 |
| --- | --- |
| `normal-start.json` | 原4222普通入口；一次首次进入约41秒，无启动异常 |
| `baseline/` | 原debug普通首页再测，约26秒；下载后24.7秒长任务 |
| `blank-control.json` | 无游戏空白页约31.3ms帧间隔，确认环境帧节奏 |
| `release-baseline/`、`release-verbose/` | 同源release普通首页及资源加载时间，约20–21秒 |
| `release-gl-profile/` | WebGL等待shader约20.46秒；纹理上传约35ms |
| `light-slots/`、`light-slots-repeat/` | 未使用灯光槽缩减候选，没有稳定改善，已撤回 |
| `candidate/`、`candidate-warm/` | 阴影分支候选及刷新对照；同浏览器刷新约3.8秒。阴影改动已撤回，不作为最终构建验收 |
| `final-delta.json` | 最终source5411b226…，仅动画快照缓存与加载文案；实际shader及所有资源不变 |
| `final-headless/` | 最终源实体路线与动画/根路/机关正确性复验 |
| [final-browser](../all-level-adjustment/loading-startup/final-browser/checks.json)、[final-motion](../all-level-adjustment/loading-startup/final-motion/checks.json)、[final-lift-motion](../all-level-adjustment/loading-startup/final-lift-motion/checks.json) | 同源debug的真实触屏路径与动作中段复验；位于all-level-adjustment目录内 |
| [final-normal](final-normal/checks.json) | 最终release普通入口，冷/暖启动、真实首次及重复生长、空闲及行走；没有QA桥 |
| [final-growth-profile](final-growth-profile/checks.json) | 独立GL插桩确认首次生长4.057秒长任务中，两次shader状态等待共3.737秒；重复动作最大32.17ms |

最终源`5411b226…`的7套无头检查9912项通过，全15关实体路线完成。1-2与3-4横屏触屏107步、117次触点、零键盘路径辅助；旋转与升降共4组动态采样通过，独立[画面复核](../all-level-adjustment/browser-review.md)已完成。

最终release冷启动21.62秒、同浏览器刷新3.71秒。首次生长最大帧间隔4187.66ms，撤销后重复生长最大62.21ms；空闲/行走中位数均约31.25ms，与空白页环境节奏接近。两次生长截图确认根桥已经生成。**功能回归通过，首次加载与首个动作的性能问题仍未解决**；局部CPU加速与实际浏览器帧率分别记录，不将“完成采样”作为“达到60fps”的通过标准。原全关报告仍保留原源码版本。
