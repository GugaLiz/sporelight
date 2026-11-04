# Sporelight Godot 迁移候选

此目录保留当前主线的 2D 等角格子玩法和图片，使用 Godot 4.7.2 与 GDScript。原 TypeScript 应用仍在仓库根目录，两者存档和预览入口分离。

当前是供原貌比较和体验验收的迁移候选。主线 12 关已接入；云庭独立 3 关尚未迁移，其旧存档原文可随迁移导入保留。完整首页小剧场、插画地图和图鉴书册版式尚未逐项复现，目前使用纸面菜单与内容入口。不可把规则验证通过理解为所有原界面已完全复现。

## 运行与构建

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
- 设置可分别启用“按住方向键连续行走”和“镜头避开界面面板”；默认关闭以便比较原貌。这些选项不改变谜题规则。
- 默认方向点按支持160ms的一个预输入，松键仍保留有效点按；连续走格保持步态相位，起步/收步不改变落格位置。
- 完成后可留下漫步；地图普通进入已完成关会重新玩；纪事的回看入口读取完成纪念且不覆盖正在重玩的进度。

## 存档

新工程使用独立 user://sporelight-godot.v1.json，并保留备份。Windows自定义用户目录名为SporelightGodotPreview；Web使用浏览器IndexedDB，与旧版localStorage不同。

菜单的旅程导入/导出工具先预览、再导入。只有明确点击“读取旧版本”时才尝试同源localStorage；不同端口、域名、协议或原生Windows需要导出/导入JSON。开发与自动测试使用独立浏览器context和测试路径。

导入支持三套旧键原文以及sporelight.save.v1回退。进行中状态、最好记录与完成纪念分别保存；损坏输入拒绝替换；存储失败仍可在内存继续游玩并导出最新进度。

## 验证与调试

godot:check 统一执行导入、规则/存档/HUD/会话/控制器/全应用回放、视觉契约/动态渲染、36状态原版镜头对照与启动检查。非零退出或Godot错误日志都会失败。

原始参考导出工具位于 tools/godot-migration/export-reference.mjs；规则基线固定为旧版本5791bbc。已有 fixtures 可直接测试，不需每次重新导出。更新基线必须明确记录原因，不能通过改解法掩盖移植差异。

图形画面对照与浏览器脚本：

    node tools/godot-migration/capture-reference.mjs --url=http://localhost:4174
    node tools/godot-migration/check-web.mjs --output=docs/qa-godot-migration/web-gameplay --mode=gameplay
    node tools/godot-migration/check-web.mjs --output=docs/qa-godot-migration/web-persistence --mode=persistence

浏览器工具默认使用本机已配置的Playwright依赖路径，可用脚本参数指定。仅Web debug构建且URL显式qa=1才安装测试桥，release构建不提供该桥。测试桥注入状态仅用于准备场景，逐命令回放使用真实键盘与按钮。若调试包在4186，上述 check-web 工具传 --base=http://localhost:4186/；check-layout 使用 --url 参数。

走停、响应布局与性能验证分别使用 check-motion.mjs、check-layout.mjs、check-performance.mjs。运动时序检查与WebM编码分开；性能采样用 --qa=0、独立空闲浏览器，并记录构建/浏览器/图形设备。--level=2-2 会在隔离测试上下文中给导出启动器传已有CLI关卡参数，不修改正式HTML。rAF间隔只表示该主机的页面节奏，不能证明全部设备60FPS。

headless通过不能代替GPU画面或人类试玩。原图字节保持，投影与关键状态有对照；字体采样、抗锯齿、软光仍可能与Canvas/CSS有差异。

## 继续开发

规则核在core，GameSession负责预演/版本核对/一次提交，main负责输入→动画→提交；presentation只消费规则状态和表现计划；HUD只消费Journey与命令数据；services管理存档和声音。

大改应先在代表关卡和独立候选验证，再推广。既有完整计划见 ../docs/25-Godot迁移与玩法画面保真开发计划.md；项目agentchanges/CHANGELOG.md记录每批实际修改与验证。

字体与引擎许可见LICENSES.md及assets/fonts/OFL.txt。
