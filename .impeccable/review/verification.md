# 2026-11-06 主题重构验收记录

## 已完成

- `flutter test --no-pub --dart-define=CAPTURE_UI=true test/workspace_test.dart test/desktop_title_bar_test.dart`：11 项通过。
- `flutter analyze --no-pub`：No issues found。
- `flutter build windows --release --no-pub`：成功生成 Windows x64 Release。
- 24 张 Flutter widget 截图：1440、1000、720、440 四种宽度，各含发送、设备、消息、记录、设置、接收确认。
- 独立 Impeccable 视觉复审：ship；无未解决的实质问题。
- 原生 Release 启动：进程响应正常，界面显示局域网已就绪；观察到设置页、自绘标题栏和首页的可访问性内容，启动错误日志为空。

## 本轮交互覆盖

- 接收请求清单与明确接收操作。
- 会话之间的草稿隔离与回车发送目标。
- 中文输入法组合期间回车不发送，组合提交后回车正常发送。
- 拖入文件后必须明确选择接收设备；对方离线禁止发送。
- 历史筛选和设置保存；440 宽度、1.3 倍文字布局。
- 自绘标题栏的既有组件测试。

## 证据边界

PNG 截图来自测试专用 `UiFixtureService`，设备、文件、消息、进度和速度都是布局夹具，不是实际传输结果。生产应用始终使用真实 `LanService`。

本轮没有改动网络协议与服务实现，没有重新执行完整网络测试套件，也没有验证两台物理设备之间的真实网络传输。原生窗口检查期间用户开始操作应用，因此没有继续自动切换页面；五页完整布局覆盖来自 widget 测试与截图复审。
