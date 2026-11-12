# 全关卡位置整理：独立视觉复核

2026-11-11。对应[72号计划](../../72-全关卡位置整理计划与验收.md)。本页只记录独立验收者实际查看的画面与读取的证据，不替代完整路线、性能或发布验收。71号历史结论及530张截图统计不改写。

## 首批候选：尚未通过完整视觉验收

源码摘要 `363c9ca6569af23eff331128ff7e2734562894b15f0484bce0210277f554a783`，572个源文件，Godot 4.7.2 debug Web。尺寸1280×720、844×390；每一尺寸分别查看普通跟随与全景。检查JSON记录实际viewport，未显式记录DPR，本页不补造DPR值。

本批固定装饰已有同高落点和完整底面检查，实际画面也显示多处改进；但CPU平面互不相交没有防止投影遮挡。以下五项保留待修，不能因[自动30例通过](all-levels/checks.json)而将本批写成全视觉通过。尺寸保持冻结，不通过缩小、抬高、关闭深度或新增地块消除问题。

### 实际看图范围

| 证据批次 | 已实际查看 | 可以支持的结论与边界 |
| --- | --- | --- |
| [sample-first](sample-first/checks.json) | 1-3 × 双尺寸 × arrival/completed/completed-clear/overview，8张原图 | 代表关空操作区及固定装饰的初步位置复核；不是四朝向动态证明 |
| [all-levels](all-levels/checks.json) | 全15关 × 双尺寸 × 上述4状态，120张原图，全部查看 | 初态、准备完成态、真实清场行走后、全景的可见表现；准备完成态不等于从头通关 |
| [sample-motion](sample-motion/checks.json) | 1-3每尺寸7张，共14张：000-before、frame-000/003/006/009/012、999-settled | 一次真实 `turn:garden` 的选帧检查；没有查看全部rAF帧，也没有覆盖四个旋转朝向。两个视口相同frame索引不代表相同动画进度 |

本轮共实际查看**142张原图 = 128张静态证据 + 14张运动选帧**，不含修改前重看的历史图，不与71号历史530张相加，不把图片数量表述成独立玩法状态数。运动样本可见固定岸装饰不随旋庭漂移、乘员留在平台、接岸梯在落稳后出现；它同时暴露默认操作站位遮牌的问题。

### 待修项与复验门槛

本页P编号只是本批局部索引，不替代69号稳定问题编号。

| 编号 | 实际现象和证据 | 返修后必须重新确认 |
| --- | --- | --- |
| P-01 默认操作站位遮控制牌 | 1-3真实操作前和落稳后，人物帽子/身体几乎遮住圆牌，桌面落稳仅露牌边；空平台图则清楚。见[桌面操作前](sample-motion/1280x720/motion/1-3/turn-garden/000-before.png)、[桌面落稳](sample-motion/1280x720/motion/1-3/turn-garden/999-settled.png)、[小屏落稳](sample-motion/844x390/motion/1-3/turn-garden/999-settled.png)。 | 保留逻辑中心、交互圈与尺寸，真实到达默认操作点后牌仍可辨；旋转各实际朝向/运动中/落稳后保持相对位置。若改默认站位，完整原路线与撤梯占用保护必须重新通过，不能放宽保护掩盖回归。 |
| P-02 3-4石灯被核心遮住 | arrival/completed/clear均只剩灯下部发光窗口，灯顶埋在核心基座后，是位置调整引入的明显退化。见[桌面清场](all-levels/1280x720/3-4/completed-clear.png)、[小屏清场](all-levels/844x390/3-4/completed-clear.png)。 | 同高合法空位中让整盏灯和基座可读，不挤核心、低门、鼹鼠及角色操作空间；初态和完成态双尺寸复看。 |
| P-03 2-4石灯挡伙伴 | 灯从核心后移出后本体清楚，但完成默认站位的小伙伴脸/身体被灯遮住大部。清场行走后伙伴重新显露，说明是默认站位投影相交。见[桌面完成](all-levels/1280x720/2-4/completed.png)、[小屏完成](all-levels/844x390/2-4/completed.png)。 | 灯、主角和伙伴在默认完成/会合站位同时可读；保留远岸授粉后的真实支撑和靠岸区。不能以清场后可见代替默认站位修复。 |
| P-04 1-4石灯与白莲竖叠 | 两物在完成及清场图仍位于同一投影线，灯挡莲的根部/叶心，视觉像花长在灯顶；双尺寸一致。见[桌面清场](all-levels/1280x720/1-4/completed-clear.png)、[小屏清场](all-levels/844x390/1-4/completed-clear.png)。 | 同高内园边带分离两个主体及根/基座，不占楼梯、花门与操作区；不能只凭底面不相交关闭。 |
| P-05 cloud-2观察花仍在清场脚边 | 默认完成站位已比原来分开，但实际清场行走后脚部仍与左侧黄花茎相交，双尺寸可见。见[桌面清场](all-levels/1280x720/cloud-2/completed-clear.png)、[小屏清场](all-levels/844x390/cloud-2/completed-clear.png)。 | 将指定观察/清场位置的花、人、小鸟进一步错开并保留台面支撑；这是本次指定位置的复验项，不泛化为玩家任何手动站位都不得遮花，更不能据此直接判定碰撞阻路。 |

