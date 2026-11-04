# Godot 迁移实施与体验打磨记录

开始实施：2026-11-04。更新日期：2026-11-05。

参考版本：5791bbc3dd90549b4c7ea302507ead577f51dd67。

状态：主线迁移候选已可运行；用户试玩后的操作、人物走停、HUD遮挡与重复计算精修已形成可验收版本。此记录不是整份计划完成声明。

## 当前入口

- 原版：http://localhost:4174/，原实现保留。
- Godot Web 正式候选：http://localhost:4185/，release导出、仅本机监听、独立存档；即使URL带qa=1也不暴露测试桥。
- 独立debug验证：http://localhost:4186/，同一运行源码指纹，显式qa=1才开放测试诊断。
- Windows 候选：godot/build/windows/Sporelight.exe，与同目录 Sporelight.pck 配套。
- 旧版旅程备份：http://localhost:4174/migration-export.html，仅用户点击后读取并下载，不修改旧 localStorage。

候选主线 12 关可玩，菜单、设置、纪事回看、图鉴内容与旅程导入导出已接入。云庭 3 关仍是后续独立范围，其旧数据原文可保留。完整首页小剧场、插画地图、图鉴书册版式尚未逐项复现，目前使用纸面菜单和内容入口。

## 四 agent 实际分工

| 角色 | 工作 |
| --- | --- |
| 主 agent | 工程/公共契约、输入动画协调与集成、运行环境、双端导出、基线/布局/交付验证 |
| 规则 agent | 12关 GDScript 规则、JS 逐步对照、归一、控制器/应用回放、真实 Web 键鼠 |
| 画面 agent | 原图白名单、等角地形/角色/机关/程序美术、GPU 与动态绘制测试 |
| 界面服务 agent | 纸面 HUD、设置、图鉴/纪事、存档迁移/失败恢复、音频、合法中文字体 |

共享主场景与工程配置由主 agent 维护。每批写入和实际检查统一追加 agentchanges/CHANGELOG.md。

## 已取得的技术结果

- Godot 4.7.2.stable.official.ed1daf0bf，Compatibility；官方编辑器 ZIP SHA256 与 Authenticode 签名有效。
- 官方 Web/Windows 模板按 HTTP Range 提取，逐条目长度和 ZIP CRC32 验证；未宣称对未完整下载的 1.28GB 模板包验证 SHA256。
- 124 个运行图片 alias 复制前后 SHA256 一致，未替换原图。
- 现有声音按原 WebAudio 参数烘焙 9 段音频，保留分组、循环和音量。
- Noto Sans SC 采用官方字体与 OFL 许可；完整文件与 23 个表校验、当前 395 个汉字覆盖检查通过。未复制 Windows 系统字体。
- 原版 12 关各入场、机关后、完成共 36 张固定时钟基线已采集，包含规则状态和原镜头数值。

## 验证证据

以下是已实际执行的结果，不把脚本存在当作通过：

| 检查 | 已取得结果 | 证据 |
| --- | --- | --- |
| 原项目 | 140/140 与 TypeScript 通过 | 根目录脚本运行输出；旧源码保留 |
| JS/GDScript 规则 | 67场景、1796命令、5575检查；含120存档样例 | qa-godot-migration/rules.log |
| 旧档合法归一 | 30检查 | qa-godot-migration/normalization.log |
| 完整应用 | 48场景、2060命令、17803检查 | qa-godot-migration/application.log |
| 会话/输入 | 17检查 | qa-godot-migration/session.log |
| 控制器 | 24检查，含撤销清方向意图 | controller.log |
| 存档服务 | 43检查 | qa-godot-migration/services.log |
| HUD | 57检查；320/390/568/738/900/901实际GPU图 | hud.log、hud-final-native-title-fit/、hud-refinement-native/ |
| 视觉契约 | 398检查 | qa-godot-migration/visual-contract.log |
| 关卡绘制 | 101检查 | qa-godot-migration/visual-scene.log |
| 动态绘制 | 224个尺寸/关卡/时间组合，headless及GPU均过 | qa-godot-migration/visual-dynamic.log及GPU记录 |
| 原版镜头对照 | 36状态/109检查；GPU捕获145检查 | qa-godot-migration/visual-reference.log、gpu-reference.log、native-reference/ |
| Web真实键鼠 | 12关393命令逐步一致，结算/留下/禁撤销，零控制台错误 | qa-godot-migration/web-gameplay/checks.json |
| Web存档刷新 | 普通重玩、未完成状态真实IndexedDB刷新、完成纪念保持、comfort长按松键 | qa-godot-migration/web-persistence/checks.json |
| Web迁移/导出 | 21项，旧键预览/导入、真实下载、移动后导出、坏JSON拒绝、旧键不变 | qa-godot-migration/web-services/checks.json |
| 原版备份页 | 独立context下载完整原文、前后localStorage不变 | 主 agent 浏览器实测输出 |
| Windows构建 | release导出成功，程序headless启动与正常退出 | qa-godot-migration/export-windows.log、windows-smoke.log |

