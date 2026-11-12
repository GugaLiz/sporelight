# 全关卡合同核对 · 2026-11-10

对应 [规则总文档](../../56-全关卡优化规则与首关验收基线.md) 与 [逐关清单](../../57-全关卡玩法契约与优化清单.md)。本次只新增/修订文档与审核证据，未修改游戏运行代码、关卡定义、图片或存档格式；本轮开始时已有的1-2试玩修改保持原样。

## 复核方式

核对主线/云庭定义、world 的通路/命令/完成/回滚实现、session 提交、现行 profile、首关文档及全部参考路线。记录正式关卡与规划试玩、历史产品稿与当前逻辑的区别。

执行已有检查：

```sh
node tools/godot-migration/check-native.mjs --only=native_route_test,native_first_garden_contract,rule_normalize,session_test --output=docs/qa-godot-native/level-contract-audit/headless
```

过滤器按名称包含关系选择，`session_test` 同时命中两套 session 测试。

| 检查 | 本轮结果 |
| --- | --- |
| `rule_normalize` | 30 项通过 |
| `session_test` | 17 项通过 |
| `native_session_test` | 15 项通过 |
| `native_first_garden_contract_test` | 93 项通过 |
| `native_route_test` | 1826 项通过；12主线+3云庭的参考路线全部完成 |
| 合计 | 5套，1981项通过 |

详细日志见 [headless/checks.json](headless/checks.json)。19208次接触采样中，最大身体/表面差约0.11891，最大视觉脚点/表面差约0.10833。这只是该批无头真实角色参考路线的测量，不是GPU画面或所有体积边界都已验收。

检查期间运行源摘要稳定：`b2786fabf6dd9982a0af42d776c6e8494be48e45c55e39a4ba1fda6de171f802`，478个文件。

## 基线与范围

[baseline.json](baseline.json) 记录实际15关的编号、目标、资源/模块摘要、定义指纹、现行首关参数及关键源码指纹。定义哈希采用UTF-8、键排序、无多余空格的JSON；文件哈希采用原始字节。它用于以后判断修改范围，不是通过行为检查的替代品。

本轮没有重录参考fixture，没有启动新的美术改版或发布新包，没有清空任何旅程。全量旧JS `rule_reference` 的首关16格/当前19格差异仍按文档52单独处理。此次完整路线使用当前原生应用和真实角色，首关终点按当前标记解析。

没有声称已覆盖所有替代解与错误顺序；逐关待补的负向、回程、恢复、画面和输入检查已在文档57列明。也没有把文档47–55的历史截图或通过数字当作本轮新画面验收。
