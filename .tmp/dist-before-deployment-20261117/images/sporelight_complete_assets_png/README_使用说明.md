# Sporelight《微光苔原》完整素材包

本包根据上传的 6 张设计图与完整清单整理，包含角色、UI、世界元素、图鉴、特效与背景素材。

## 目录
- characters：露薇角色姿态与序列帧
- ui/buttons：所有按钮默认/悬停/按下/禁用状态
- ui/panels：弹窗、对话框、边框、卡片
- ui/icons：UI图标
- ui/progress：进度条
- ui/logo：Logo与章节文字基底
- world：可交互世界元素与生长序列
- gallery：图鉴卡片、插图与详情组件
- fx：特效粒子
- backgrounds：页面与关卡背景、视差层
- meta：素材清单 JSON

## 九宫格规则
- ui_dialog_normal.png：四角固定 24px，小尾巴固定左下，正文区域拉伸。
- ui_panel_popup.png：四角固定 24px，边缘拉伸，中间平铺或拉伸。
- ui_frame_border.png：角固定 32px，边框拉伸，中间透明。
- ui_progress_bg.png / ui_progress_fill.png：左右端各 12px 固定，中间横向拉伸。
- ui_divider.png：左右装饰固定，中间线段横向拉伸。

## 动画建议
- idle：01 → 02 → 03 → 02，0.8s 循环。
- roll：01 → 02 → 03，0.35s 循环，配合 fx_spore_trail。
- sow：01 → 02 → 03，播种第2帧触发 fx_sow_dust + fx_growth_ring。
- bow：01 → 02，结算页使用。

## 注意
部分素材由当前设计图与已生成素材进行切分、变体、补齐，已按透明 PNG 输出。实际项目中建议再进行一次美术精修与动画帧对齐。
