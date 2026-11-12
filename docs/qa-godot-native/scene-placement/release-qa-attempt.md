# 正式包QA接口取图误用记录

2026-11-11，源码f79f639ca207a8d39426aa680d90e9bd9f55c701dbf3eec3968e4b77a7c10974/572。

`check-scene-placement-browser.py --base http://localhost:4262/`首次指向了release包，等待`window.__sporelightState.snapshot`120秒后超时，没有生成关卡取图或通过结论。`main.gd`只在debug Web开启查询参数和QA状态桥，release不提供该接口；此失败不能当作正式游戏加载耗时测量或画面结果。

保持生产代码和release调试边界不变，改导出同源码`scene-position-final-qa`调试包进行准备状态取图；正式包另做无QA普通入口、真实行走/旋转与视觉复核。原失败不以修改release开关掩盖。
