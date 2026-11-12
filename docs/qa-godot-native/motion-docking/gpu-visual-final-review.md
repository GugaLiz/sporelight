# 连续运动修复后的独立复核（1503）

源码：`1503ad6ad584bf64d8df0543cef6ff380761beb21cc7abbb92a61da9772de293`（496 文件），官方 debug Web 模板。证据：[定点批次](gpu-visual-final-probe/checks.json)、[其余批次](gpu-visual-final-remaining/checks.json)。

两批共 40 条自动记录均通过、浏览器/Godot 错误为 0；去掉重复的双尺寸 1-1 基准后，为 38 个唯一用例：全部 15 关 × 2 尺寸镜头，以及 1-3、cloud-1、cloud-2、cloud-3 × 2 尺寸运动。实际输入和完整 PNG 均保留，自动报告的 `visualReview: pending` 不改写为人工结果。

已人工检查全部镜头三联图（arrival / overview / returned）、全部 8 个运动关键帧表、cloud-1/cloud-3 双尺寸完整连续帧分页，以及 cloud-1 桌面半转原图、1-4 双尺寸全景原图。cloud-1/cloud-3 旋桥已连续转动，保留源顶面与封闭侧壁；1-3 旋转和 cloud-2 升降未发现几何或接触回归。1-4 全景底座已避开消息面板。

尚未通过的视觉项仅为 cloud-3 全景：右下岛屿前沿/底座仍进入消息面板。桌面安全区底边 578，最低可走格中心 577.798645，消息区从 y=590 起；横屏安全区底边 288，最低格中心 287.897919，消息区从 y=300 起。格子中心在安全区内不能证明实际地形边缘/底座完整可见。原图：[桌面](gpu-visual-final-probe/1280x720/framing/cloud-3/overview.png)、[横屏](gpu-visual-final-probe/844x390/framing/cloud-3/overview.png)。其余全景未发现新的面板遮挡。

结论：本构建的连续运动修复和上述回归通过人工复核；全景仍需按真实地形投影边界修复，再重跑全 15 关双尺寸镜头。这里不宣称全部视觉验收通过，不覆盖普通 release 性能。
