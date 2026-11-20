# 角色重绘图集包装与审阅

2026-11-17。此目录记录完整 ImageGen 姿势的机械包装与像素侧候选审阅，不代表 Godot GPU 动作已经通过。

## 实际输入与去重

- `actor-frontwalk-sheet.png`：七种完整正面步态；原4×2布局最后一格为空。
- `actor-backwalk-sheet-v2.png`：六种完整背面步态。初稿误把正面红莓／绳结画在背面，已由 ImageGen 改为原层叠叶披肩；旧初稿保留，不作最终输入。
- `actor-sidewalk-sheet.png`：七种完整侧面步态，首格双脚齐站；完整首格也用于新侧面 idle，防止停步切换身体尺寸。
- `actor-jump-sheet.png`：五种完整跳跃表情姿势，保持原12个播放位置的旧重复组；没有在PNG内追加整个人物的跳跃轨迹。
- 背面 idle 复用修正后背走首格；sow末帧复用同语义完整闭眼鞠躬稿。原文件各自的别名、完整timeline、fps、loop与已有运行时校准仍然保留。

配置共33个去重actor条目可解析：已有正面idle一条，本工具更新其余32条。PNG原图不覆盖，角色身份、碰撞、速度、存档与能力未变。

## 包装方法

`pack-actor-redraw-sheets.mjs` 只做完整格裁片、等比注册与透明PNG／GIF包装。不做颜色抠图、身体切片重组、光流、形变或重新绘画。每个clip只求一次scale和共同anchor，再统一作用到所有格；不会把举手／迈步每一帧单独fit成同一bbox。1774×887的4×2输入以分数格边界向下取整分区，保留443／444像素格的完整原图像素；没有先拉伸图集凑整数格。

背走／跳跃母图的普通预览曾显示棕色背景，但实际角落alpha为0。合成到橄榄底复查后背景不可见，因此没有把透明RGB颜色当作需要再次抠除的底色。四张最终sheet都有足够透明像素和连续alpha，完整主体没有触到格边。

### 原生动作校准

现 `native_actor_pose.gd` 对蹲下／播种／鞠躬使用原有独立scale和鞋底坐标。新动作PNG依据这些实际运行值反推注册，避免先缩成站姿大小后再被运行时缩小一次。interact、sow、salute各个候选的实际头宽均为116逻辑像素；脚锚沿用原表，土堆和裙摆不当作鞋底。

像素检查的完整数值、整图SHA、格坐标、所有播放位置与fps见 [actor-sheet-review.json](actor-sheet-review.json)。动作预览 `actor-*-runtime-pose.png` 已应用原scale/foot，仍只是二维采样预览。

新interact蹲姿较旧稿更直，保持真实鞋底后，头和手较原姿偏右约0.1m。该差异保留为实际GPU手／物件接触的审阅项，不能靠把图片虚移到身体脚外掩盖。滚动球以单一等比缩放居中于原89×99画布，没有拉成旧整幅包围盒的椭圆。

## 动画审阅文件

`frontwalk.gif`、`backwalk.gif`、`sidewalk.gif`、`jump.gif` 按现有完整timeline回填。GIF时间受10ms格限制，按累计时间量化以控制整圈误差；游戏里的fps和loop定义没有因此更改。GIF优化器可能合并相邻完全相同画面，不能拿GIF文件pages数量反推引擎帧数。

各clip的 `*-registered.png` 为未放大的256逻辑画布联系表；对应橄榄底母图只用于检查alpha。原生GPU应另检查停步→迈步→循环、正侧背切向、跳跃开始／中段／落地、播种／照料中间帧和滚动后的恢复。

## 复现

```powershell
node tools/godot-migration/pack-actor-redraw-sheets.mjs --apply-config
```

不加 `--apply-config` 只生成候选报告和预览，不写共享配置。运行主题激活、Godot导出和4222服务由主任务统一处理。