### 逐关观察

下表每关均看完双尺寸各4张。没有发现新问题只适用于本批已采状态；不代表未知朝向、水位、全部可选操作或性能通过。

| 关卡 | 实际画面结果 | 当前独立结论 |
| --- | --- | --- |
| 1-1 | 专用花床、灯、核心与楼梯关系保持，未见新增悬空或挤占。 | 已采静态位置回归未发现问题；作为保留基准。 |
| 1-2 | 两岸灯/花/蘑菇落地，专用安全映射保持。红菇在人物靠近时淡出属于既有遮挡处理，不能误记为删除。 | 已采静态位置未发现新问题；上下两解/第四节接岸须引用独立真实输入结果，本图不能证明两解。 |
| 1-3 | 岸边灌木、蘑菇和南岛石灯调整后底部有支撑，拱柱落地；四岛轮廓保留。核心前灌木在人物靠近时淡出。 | 固定装饰已采画面未见支撑问题；P-01未关闭。 |
| 1-4 | 花床、喷泉、花门、核心及鼹鼠支撑关系保持；灯与白莲仍叠放。 | P-04未关闭。 |
| 2-1 | 核心右侧岩石完整显露，低岸莲池支撑完整，中台机制花床保留。 | 已采画面未见新问题；不是全部三水位视觉证明。 |
| 2-2 | 灯与大阻挡石已有分离，花草及莲池落地，镜叶/光路仍可见。 | 已采位置未见新问题；通路与自由放镜由逻辑/实体验证承担。 |
| 2-3 | 高岸石灯与入口清楚；拱仍在核心左后，门洞可辨，两柱未见离地。清场后人物与前花分开。 | 未发现新增硬缺陷；不将相邻花冠投影接近自动判成碰撞错误。 |
| 2-4 | 石灯本体从核心后显露，远蕨在清场时可读；近木灯灯笼在帽子侧仍可辨。 | 新灯位遮伙伴，P-03未关闭。 |
| 3-1 | 蓝菇靠桥侧但入口仍清楚；暗态隐藏区域保持，低门与蕨有部分投影叠合。 | 已采状态未发现新增支撑问题；不把暗区初态未显示误记为丢元素。 |
| 3-2 | 灯位从桥接头退开；蓝花在核心左侧，与蓝菇局部重叠但身份及脚部仍可辨。日/月柱保留。 | 已采位置未见新增硬缺陷；记忆影与实时影路线另验。 |
| 3-3 | 核心旁晶体完整显露，灯与右侧操作区分开，前蓝菇在人靠近时淡出。 | 已采状态未见新增支撑问题；旋转/分水完整状态另验。 |
| 3-4 | 左侧碎石清楚，鼹鼠仍在前右合法位置，远塔及右侧晶体保留；灯主体埋在核心后。 | P-02未关闭；不以鼹鼠已通过推定新灯位通过。 |
| cloud-1 | 终点盆与地面星标分开，塔底完整，花链/门清楚；普通镜头远拱顶部有裁切，全景完整。 | 未见新增位置问题；远拱镜头裁切不作为搬建筑的理由。 |
| cloud-2 | 默认完成站位花与人/鸟已分离，方池、水口、绿台支撑保持；清场后仍踩花茎。 | P-05未关闭，需针对指定清场/观察站位复验。 |
| cloud-3 | 中岛花簇不再压控制台，盆与花分组，门/长凳/终点星标清楚，粉桥保持。 | 已采位置未发现新增问题；转桥动态由专项补证。 |

