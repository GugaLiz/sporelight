# 原版元素审计：苔藓山谷与池塘（1-1 至 2-4）

日期：2026-11-11。用户指定的正确美术基准是 https://gugaliz.github.io/sporelight/ 每关的元素及比例。本报告只读审计本地 TypeScript 与当前 Godot native 实现；**本地源码是否与线上版本一致，待集成者核对远端资源、版本和截图**。本报告没有运行浏览器/GPU，没有修改玩法或运行时代码，不能作为恢复后的画面验收。

## 取证方法与机器清单

通过现有 esbuild 在内存中打包并直接执行本地 `GARDEN_LEVELS`、`GardenWorld`、`gardenScenery`、`pondBank`、`pondResidents`、`runoffSource`，得到最终关卡定义（包括 `levels.ts` 后半段的高差/地形调整），不是只读最初的 `out.push`。输出为 [source-valley-pond.json](source-valley-pond.json)：8 关全部地面装饰的资产名、逻辑坐标、高度、宽度、投影地块比例、初始 marks/items、岩石、隐藏花园、瀑布源、山谷藤蔓面和池岸绘制候选，并记录 6 个 TS 源文件、CSS、相关 PNG 的 SHA-256。

JSON 中 `widthPerTile` 是原版整张 PNG 的绘制宽度 / 地块屏幕宽度；`nominalHeightPerTileWidth` 是 PNG 等比例高度 / 地块屏幕宽度。**没有测量 PNG alpha 可见轮廓**，不能将这些字段误称为可见主体宽度。岸边绘制候选也不等于截图中无遮挡的可见数量。机器清单包含初始状态，不涵盖所有中途机关姿态。

来源入口：`src/app/garden2/scenery.ts:17`、`render.ts:32`、`render.ts:154`、`landscape.ts:50`、`gardenArt.ts:9`、`pondWeather.ts:54`；当前 Godot 对照入口为 `godot/presentation/native/*_garden_dressing.gd`、`scenery_scale.gd`、`native_garden_stage.gd`、`native_garden_atmosphere.gd`、`native_garden_effects.gd`。

## 尺度合同：以原版屏幕比例为目标，不直接搬世界单位

原版未缩放投影是 `screenX=(x-z)*35`、`screenY=(x+z)*17.5-h*48`。一格顶面是 **70×35 px**，一单位高差是 **48 px**，然后整个场景同乘 `renderer.scale`。因此一般装饰 30 px 对应 **0.429 个地块屏幕宽**，不是 Godot 0.429 世界单位；Godot 的相机方位、billboard 和地块斜投影会影响换算。恢复时应对相同视口、同一参考格测量资产可见主体，不能把 JSON 比例直接当 Sprite3D 宽度。

装饰以完整 PNG 等比例绘制：`height=width*naturalHeight/naturalWidth`，锚点 0.9，落点是投影坐标再向下 7 px。原版的这项锚点并不保证 3D 足点正确；Godot 应保持真实支撑，必要时移动装饰落点，不能靠抬空或虚假地块凑相同坐标。

| 原版元素 | 未缩放绘制参数 | 对 70 px 地块宽的比例 |
| --- | --- | --- |
| 默认花草/蕨 | 按装饰顺序 i：i%3=0 为 35，否则 30 | 0.500 / 0.429 |
| berry-bush / bush | 宽 39 | 0.557 |
| small-pebbles / river-rock / pebble-cluster | 宽 25 / 30 / 29 | 0.357 / 0.429 / 0.414 |
| stone-lantern / gold-lotus / lotus-pool | 宽 30 / 32 / 47 | 0.429 / 0.457 / 0.671 |
| 1-3 额外 arch / 2-4 额外 wood-lantern | 宽 90 / 40 | 1.286 / 0.571 |
| 1-4 花园固定花丛 / 灌木 / 灯 | 宽 42 / 46 / 29 | 0.600 / 0.657 / 0.414 |
| 主花床 flower→bloom | 宽 110，y+10，anchor 0.9 | 1.571，完整 PNG 比例 |
| 根台 vine / 功能小花 flowers→bloom | 宽 65 / 55，y+8 | 0.929 / 0.786 |
| 1-4 门框与封印 | 两者宽 112，y+13，anchor 0.93 | 1.600；开门仅封印缩 X、淡出 |
| 1-4 喷泉 | drawFountain size=92，内部缩放 92/90，池盆直径 86 | 池盆直径约 87.91 px，即 1.256 格宽 |
| 1-4 重杆 / 叶踏板 | 绘图 size=57 / 64；重杆偏移 x+28,y-8 | size 不是物体包围盒宽，需用图形实际范围核对 |
| 清露植物→包裹 | 宽 49→34，anchor 1 | 0.700→0.486 |
| 镜叶 / 光虫 / 普通收藏光球 | 宽 52 / 40 / 35 | 0.743 / 0.571 / 0.500 |
| 1-2 岩石 / 2-2 岩石 | 宽 38（alpha .65）/46 | 0.543 / 0.657 |

