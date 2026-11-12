# 独立岛基座厚度调整

固定岛按完整几何快照中的四邻关系分组，以本岛最低格面高度减 0.67 世界单位作为共同底部。同岛高台继续保留真实高差，独立高岛不会因为绝对海拔增加而变成高柱。分组不读取可见性，不经根路、影路、桥梁、移动模块或云庭升降台合并固定岛。

模块按 module ID 共底；云庭没有 module ID 的 lift 按独立连通组处理，gate 也不合并固定岸。升降时基座底面跟随同一个高度变化。运动阶段复用 stage 的 departure geometry_tiles，因此中途不按目标状态重新削切侧壁。首关和第二关仍使用原有 terrain profile 和 foundation，薄桥仍由 native_surface 的 0.20 厚度规则处理。

此次变更只新增 `island_foundations.gd`，并在 stage 的 `_update_terrain` 中替换底面高度参数。没有修改材质、镜头、tile 高度、坡度或关卡规则。侧壁原本属于碰撞网格，所以侧向碰撞会随可见基座底部同步变薄；可行走顶面碰撞三角形保持原样。

已执行 Godot 4.7.2 headless 验证：

| 测试 | 断言 | 结果 |
| --- | ---: | --- |
| native_island_foundations_test | 3,788 | 通过 |
| native_motion_terrain_test | 83,520 | 通过 |
| native_chapter_presentation_test | 295 | 通过 |

专项测试覆盖全部 15 关新旧 bottom 的独立网格对照：顶面、坡面、踏步、立阶与可行走碰撞三角形一致；首两关及薄桥完整碰撞一致；stage 实际安装本岛底面；岛内高差共底；模块相邻不合并；高低独立岛互不影响；云庭升降台高度切换保持厚度。运动测试覆盖 32 个正向/反向状态组合，确认途中复用相同 mesh 与 collision、靠岸后正确构建目标几何。

没有运行 GPU。最终 15 条原生完整路线由 mechanisms 代理在 `docs/qa-godot-native/motion-docking/routes-foundations-final-headless` 验收，实景比例、侧壁视觉与遮挡由主任务统一截图验收；此处不把数值测试冒充视觉验收。
