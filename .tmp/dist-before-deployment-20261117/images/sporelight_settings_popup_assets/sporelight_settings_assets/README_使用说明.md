# 《微光苔原 / Sporelight》设置弹窗切图包

本包按照「设置页输出清单.md」生成，包含设置弹窗框架、标题文字、滑块、选项卡、开关、下拉菜单、按钮三状态、确认弹窗、提示文字与特效装饰素材。

## 九宫格建议
- ui_settings_bg.png：left/right/top/bottom = 36px
- ui_settings_frame.png：left/right/top/bottom = 40px
- ui_confirm_dialog_bg.png：left/right/top/bottom = 28px
- ui_dropdown_menu_bg.png：left/right/top/bottom = 20px
- ui_slider_bg.png / ui_slider_fill.png：左右保留 4px，中间横向拉伸
- 大按钮、下拉框、选项卡：左右圆角区域不要拉伸，中间区域可横向拉伸

## 交互状态
- normal：默认状态
- hover：悬停状态，边缘更亮
- press：点击状态，整体略暗/下压
- toggle_on/off：开关打开/关闭
- slider_thumb_hover/press：滑块悬停/拖动中

## 开发建议
建议将文字类素材用于高保真还原；如果后续需要多语言，推荐用 CSS/WebFont 渲染文字，PNG 只保留面板、按钮背景、图标和特效。