角色仅作为尺度参照：露薇完整 PNG 宽 115、anchor=236/256；小苔灵绘制 size=46；滚动球宽 68。不要为凑装饰比例修改角色、关卡高度或可走面积。

## 逐关实际地面装饰

此表只统计 `gardenScenery` 的返回结果，**不包括**每格悬垂藤、花床、机关、物品、瀑布、池岸、睡莲、芦苇、青蛙、天气。全部坐标与逐项宽度在 JSON；不能用一个通用数量替代。

| 关卡 | 数量 | 实际资产及数量 | 必须独立保留的内容 |
| --- | ---: | --- | --- |
| 1-1 | 6 | small-pebbles、pink-flowers、stone-lantern、yellow-flowers、red-mushroom、blue-flowers 各 1 | 根台、主花床、初始 7 个藤蔓面、瀑布源 f:4:0；当前 Godot 首关是另行设计过的参考，不能盲目回滚其物理地形。 |
| 1-2 | 3 | stone-lantern、yellow-flowers、red-mushroom 各 1 | 中央岩石、根台、主花床、初始 3 个藤蔓面、瀑布源 f:4:2。该 TS 固定格与现 Godot 正式 revision2 不完全相同，尤其瀑布源格已调整，需依现有支撑迁移而非恢复旧拓扑。 |
| 1-3 | 14 | red-mushroom×2、blue-flowers×2、gold-lotus×2；bush、berry-bush、fern、small-pebbles、pink-flowers、stone-lantern、yellow-flowers、arch 各 1 | 额外 arch 在 (-5,-1,0)，宽 90；初始 8 个藤蔓面；瀑布源 f:1:-3；四岛庭院转动的出入口保持。 |
| 1-4 | 19 | gold-lotus×3；bush、berry-bush、pink-flowers、stone-lantern、yellow-flowers、blue-flowers 各×2；fern、small-pebbles、red-mushroom、ivory-lotus 各 1 | 前区 12 件＋花园固定 7 件；喷泉、4 蝴蝶、门框/封印、鼹鼠、门铃、重杆、踏板、门闩、花床；初始 17 个藤蔓面，瀑布源 f:-10:2。 |
| 2-1 | 12 | blue-flowers、ivory-lotus、berry-bush 各×2；yellow-flowers、lotus-pool、pink-flowers、stone-lantern、fern、river-rock 各 1 | 清露植物/包裹、浮台小花、水阀、主花床；低/中/高水态；初始瀑布源 f:1:-3。 |
| 2-2 | 7 | berry-bush、yellow-flowers、lotus-pool、pink-flowers、stone-lantern、fern、river-rock 各 1 | 固定光源、两片编号镜叶、镜叶光槽、石壁、光线/箭头/焦点提示、主花床；初始瀑布源 f:5:-1。 |
| 2-3 | 4 | lotus-pool、pink-flowers、stone-lantern、fern 各 1 | 雨滴琴/动作叶、花台、门闩、主花床；旋转/升降/停拍提示；初始瀑布源 f:0:-3。 |
| 2-4 | 3 | stone-lantern、fern、wood-lantern 各 1 | 额外木灯在 (-5,-1,0)，宽 40；花粉/蜜花/光虫及载运状态；初始瀑布源 f:-2:0。 |

