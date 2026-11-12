# 原站元素恢复：冻结候选的 CPU 验收

运行时 SHA-256：`29da2daf52a04706ac29339910bb3c4a9c2977c626f377ad1a511af08e389c42`，558 个文件，运行前后摘要一致。完整证据见 [checks.json](checks.json)。本轮仅调整测试中的旧呈现预期，没有修改运行时；未执行 GPU 渲染验收。

**结果未通过：14 套中 11 套通过，3 套因真实运行时错误失败。** 虽然共 20,816 项断言均未报告断言失败，但运行器正确拒绝了含 `ERROR` 的输出，不能将本批标为通过。

| 套件 | 断言数 | 结果 |
| --- | ---: | --- |
| native_actor_pose_test | 606 | 通过 |
| native_first_garden_contract_test | 91 | 通过 |
| native_garden_effects_test | 2156 | 通过 |
| native_mechanism_props_test | 267 | 运行时错误 |
| native_motion_cache_test | 9087 | 运行时错误 |
| native_movement_test | 45 | 通过 |
| native_original_carry_test | 105 | 通过 |
| native_original_cloud_test | 400 | 通过 |
| native_original_dressing_test | 1687 | 通过 |
| native_original_pond_test | 686 | 通过 |
| native_original_prop_ratios_test | 92 | 通过 |
| native_prop_alignment_test | 3108 | 运行时错误 |
| native_prop_scale_test | 660 | 通过 |
| native_route_test | 1826 | 通过 |

三套失败具有相同错误：`Original scenery has no real flat support: 2-1/7/fern`，来自 `original_garden_dressing.gd:206`，由 `set_motion → refresh_world → _update_props → _add_scenery` 触发。静态景物状态通过，运动入口测试失败，错误未被忽略。

待调查假设：蕨类原始点 `(-4.24, 4, h0)` 的支撑为 `f:-4:4`；水位切换时逻辑 `_tile_map` 仍含该格，而物理 `_surfaces` 已移除低岸，导致寻找真实支撑失败。此为推断，尚须以运行时状态核实。不得以跨岛挪动、伪造支撑或吞掉错误消除失败。

15 条完整参考路线全部完成，共 477 步、19,248 个物理样本；最大角色表面间隙 `0.171366333961487`，最大视觉接触误差 `0.16247969865799`。路线成功不覆盖上述瞬态入口错误，也不能证明最终 GPU 画面合格。

旧呈现断言迁移依据和原始失败证据见 [预检记录](../final-headless-preflight/README.md)。携带检查改为原站叶包 `.65` / 伙伴 `.66` 和包内缩略图语义，地面检查仍独立按原站像素常量计算；实际拾取、放下、角度、撤销、恢复和缓存检查保留。机制交互根、物理支撑及运动容差未放宽。

后续修复应使用新证据目录，保留本批失败记录。
