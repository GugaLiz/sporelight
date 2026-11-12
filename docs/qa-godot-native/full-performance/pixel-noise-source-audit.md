# 固定快照像素自噪声的只读审计

三关探针在同一引擎的连续截图间也存在10–121个变化像素，多数最大通道差1，2-1个别为5；画面为1280×720。固定物理更新和相机后，可观察的native、character、origin、scale记录完全相同，仍未消除这些变化。不能据此把差异归因于候选引擎，更不能声称严格像素一致。

对固定 Godot 4.7.2 commit ed1daf0bf001b61586d9930840f2f1394092c079 的只读源码复核：

- 项目原生shader未读取TIME；低动态模式水流相位固定为0.35。
- `drivers/gles3/rasterizer_scene_gles3.cpp:4525` 的材质debanding未实现，`render_scene_buffers_gles3.h:109`对应设置为空。
- `drivers/gles3/shaders/sky.glsl:134` 的噪声只依赖gl_FragCoord，且本项目原生场景未使用Sky。
- `render_scene_buffers_gles3.cpp:152` 使用RGBA8，`scene.glsl:2796`附近执行tonemap/sRGB，`rasterizer_scene_gles3.cpp:3040`执行MSAA resolve。这些环节可能把微小数值扰动量化为1级色差，但并不能证明扰动来源。
- `rasterizer_scene_gles3.h:723`附近的透明排序比较优先级/深度，没有平局键；舞台每帧也会重写若干变换。这些仅是待隔离假设，没有被认定为根因。

没有修改游戏画质、关闭shader、遮罩差异区域或放宽原strict exact断言。精确比较结果保留false；实际视觉评估另见`template-pixel-all-states/review.md`与完整逐状态数据。1-4两状态各有一个花边像素的跨引擎差17，不能说它已在该状态自对照中复现。独立全幅复核未发现几何、材质、角色、光照和水/光路的实质性静态回退，但不得把这一评估改写成“所有像素相同”。