### 与自动、玩法和发布证据的关系

- [headless](headless/checks.json)是支撑/路径等自动结果；数值检查不能关闭上述主体可见性问题。
- [1-2真实输入](second-input/checks.json)与[1-4真实输入](sanctuary-input/checks.json)由主验收执行，本独立看图页不冒充亲自重走，也不将准备完成态变成完整浏览器通关。
- 修后图需保存到新目录并标明新源码摘要，保留本页首批失败证据。放行还需要原路线、默认操作占用保护、受影响动态和正式包实际资源一致。
- 本轮不新增性能通过结论，GQ-011按69/71号保持开放。

## 修后复验

### f79f639c定向静态复验

新源码 `f79f639ca207a8d39426aa680d90e9bd9f55c701dbf3eec3968e4b77a7c10974`，572文件；[final-visual检查清单](final-visual/checks.json)明确为同源码**debug**构建。不是正式release包截图：最初向release请求QA接口超时的过程由主任务另留记录，不能把后续debug准备状态的图标为release实玩。

独立查看1-3、1-4、2-1、2-4、3-2、3-3、3-4、cloud-2八关的双尺寸arrival/completed/completed-clear/overview，**64张原图全部查看**。首批142统计不变，本位置专项累计独立看图206张，其中运动仍只有首批14张选帧，其他192张是静态证据。

| 问题 | 此批实际结果 | 结论 |
| --- | --- | --- |
| P-02 3-4石灯 | 灯移到核心左侧，灯顶、窗口、完整基座都可见，初态/完成/清场均没有埋入核心，低门与鼹鼠关系保持。见[桌面](final-visual/1280x720/3-4/completed-clear.png)、[小屏](final-visual/844x390/3-4/completed-clear.png)。 | 本项视觉关闭。 |
| P-03 2-4伙伴 | 默认完成站位中灯与伙伴横向分离，伙伴帽、脸与身体清楚；清场后仍正常。见[桌面默认完成](final-visual/1280x720/2-4/completed.png)、[小屏默认完成](final-visual/844x390/2-4/completed.png)。 | 本项视觉关闭。 |
| P-04 1-4白莲 | 灯与莲各自具有独立轮廓和基部，没有再呈现花叠在灯顶，保留内园通道和喷泉位置。见[桌面](final-visual/1280x720/1-4/completed-clear.png)、[小屏](final-visual/844x390/1-4/completed-clear.png)。 | 本项视觉关闭。 |
| P-05 cloud-2观察花 | 指定清场站位的花茎已在主角左侧，双脚/地面影与花分开，小鸟也清楚；默认完成站位保留分离。见[桌面](final-visual/1280x720/cloud-2/completed-clear.png)、[小屏](final-visual/844x390/cloud-2/completed-clear.png)。 | 指定站位问题视觉关闭；不承诺任意手动站位零遮挡。 |
| P-01默认控制牌 | 1-3空台控制器横向摆放，2-1初态牌从人物侧边可见，3-2初态符号也可见；这些静态图未覆盖1-3真实默认操作四转。 | 等instrument-input和动态复验，不提前关闭。 |

**新发现P-06：3-3完成态控制器杆/基座消失。** 在[f79f桌面清场](final-visual/1280x720/3-3/completed-clear.png)及[小屏清场](final-visual/844x390/3-3/completed-clear.png)中，左侧turn控制器只剩圆牌，杆和基座被前方高台遮住；completed同样如此，arrival则完整。对照[363c同机位清场](all-levels/1280x720/3-3/completed-clear.png)，旧位置有完整杆和基座。这是新侧移在该朝向引入的明显表现退化，不能以轮面符号仍可辨就宣称整个控制器正确。原因暂按邻接高台遮挡/实际支撑待核，不凭截图断言碰撞下沉。需核实实际同高支撑、偏移父级及各朝向遮挡，再补双尺寸完成/清场和操作过渡。不得抬高牌、关闭深度或放宽撤梯保护消除现象。