1-4 花园固定位置：五丛花在 (-11,-2)、(-11,2)、(-9,2)、(-7,-2)、(-7,2)，顺序为 pink、blue、yellow、ivory、gold；灌木在 (-11,0)，灯在 (-7,-1.7)。高度来自 sanctuary 当前格（前者多为 h=2，右侧 h=1）。喷泉位于 (-9,-2,h=1)，蝴蝶使用这些花朵的投影位置和图像高度×0.70 作为停靠参考，非随意绕圈光点。

## 生成规则与池塘环境的额外清单

`gardenScenery` 候选必须不是 small/solid/water、不是起点/伙伴/收藏格，距功能 landmark 曼哈顿距离至少 2，距机关未来扫掠范围及根 socket 大于 1，并且有缺失邻格的边缘。按 x+z 稳定排序，每件与已有装饰曼哈顿距离至少 1.3；普通部分上限 13。边缘方向优先 `(-1,0),(0,-1),(1,0),(0,1)`，向该边缘偏移 0.24；资产索引用 `(当前件数+关号末位*2)%palette.length`。特殊花园与额外 arch/灯在普通上限之后追加。

山谷有 10 种普通 palette，池塘有 9 种，不能缩成 3 种。山谷每个可见侧面另计算藤蔓：`abs(x*19+z*31+(left?3:0))%3==0` 且侧面深度>25 px；长度 `min(depth*.75,85)`、宽 `min(24,length*imageAspect)`，裁切在墙面内。JSON 的藤蔓面数为初始几何结果，不代表所有面都在画面无遮挡；也不是统一每关两条藤蔓。

池塘在 `drawPond` 中独立生成如下层次，不能因 `gardenScenery` 少于六件而判定“环境已经齐全”：

| 关卡 | 有机岸线采样点 | 岸边 PNG 绘制候选 | 额外后岸灌木 | 青蛙/叶座 |
| --- | ---: | ---: | ---: | ---: |
| 2-1 | 48 | 25 | 2 | 2 |
| 2-2 | 36 | 19 | 2 | 2 |
| 2-3 | 42 | 22 | 2 | 1 |
| 2-4 | 36 | 19 | 2 | 2 |

上表岸线采样数由 JSON 实际计算；岸边候选包括石、蕨和后侧灌木，各项索引/坐标/宽度在 JSON。全部仍需远端截图确认可见轮廓。

- 岸线取固定地块及移动平台两个端点，向八方向各扩张 **3.2 逻辑格**，取凸包再每角采样 3 点平滑。岸边再加 x=sin(i*.7)*.42、z=cos(i*.9)*.36 扰动。
- 苔岸团块：i%3!=0，椭圆半径 x=10+seed%18、y=5+seed%7；`seed=i*29%67`。石 i%5=0，river-rock/small-pebbles 交替，宽 22+seed%16；蕨 i%4=1，宽 20+seed%10；背侧灌木 i%13=4 且屏幕 y<65% 岸线范围，宽 33+seed%13。叶片 i%7=2。
- 后方两个草岸团块位于背岸点序的 .18/.76，半径 62×23 / 48×18，分别带 bush 宽 53、berry-bush 宽 44。
- 水面有四色渐变、water-pigment alpha=.4、背景倒影 alpha=.055、岸缘暗浅线；不是单一蓝色矩形。初始水高 2-1 为 -.55，随阀位每档 +.18；其余 -.5，平台升降不等于整个水面同步升到岸顶。
- 水上网格种子 `abs(x*37+z*61)`：%3=0 画波纹；距实际地块曼哈顿距离<1.6 则跳过装饰；%7=0 画睡莲，宽 19+seed%11、高为宽*.54，偶数种子再画小莲花；%13=0 画四枝芦苇，主体高 21/33，顶部再延长 5 px。全部受有机水面裁切，因此算法候选不能直接当可见数量。
- 青蛙最多 2 只，排除靠地面/机关扫掠区；叶座 **44×21 px**，青蛙身体为独立矢量多部件，有眨眼与轻微浮动，不是移动平台镜叶。
- 雨层正常宽屏 76、窄屏 38；前后雨层共用同一列表，不能重复算 152。另有 23 个落水候选，排除近岸，包含雨滴→冲击→双环过程。lowMotion 或关闭 particles 会停用对应雨效果。
- 瀑布每关按最高且靠东的合法南边缘选一个源，不在模块/small/solid/mark 格生成。山谷落差 2.8h，池塘落到实际水面；原版主宽 10 px、底部扩到约 18 px，附入水浅池、3 道流线和 3 圈水纹。不能把瀑布删掉当作性能优化。

