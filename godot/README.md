# Sporelight Godot 原生 2.5D

此目录使用 Godot 4.7.2 与 GDScript。默认采用真实 3D 地形/碰撞、固定正交相机与原图片角色的 2.5D 场景；格子 ID 用于解谜规则，人物在合法支撑面内连续移动。原 TypeScript 应用仍在仓库根目录，两者存档和预览入口分离。

主线 12 关和云庭独立 3 关共用原生场景、移动和界面。种子预算、未开放通路、双角色能力、空间机关与光水影因果继续由规则核控制。首页、分章地图、继续、回看、图鉴、纪事、设置和存档工具保持独立语义。发布状态、构建摘要与实际验证范围见 [验收记录](../docs/37-原生2.5D全游戏重构与验收.md)；规则通过不能代替画面和体验验收。

原动态封面已恢复，后续版本与入口检查见 [封面恢复记录](../docs/38-原动态封面恢复与验收.md)。封面由 ui/menu_cover.gd、ui/menu_vignette.gd 独立呈现，与引擎启动图分别管理。

Web引擎加载页使用 web/loading-shell.html，加载前显示独立的首页同风格素材与真实下载进度，完成后进入动态封面。当前加载页版本及真实慢网/失败重试验收见 [加载页记录](../docs/39-Web加载页与首页风格衔接.md)；普通export会自动复制所需loader图片。

加载页Logo与首页原生控件坐标、高DPI换算及跨阶段检查见 [品牌坐标对齐](../docs/40-加载页与首页品牌坐标对齐.md)。修改品牌布局后执行 check-brand-alignment.py；不得仅修改build目录的HTML。

首页采用一个主要旅程入口，探索收藏默认折叠，导入导出归入设置。焦点与hover样式、分类返回和真实输入验收见 [首页入口层级](../docs/41-首页焦点样式与入口层级.md)。

地图采用固定标题/工具/返回区与中间章节滚动列表，公共按钮状态和验收见 [地图按钮规范](../docs/42-地图按钮规范与固定操作区.md)。

图鉴共用固定菜单框架，切换分类置顶、重复点击保留阅读位置、故事返回恢复原分类与滚动，详见 [图鉴阅读位置规则](../docs/43-图鉴分类与阅读位置规则.md)。

## 运行与构建

修改人物比例、相机、楼梯或碰撞前，遵循 [原生角色楼梯接触与防穿模规则](../docs/50-原生角色楼梯接触与防穿模规则.md)，同时验收物理支撑与实际遮挡画面。

在仓库根目录、Node 18+ 环境执行：

    npm run godot:setup
    npm run godot:assets
    node tools/godot-migration/bake-audio.mjs
    npm run godot:check
    npm run godot:export -- --release
    npm run godot:preview -- --variant=web-release

浏览器打开 http://localhost:4185/。预览仅监听本机；不占用原版 4174 或其他项目 4173。

也可以在 Godot 编辑器中打开本目录 project.godot，再运行 main.tscn。Windows 导出位于 build/windows，运行 Sporelight.exe 时需保留同目录 Sporelight.pck。

setup 使用官方发布资产、固定引擎 SHA256，以及官方模板目录中各条目的 CRC32/长度。模板按平台提取，不声称校验过未下载的完整模板包。实际固定版本见 toolchain.json。

自定义引擎可设置环境变量 GODOT_BIN；其他主机需自行提供对应固定版本和导出模板。当前 bootstrap 专用于 Windows。普通 export 生成 build/web 调试包，--release 生成独立 build/web-release 正式包；Windows始终导出release。两种 Web 包各有 build.json，检查和导出都会拒绝期间发生运行源码变动的结果。

调试验证可单独运行 npm run godot:export，再用 npm run godot:preview -- --variant=web --port=4186。预览参数允许两个版本各占本机端口，避免将带测试接口的调试包当作正式性能结果。

## 操作

- 方向键 / WASD：沿等角格移动；E：当前主要操作；数字 1–9：当前命令。
- T：换手；Z：撤销；H：提示；J / Space：跳跃。
- 鼠标可点地块走路、点发光“＋”生长，或使用面板。
- 原生模式始终连续行走，松键停步，不强制回到格子中心。靠近对象显示明确动作，根台先选择合法方向。桌面隐藏方向盘，触屏可在设置选择方向键。
- H 提供分级帮助，具体步骤仅在主动深入请求后显示。旧 continuousInput/safeCamera 字段继续兼容导入，原生模式不再采用逐格移动实验模式。
- 完成后可留下漫步；地图普通进入已完成关会重新玩；纪事的回看入口读取完成纪念且不覆盖正在重玩的进度。

## 存档

