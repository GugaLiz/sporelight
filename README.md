# 微光苔原 / Sporelight

陪露薇探索、播种，让植物成为前进的道路。基于现有设计与美术完成的12关可玩首版：3个章节、8项自然图鉴、真实收集与结算、本地续玩、撤销与提示、音景及画面设置。

## 先看文档

- [游戏产品文档](docs/01-游戏产品文档.md)：定位、规则决议、12关设计、页面、数据、验收与后续范围。
- [开发落地方案](docs/02-开发落地方案.md)：架构、数据、资源管线、测试与部署。
- [素材制作规格与提示词](docs/03-素材制作规格与提示词.md)：素材清单、切图规范、后续AI制作提示词。
- [交付与验收记录](docs/04-交付与验收记录.md)：本版实现、验证证据与明确限制。

## 启动

Node.js 18+，建议20或更高。当前系统默认Node 14不满足Vite 5要求，请先切换版本。

```sh
npm install
npm run dev
```

浏览器打开 `http://127.0.0.1:4173/`。生产构建与检查：

```sh
npm run check
npm test
npm run build
npm run preview
```

若在当前Codex环境使用已提供的运行时，可用PowerShell直接启动：

```powershell
& 'C:/Users/liuli/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' node_modules/vite/bin/vite.js --host 127.0.0.1 --port 4173
```

## 操作

点击石台或孢子移动，点击脚下的植物 / E / 「播种与互动」触发机关。方向键或WASD移动到相邻石台。Esc暂停；设置里的「减少动态」同时解除雨滴节拍的等待。普通关可不全收集通关，最终关需要8粒孢子和①②③④依序点亮。撤销回退上一步，提示不扣分。

每一步自动存入浏览器localStorage，刷新后「继续上次的微光」恢复。每个浏览器独立保存；存储不可用时仍可游玩但无法跨刷新保留。v1旧档自动迁移，原v1键保留。不同关卡共用一个进行中存档，进入另一关会替换上一次未完成局。

## 素材

`assets/images/production/` 包含31项资源、透明PNG图集、manifest、预览页和联系表。访问开发服务器的 `/images/production/index.html` 可查看。运行 `python scripts/prepare_assets.py` 可重新导出，需要Python 3和Pillow；脚本不覆盖源文件。

素材来自当前项目既有美术，经重新裁切、透明背景处理、锚点对齐和背景调色导出。本次没有调用AI图片生成服务；全新独立场景/NPC/过场的制作要求已写入素材文档。

## 回归测试

`npm test` 执行22项规则/存档测试，包括全部关卡自动解法。浏览器测试额外需要Playwright和本地Chrome，先运行开发服务器，再执行：

```sh
node scripts/browser-check.mjs
```

也可将已安装的Playwright模块绝对路径作为第一个参数，`PLAYWRIGHT_CHANNEL=msedge`可选择Edge。该脚本使用独立的无头浏览器会话，通过实际UI游玩12关，不修改日常浏览器存档。截图和结果写入 `docs/qa/`。

## 实现范围

固定路径节点 + Canvas移动演出，非360°自由碰撞；反射为离散角度机关，非物理光线追踪；伙伴让路用花与光虫演出，尚无鼹鼠独立动画；场景复用一个背景的章节调色，尚无完整过场与录制配乐。网页首版可运行并完成12关，后续正式内容按产品文档扩展。
