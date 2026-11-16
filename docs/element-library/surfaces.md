# 地表元素：外观主题与物理构型分离

覆盖大关卡 1～3 的 12 个小关卡。此轮抽取前冻结了 558 种冷启动/作者快照地表状态，1129 项断言验证地面选图、墙面、楼梯贴图、密度、UV 比例、物理坐标、瓦片尺寸及高度采样保持一致。默认资产没有重新绘制，关卡路线和机关条件没有改写。

## 统一入口

- 数据：`godot/content/surface-elements.json`。
- 查询/预览：`godot/elements/surface_definitions.gd`。
- 贴图别名到实际资源：项目的 `ElementAssets`；更换同一别名资源会影响引用该别名的全部实例。
- 材质构造：`chapter_surface_materials.gd`、`terrace_materials.gd`。
- 几何、承托、碰撞：`native_surface.gd` 和楼梯 geometry 模块。主题不能覆写这些数据。

`definitions()` 返回完整、深拷贝目录，含 `elements/themes/profiles/patchPolicy/roots`；编辑器可以枚举它，但仍需由 World 生成具备玩法语义的地图实例。材质目录不是可通行性来源。

| 元素 ID | 用途 | 共享规则 |
|---|---|---|
| surface.floor | 普通平台地面 | stone/grass/moss；按原有关卡标记和确定性斑块选择，禁止每帧随机 |
| surface.wall | 岛屿立面 | wallLeft/wallRight 独立槽，统一像素密度；不是场景里的障碍岩石 |
| surface.stair | 台阶踏面和立面 | stairPaint/stairGrain；逐级重启 UV，不能用斜坡代替真实台阶 |
| surface.root | 生长道路 | 根路颜色与资源共用；World 决定生成数量和顺序，不能在已有落地平台再生成终点格 |
| surface.shadow | 日/月投影与记忆道路 | 日/月配色及固化发光来自状态；换肤不能固化路线 |
| surface.moving-board | 旋转/移动板 | 固定对象局部贴图参考；texture_origin、texture_turn 随板携带，禁止旋转后换铺装 |

## 全局替换与局部主题

两种操作都不需要修改每个关卡：

1. 保留资源别名（例如 `paving-valley`、`masonry-valley`），在统一资产入口替换路径；所有使用此资源的关卡实例统一更新。共享别名可能同时用于地板和楼梯石纹，想让两者不同应先拆分主题槽。
2. 修改 `themes` 中某章的槽引用，或预览时调用 `set_theme_overrides(chapter, values)`。传入一个主题的完整覆盖集合，每次调用替换该章之前的覆盖集合，不做增量合并。

```gdscript
const Surfaces = preload("res://elements/surface_definitions.gd")
# 仅预览谷地墙面；地板和楼梯不变。
Surfaces.set_theme_overrides("valley", {
    "wallLeft": "my-masonry-left", "wallRight": "my-masonry-right"
})
# 与 ElementAssets 注册的逻辑别名配套；不要把磁盘路径塞进槽位。
```

主题 API 验证槽名、资源别名和可加载纹理、颜色及正数像素密度。未知主题或非法字段整批拒绝。`reset()` 清除预览覆盖并在下次读取时重读目录；`revision()` 提供缓存失效依据。舞台需重建使用旧版本的材质，单独修改 JSON 不会自动改变已存在的 Godot Material。

| 槽位 | 说明 |
|---|---|
| stone | 每块瓦片选择策略中的基础铺石 |
| terrainTop | 章节基础材质的默认顶面；统一替换基础地板时与 stone 一起配置 |
| grass / moss | 草地/苔石铺装 |
| terrainSide | 非绘画路径的侧面；谷地/洞窟默认 masonry-valley，池塘 masonry-pond，保持历史几何材质 |
| wallLeft / wallRight | 两个朝向的立面纹理；无需更改平台网格 |
| stairPaint / stairGrain | 楼梯绘画纹理与石纹；踏面和立面共用 |
| wallWash | 墙面综合色调，HTML 色值 |
| wallPixelsPerUnit | 墙面 X/Y 单位世界长度对应像素数，保持像素密度 |

根路/日月配色放在 `roots`，通过 `root_style(kind, mode, memory)` 获取。云端章节仍沿用原有米色程序化材质，未迁入前三章主题。

## 几何与编辑器组合约束

1-1、1-2 使用各自已验收的 authored profile；只让 `material_spec()` 调用公共主题，保留物理缩放、平台间距、高度、楼梯步数。其他章节保留既有通用地形。地图编辑器应选择几何 profile，再选择外观 theme；不能让材质默认尺寸覆盖几何实例。

普通平台、薄桥、根路、台阶、移动板不能因为“同样是地板”而合并成同一碰撞盒。坡道/台阶使用真实采样高度；生成路必须检查静态落点占位；移动板的网格、碰撞、角色承托与纹理参考统一跟随同一状态变换。水流、光路、机关和道路的状态归 World，目录只描述视觉资源。

## 验证

- `native_surface_elements_baseline_test.gd`：默认材质与物理输出冻结比较，1129 项通过。`--record` 仅用于刻意建立新基线，验收不能重录后比较自身。
- `native_surface_elements_test.gd`：32 项覆盖地板/墙面/楼梯独立替换、章节隔离、覆盖拒绝原子性、目录拷贝与原日月配色。
- 旋转贴图生命周期沿用 `native_surface_identity_test.gd`。本次只抽取主题，不改旋转纹理路径；整体集成后由主任务运行相关回归。

这是一套已经接入现有材质创建链路的共享元素定义，不是地图编辑器成品。实时编辑 UI、保存编辑地图及额外几何类型属于后续功能。
