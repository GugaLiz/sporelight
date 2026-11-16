# 12 关元素清单（生成文件）

由 `godot/tests/export_element_inventory.gd --write` 读取现行关卡和真实原生舞台生成；不是人工估数。详细实例、状态绑定、原始关卡 payload 和全域定义见 `inventory.json`。

| 关卡 | 固定地表 | 机关标记 | 移动模块 | 根路锚点 | 搬运物 | 收集物 | 装饰实际精灵 | 延迟装饰 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1-1 初生的孢子 | 19 | 4 | 0 | 1 | 0 | 3 | 22 | 0 |
| 1-2 第一朵花 | 12 | 4 | 0 | 1 | 0 | 3 | 11 | 0 |
| 1-3 苔藓山谷 | 36 | 4 | 1 | 0 | 0 | 4 | 21 | 0 |
| 1-4 鼹鼠的家 | 38 | 8 | 0 | 0 | 1 | 4 | 35 | 0 |
| 2-1 池塘之声 | 36 | 6 | 1 | 0 | 1 | 4 | 12 | 0 |
| 2-2 涟漪之谜 | 34 | 7 | 0 | 0 | 2 | 5 | 7 | 0 |
| 2-3 雨滴节拍 | 18 | 6 | 1 | 0 | 0 | 4 | 4 | 0 |
| 2-4 池塘守护者 | 18 | 7 | 1 | 0 | 1 | 5 | 1 | 2 |
| 3-1 微光引路 | 41 | 6 | 0 | 0 | 1 | 5 | 11 | 0 |
| 3-2 影子的形状 | 22 | 9 | 0 | 0 | 2 | 5 | 5 | 0 |
| 3-3 共生之歌 | 36 | 8 | 2 | 1 | 1 | 6 | 12 | 0 |
| 3-4 沉睡的守护者 | 36 | 10 | 4 | 1 | 1 | 0 | 8 | 0 |

每关都包含露薇与小苔灵两个角色定义。装饰精灵数是初始状态实际节点，不是浏览器旧版 SOURCE_PROPS 条目数；程序化装配、特效和变化状态由对应 adapter 记录，不把每个网格零件当成独立游戏元素。

## 1-1 初生的孢子

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `effect.collectible` × 3
- `effect.environment` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.root` × 1
- `scenery.blue-flowers` × 2
- `scenery.bush` × 1
- `scenery.fern` × 4
- `scenery.pink-flowers` × 3
- `scenery.red-mushroom` × 2
- `scenery.small-pebbles` × 2
- `scenery.stone-lantern` × 1
- `scenery.trailing-vine` × 4
- `scenery.yellow-flowers` × 3
- `surface.floor` × 19
- `surface.generated-routes` × 1
- `surface.root` × 3

## 1-2 第一朵花

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `effect.collectible` × 3
- `effect.environment` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.rock-obstacle` × 1
- `prop.root` × 1
- `scenery.blue-flowers` × 1
- `scenery.fern` × 1
- `scenery.pink-flowers` × 1
- `scenery.red-mushroom` × 2
- `scenery.stone-lantern` × 1
- `scenery.trailing-vine` × 4
- `scenery.yellow-flowers` × 1
- `surface.floor` × 12
- `surface.generated-routes` × 1
- `surface.root` × 5

## 1-3 苔藓山谷

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `effect.collectible` × 4
- `effect.environment` × 1
- `module.rotate` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.turn` × 1
- `scenery.arch` × 2
- `scenery.berry-bush` × 2
- `scenery.blue-flowers` × 4
- `scenery.bush` × 2
- `scenery.fern` × 2
- `scenery.gold-lotus` × 4
- `scenery.pink-flowers` × 2
- `scenery.red-mushroom` × 4
- `scenery.small-pebbles` × 2
- `scenery.stone-lantern` × 2
- `scenery.trailing-vine` × 7
- `scenery.yellow-flowers` × 2
- `surface.floor` × 36
- `surface.generated-routes` × 1
- `surface.module` × 14

## 1-4 鼹鼠的家

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `assembly.sanctuary` × 1
- `carry.bell` × 1
- `effect.collectible` × 4
- `effect.environment` × 1
- `prop.bell-return` × 1
- `prop.item` × 1
- `prop.latch` × 1
- `prop.lever` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.plate` × 1
- `prop.rest` × 1
- `scenery.berry-bush` × 4
- `scenery.blue-flowers` × 4
- `scenery.bush` × 4
- `scenery.fern` × 2
- `scenery.flower-gate-frame` × 1
- `scenery.flower-gate-seal` × 1
- `scenery.gold-lotus` × 6
- `scenery.ivory-lotus` × 2
- `scenery.pink-flowers` × 4
- `scenery.procedural-sprite` × 2
- `scenery.red-mushroom` × 2
- `scenery.small-pebbles` × 2
- `scenery.stone-lantern` × 4
- `scenery.trailing-vine` × 12
- `scenery.yellow-flowers` × 4
- `surface.floor` × 92
- `surface.generated-routes` × 1
- `surface.root` × 5