## 对照当前 Godot native 的具体差异

1. `garden_landscape.gd:330` 中虽存在大体移植的原版 scenery 算法，但 native 舞台 `_add_scenery()` 在 `_dressing != null` 时直接调用 dressing 并返回。**旧算法存在不代表当前画面使用了它。**
2. `chapter_garden_dressing.gd:31` 当前按 tile id 排序和 hash 筛选，普通装饰上限 6，山谷仅 fern/pink-flowers/red-mushroom，池塘仅 blue-flowers/fern/yellow-flowers，第一件强制变灯，藤蔓最多 2。这改变了原版的品类、密度、位置和特例：1-3 14 件/arch、1-4 19 件/五种花、2-1 12 件/莲池与岩、2-2 7 件/莲池等均不可能被该规则完整表示。
3. 1-2 的独立 dressing 是灯＋六株花草＋两条藤，并不是原版三件；1-1 也是另行手工布置。用户这次选择原版后，需逐项比对差异和实际支撑，不应把过去的“首关候选大小”当作所有原版资产的比例答案，也不应误称原版每关都更密。
4. `scenery_scale.gd` 仅记录九类、候选宽度 fern=.44 / pink=.34 / blue=.30 / yellow=.28 / mushroom=.27 / stone-lantern=.43 / wood-lantern=.40 / vine=.23。缺少 berry-bush、bush、ivory/gold-lotus、lotus-pool、river-rock、small-pebbles 和 arch 的原版恢复契约；这些世界宽度也未建立对原版 70 px 格宽的同屏映射。
5. native 已有瀑布、雨滴、雨击、喷泉水流、4 蝴蝶；不能笼统称全部缺失。但 sanctuary 当前蝴蝶锚点取固定格+0.42，而通用 dressing 未补齐原版五组花，会出现有停靠逻辑却无对应花丛的问题。喷泉当前有模型轮廓，需对照原版池盆比例及苔/小花细节。
6. 对 native `.gd` 搜索未找到 `pondResidents`/frog、lotus-pool、独立 pond bank/reed 的实现；lilypad 仅出现于机制镜叶/踏板，不等于池面装饰睡莲。目前可确证“存在天气”而不能据此声称“有机池岸、石蕨灌木、睡莲芦苇、青蛙已恢复”。这些是第二章重点缺口，仍需集成者核对其他实际执行路径和截图。
7. 现 Godot 1-2 revision2 接岸、楼梯/碰撞、3D 实体承托和相机已与 TS 实现不同。原版资源清单只能驱动表现层恢复；不可复制 TS 旧 f:3:1/f:4:2 等逻辑格来恢复装饰，不可改变预算、模块轨迹、通关/伙伴条件。

## CSS 与镜头影响

`src/styles/garden2.css` 让 canvas 填满容器，场景内 PNG 不是由 CSS 单独设宽。尺寸主要由 renderer 投影/scale 控制，CSS 控制头部、工具条和提示遮挡。原版桌面 scale 上限山谷 1.5、池塘 1.28，自动拟合预留宽 330、高 185；窄屏普通视图固定 scale=.92 并跟随人物，overview 改全景拟合。取对照图必须固定普通/全景、视口/DPR、初始/机关状态及 UI；不能从不同镜头截图推算“统一放大几倍”。

## 恢复与验收顺序建议

先由集成者验证远端版本和至少 1-3 / 1-4 / 2-1 / 2-4 的截图，再以本 JSON 为逐关资产与布局初稿。逐关恢复对象品类及特殊装饰，在当前实体地面上找合法落点，随后校准同屏相对宽高；完成一关记录已恢复/有意保留差异/待验证，再进入下一关。

每关最低证据应包括初始原图、代表机制开始/中途/落稳/撤销、原版对照、地块与主体宽度比、遮挡和足点检查；池塘另检查岸线、水生装饰、青蛙、降雨开关与低/中/高位。玩法检查仍使用当前 Godot 合同，所有恢复的环境装饰不添加可走碰撞、不改变光路阻挡、不进入机关扫掠区。数量清单通过不等于视觉验收通过。