部分表格的独立验证在统一报告生成后追加，最后交付前应再次运行受本批改动影响的检查并记录准确数字；不能把旧 checks.json 的失败或通过覆盖解释为新版本结果。

视觉验证没有断言逐像素一致。原图、投影和关键状态可以硬性对照；字体、抗锯齿、软光近似及纸面采样仍有跨引擎差异。

## 已发现并修正的问题

1. 官方下载首次遇 DNS/连接重置，经官方资产 API 与可恢复 Range 完成，未更改系统代理、VPN或DNS设置。
2. 首轮规则命令文案差异、Projection 内建类型重名、Variant 推断和装饰排序差异。
3. Godot JSON 数字为 float，导致水位/留影恢复与持久化深比较错误；改为严格 JSON 数值语义，并增加真正 stringify/parse 回放。
4. 动画前提前落盘、无变化命令占撤销、试奏撤销继续播放、完成漫步可撤销、Esc退出结算后锁死。
5. 首次 HUD 消息与旅程卡片被最小尺寸反馈撑大、离树取默认主题导致灰按钮、变量字体字重 tag、缺字星号与图标尺寸。
6. 原图装饰排序和池塘凸包起点/方向差异。
7. WebGL 小眼睛高光椭圆耳切三角化错误；改为凸椭圆三角扇并增加224动态组合，再由全12真实Web确认零错误。
8. 存档写失败后导出不含最新进度；新增只更新内存的 stage_run，并保留坏档/有效备份。
9. 短横屏和双角色工具栏溢出；按原布局策略补紧凑模式。
10. 提示12/20秒到期、1-2根线提示持续条件与模式按钮反馈。

首次错误记录与临时失败截图保留，不能把首次失败后的修复描述为从未发生错误。

## 用户试玩后的新反馈与本批工作

用户反馈：移动仍然生硬，与旧版感觉接近；整体画面衔接较稳定，但仍需继续优化操作、界面、人物动作与渲染。

这说明原貌迁移基本建立了对照，但保留旧输入/动画并没有自动改善手感。当前精修按以下边界进行：

- 方向快速点按允许短窗口内的单个明确意图，避免按键在动画中被吞。
- 连续格移动在同一帧衔接，消除每格之间短暂切回 idle。
- 人物行走到站立采用短时姿态过渡，足底仍准确落格，不增加物理惯性或改变可达规则。
- 连续行走、镜头避开面板两个设置保持独立；资源操作不因长按自动重复。
- HUD 保持纸面和现有布局方向，只精修主动作、条件提示、焦点/按下反馈及小屏。

该精修批次已实现并通过统一技术检查；最终布局与正式包性能仍需以下独立验收，主观手感由用户再次试玩确认。

### 本轮落地与新增证据

