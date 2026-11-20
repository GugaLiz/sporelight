# 原生 GPU 素材重绘对照

2026-11-16，运行源 `38df2424d54815e5465bda9527c5bc35e76383bbe94b4bcde3b88798bd643b23`。最终结果及每张图的快照、相机、纹理路径、mipmap 数量见 [report.json](report.json)。

- Windows / NVIDIA GeForce RTX 5060 / `gl_compatibility` / OpenGL 3。
- 两个普通游玩视口：1280×720、844×390，DPR 1。七个场景准备态，每对原图／新图使用相同快照、角色 idle 第0帧、视觉时间1200、相机位置／尺寸／焦点；共28张原始完整图，另存未缩放的局部像素裁片。
- 场景：1-1初态与完成态、1-3初态、2-3初态、1-4完成态、3-3完成态，以及3-3完成清场准备态。清场只把两位人物放到相邻同高永久岸 `f:1:5` / `f:0:5`；`completed=true` 和原机关/收集状态保持。该清场是准备快照，不冒称实际走位。
- `captureChecksPassed=true`、`sourceFilesStable=true`、28张保存成功，游戏脚本／渲染错误为空，标准错误日志0字节。14对图的相机位置、相机尺寸和快照分别一致。新7种纹理在实际引擎中均有6–8层mipmap。

## 原图审阅

已查看双尺寸普通画面及门、金色白花、象牙白花、蓝铃花、花坛的1:1局部对照。原素材边缘的白色碎点／硬白轮廓在新版明显减少，花叶和门柱轮廓更连续；未见本次替换导致的底座突然放大、跳位或新增悬空。花坛未完成和完成两态保留同一基座位置。修正版微光保持近圆形主球，已移除厚白抠边。

`../native-gpu/` 为中间稿：机械注册把微光主体横拉成椭圆，被看图否决。最终导出改为按主球色域等比缩放和中心注册后，重新导入并完整复拍本目录。中间稿不作为最终画面依据。

现有的角色／前景短时遮挡、部分小尺寸远处细节、旧章节未改造素材仍可见；本批不把它们记为全部修复。以上是本机固定准备场景的开发看图结果，用户美术认可、真实游玩、Web发布、声音和性能分别验收。

## 复现

在仓库根目录，使用本机固定 Godot 4.7.2 的 Windows console 可执行文件运行，启动器使用 `Start-Process -WindowStyle Hidden` 隐藏根窗口：

```powershell
--path godot --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --script res://tests/native_scene_redraw_capture.gd -- --output=<绝对输出目录> --source-sha=<sourceDigest>
```

先运行 `--headless --path godot --editor --import`。`--audio-driver Dummy` 仅用于纯视觉 QA，避免无音频设备机器的 WASAPI 初始化错误；不作为声音通过证据。
