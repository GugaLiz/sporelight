# 当前布局与历史 TS 规则测试适用范围审计

本次仅修改 `godot/tests/rule_normalize.gd`；未修改运行时、关卡、历史 `reference.json` 或 `save-cases.json`。原 delivery-headless 失败日志保持不动。

## 两项失败的原因

- `rule_reference`：归档提交 `5791bbc3dd90549b4c7ea302507ead577f51dd67` 的 1-1 初始格数为 16，现行已批准原生首关为 19 格，核心在 `f:3:-2`。现行契约见 docs56 与 `native_first_garden_contract_test.gd`。1-2 归档同样早于 docs68 的 revision2：现行删除 `f:3:1`、`f:4:2`，要求第四节真实接岸，存档新增 `layoutRevision:2`。因此不能宣称当前这两关与旧 TS 逐字段等同，不能回退布局或重录归档来消除差异。原严格历史比对脚本保持原状，未静默跳过案例。
- `rule_normalize` 的 `1-2/json-numeric-enums`：归一化实际成功，旧 expected 只缺 `layoutRevision:2`。该案例人物仍在 `f:0:1`，没有触发迁移；显式补此唯一字段后整个快照严格相等。测试预期现明确增加该版本戳，其余字段仍按原 expected 比较，另测幂等、输入未变、四个枚举整数类型、revision2 拒绝旧落脚 ID、错误/未来版本拒绝。

## 独立验证

[逐关原始严格审计](per-level.json)：1-3、1-4、2-1～2-4、3-1～3-4 全部通过，共 **49 个案例、1,665 个命令、5,044 项检查**。每一步仍比较完整观测、存档往返、未来世界隔离。2-2 为 3 个案例、93 个命令、282 项检查，墙坐标数值比较修复没有破坏既有 TS 正解/拒绝/全收集参考。此次逐关调用没有执行该历史脚本末尾的全关 save-cases 比对，不将其计入覆盖。

[现行契约定向结果](current-contracts/checks.json)：

| 套件 | 检查数 | 结果 |
| --- | ---: | --- |
| rule_normalize | 40 | 通过 |
| native_first_garden_contract_test | 91 | 通过 |
| native_second_garden_fourth_link_test | 47 | 通过 |
| native_second_garden_save_migration_test | 872 | 通过 |

合计 **1,050 项**；运行时摘要稳定。第四节检查覆盖上下两条绕行、前三节连续/斜向输入阻断、第四节实体可通行、原观察点可达；4,636 个物理样本最大接触误差 `0.10176545381546`。迁移检查覆盖 0～4 节、两路线、旧落脚点、幂等、错误输入、真实仓库磁盘往返与旧文件读取。

归档文件 SHA-256（git diff 无变更）：

- reference.json：`26fa81bfdcccbdf288e4a70ddbc7aab3976315cd47b8d76b22ef0ab17c4ce8a2`
- save-cases.json：`ae26845b33c571d8e710a8fe12f9d6480c4ca7f26eb6767c79a6f297a48b652d`

结论：两条 delivery 失败是历史布局/存档契约不适用，未发现本轮墙数值比较导致的规则回归。不能把旧全12关 TS 历史脚本标为通过；当前首两关由现行原生契约和迁移/接岸负向检查验收，其余十关保留原 TS 严格比对。
