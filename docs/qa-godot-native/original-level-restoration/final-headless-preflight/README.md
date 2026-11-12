# 最终原站语义回归：旧断言迁移与预检

2026-11-11。冻结运行时`29da2daf52a04706ac29339910bb3c4a9c2977c626f377ad1a511af08e389c42`，558文件。本分工只改测试，未修改运行时，也未启动GPU。最终串行批次见[final-headless](../final-headless/checks.json)，其日志中的运行时ERROR计为失败，即使测试自身打印passed=true。

## 明确替代的历史候选

原站`src/app/garden2/render.ts`的地面像素与`itemArt.ts`的手持叶包是不同语义。此前“地面与手持主体等大”、主角手持真实完整镜面、铃铛携带mesh缩放.7都是旧候选，不是原站不可改golden。现`native_prop_scale_test`独立使用原源常数进行验证，不读生产宽度表作为期望值：

- 地面：露水植株49px、露水包34px、光/水晶36px、镜叶52px、铃铛28px、虫40px、收藏微光35px，均除原全格70px并乘原生全格投影宽√2；主体alpha框另外测量，不把画布当主体。
- 携带：缩略图18px/露水25px、叶包缩放.65、伙伴额外.66；按保留的角色画布1.6/原115px换算。测真实合成图alpha轮廓、透明边、.65/.66 metadata、手部锚点、场景深度、日月颜色以及热缓存。
- 真正执行全部8个参考拾取（包括伙伴提灯）、8个命令列表提供的放下、镜叶/灯方向改变、撤销、恢复；另外保留4个原参考特定放下。地上镜面仍独立检查.53×.42×.025真实panel、4条边和规则angle，包内缩略图不冒充地面反射器。
- 云庭星种继续使用独立原星形与专用携带物，没有套主线叶包。

[prop-scale-source-pouch.log](prop-scale-source-pouch.log)：预检660项通过；不宣称GPU美术合格。

## 先实证、后改旧节点断言

[alignment-original.log](alignment-original.log)证实旧`native_prop_alignment_test:93`依然访问`blue_flowers`，但主线rest/observe已经恢复原`flowers`，云庭未发现故事点原本没有地面花。改为验证对应原资源、主线34px比例及同一交互根中心；云庭未发现状态验证无多余地面道具。完整环/支撑/运动门槛保持。

[mechanism-original.log](mechanism-original.log)证实旧`native_mechanism_props_test`仍要求2-4子控制器(.45,-.45)，与已独立验过花轮廓间距和全船底座的(.60,-.60)不符；并要求云庭通用`MotionKind`/`InstrumentBase`，原矢量控制器已替代这些节点。测试改为已记录显示轴以及原矢量资源/58px格比例/深度/碰撞；新增云庭参考状态下真实rotate/lift与undo，不删掉动作或逻辑验证。

## 没有被当成旧断言的运行时错误

上述两个预检都记录了真实`ERROR: Original scenery has no real flat support: 2-1/7/fern`，来自`original_garden_dressing.gd:206`，调用链经过`set_motion → refresh_world → _update_props → place_original`。蕨草原点(-4.24,4,h0)、原支撑`f:-4:4`。可能是水位过渡期间逻辑tile索引与物理surface集合的时序差异；已向主任务报告，未压错、未改迁移阈值、未添加假支撑。最终批次是否因此失败，以[checks.json](../final-headless/checks.json)为准。
