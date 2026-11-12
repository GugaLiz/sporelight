# 浏览器验收中的占用核心接近站位

本次只调整 QA 工具，未修改生产代码、关卡定义或原路线 reference。

## 适用范围

唯一例外是 `3-4` 的明确 `kind=core` 标记 `f:-4:0`，其完整石基占据中心；生产首选接近站位是原有相邻同高格 `f:-3:0`。`qa_core_approach.py` 还要求当前关卡定义仍标记该核心、实时 tiles 存在两格且曼哈顿距离为 1、高差不超过原 `near` 合同的 0.1、接近格非 solid。实际到达还要求停止移动、逻辑与 native support 一致、有限脚点在实际接近格内并与实际地面接触。

普通 floor、其他关卡、其他近邻格、不同高度、只修改 support 标签或仍在移动均不能借此通过。石基碰撞与中心不可走由同源 native 路线和碰撞套件独立验证；该浏览器助手不宣称读取了 GPU 深度或完整碰撞形状。

## 工具接口

- `authored_core_approach(state, requested)`：返回唯一许可的接近合同，或 `None`。
- `reached_core_approach(state, requested, actor=None)`：返回真实停稳到达证据，或 `None`。
- `check-native-browser.py` 的 `move_to(page, tile)` 保持接口和原路线请求不变，点击仍提交原核心目标，由生产寻路执行。只有该显式核心的键盘回退选择上述接近格；日志保留原 `target` 并另写 `physicalTarget`，成功写 `inputTrace.kind=core-approach`。
- `check-level-acceptance.py` 保持原 snapshot 设置，只在 `actors` 中认可上述恢复迁移，并写入 `results[].coreApproaches`。完成状态、物品、机关等字段仍逐项严格比较。

旧 fixture 的正常标准化差异（例如补齐模块 turns 默认键）不在此例外范围，若出现应独立查明，不能归入“核心接近”而忽略。

## 使用

```powershell
python tools/godot-migration/test_qa_core_approach.py
python tools/godot-migration/check-native-browser.py --base=http://localhost:4291/ --mode=gameplay --levels=3-4 --sizes=1280x720 --output=docs/qa-godot-native/all-hard-bases/core-browser
python tools/godot-migration/check-level-acceptance.py --base=http://localhost:4291/ --levels=3-4 --sizes=1280x720 --output=docs/qa-godot-native/all-hard-bases/core-states
```

本次工具检查：5 个 CPU 正负测试通过；三个 Python 工具语法编译通过。本文不表示上述两条浏览器命令已执行；GPU 由主任务串行运行，运行结果以对应独立报告为准。
