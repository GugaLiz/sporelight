# Sporelight 项目适配

在当前工作区内解析以下路径；不要把本机绝对路径当成其他电脑的默认仓库。标识：`godot/content/levels.json`、`godot/presentation/native/`、`tools/godot-migration/`。非此项目不套用以下特例。

## 规则入口

- 先读仓库 `docs/69-游戏开发基础质量规则与问题台账.md`：最新反馈、基础问题状态与补充模板。它可能比本 Skill 的摘要更新。
- `docs/56-全关卡优化规则与首关验收基线.md`：玩法保护、基准、领域与表现边界。
- 改某关逻辑/空间时读 `docs/57-全关卡玩法契约与优化清单.md` 对应关卡。
- 楼梯改动读 `docs/66-全关实体楼梯与显隐统一计划及验收.md`；旧65号坡面加踏边方案已被替代。
- 材质/拾取/环境/地图入口读 `docs/67-原版地图与关卡美术动效恢复及验收.md`；1-2接岸、旧档和装饰历史读 `docs/68-第二关第四节接岸修正与场景装饰恢复及验收.md`。
- 原站15关元素及比例恢复读 `docs/71-原版逐关元素恢复与比例验收.md`；原站来源清单与恢复后的验收证据分开记录，不能沿用70号候选尺寸作为原站标准。
- 用户认可当前大小后的位置整理读 `docs/72-全关卡位置整理计划与验收.md`；保留尺寸，分别检查完整底座、投影遮挡、默认操作站位与动态接岸。首轮CPU/截图通过后被独立看图否决的实例也保留在该文档，不当作最终视觉结论。
- 1-4重杆持续动作与原生松手读 `docs/73-第四关重杆动作与保持逻辑修复及验收.md`：真实走近后站立保持，同格内实际移动即释放，占桥时身体与规则一同回滚；重复保持幂等，明确松手单列，永久门闩后清除临时动作。此专项不替代72号其他场景结果，也不关闭性能问题。
- 1-4元素间距与默认站位后续读 `docs/74-第四关元素间距整理与验收.md`：保留尺寸、逻辑格和重杆握点，门闩侧站、门铃同格错位；归铃前/开门/接回伙伴分别看双人、家花、NPC与剩余拾取。将NPC前移会遮伙伴的候选已否决，最终保留其既有合法位置。
- 镜头尺度历史读 `docs/64-机关落稳建模与全关视觉尺度验收.md`。历史性能与截图只覆盖对应源码，不能证明当前画面合适。

用户当前要求优先；规则冲突查明修订来源，不按文档编号盲目覆盖全部早期约定。用户对本次比例的否定优先于68号的装饰通过记录；实际待修状态以69号为准。

2026-11-11 用户重新明确原站 `https://gugaliz.github.io/sporelight/` 为每关元素与比例标准。其主线 `itemArt.ts/drawCarryBag` 用角色腰侧叶包承载缩略物品：包体 .65、小苔灵 .66，镜叶用叶片图示而非手持地面镜体，清露为 25 px 小包，门铃为包内矢量小铃。此语义替代此前自行提出的“地面与手中主体必须同大”；原生手锚和正常深度仍保留。云庭星种另有专用角色表达，不机械套主线叶包。

## 必须保留的项目语义

全15关硬底座、真实绕行/放置、默认双人可读性、原版地面拼接、1-4阶段提示与三章地图统一整改见 [76号](../../../../docs/76-全关场景与章节地图统一整改计划及验收.md)。该记录保存逐关审计、被看图否决的中间候选和最终版本证据；原站71号尺寸优先于70号候选，不能把旧通过当作新反馈已关闭。

1-4及2-2穿模修复读 [75号](../../../../docs/75-第四关与涟漪关穿模修复及验收.md)：局部硬石基、镜座与灯石防入和点击/跟随绕行联动，放镜前真实旁站、拾起/撤销清障碍，旧非法pose只修同层落点保留进度。2-2花坛在既有同高台面后右侧摆放以留出原接近方向；逻辑花坛/光源格、镜叶朝向和核心规则不变。此专项新增物理占地限制，不能称为纯贴图修改，也不能据此关闭性能问题。

- 主线实际ID为1-1…1-4、2-1…2-4、3-1…3-4；另有cloud-1…cloud-3。口语“1-12”不是运行ID。云庭状态不只来自JSON modules，需查 `cloud_garden_world.gd`。
- 1-1是用户认可的参考，不应为“统一”随意改它；复用其质量标准，不能复制其预算、坐标、每关台阶数。首关0.65、正式1-2的0.45物理层高不同是已记录设计，不能为道具比例改掉。
- 正式1-2当前12个固定格、4节根路、7个socket，两条绕行都必须到第四节才真正接岸；固定f:3:1/f:4:2已移除，布局revision2迁移保留旧进度。规划试玩与正式版分开。
- 当前楼梯生长按真实前驱方向裁切各面，不逐帧重建或压缩Y。回收是即时移除消失格，而非假称已有倒放动画。离岸外接梯收平封边，内部梯保持，落稳才建立新接岸梯。
- 主线满足ready不等于自动通关；需要合法位置主动repair及对应伙伴条件。可选收藏/观察不变为门槛。正式存档、纪念、重玩、试玩与旧TS导入保持隔离。

## 实现定位（读实际代码再改）

| 主题 | 入口 |
| --- | --- |
| 关卡与状态 | `godot/content/levels.json`、`godot/core/garden_world.gd`、`cloud_garden_world.gd` |
| 首两关尺度与装饰 | `godot/presentation/native/first_garden_profile.gd`、`second_garden_profile.gd`、对应 `*_dressing.gd` |
| 后续章节装饰 | `godot/presentation/native/chapter_garden_dressing.gd` |
| 贴图、表面与楼梯 | `native_surface.gd`、`terrace_materials.gd`、`chapter_surface_materials.gd`、`generic_stair_geometry.gd`、`stair_geometry.gd` |
| 坐标/支撑/生命周期 | `native_garden_stage.gd`、`godot/application/native_movement.gd` |
| 素材元数据 | `godot/content/visual-assets.json`；实际Sprite创建未必消费全部anchor元数据，需核对调用 |
| 镜头/效果 | `garden_camera_scale.gd`、`native_garden_effects.gd`、`native_garden_atmosphere.gd` |

## 有针对性的验证入口

从仓库根执行。先检查工具参数/测试文件仍存在，再按影响范围选择；输出使用新的批次目录，避免覆盖历史失败证据。

```sh
node tools/godot-migration/check-native.mjs --only=native_chapter_presentation_test,native_garden_effects_test --output=docs/qa-godot-native/quality-pass/props
node tools/godot-migration/check-native.mjs --only=native_surface_alignment_test,native_stair_lifecycle_test,native_route_test --output=docs/qa-godot-native/quality-pass/geometry
```

第一条适合装饰/效果定向检查，第二条仅在几何/楼梯/路线受影响时使用；检查数不作为画面正确的证明。浏览器脚本 `check-native-browser.py` 的capture模式用于取图，gameplay及专项脚本用于真实输入，不能混称；确认当前可用浏览器工具并按其适用说明使用，缺工具时如实记录实际采用的运行方式。

发布构建、原生数据与旧TS不是同一个入口。交付前核对当前服务 `__build.json`、运行源码摘要与实际资源；保留原origin的用户存档。Skill维护任务本身不需要重新导出、切换服务或运行游戏测试。