新工程使用独立 user://sporelight-godot.v1.json，并保留备份。Windows自定义用户目录名为SporelightGodotPreview；Web使用浏览器IndexedDB，与旧版localStorage不同。

菜单的旅程导入/导出工具先预览、再导入。只有明确点击“读取旧版本”时才尝试同源localStorage；不同端口、域名、协议或原生Windows需要导出/导入JSON。开发与自动测试使用独立浏览器context和测试路径。

导入支持三套旧键原文以及sporelight.save.v1回退。进行中状态、最好记录与完成纪念分别保存；损坏输入拒绝替换；存储失败仍可在内存继续游玩并导出最新进度。

## 验证与调试

godot:check 统一执行规则/保存/UI/会话/控制器、真实输入、连续运动/体积、十五关完整 motor 路线、真实文件持久化、原生几何/相机和启动检查。校验期间运行源摘要必须一致。非零退出或 Godot 错误日志都会失败。godot:check:legacy 保留旧表现对照用途，不把旧像素契约用于约束新场景。

原始参考导出工具位于 tools/godot-migration/export-reference.mjs；规则基线固定为旧版本5791bbc。已有 fixtures 可直接测试，不需每次重新导出。更新基线必须明确记录原因，不能通过改解法掩盖移植差异。

原生候选与浏览器脚本（Python 需有 Playwright，项目 .cache/native-qa-python 可用于隔离依赖）：

    node tools/godot-migration/export.mjs --variant=native-candidate --web-only
    node tools/godot-migration/serve-preview.mjs --variant=native-candidate --port=4190
    python tools/godot-migration/check-native-browser.py --mode=gameplay --sizes=1280x720
    python tools/godot-migration/check-native-browser.py --mode=home
    python tools/godot-migration/check-native-browser.py --mode=motion --sizes=1280x720
    python tools/godot-migration/check-native-browser.py --mode=capture

浏览器工具使用项目 .cache/native-qa-python 中的 Playwright，也可使用当前 Python 环境已安装的库。仅 Web debug 构建且 URL 显式 qa=1 才安装测试桥，release 构建不提供该桥。测试桥注入状态仅用于准备场景，逐命令回放使用真实键盘与按钮。原生浏览器脚本以 --base=http://localhost:4190/ 指定入口；--mode=mechanisms 另查机关旋转中段，--levels 可筛选关卡。

原生走停与尺寸检查使用 check-native-browser.py 的 motion/capture 模式；旧 check-motion.mjs、check-layout.mjs 保留给 legacy 对照。性能使用 check-performance.mjs --qa=0 --level=3-4 --url=http://localhost:4185/，在独立空闲浏览器记录构建、浏览器、图形设备和帧节奏。脚本在隔离上下文中给启动器传已有 CLI 关卡参数，不修改正式 HTML。走动使用持续按键；rAF 间隔只表示该主机的页面节奏，不能证明全部设备 60FPS。

headless通过不能代替GPU画面或人类试玩。原图字节保持，投影与关键状态有对照；字体采样、抗锯齿、软光仍可能与Canvas/CSS有差异。

## 继续开发

首关保留原素材、真实阶梯与交互修正版使用试玩入口 `http://localhost:4216/`（release），调试入口为 `http://localhost:4217/`，详见 [首关原素材恢复与阶梯修正](../docs/47-首关原素材恢复与阶梯修正.md)。该候选不自动替换 4185 的正式包。专项测试为 `native_first_garden_material_test.gd`、`native_first_garden_structure_test.gd` 和 `tools/godot-migration/check-first-garden-ui.py`。此前文档46中的程序化石材和替代花床方案已被用户否定。

当前建模修订进一步校正了楼梯透视贴图、横向高差及压条收口，并收薄岛体、放大原花坛和根台，见 [楼梯对齐与物件比例](../docs/48-首关楼梯对齐与物件比例.md)。

根台、花坛和孢子的接地与材质融合修订见 [首关物件与地图融合](../docs/49-首关物件与地图融合.md)，沿用同一预览入口，保留已确认的楼梯和地图结构。

规则核在core，GameSession负责预演/版本核对/一次提交，main负责输入→动画→提交；presentation只消费规则状态和表现计划；HUD只消费Journey与命令数据；services管理存档和声音。

大改应先在代表关卡和独立候选验证，再推广。当前方案见 [全游戏重构计划](../docs/36-全游戏体验重构与Godot原生开发方案.md)，公共几何、接触、素材与渲染规范见 [native/README.md](presentation/native/README.md)。文档 25 保留为早期移植历史；项目 agentchanges/CHANGELOG.md 记录每批实际修改与验证。

字体与引擎许可见LICENSES.md及assets/fonts/OFL.txt。
