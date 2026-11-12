# Godot 4.7.2 Web 场景 shader 按需编译模板

此模板单独构建，不覆盖 Godot 官方安装。项目另设 `Web Optimized` 导出预设，保留原 `Web` 与 Windows 预设。采纳前必须完成同场景像素对比和普通入口冷启动计时，验收状态见 [结果记录](../../docs/62-动作比例与运行性能优化结果.md)。

## 修改边界

官方 `4.7.2-stable`，commit `ed1daf0bf001b61586d9930840f2f1394092c079`。唯一引擎修改见 `patches/godot-4.7.2-web-scene-demand.patch`：在 `ShaderGLES3::_initialize_version` 已创建每个 variant 的空 map 后，只对 `WEB_ENABLED` 且名称严格等于 `SceneShaderGLES3` 的 shader 跳过默认 specialization 预编译。

名称来自同版本 `gles3_builders.py` 对 `drivers/gles3/shaders/scene.glsl` 生成的类名及 `_setup` 参数。`_version_bind_shader` 原有同步路径会在 map 缺少所需项时，按本次 draw 的准确 specialization 编译并缓存；真正需要默认 mask 的 draw 也仍会编译默认项。现版本异步分支为 `if (false)`，没有依赖预先存在的默认项；不得未经复审移植到其他版本。

不修改 scene GLSL、光源数量、法线、阴影、光照方式、材质、采样、分辨率或其他 shader 初始化。Web 的二进制 shader cache 原本禁用；桌面编译由宏隔离，仍保持原路径。失败时仍使用引擎原有编译错误处理。

## 可复现构建

Windows x64 主机需要已有 Python 与 Git。首次构建隔离下载约 705 MB 的 Emscripten 依赖，另有 Godot 源码。目录默认是 `%USERPROFILE%/.cache/sporelight-godot/custom-web-4.7.2`，不安装系统 PATH/注册表项目。

```powershell
python tools/godot-migration/build-web-template.py --prepare-only
python tools/godot-migration/build-web-template.py --target release --jobs 4
# 可选：单独构建 debug；会产生另一套目标文件，不假设是低成本增量。
python tools/godot-migration/build-web-template.py --target debug --jobs 4
```

脚本验证源码 commit、唯一补丁 diff、SCons wheel 和工具链可执行文件 SHA256。`web-template-toolchain.lock.json` 锁定 Emscripten 4.0.20、SDK commit `e4fe26ef59168ff44f4c23c466e497bf60b3411e`、SCons 4.9.1 以及关键二进制。构建参数：`platform=web target=template_release arch=wasm32 threads=no dlink_enabled=no javascript_eval=yes production=yes debug_symbols=no optimize=size lto=thin use_closure_compiler=no linkflags=-Wl,--thinlto-jobs=4`。编译与 ThinLTO 均最多 4 个任务；保留正常模块集。首次记录的宿主 Python 是 3.14.3。

结果在 cache 的 `artifacts/godot-4.7.2-web-scene-demand-release.zip`。项目 `docs/qa-godot-native/custom-web-template/release-build.json` 记录源码、工具、补丁、参数、耗时和最终模板/成员文件哈希，旁边保存编译日志。ZIP 时间戳可能因构建时间不同而变化，不声称逐字节重建一致。

## 集成与回退

`export.mjs --release` 读取构建 manifest，验证完成状态、release 类型、固定源码 commit、当前补丁 SHA256 和模板 ZIP SHA256，再复制到项目 `.cache/godot-web-templates/web_release.zip` 并选用 `Web Optimized`。未构建或校验失败时停止，不能悄悄降回官方版本。构建元数据记录实际模板来源与哈希。未传 `--release` 的 debug 导出仍使用官方模板。

```powershell
# 首次先构建模板；之后通常直接导出游戏即可。
node tools/godot-migration/export.mjs --web-only --release --variant=performance-optimized
# 显式使用官方 release，作对照或回退。
node tools/godot-migration/export.mjs --web-only --release --official-web --variant=performance-official
```

不覆盖官方 `export_templates`。模板构建脚本只构建，不执行项目导出、浏览器或 GPU 测试。当前配方只产出 release；不能将它填到 debug 模板选项。

`prepare-template-visual-comparison.py` 单独复制运行源码到固定 workspace cache，移除 `main.gd` 的三处 QA debug guard，使两种 release 引擎可使用相同验证入口；另在快照请求显式 `freezePhysics=true` 时暂停物理移动并立即对齐相机，避免静态画面对照被持续接地微调污染。两份 PCK 哈希必须完全相同。导出预设仅在该副本中改为已校验模板的绝对路径。此工具的 `template-visual-*` 包明确标记为验证专用，不能交付。正常游戏源码的 guard 和物理更新保持不变，普通入口性能必须另外使用正常 release 测量。

验收必须比较相同游戏源码、同状态、同相机和固定视觉时间的官方/候选截图，确认材质/角色/水体/光线不变；再使用独立浏览器冷启动记录启动时间及 `getProgramParameter` 阻塞。切换关卡与首次遇到新材质也需覆盖，以免把预编译延迟搬到后续交互。

官方依据：[4.7 Web 编译要求与模板命令](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_web.html)、[4.7.2 Web 构建配置](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/detect.py)、[4.7.2 shader 绑定路径](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shader_gles3.h)。
