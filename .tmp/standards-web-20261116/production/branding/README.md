# Sporelight 品牌图标

代码原生SVG母版：`icon.svg`（应用图标）和`favicon.svg`（小尺寸双蘑菇）；`pinned.svg`是Safari固定标签用的单色版。按用户指定，以主角的红色白斑尖蘑菇帽与圆帽蘑菇宠物作为身份特征，保留苔绿底和奶油色。原角色和游戏场景素材保持不变；此版本替代此前的嫩芽图标。

重新导出：

```powershell
python -B scripts/prepare_brand_icons.py
```

需要Python/Pillow及项目固定版Godot，也可通过`--godot`指定其可执行文件。脚本先由Godot的SVG渲染器按各尺寸生成PNG，再按已渲染帧组装ICO；不从一张小图连续放大。

| 用途 | 输出 |
| --- | --- |
| 浏览器tab、书签 | `favicon.svg`、`favicon-16.png`、`favicon-32.png`、`favicon.ico` |
| Safari固定tab | `pinned.svg`，颜色由HTML指定 |
| Apple收藏/主屏幕 | `apple-touch-icon.png`，180px、不透明背景 |
| 其他主屏幕/快捷方式 | `site.webmanifest`、192/512px普通PNG和独立maskable PNG |
| Godot运行窗口 | 复制`icon-512.png`到`godot/assets/branding/icon.png` |
| Windows程序、任务栏 | `sporelight.ico`，16/24/32/48/64/128/256px，复制到Godot同目录 |

manifest在`branding/`目录，`id/start_url/scope`使用`../`，以适配站点根目录和GitHub Pages子目录。没有启用离线缓存或新增服务工作线程。

公开资源由Vite的`publicDir`及Godot导出脚本复制；不要只改`godot/build`中的文件。`assets/favicon.ico`是兼容隐式请求的副本。`manifest.json`记录生成来源、输出尺寸和SHA；当前预览位于`docs/qa-godot-native/mushroom-icons/preview.png`，旧方案预览留作历史。
