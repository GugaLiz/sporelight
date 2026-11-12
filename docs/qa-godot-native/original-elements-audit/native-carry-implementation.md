# 原版携带叶包恢复

日期：2026-11-11。用户最新选择原站作为元素及比例标准，主线携带语义以 `src/app/garden2/itemArt.ts/drawCarryBag` 为准：叶包、系绳和小物品图示。此前自行要求“地面与手中可见实体同大”的方案在此明确撤回；地面镜体与包中镜叶图示是不同表现职责。

新增 `godot/presentation/native/original_carry_art.gd`，调用 `OriginalCarryArt.apply(stage, who, carrySprite, model, item_id, item)`。只替换现有手锚上的显示：不改变 Sprite/CarryModel transform，不修改 item 或规则状态，正常参与深度；隐藏旧 CarryModel，显示携带 Sprite。舞台仍负责释放旧模型、决定持有者、未持有时隐藏、切换非本模块显示时重置 model.visible。

尺寸：原角色 PNG 宽 115 对应 native 1.6，故每原像素为 `1.6/115` 世界宽。叶包自身保留 `.65`，伙伴另乘 `.66`；露水为原 `dew-parcel` 25 px 图，包中灯/镜叶/晶体为原图 18 px，镜叶用 lilypad，门铃用原小铃矢量形状（包内 .45）。完整 64×64 透明组合画布以 4 倍 CPU 栅格化，仅可见包体具有上述尺度，不可拿整张透明图宽误判物件大小。源包中心 `(7,-18)` 对齐既有 native 手锚，角色蹲姿/转身的空间位移继续由既有手锚负责。

叶包与系绳采用 SVG→Image；物品 thumbnail 直接取现有 PNG，通过 CPU `Image.blend_rect` 与底包、前叶扣组合。这样不依赖 SVG 对 dataURL 的支持，也没有 SubViewport 或逐帧重画。缓存按 item、稳定资产路径和系绳版本区分，初始化预热有绳/无绳两张；之后 `pose(carrySprite, who, pose_name, rolling)` 只切换缓存引用，按原前向/侧向/滚动规则显隐系绳。舞台可在已有姿态更新处调用该轻量接口，不必重跑 apply。

item ID、angle、携带语义、源像素宽等保存在 metadata，sunPost/moonPost 保留身份颜色。angle 不再驱动包内缩略图变成完整 3D 镜板。云庭 `cloudSeed` / `cloud-seed` / `seed` 提前返回，保留专用星种携带。

规则已同步 `.agents/skills/game-scene-quality/references/scene-contract.md` 与 `references/sporelight.md`：先遵循认可的携带语义；直接拿实体和包内小图示分别验收，不强迫二者同大。

新增 `godot/tests/native_original_carry_test.gd`，**105 项、0 失败**，8 种物品共 16 张缓存组合；检查规则不变、手锚不变、原比例、伙伴缩放、完整正常深度、姿态切换复用缓存和云庭种子排除。结果见 [native-carry-headless.json](native-carry-headless.json)。CPU 输出已查看 [露水](carry-dew.png)、[门铃](carry-bell.png)、[镜叶](carry-mirrorA.png)，可辨系绳、包体和各图示；这些透明纹理预览不是角色实际 GPU 截图。

本任务未修改 stage，也未启动 GPU。集成后仍需看露薇/伙伴站立、转身、蹲姿、滚动、拿起/放下/撤销的真实画面，确认包体与角色接触、遮挡和可读性。
