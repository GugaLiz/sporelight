# 全量重绘的覆盖与画面检查

2026-11-17。本文记录本轮准备好的验证工具；准备完成不表示所有素材已经绘制、接入或通过画面验收。

## 覆盖口径

冻结的场景与UI/角色清单合并后，严格检查102条实际旧源路径。78是按旧内容字节去重的输出组，33是角色相关独立旧内容组，三个数不能相互替代。角色动画中的重复帧可复用重绘母图，但每条实际路径／别名都必须解析到新图。

`check-full-redraw-coverage.mjs` 验证：

- 每条旧源路径的原始SHA保持，运行主题与bitmap源重定向已经生效。
- 最终纹理具有本批或上一批七张重绘的母图来源记录，实际输出SHA一致，PNG逻辑画布不变。
- 同源UI与世界别名指向同一纹理，UI与native场景不再直接加载绕过解析的旧切图。
- 33个角色旧字节组的全部实际路径已覆盖，loader logo声明的源身份与解析结果一致。loader编码字节仍需单独运行同步工具的 `--check`。

```powershell
node tools/godot-migration/check-full-redraw-coverage.mjs
```

默认写 `coverage.json` 及供引擎测试使用的 `coverage.requirements.json`，不完整时非零退出。准备阶段可加 `--allow-partial` 只看差异，但报告仍保留 `passed=false`；`--candidate` 仅读待审主题/bitmap候选，不能作为已部署证据。

## 实际引擎绑定

`godot/tests/native_full_redraw_coverage_test.gd` 检查真实Texture2D、SpriteFrames及HUD／地图详情绑定。角色所有clip的帧数、fps、loop和每帧别名逐一对照，程序化伙伴保留，构造场景前后的规则快照一致。该测试明确不是GPU／指针／画面质量测试。

```powershell
& '<固定Godot console路径>' --headless --path godot --script res://tests/native_full_redraw_coverage_test.gd -- --output=<绝对结果JSON路径>
```

默认读取新的冻结需求清单 `godot/tests/fixtures/full_redraw_required_paths.json`，无需依赖已生成报告；也支持 `--requirements=<绝对路径>` 传入上一步输出的同一102路径集合。此清单是本轮新建的消费者覆盖要求，不是重录已有规则或旧美术oracle。两份新的GDScript均已通过 `--check-only` 解析检查，完整绑定测试等待最终资源生效后执行。

准备期4套463项已通过并保持源稳定，见 [qa-preparation-headless/checks.json](qa-preparation-headless/checks.json)：HUD182、bitmap resolver27、element assets177、element cache77。它们没有被记作全部新美术完成。

## GPU 原图

`godot/tests/native_full_asset_redraw_capture.gd` 准备13类固定场景／界面：首关、1-3、1-4闭门及完成、2-1、2-4、3-3完成、cloud-1、首页、三章地图及已解锁图鉴。1280×720和844×390，各拍基础原资源库与最终／候选图，共52张完整原图。每对场景使用相同快照、普通镜头、相机位置／尺寸、idle姿态与时间1200；UI使用内存完成记录，不访问用户存档。

首关另保存walk-front/back/left、jump、sow、interact、complete首／中／末帧的1:1实际画面裁片。`NativeActorPose` 原有的姿态scale／foot仍实际生效，报告保存实际pixelSize、offset和纹理路径，用于发现重复校准或动作跳位。裁片不缩放，也不算完整实际游玩。

固定引擎以隐藏根窗口和真实OpenGL SubViewport运行，音频设Dummy仅供视觉QA：

可直接使用本批非聚焦／屏外根窗口启动器，运行源摘要在启动前后独立核对：

```powershell
node tools/godot-migration/capture-full-redraw.mjs --output=docs/qa-godot-native/full-asset-redraw-20261116/native-gpu-final
```

启动器支持 `--source-sha=`，不匹配当前源码时拒绝运行。它仅在 `.tmp` 中创建QA宿主目录，根窗口置于 `-32000,-32000`、64×64、no-focus；实际52张游戏／界面图仍由明确尺寸的原生SubViewport渲染，不改变可玩的project.godot。

```powershell
--path godot --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --script res://tests/native_full_asset_redraw_capture.gd -- --output=<绝对输出目录> --source-sha=<sourceDigest>
```

可附加 `--theme=<绝对候选JSON>` / `--bitmap=<绝对候选JSON>`。启动器必须隐藏根窗口；这不等同于headless，脚本会拒绝headless画面验收。完整输出含源码／实际引用图片的前后SHA、显卡、尺寸、各图相机与快照、实际TextureRect/Sprite资源绑定、错误日志和准备范围。图像保存成功不自动认定美术通过，必须逐图审阅主体比例、边缘、硬底座和状态对齐。

旧 `native_actor_pose_test` 中有原PNG字节不变断言，与本次明确重绘目标不兼容；保留旧oracle和诊断，不放宽阈值掩盖问题。本轮用新来源覆盖、实际动作绑定和GPU姿态原图分别验收。