- 输入：160ms单个方向意图、松键保留有效点按、OS重复不入队、同帧连续走格、撞边停止重试；稳定态撤销清held与待输入，动作中撤销仍禁用。input37/controller24通过。
- 人物：原PNG按front/side/back组织帧，70ms起步/100ms收步，固定脚锚点；同格8px避让在动作内过渡。headless551、GPU570含19帧通过；最终Web9专项208采样见web-motion-delivery/，此前独立WebM在web-motion/，历史夹具失败独立保留。
- HUD：窄竖屏说明折叠/操作区上移，320短屏方向44px单排，滚动动作卡140×96；568短横屏纸卡74h容纳按钮、标题17px单行。完整命令仍可滚动，工具主动作可用。320小卡是已知面积折中，未变更镜头/角色比例。
- NPC：气泡避实际HUD与当前角色保护区；390正常移位，320无可用区域时只隐藏装饰寒暄，谜题提示仍在。npc-current/有真实GPU图及几何。
- 绘制：保留显式fan、双精度单位圆缓存；地块/ID索引只在本次draw复用。曾试验一次indexed提交以减少脚本调用，但正式包无明确性能收益，且GLES3每个polygon不可合批、每帧创建GPU几何对象，已撤回到可合批primitive。visual-cache206、动态224通过；恢复后19张GPU图与原fan逐像素相同，详见primitive-motion-native/。这是被撤回的性能实验。
- 查询：commands在一次纯查询内向near/point_for/together传同一board，不跨帧/act缓存，不绕过外部存档验证。query-scope10通过；全部67规则场景5575检查及48应用场景17803检查重过。
- CPU剖分：相同150次原生CPU样本，1-1每格均值5.960→2.758ms；2-2为53.802→14.019ms，反馈miss24.170→4.497ms。数据排除绘制/存储IO，不能等同Web帧率；原始before/after JSON已保留。
- 池塘：单View仅缓存一份worldspace内部格点/near/粒子/边沿，关卡定义或实际地块变化替换；相机、水位、时间仍逐帧投影和绘制。12状态180项通过，36张GPU前后图逐像素一致；原生GPU绘制16.25→10.83ms，池塘7.95→4.01ms，详见native-draw-profile/。
- 最终集成：a1aed27f2d8092593980b779565d9253a7ae576b17c94cf393e7187adab33fb7，322运行文件；统一check、debug/release导出指纹一致。Windows隐藏进程实际Wait退出0、stderr空。全12关393实际Web命令再次通过，见web-gameplay-final/。

最终候选指纹为4ea7da7ce00475647078a03b85ddd578e810dedacfae22dd9ba7d5359d34bb5d，322运行文件，新增池塘缓存/primitive回退/中等高度标题后统一check全过，debug/release指纹一致。最终运动9专项208样本、1-1/2-2/3-4的128真实命令、Windows release启动退出0/stderr空。上面的a1aed27f是先前已全关393命令验证的版本，其失败及复验报告不冒充最终源结果。

正式Web输出为build/web-release，debug为build/web；每个variant保存自己的build.json，构建/检查均拒绝执行期间源码变动。正式候选不提供QA桥，键鼠/状态检查使用独立debug。

### 布局与性能的验收边界

初次强化布局矩阵在320×568发现标题/方向/动作卡重叠，修复后又在568×320发现按钮超过纸卡5px（实际未出视口）；两次失败证据分别保留layout-current/、layout-refined/。最终矩阵还曾在与另一浏览器测试并行时，1920切换后出现render target status36061与黑帧；新context及相同尺寸切换的独立诊断暂未复现。该次报告不得当作画面通过，需加入近纯黑检测并独占重验。

已完成独占重验：layout-final-isolated/的a1版96case真实像素通过；随后修复738/3-4标题与tiny170关名后的最终4ea7在layout-delivery/再次96/96通过，32截图、全尺寸受控角色全身保护区/同伴脚点通过、近黑帧检测通过，错误与警告均空。首次黑帧因果仍未确定，旧失败证据保留，不能声称根因已修复。

最终默认镜头仍有10个用例的远景/后续导航目标被HUD覆盖，11个用例地图部分在屏外；人物当前保护区均已通过。实验安全镜头无目标遮挡/地图屏外，但40/48个用例地块宽小于28px，最小约5.13px，可读性不足，继续默认关闭。完整地图无需都缩入极小屏，仍可用全景或移动接近查看；该限制不冒充小屏体验已全部解决。

性能已有无QA、无录像的隔离采样：旧debug walking p9541–50ms，旧release仍约41.68ms。最终4ea7正式包，在Chrome156/RTX4090D、DPR1、1280×720与1920×1080中，1-1移动p95约8.44/8.43ms；2-2移动p95约41.68/41.67ms，对比同负载primitive池塘缓存前133.34/116.70ms有改善，但2-2仍未达到16.7ms预算。performance-release-final-1-1/及-2-2/记录环境/启动关卡/构建/每帧采样，报告明确区分采集无错与预算达标。rAF只表示这台主机页面节奏，不能认证所有设备60FPS。

## 尚未完成的范围

- 用户对新走停和界面精修的再次体验验收。
- 低配/手机真机、Safari、字体放大与性能预算的完整采样；本机96case矩阵已完成。
- 完整首页小剧场、插画地图和图鉴书册的 Godot 场景级原貌重建。
- 云庭玩法移植、Android/iOS 原生、商店发布等后续范围。
- 后续默认产品入口切换与旧实现清理；当前保留4174原版、4185正式候选、4186调试，未删除旧实现。

工程结构和复现命令见 godot/README.md；原实施计划见 docs/25。本记录会随实际验证追加更新，不以“已能启动”替代完成定义。
