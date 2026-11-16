# 角色与蘑菇伙伴复用元素

适用：1-1～3-4 共 12 个主线小关，沿用当前原生 Godot 场景。此次只抽取配置和组装入口，不改变形象、机关权限、路线、跳跃语义或关卡解法。

## 单一入口与职责

| 层 | 入口 | 负责内容 |
|---|---|---|
| 配置 | `godot/content/actor-elements.json` | 身份、默认外观、碰撞胶囊、手持锚点、运动数值、动画帧、脚锚、携带缩略图比例 |
| 查询 | `godot/elements/actor_definitions.gd` | 加载一次、校验外观、注册自定义皮肤；编辑器通过 `definitions()` 获取副本 |
| 实体组装 | `actor_visual_factory.gd` / `native_actor.tscn` | 按身份生成原生身体；按皮肤装配 SpriteFrames；共享呼吸和原地跳跃动画 |
| 运动 | `application/native_movement.gd` | 键盘、点击路线、伙伴跟随共用物理执行器，读取 motor 配置 |
| 渲染 | `native_actor_pose.gd` / stage | 动画切换、脚锚、镜像补偿、遮挡与坡面视觉贴合 |
| 手持物 | `original_carry_art.gd` | 小叶袋和缩略图；按持有者皮肤应用携带比例，不把地面模型直接缩小塞到手上 |

以上原生脚本路径均位于 `godot/presentation/native/`，另有明确路径者除外。旧二维 `character_motion.gd` 不是当前原生执行器，不将其时间数值与原生动画混用。

## 同类规则

1. `actor_id` 是稳定玩法身份（`luvie` / `buddy`）；`skin_id` 是外观。换装、替换蘑菇贴图不改变身份、碰撞体、支撑格、物品持有者或存档。
2. 行走、跟随、翻滚分别使用共享 motor：3.25、3.45、行走 ×1.15。主角各方向步态周期均为 0.55 秒，转向保留步态相位。
3. 当前跳跃是原地表情动画：只移动视觉子节点，常规高度 0.3、低动态高度 0.04，不改变物理支撑，不能跨断路。未来真正跳跃应新增经过玩法验证的能力，不能改皮肤配置伪造通过。
4. 脚锚使用每个皮肤的 `standing.canvas/foot/pixel_size`；蹲下、种植、敬礼可以有按动作/逐帧校正。镜像时同时镜像偏移。画布不是可见身体尺寸，不按整张透明 PNG 推断碰撞体。
5. 原伙伴保留缓存的程序绘制表面；呼吸、摇摆、等待和睡眠通过变换表现，不逐帧重绘纹理。新伙伴可注册完整方向帧皮肤，无需复制整套角色或关卡脚本。
6. 身体比例与锚点由 `actors.*.body` 统一定义，仅生成身体时使用；运行时换肤 API 不重建身体。需要更换实体体型时必须重新验证通道、楼梯、碰撞和拿取距离，不能自动从新贴图推导体型。
7. 携带物统一 `carry` profile，伙伴默认 0.66；保持各关现有手部位置。缓存包含元素/资源版本，重新载入美术后不复用陈旧缩略图。

## 换装与编辑器接入

```gdscript
const Actors = preload("res://elements/actor_definitions.gd")
var skin := Actors.skin("luvie.original").duplicate(true)
skin.allowed_actors = ["luvie"]
# clips 的 frames 使用已注册美术别名；更换画布时同时更新 canvas、foot 与姿势锚点。
skin.clips.idle_front.frames = ["my-costume-idle-front"]
var registered := Actors.register_skin("luvie.my-costume", skin)
if registered.ok:
    var applied := stage.set_actor_skin("luvie", "luvie.my-costume")
    # applied.ok 为 false 时原外观仍保持。错误码可供编辑器显示。
```

`set_actor_skin` 在提交前完成身份兼容性、帧资源和结构校验；应用后保留动作相位、身体和世界规则状态，并重建遮挡界限与手持显示。`actor_skin_id(who)` 查询当前外观，`refresh_actor_visuals()` 用于资源主题重载。不支持的动作回退到 `idle_front`，不会让精灵消失。

JSON 的 `skins` 是项目默认皮肤目录；`register_skin` 是本次运行的扩展目录。当前没有新增换装 UI、购买入口或持久化皮肤选择。编辑器以后保存稳定 skin ID，不能把 Node、Texture 或临时运行字典写入玩法存档。

`capability_profiles` / `has_capability` 描述原有身份能力：伙伴钻小道，主角搬重镜、种植、照料和扳重摇杆。它们是复用目录元信息，**本次没有把核心规则变成任意可配置技能系统**。后续不同蘑菇功能应新增能力 ID、明确规则命令和测试，再接入核心；不能只改皮肤获得能力，也不能把这些描述字段当成已完成的可选技能执行器。

## 回归证据

- `native_actor_element_baseline.gd` 在提取前记录实际场景输出；已有 fixture 时拒绝覆盖。`fixtures/actor_element_baseline.json` 保存两角色原碰撞体、手持锚点、脚锚、逐帧资源路径、FPS 和循环设置。
- `native_actor_elements_test.gd`：对照冻结基线，验证换肤原子拒绝、身份隔离、伙伴切换帧动画、步态相位、12 关世界状态不变。
- 保留原 `native_actor_pose_test.gd`、`native_actor_depth_test.gd`、`native_original_carry_test.gd` 与物理移动测试，不以“配置读写一致”替代实际场景验收。
- CPU/无头测试不代表 GPU 画面和人工观感验收；需合并阶段按项目场景质量规范检查截图。