## 2-1 池塘之声

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `carry.dew` × 1
- `effect.collectible` × 4
- `effect.environment` × 1
- `module.lift` × 1
- `prop.item` × 1
- `prop.observe` × 1
- `prop.planter-task` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.valve` × 1
- `scenery.berry-bush` × 4
- `scenery.blue-flowers` × 4
- `scenery.fern` × 2
- `scenery.ivory-lotus` × 4
- `scenery.lotus-pool` × 2
- `scenery.pink-flowers` × 2
- `scenery.river-rock` × 2
- `scenery.stone-lantern` × 2
- `scenery.yellow-flowers` × 2
- `surface.floor` × 36
- `surface.generated-routes` × 1
- `surface.module` × 27
- `surface.root` × 3

## 2-2 涟漪之谜

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `carry.mirrorA` × 1
- `carry.mirrorB` × 1
- `effect.collectible` × 5
- `effect.environment` × 1
- `effect.light-path` × 1
- `prop.item` × 1
- `prop.lamp` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.rock-obstacle` × 1
- `prop.slot` × 1
- `prop.turn` × 1
- `scenery.berry-bush` × 2
- `scenery.fern` × 2
- `scenery.lotus-pool` × 2
- `scenery.pink-flowers` × 2
- `scenery.river-rock` × 2
- `scenery.stone-lantern` × 2
- `scenery.yellow-flowers` × 2
- `surface.floor` × 34
- `surface.generated-routes` × 1

## 2-3 雨滴节拍

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `effect.collectible` × 4
- `effect.environment` × 1
- `module.rotate` × 1
- `prop.latch` × 1
- `prop.observe` × 1
- `prop.passenger-deck` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.song` × 1
- `scenery.fern` × 2
- `scenery.lotus-pool` × 2
- `scenery.pink-flowers` × 2
- `scenery.stone-lantern` × 2
- `surface.floor` × 18
- `surface.generated-routes` × 1
- `surface.module` × 19
- `surface.root` × 5

## 2-4 池塘守护者

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `carry.bug` × 1
- `effect.collectible` × 5
- `effect.environment` × 1
- `module.slide` × 1
- `prop.observe` × 1
- `prop.planter-task` × 2
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.shared-plant-invitation` × 1
- `prop.turn` × 1
- `scenery.fern` × 1
- `scenery.stone-lantern` × 1
- `scenery.wood-lantern` × 2
- `surface.floor` × 18
- `surface.generated-routes` × 1
- `surface.module` × 27
- `surface.root` × 3

## 3-1 微光引路

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `carry.lamp` × 1
- `effect.collectible` × 5
- `effect.environment` × 1
- `effect.light-path` × 1
- `prop.item` × 1
- `prop.lever` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.slot` × 1
- `scenery.blue-flowers` × 4
- `scenery.blue-mushroom` × 2
- `scenery.fern` × 4
- `scenery.glow-flower` × 2
- `scenery.small-pebbles` × 2
- `scenery.stone-lantern` × 4
- `scenery.violet-crystal` × 4
- `surface.floor` × 41
- `surface.generated-routes` × 1
- `surface.root` × 3

## 3-2 影子的形状

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `carry.moonPost` × 1
- `carry.sunPost` × 1
- `effect.collectible` × 5
- `effect.environment` × 1
- `effect.shadow-projection` × 1
- `prop.item` × 2
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.shadow-memory` × 1
- `prop.slot` × 2
- `prop.valve` × 1
- `scenery.blue-flowers` × 2
- `scenery.blue-mushroom` × 2
- `scenery.glow-flower` × 2
- `scenery.small-pebbles` × 2
- `scenery.stone-lantern` × 2
- `surface.floor` × 22
- `surface.generated-routes` × 1
- `surface.shadow` × 3

## 3-3 共生之歌

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `carry.dew` × 1
- `effect.collectible` × 6
- `effect.environment` × 1
- `module.lift` × 1
- `module.rotate` × 1
- `prop.item` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.root-basin` × 1
- `prop.shared-growth-anchor` × 1
- `prop.turn` × 1
- `prop.valve` × 1
- `scenery.blue-flowers` × 2
- `scenery.blue-mushroom` × 4
- `scenery.fern` × 4
- `scenery.glow-flower` × 4
- `scenery.small-pebbles` × 4
- `scenery.stone-lantern` × 2
- `scenery.violet-crystal` × 4
- `surface.floor` × 36
- `surface.generated-routes` × 1
- `surface.module` × 40
- `surface.root` × 12

## 3-4 沉睡的守护者

- `actor.buddy` × 1
- `actor.luvie` × 1
- `adapter.scenery` × 1
- `carry.mirror` × 1
- `effect.environment` × 1
- `effect.light-path` × 1
- `module.lift` × 1
- `module.rotate` × 3
- `prop.item` × 1
- `prop.observe` × 1
- `prop.planter-terminal` × 1
- `prop.rest` × 1
- `prop.root` × 1
- `prop.slot` × 1
- `prop.turn` × 2
- `prop.valve` × 2
- `scenery.blue-flowers` × 2
- `scenery.blue-mushroom` × 2
- `scenery.fern` × 2
- `scenery.glow-flower` × 2
- `scenery.light-tower` × 2
- `scenery.small-pebbles` × 2
- `scenery.stone-lantern` × 2
- `scenery.violet-crystal` × 2
- `surface.floor` × 36
- `surface.generated-routes` × 1
- `surface.module` × 62
- `surface.root` × 15

导出时完成 48 项只读性、JSON 往返、装饰观察与稳定 ID 检查。此清单不等于 GPU 视觉验收。
