# 元素总目录与关卡文档契约

此轮为 1-1 至 3-4 建立可查询的元素目录和无损关卡文档，不改变关卡动作、操作顺序、通关条件和地图布局。目录复用角色、地表、道具三个域已有定义，保留专用建模与表现适配器。

## 入口与产物

| 文件 | 用途 |
|---|---|
| `godot/elements/element_catalog.gd` | 汇总类型、域定义、资源槽；按真实 World 生成元素索引 |
| `godot/elements/element_document.gd` | JSON 编解码、类型与支撑引用校验、原始关卡 payload 往返 |
| `docs/element-library/inventory.json` | 12 关完整目录、逐实例索引、原关卡数据、初始状态、动态道路观察 |
| `docs/element-library/inventory.md` | 自动生成的逐关数量表与类型列表 |
| `godot/tests/export_element_inventory.gd` | 用真实原生舞台读取初始装饰，校验后生成上述清单 |

当前清单包括 **1104 条索引记录**，其中 **149 个初始状态实际装饰精灵**。索引同时表达定义、实例、功能角色与观察结果：例如一个镜叶有机关标记和搬运状态两条记录，一块平台有模块定义及其地表记录，装饰有 authored source 及 resolved observation。**1104 不是场上物件数量**，两类记录不能相加当成独立物件数。

## 类型、实例、状态分别负责什么

`GardenElementCatalog.definitions()` 返回 `types / actors / surfaces / props / resources / contracts`。`types` 是平面类型注册表；每个实例的 `element_id` 必须在表中存在。

`scenery.*` 中按资源别名生成的项是**资源引用索引**，其中也可能有角色帧；它们不是编辑器可直接放置的物件列表。后续素材栏必须按实际场景实例、明确用途及支撑规则建立可放置类型白名单，不能将所有纹理当作装饰物。

| 字段 | 契约 |
|---|---|
| `domain_ref` | 关联共享域定义、原始关卡字段或资源槽；部分是说明性引用，不是可执行 JSON Pointer |
| `renderer` | 现有专用 renderer 或分发入口；不凭类型名自动生成万能节点 |
| `state_owner` | World 或只读表现适配器；贴图不能变更操作、背负能力、承重或通关条件 |
| `support_required` | 角色、标记、地表、模块、根路、收集物必须有合法支撑；独立墙体/特效/组合物可明确由 adapter 托管 |

实例使用 `level/category/authored identity` 组成 `instance_id`，并保留：

- `source`：原始瓦片、机关、模块、根路、搬运物或资源记录。
- `support`：真实瓦片 ID 及支撑策略；移动平台采用模块形状中的实际格，不假设一定存在中心格。
- `state_binding`：由哪一个 World 状态或只读查询驱动。
- 观察项另带位置、尺寸、来源步骤或延迟状态。

角色 ID 始终是 `luvie` 与 `buddy`；换装和蘑菇皮肤使用域中的 skin/capability 契约，不替换身份。`flower` 仅是历史标记 kind，不能据此把所有物件做成花坛：2-3 的 `stage` 是乘坐花台、3-2 的 `freeze` 是投影记忆、3-3 的 `care` 是根盆。总目录调用 `PropDefinitions.semantic_for_mark()` 统一解析这些例外。

搬运物显式区分 `on-support / held / removed-from-board` 生命周期。手持物保留源状态的空 tile，同时把实例支撑绑定到实际持有角色，记录 holder；交还或消耗后才允许以 removed-from-board 表示空支撑。校验要求 source 与导出快照中的 items 完全一致，空支撑例外不能用于角色、仍在手中的物品或放置于地面的物品。

## 遍历范围与真实性

逐关读取 `content/levels.json`，并通过 `GardenWorld` 获取真实初始的 actors、items 和派生地板。原始 payload 完整保留，包括故事、入口、机关、模块、根路、障碍和 1-4 的 sanctuary；导出不重新构造或省略这些字段。

装饰分为两层：

1. 1-3 起读取当前仍生效的 `OriginalGardenDressing.SOURCE_PROPS`，注明其只是待放置位置，实际支撑由布局适配器决定。1-1/1-2 已有专门布局，禁止误把旧浏览器装饰列表当成当前布局。
2. headless 创建实际舞台，记录直接附着在 props 层的装饰 Sprite3D，包括真实尺寸、位置、支撑和延迟放置。1-1/1-2 因此也会被完整观察。未显式标记支撑的手工锚点保留为 authored-world-anchor，不猜一个 tile 绑定。

无 PNG 路径的庭院程序化精灵明确归为 `scenery.procedural-sprite`，由 sanctuary 适配器负责。庭院门、喷泉和居民作为组合物记录；特效内部小网格、粒子、每级台阶不是独立可交互游戏元素，不逐个拆成编辑器积木。

动态道路另遍历 `tests/fixtures/reference.json` 的 12 条 authored 路径，去重记录非固定地表的 ID/坐标/高度和对应步骤。`terrain-generator` 还明确引用 `GardenWorld.tiles()`，负责根路、门闩桥、升降台入口及日月影路等状态生成。**这些观察覆盖已有作者操作路径，并非所有可达状态穷举**；将来编辑关卡仍须运行 World 的玩法回归。

观察实例 ID 不采用 Godot 自动节点名。优先使用原布局索引或墙面支撑/朝向；只有未具备明确 provenance 的手工装饰，才用资源别名、锚点和重复序号构成迁移 ID。同一场景重建与重复读取稳定。未来编辑器应将首次导入 ID 固化到自己的持久文档，不能在移动锚点后重新计算 ID。

## 编解码与编辑器使用

```gdscript
const Catalog = preload("res://elements/element_catalog.gd")
const Document = preload("res://elements/element_document.gd")
var document = Catalog.for_world(world)
var text = Document.encode(document)
var imported = Document.decode(text)
if imported.ok:
    var original_level = imported.level
```

`source_level` 是玩法源数据；`instances` 是只读派生索引。修改实例坐标不会偷偷改写 source_level，也不会直接构造新关卡。解码校验格式版本、关卡与快照身份、集合结构、重复 ID、未知类型、非法模块坐标和缺失/未知支撑。允许空支撑的对象必须在类型中声明允许，并使用明确的 adapter-owned 策略。

编辑器后续应先修改原始关卡数据，再通过相应关卡/领域适配器校验和重建索引。当前没有实现可视地图编辑器、任意新关卡规则编译、实例到原始模型的反向自动合并、保存文件导入或在线编辑器 UI。已有 renderer、碰撞与玩法引擎仍是运行时权威。

## 导出和验证

```text
Godot --headless --path godot --script res://tests/element_catalog_test.gd
Godot --headless --path godot --script res://tests/export_element_inventory.gd
Godot --headless --path godot --script res://tests/export_element_inventory.gd -- --write
```

前两条只校验，最后一条在全部校验通过后更新 inventory.json/md。它不会回写关卡、存档或玩法文件，不弹出游戏窗口。

- 目录测试先在 API 不存在时失败，再实现；最终 **2453 项通过**，覆盖 12 关来源保持、类型解析、稳定 ID、原始 payload JSON 往返、手持/已消耗物品生命周期及错误输入拒绝。
- 实际舞台导出 **48 项通过**，覆盖只读性、真实装饰观察、重复观察 ID 稳定和完整文档往返。
- 此处是 CPU/headless 结构与契约验收，不替代 GPU 画面和实际游玩验收。
