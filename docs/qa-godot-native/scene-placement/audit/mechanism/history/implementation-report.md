# 机关、核心点击与云庭底面位置修正

本子任务保留尺寸、素材、规则、地图、碰撞及动作轨迹；未运行GPU、未导出。主验收仍需查看正式渲染。

## 实施

- `mechanism_props.gd`：普通主线机关可见底座/杆/轮/符号/水位点统一在原root内偏移(-.21,0,-.21)。原底座top radius .19、bottom radius .1995、height .12保持；偏移半径.296985+.1995=.496485，小于1×1平台内切圆半径.5，任意旋转角仍有支撑。2-4原(.6,0,-.6)控制器及云庭专属原图保留。
- `native_garden_stage.gd`仅改actor_rest_offset和hit_test：普通机关格默认实体停步点为主角(.1,0,.1)、伙伴(.3,0,-.15)；1-1/1-2/2-4及云庭不套该策略。逻辑mark与交互环仍在原中心。既有核心站位不变。
- `native_movement.gd`仅本次新增排除：机关格显式保存姿态不走旧completed中心兼容迁移。测试包括精确中心及手动偏位、活动/完成存档、真实电机点击移动；不吸回用户手动位置。
- `native_prop_picking.gd`：只对实际ground_footprint_center带偏移的核心启用物件拾取，1-1保留原路径；逐像素alpha映射到原mark.tile。保留物理地形遮挡，补静态卡片、角色当前帧及不透明Mesh三角形遮挡。透明边距不抢地面点击。静态像素/三角形缓存，屏幕射线不在画布内先返回；动态ViewportTexture仅真正命中时取当前帧，不缓存过期帧。
- `original_cloud_dressing.gd`：补完整底面检查后发现cloud-1塔后角越北岸.0345、cloud-3粉拱门两后角越边.0241。分别仅z+.08、x/z+.05，保持同高原支撑身份与原始点metadata。其余云庭物件未移动。
- 核心位图脚锚、接触补片、收藏浮动及其高度未改；没有明确建筑阻挡证据的收藏/rest叠置不做猜测迁移。

## CPU证据

组合批次 `.tmp/mechanism-placement-final-cpu/checks.json`：7套均通过，稳定源码`68ec1bf241bfa65dd440c99b954a3ad019ea1425242117cff944a77984394fb2`，569文件。

| 套件 | 检查 | 证据范围 |
| --- | ---: | --- |
| native_core_click_test | 5594 | 全11个后续主线、19个可见初/完成核心，普通/全景alpha命中、透明/前景卡片/实体网格负向遮挡；1-4真正输入→物理接近→主动repair |
| native_core_stance_test | 495 | 原有核心站位、完整胶囊支持、主动repair动画与保存恢复 |
| native_instrument_stance_test | 225 | 1-3/2-1/3-2/3-3/3-4全部普通机关，默认与实际移动后胶囊避让、完整支持、手动保存位置 |
| native_mechanism_props_test | 267 | 原机关尺寸/状态/符号、无碰撞添加、真实动作及撤销、水位指针随动 |
| native_prop_alignment_test | 3768 | 全15关mark/item逻辑根及环不变；34正反运动中每个机关底座32点圆周支持与资源复用 |
| native_original_cloud_test | 434 | 原云庭图形比例/状态；建筑底面9×9完整映射支撑；鸟全宽及原动效 |
| native_motion_cache_test | 9087 | 运动缓存和原机制轨迹、120角色采样，运动帧无额外tiles调用 |

最后仅补拾取画布边界早退（避免不相交动态卡片GPU读回），定向重验核心点击5594项通过：`.tmp/mechanism-placement-final-picking/checks.json`，稳定源码`ae28a268b29039c42fd98e9112c263180daefa485cadcce5f2107d19703a6464`，569文件。它与上面的组合证据属相邻版本，不能把组合版本号改写为最终版本。

相对锁定5ea00批次重新运行同一只读审计，30初/完成状态、197个mark/item根、140张直接子卡片的root/tile、画布宽、offset、local position逐项完全一致，见`.tmp/mechanism-placement-invariants.json`与`.tmp/position-audit-mechanisms-after.log`。机关mesh只平移，云庭两处scenery只平移，未更改尺寸常量。

失败证据保留：`.tmp/mechanism-placement-cloud-footprints-detail`明确记录修复前云庭完整底面的两处越界；早期拾取/姿态测试调试日志均未覆盖。

## GPU交接与界限

主验收重点：1-3初态转庭、2-1初态阀门、3-3转/升、3-4四机关的普通视图；动态前中后/撤销；cloud-1塔及cloud-3粉门的两后角；1-4偏移花瓣实际点击，其他后续关普通/全景核心不抢遮挡物前的点击。

无头渲染器没有伙伴/鼹鼠ViewportTexture像素；该类动态角色的真实alpha遮挡由实际GPU当前帧验证，CPU只验证静态卡片、主角源图、实体网格和地形逻辑。上述通过不等于GPU画面、美术比例或性能验收。完整15关物理路线与最终正式包归主任务统一验证。