其他已采图没有发现新增底座越界或桥口退化。此批仍未整体视觉放行：P-01待动态，P-06待修。

### f79f639c实际操作站位复验

[instrument-input](instrument-input/checks.json)同为f79f639c/572 debug，QA仅准备前置条件，其后的四次旋转和两次日/月切换通过真实输入执行。本次独立查看1-3双尺寸00～04-operation各5张、3-2双尺寸00～02-operation各3张，**16张全部查看**。包含四次旋转落稳后的方向和回到起始方向，不是动画每帧。新增后本专项累计222张独立原图（128首批静态+14首批运动选帧+64修后静态+16真实操作静帧）；同图重复对照不计数。

P-01原来的主角挡整块圆牌已有改善，但默认伙伴站位引入互相遮挡，**尚不关闭**：

- 1-3的00/04操作站位，圆牌盖在伙伴面部前，只露红帽和局部身体。见[桌面00](instrument-input/1280x720/1-3/00-operation.png)、[小屏00](instrument-input/844x390/1-3/00-operation.png)。
- 1-3旋转到02时，伙伴帽子遮圆牌下半，牌不再完整，见[桌面02](instrument-input/1280x720/1-3/02-operation.png)、[小屏02](instrument-input/844x390/1-3/02-operation.png)。01/03方向分离较好，不能用这两向代表四向。
- 3-2日/月操作的三张默认站位，伙伴同样位于牌后，面部大部被盖住。见[桌面00](instrument-input/1280x720/3-2/00-operation.png)、[小屏00](instrument-input/844x390/3-2/00-operation.png)。

这是与P-03灯挡伙伴一致的默认站位可读性问题，不能只检查主角alpha与轮面射线便关闭。修正须将伙伴实际轮廓纳入各方向，保持正常深度、角色/控制器尺寸、连续刚体随动、完整支撑与离岸占用保护。当前不将这些遮挡推断为路线失败。

### 中间候选的独立复验记录

以下两批保留过程证据，不改写为最终源码：

- `fa415c8d8320c69a754770865fd9812fdcacfd19230d5d0e41f069d53faaac58` /572，位于仓库 `.tmp/mechanism-buddy-water-candidate6/`。实际查看 `gpu-instrument` 的1-3双尺寸各5张、3-2双尺寸各3张，以及 `gpu-water` 的3-3双尺寸各4张，共24张原图。普通turn、日/月的伙伴脸和符号已经分开；3-3完成与清场的杆/基座恢复。此批没有独立检查lift例外，不作全机关通过结论。
- [reviewed-instrument](reviewed-instrument/checks.json)为 `7709273e09a34cb40f9958984615a0436bcb8d4b8771c44bc571cd03a37683e4` /572。只查看3-3/valve-lift双尺寸各3张与3-4/turn-light双尺寸各5张，共16张原图；不是独立看完该目录全部42张。所看轮面及角色脸可辨认；旧light底座净空问题仍需后继候选的实际支撑证据，不能仅凭截图关闭。

### 974eda68最终候选的静态与实际操作复验

本节对应源码 `974eda6805323f695f8d042653fec40f8e699acd25f760dd32062b780887e9bb` /572，Godot 4.7.2官方debug Web。直接读取以下检查清单确认摘要一致；这些图片仍是debug QA，不是无QA正式入口截图。

| 批次 | 独立实际查看范围 | 结果 |
| --- | --- | --- |
| [accepted-visual](accepted-visual/checks.json) | 1-3、2-1、3-2、3-3、3-4，双尺寸各arrival/completed/completed-clear/overview，共40张原图全部查看 | 3-3杆和底座完整恢复，3-4灯仍完整可见，2-1伙伴移到牌侧且面部可读；已采静态图未发现新退化。 |
| [accepted-instrument](accepted-instrument/checks.json) | 每尺寸1-3五张、3-2三张、3-3 turn-water五张、3-3 valve-lift三张、3-4 turn-light五张，共42张原图全部查看 | 四向旋转、日/月、升降落稳及light双人四转中，控制符号和伙伴面部可辨；没有再出现圆牌遮住整张脸。 |

