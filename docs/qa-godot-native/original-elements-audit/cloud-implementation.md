# 云庭原矢量元素恢复：实现与验收边界

2026-11-11。原来源为 `src/app/cloud/renderer.ts`，对应源审计见[元素清单](source-cave-cloud.md)。主任务已核对远端JS/CSS与本地vite产物SHA一致。保留当前已认可角色、规则、真实地形和路径；本实现仅添加无碰撞装饰、标记与背景。

## 文件与接入

- `godot/presentation/native/original_cloud_art.gd`：逐个原矢量道具转为SVG，CPU栅格化并缓存，不使用整关截图。缓存区分种类与完成状态。
- `original_cloud_dressing.gd`：`scenery(stage)`、`planter(stage,parent)`、`build_mark(stage,parent,mark)`、`update(stage)`、`draw_background(stage,target)`；主stage负责接入。
- `godot/tests/native_original_cloud_test.gd`：CPU和规则隔离检查，不等同GPU验收。

`cloudSeed`、`observations`、`completed`需要进入stage装饰签名。动态读取既有`visual_time`，`update`跟随stage暂停时钟；`lowMotion`固定动态，`particles`控制瀑布滴粒，不删除水帘。点击/键盘操作继续使用原生action badge及命中区域，本helper不改交互。

## 原元素与状态

| 关卡 | 固定元素 | 完成变化 |
| --- | --- | --- |
| cloud-1 | 1大花盆、2小花盆、1长椅、1拱门、1钟塔 | 钟塔窗亮、藤蔓与花、窗星；原分布地面花 |
| cloud-2 | 1拱门、1水池、1大花盆、1长椅 | 水池填水、睡莲与花；鸟、水帘与3滴粒；原分布地面花 |
| cloud-3 | 1粉拱门、1长椅、2小花盆、1组5灯灯串 | 灯灰转金、灯上5星、上方3星；原分布地面花 |

地面花只生成于当前floor且`(x*7+z*13)%11==0`，故事被发现后生成3花。finish保留原双椭圆台和星，seed取走后消失。原版没有物理底座的门闩和未发现故事点不额外添加假机关。背景恢复各关天空渐变、光晕、3远岛、3云；cloud-3增加18颗背景星。

## 比例、脚锚与物理例外

原格横向58px对应原生投影宽`√2`世界单位，每源像素为`√2/58≈0.024383`。SVG以2倍栅格化，sprite pixel_size减半。卡片直立，Y按`1/cos30°`补偿投影缩短，不关闭深度。原绘制下缘`foot`先沿地面前移`foot×pixel/0.5`，sprite将此下缘锚在同一支撑高度，保留原源坐标投影；并非直接抬高整件物体。主体透明边距不参与比例。

| 道具 | 原横向主体宽/58 | 源脚锚Y | 备注 |
| --- | --- | --- | --- |
| 拱门 | `68×(.8/.9/.95)/58` | 15，按各关倍率 | 保留逐关原倍率和粉色变体 |
| 钟塔 | `84/58≈1.448` | 19.5 | 窗/花变化共用尺寸与锚点 |
| 水池 | `84/58≈1.448` | 30 | 干湿共用基座 |
| 长椅 | `40/58≈.690` | 12 | 原靠背保留 |
| 大/小花盆 | 植叶原椭圆轮廓 | 17 / 9.5 | 不统一放大 |
| finish | `32/58≈.552` | 8 | 星横宽24px |
| seed | `24/58≈.414` | 5 | 星与底盘分布保持原源像素 |

固定装饰从原逻辑点经`tile_position`映射，真实`NativeSurface.sample_height`校准源点高度，支撑ID记录在meta；卡片正Y底部保留原画地面延展。大件原本跨格，完整底部支撑、卡片遮挡和可辨性仍需GPU看图，CPU支撑ID检查不能代替这一步。

**瀑布明确例外**：原Canvas在`(10,4,h3)`右偏38px画水帘，直接转3D会穿过固体平台。现水源移到真实`floor:11:3`东岸`(11.5,3,h3)`，加短水唇，无碰撞，不造接水池；保留水帘原宽、落差、颜色与滴粒节奏。需要GPU检查水源是否衔接、落差消散和岸壁遮挡，不将原平面坐标机械当3D岸口。

## 本分工证据

[cloud-headless-2/checks.json](cloud-headless-2/checks.json)：单进程无头380项通过、运行期间源码稳定。覆盖23类独立资源及双状态缓存/非空/水平裁切，三关双状态原装饰分布、真实规则tile ID、没有碰撞、深度测试开启、世界/tiles不变、花种消失、故事花、瀑布时钟/减少动态/粒子设置、完成图变化但尺寸/锚点一致。

[首轮失败日志](cloud-headless-1/native_original_cloud_test.log)保留：测试误用Vector2i的`is_zero_approx`，修正为Vector2i.ZERO比较后重跑通过；不是运行时画面缺陷。

**状态：实现可接入，CPU验收通过；尚未完成集成GPU画面验收。** 本报告不声明三关画面已最终合格，发布构建、双尺寸普通视图、完成前后、路径与交互集成结果由主任务继续记录。当前采用独立原矢量卡片而非厚度建筑mesh，若实际遮挡不足，需要按真实支持面改几何，不能关闭深度或用全景截图覆盖。

## GPU候选反馈修正：鸟与升降标牌

实际查看了`original-level-restoration/candidate/1280x720/cloud-1/restored.png`、`cloud-2/restored.png`、`cloud-3/restored.png`，并与`reference-stroll/1280x720/cloud-2/final-canvas.png`对照。cloud-2鸟在原逻辑点(11,3,h3)被水池前壁遮住，只有尖角露出。原Canvas按绘制顺序把鸟放到池上，直接转有深度的3D不能照搬这种覆盖关系。

修正将鸟移至同一高台(11.2,4.4,h3)，支撑ID`floor:11:4`；原来源位置仍记入`source_point`，变化原因写入`placement_reason`。原高度、源像素大小和深度测试保持，鸟沿地面到池前缘；卡片平面较水池前移约.181世界单位，完整横向轮廓足点均落在现有高台上，没有增添碰撞、假台或抬高。

cloud-2的valve/dock恢复原中心y=-31、半径11的圆牌，牌内双向箭头用3条几何折线绘制，不用SVG文本/系统字体；原操作柱及椭圆底座保留。标牌属于现有独立3D道具，正常深度参与遮挡，不改命中区域与交互命令。

[cloud-visibility-headless-1](cloud-visibility-headless-1/checks.json)单进程CPU **400项通过，源码稳定**，包含全量原云庭资源检查及新增鸟同高/全横向支撑/池前平面、箭头上下端与中轴像素颜色、无字体依赖。没有启动GPU；本次修复后的可见性仍需主任务下一批截图复核。候选中塔顶出屏与桥/格材质由主任务分别处理，本分工未修改相机或地形材料。
