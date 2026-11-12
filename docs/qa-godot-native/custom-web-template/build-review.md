# Web 场景 shader 按需编译候选模板构建记录

已完成 Windows 主机隔离构建，退出码 0；SCons 编译和 ThinLTO 链接均限制 4 个任务，耗时 2052.156 秒（约 34.2 分钟），未发生 OOM。完整参数、工具 SHA256、源码 commit、补丁哈希与 ZIP 成员哈希见 `release-build.json`；完整构建输出见 `release-build.log`。

- 源码：Godot `4.7.2-stable` / `ed1daf0bf001b61586d9930840f2f1394092c079`。
- 唯一源码 diff：`drivers/gles3/shader_gles3.cpp` 增加 8 行，仅 Web `SceneShaderGLES3` 的未使用默认 specialization 改为首次实际使用时编译。生成后的 `scene.glsl.gen.h` 已核实 `_setup` 名称严格匹配。
- 模板：`C:/Users/lizme/.cache/sporelight-godot/custom-web-4.7.2/artifacts/godot-4.7.2-web-scene-demand-release.zip`，10,320,561 字节。
- ZIP SHA256：`51d3a8bac3b56cb9187a5d3545d9e60ead680ce0ddbe8ab1a20417cb4cfe35c9`。已独立检查 ZIP CRC 与完整文件 SHA256。
- WASM：39,516,028 字节；同版本官方 release 为 39,514,754 字节，候选增加 1,274 字节。
- 构建警告：未修改的上游 WebXR JS 库引用 Emscripten 内部 `$MainLoop`；日志有 `-Wjs-compiler` 提示，构建成功，无编译/链接错误。

官方安装未被覆盖，项目运行时代码和导出 preset 没有由本构建任务修改。没有启动 debug 构建、浏览器或 GPU 测试。此记录只证明模板构建与产物校验完成，**不证明画面一致或启动性能改善**；两项结论须由主任务的配对截图和普通入口冷启动测试补充。模板编译进程已退出，可进行无并行编译负载的测量。

复现命令与修改边界见 `tools/godot-migration/custom-web-template.md`，脚本为 `tools/godot-migration/build-web-template.py`，补丁和工具链锁文件均保存在同目录。