P-01在上述默认操作站位和已采朝向内**视觉关闭**。重点证据包括[1-3起始](accepted-instrument/1280x720/1-3/00-operation.png)、[1-3反向](accepted-instrument/844x390/1-3/02-operation.png)、[日/月](accepted-instrument/1280x720/3-2/01-operation.png)、[lift上层](accepted-instrument/844x390/3-3/valve-lift/01-operation.png)、[light第二向](accepted-instrument/1280x720/3-4/turn-light/02-operation.png)。验收允许主角与跟随伙伴的正常局部叠合，以及控制杆局部被角色遮挡；不要求任何角度两个角色全身轮廓完全独立，不为帽沿重叠继续把角色挤出平台。符号与面部的主要辨识特征仍须可读。

P-06在双尺寸静态完成/清场和实际turn-water四向落稳中**视觉关闭**，见[桌面清场](accepted-visual/1280x720/3-3/completed-clear.png)、[小屏清场](accepted-visual/844x390/3-3/completed-clear.png)、[真实转水落稳](accepted-instrument/1280x720/3-3/turn-water/02-operation.png)。先前P-02～P-05的已采修复结论保留；本节不冒充对那些未改变关卡再采了一整轮图。

### 974eda68运动选帧与残余可读性边界

[accepted-motion](accepted-motion/checks.json)源码摘要同上，22个自动用例通过。独立查看**22张六帧拼图**，每个尺寸各11种操作：1-3 turn-garden、2-1 valve-water、2-4 turn-boat、3-3 turn-water/valve-lift、3-4 turn-inner/turn-light/valve-lift、cloud-1 rotate、cloud-2 lift、cloud-3 rotate。每张含实际采样的起点、约25%/50%/75%/100%及落稳后，标注observed进度，不用相同帧号假定两个视口进度一致。只看拼图中的选帧，不声称逐张看完所有rAF原图，也不由六帧推定帧率稳定。

已采运动中，主线平台、人物与控制器相对位置保持，固定岸装饰没有随旋庭漂移；接岸随落稳显现，未见新增浮空、离台或控制器基座被高台吞掉。3-3的[转水桌面六帧](accepted-motion/1280x720/motion/3-3/turn-water/keyframes-sheet.png)与[小屏六帧](accepted-motion/844x390/motion/3-3/turn-water/keyframes-sheet.png)补足P-06过渡检查。cloud-1/3旋桥和cloud-2升台在所看选帧里按预期运动；这不替代整条通关路径证明。

另外独立放大查看cloud-2 lift和cloud-3 rotate的双尺寸before/settled，共8张原图，确认两处尚需主任务核实的角色可读性现象：

- **cloud-3操作站位被粉门遮住大部。** [桌面before](accepted-motion/1280x720/motion/cloud-3/rotate/000-before.png)与[桌面settled](accepted-motion/1280x720/motion/cloud-3/rotate/999-settled.png)主要只露帽侧和少量衣服；[小屏settled](accepted-motion/844x390/motion/cloud-3/rotate/999-settled.png)可见部分面部。门是实体前景，不是正常伙伴跟随的局部重叠。此批不能写成“所有默认操作点人物清楚”。本次门仅作完整底座微移；是否原有问题、以及QA准备位置是否等同自然行走停步点，须结合真实路线核实，不能凭截图断言此次新增或直接判成路径失败。
- **cloud-2低位升台开始时人物被高台挡住。** [桌面before](accepted-motion/1280x720/motion/cloud-2/lift/000-before.png)、[小屏before](accepted-motion/844x390/motion/cloud-2/lift/000-before.png)可见下层伙伴和主角帽尖，升到上层后恢复正常，见[桌面settled](accepted-motion/1280x720/motion/cloud-2/lift/999-settled.png)。保留真实深度和上下层遮挡，不能用抬高sprite或关闭深度伪装修复；是否需要同层站位调整由主任务核实。

以上现象已反馈主任务；本页此刻只关闭P-01/P-06，保留云庭操作位的核实边界，不把自动22例通过扩张为所有角色可见性通过。GQ-011性能问题继续开放。

### 本位置专项独立看图累计与证据限制

本页累计**352张独立原图 + 22张六帧拼图**：首批142、f79f静态64、f79f操作16、candidate6选图24、7709选图16、974eda静态40、974eda操作42、974eda云庭运动原图8。拼图包含132个已看画面，但不再次按132张独立原图累加；重看对照图也不重复计数。该统计仅属于72号位置专项，与71号的530张原图及22张拼图分开。

主任务提供的CPU站位1251项通过可由[日志](accepted-headless/native_instrument_stance_test.log)核对。accepted-headless的旧mechanism_props硬编码坐标失败原样保留；同一974eda源码的[accepted-axis-contract补验](accepted-axis-contract/native_mechanism_props_test.log)267项通过，不改写旧失败。完整路线、碰撞/梯口保护、正式入口及资源一致性由主任务的独立验收记录承担；本独立看图报告不将读取自动结果说成亲自玩完15关，也不以CPU结果替代上述画面发现。

## 1e1f3f3d最终补验：位置专项视觉可交付

最终源码 `1e1f3f3d126699eff348f5100808689e5f40b6819ecafface3b0aa52cf4c5a51` /572。主任务将cloud-3控制格的默认停步点调整为主角 `(.30,-.30)`、伙伴 `(.48,-.05)`，通过 `MechanismProps.standing_offset` 应用，保留明确的手动保存姿态；粉门、地图支撑和控制逻辑根保持不动。本节使用同摘要的新增debug证据，不把974eda旧截图改称新源码。

独立逐张查看[complete-cloud-natural](complete-cloud-natural/checks.json)双尺寸natural-arrival/after-rotate，共4张原图。检查清单明确先准备前一真实地块，再真实走到控制器并执行rotate；不是直接放到修后站位拍照。[桌面自然到达](complete-cloud-natural/1280x720/natural-arrival.png)、[小屏自然到达](complete-cloud-natural/844x390/natural-arrival.png)中人物在粉门右侧，主角侧脸、帽和伙伴面部可读；[桌面转后](complete-cloud-natural/1280x720/after-rotate.png)、[小屏转后](complete-cloud-natural/844x390/after-rotate.png)保持该关系，没有再被门遮到只剩帽沿。人物与控制盘存在正常局部重叠，脚部仍在台面内。

另逐张查看[complete-cloud-motion](complete-cloud-motion/checks.json)的[桌面六帧拼图](complete-cloud-motion/1280x720/motion/cloud-3/rotate/keyframes-sheet.png)、[小屏六帧拼图](complete-cloud-motion/844x390/motion/cloud-3/rotate/keyframes-sheet.png)，并分别放大两尺寸000-before/999-settled，共4张原图。实际旋桥起、中、止的采样画面中，人物与粉门分离，控制盘、桥端和同高脚部保持，未见新漂浮或接岸退化。独立没有逐张查看该目录所有rAF原图，不将两张拼图表述成全部动画帧。

**P-07（上节cloud-3门遮操作位）在自然行走到达、真实旋转和所采动态状态内关闭。** P-01～P-06已修项目结论继续有效，本位置专项未剩已确认的阻断性视觉问题，可以交付主任务整合。正式release入口及资源一致性仍以主任务发布验收为准，本报告没有把debug证据称为release实玩。

cloud-2的低位遮挡核实为既有3D高差边界：[71号所引用的正式包复核](../original-level-restoration/release-review.md)已明确记录“前高岸对低位角色的正常遮挡保留”；此前[候选复核](../original-level-restoration/candidate-review.md)也将低位人物自然遮挡与当时绿顶缺面区分。本次没有改动该高岸/升台几何或低位站位，所看动态升高后人物正常露出；不为这项既有深度关系搬高岸、抬人物或关闭深度，也不把它列成此次未修回归。

读取[complete-validation](complete-validation/checks.json)确认最终摘要稳定且通过；其中[全15关路线日志](complete-validation/native_route_test.log)记录1826项、477步、19334采样、15条路线全部完成。该项是主任务执行的自动路线证据，独立视觉审核没有冒称亲自重走。GQ-011性能边界保持开放。

最终位置专项独立累计为**360张原图 + 24张六帧拼图**，即上一节352/22再加本节8/2；与71号历史530张原图和22张拼图继续分开。所有历史失败与中间候选结论保留，不覆盖成最终通过。
