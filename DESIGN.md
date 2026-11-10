---
name: "邻传 NearLink"
description: "明亮、清晰、年轻的原生桌面互传工作区"
colors:
  blue: "#2463EB"
  blue-tint: "#EAF0FF"
  ink: "#17233A"
  muted: "#62718A"
  canvas: "#F5F7FC"
  shell: "#EDF2FC"
  line: "#E0E7F2"
  white: "#FFFFFF"
  field: "#F8FAFE"
  green: "#147D5A"
  mint: "#E7F6EF"
  danger: "#B83D4E"
  amber: "#986111"
typography:
  headline:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Segoe UI"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.35
  title-large:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Segoe UI"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.4
  title:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Segoe UI"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.5
  body-large:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Segoe UI"
    fontSize: "15px"
    lineHeight: 1.6
  body:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Segoe UI"
    fontSize: "14px"
    lineHeight: 1.5
  caption:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Segoe UI"
    fontSize: "12px"
    lineHeight: 1.5
  label:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Segoe UI"
    fontSize: "13px"
    fontWeight: 600
rounded:
  status: "8px"
  chip: "10px"
  control: "12px"
  avatar: "14px"
  surface: "16px"
  dialog: "20px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  surface: "24px"
  section: "28px"
  page: "32px"
components:
  button-primary:
    backgroundColor: "{colors.blue}"
    textColor: "{colors.white}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "13px 20px"
  button-outlined:
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "13px 16px"
  button-text:
    textColor: "{colors.blue}"
    rounded: "{rounded.control}"
  input:
    backgroundColor: "{colors.field}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "15px 16px"
  surface:
    backgroundColor: "{colors.white}"
    rounded: "{rounded.surface}"
    padding: "24px"
  navigation-selected:
    backgroundColor: "{colors.white}"
    textColor: "{colors.blue}"
    rounded: "{rounded.control}"
    padding: "14px"
  chip-selected:
    backgroundColor: "{colors.blue-tint}"
    textColor: "{colors.blue}"
    typography: "{typography.label}"
    rounded: "{rounded.chip}"
    padding: "8px"
---

# Design System: 邻传 NearLink

## Overview

**Creative North Star: "让分享，近一点"**

这是已实现的 Flutter Windows 桌面视觉系统：浅冷白工作区、柔和蓝色外壳、明亮蓝色行动与深色中文文字。年轻感来自色彩、呼吸空间和亲切文案，内容层级保持实用、清晰。品牌保留「邻传 / NearLink」，使用两段圆角端点组成的开放式 N 标志。

本文件从 `lib/ui/app_theme.dart`、`components.dart`、`workspace.dart` 与 `desktop_title_bar.dart` 提取。前置 YAML 是可复用 token 的规范层；其中 px 对应 Flutter 逻辑像素，不是物理屏幕像素。原生代码决定实际渲染，`.impeccable/design.json` 的 HTML/CSS 仅为组件 token 预览，不是另一套生产界面。产品能力见 [PRODUCT.md](PRODUCT.md)，协议见 [docs/PROTOCOL.md](docs/PROTOCOL.md)，页面策略见 [.impeccable/surfaces/desktop.md](.impeccable/surfaces/desktop.md)。

**Key Characteristics:**
- 清楚的中文任务标题与 Lucide 线性图标。
- 冷白底色、蓝色操作、文字与图标共同表达状态。
- 柔和圆角、平面色块、适应窗口宽度的任务布局。

## Colors

### Primary

`blue` 是活力蓝，用于主要行动、选中的设备、发送进度和焦点描边；`blue-tint` 为选择、拖放与轻量强调提供浅底。

### Secondary

`green` 与 `mint` 表达连接、完成和接收确认；`danger` 表达失败，`amber` 用于等待或需要注意的状态。状态仍须有文字。文件类型还使用紫色视频和莓色音频图标，这些是局部分类色，不扩展为全局品牌主色。

### Neutral

`ink` 用于主要文字，`muted` 用于说明与元信息；`canvas` 承载工作内容，`shell` 承载侧栏，`white` 承载内容表面。`line` 分隔控件，`field` 为输入框提供轻微底色。避免把浅背景 token 当成正文颜色。

**The State Has Words Rule.** 连接、进度、失败与送达必须同时使用可读文字，颜色只辅助辨认。

## Typography

中文界面继承 Microsoft YaHei UI，回退到 Microsoft YaHei 和 Segoe UI。NearLink 英文标识与部分数字元信息使用 Segoe UI。没有独立装饰性 display 字体。

前置 token 描述主题层级：headline 用于页面标题；title-large 用于较大的标题；title 用于内容组；body-large/body 用于正文；caption 用于辅助信息；label 用于按钮。`SectionTitle` 使用 16 逻辑像素、700 字重，状态标签使用 11 逻辑像素、600 字重；它们是组件内层级。品牌中文标识为 21 逻辑像素、800 字重。

正文允许自然换行，长文件名和设备名依场景截断或在详情中显示。避免通过缩小整页字体容纳内容；优先重排与滚动。

## Layout

宽窗口使用 208 逻辑像素侧栏；窗口宽度低于 900 时改为 76 的图标栏，低于 640 时改为高度 68 的底部导航。自绘 Windows 标题栏高度 64，保留拖动、系统菜单和窗口按钮。

普通页面内容最大宽度 1200，水平外边距通常为 32，底部为 32；底部导航布局的水平外边距为 18、顶部为 22。组件间距使用前置 spacing 尺度，局部布局可用源码中的细调值。Surface 默认内边距为 24。

响应式判断区分窗口宽度与组件的可用宽度：发送区在可用宽度 660 起并排，聊天在 760 起并排；页面标题在 620 以下将操作放到标题下方。具体五页组合和其余断点记在 surface brief，不能把单页的组成硬编码成所有页面的模板。

## Elevation & Depth

主要工作区依靠底色和留白区分层级。Surface 不添加自定义阴影，主要按钮显式使用零 elevation。对话框、浮动提示和系统窗口阴影保留 Flutter/Windows 的默认行为；接收提示的局部悬浮阴影例外见 [桌面 surface brief](.impeccable/surfaces/desktop.md)。本系统没有独立的全局阴影 token。

拖放区域的背景变化使用 `uiMotion`（180 ms），系统禁用动画时立即切换。按钮与 InkWell 的悬停、按压和焦点反馈由 Material 3 提供，不为其虚构另一套自定义动效参数。

## Shapes

控件采用 control 圆角，内容面板采用 surface 圆角，弹窗采用 dialog 圆角。设备头像、消息气泡采用 avatar 圆角，状态标签采用 status 圆角。接收设备选中时有明确的蓝色背景或描边。操作图标来自 Lucide；圆点仅辅助显示状态。

品牌标志使用独立的圆角 N 图形。程序内 `Brand` 以 36 × 36 显示蓝底、白色与薄荷色端点的应用图标；标题栏、紧凑导航和关于区域共用此组件。Windows 应用与托盘使用相同图形的多尺寸 ICO。品牌资源位于 `assets/brand`，蓝色为 `#2463EB`，图标薄荷色为 `#93F1CB`；后者仅用于 Logo，不改变界面的状态色。SVG 为矢量源，PNG 用于 Flutter，ICO 包含 16–256 px 九种尺寸。`tool/generate_icon.ps1` 将确认后的 ICO 同步到 Windows 资源。

## Components

### Buttons

FilledButton 为主要行动，OutlinedButton 为文件夹、连接等次要行动，TextButton 用于轻操作。前两者最小高度为 44；文本按钮最小高度为 40；图标按钮最小区域为 40 × 40 并带 tooltip。描边按钮文字为 13、500 字重，主要按钮使用 label token。禁用、悬停、按下与键盘焦点继承 Material 3。动作处理中保留文字并显示小进度指示器。

### Chips and status

筛选使用 ChoiceChip：白色默认底、选中使用 blue-tint，无默认勾号。StatusPill 使用状态色 8% 透明度的底色、10 × 6 内边距和可选圆点；标签本身传达状态。

Windows 与 Android 会话列表的消息预览行固定显示可读状态：绿色实心点配“在线”，灰色空心点配“离线”。状态不被草稿、文件预览或未读数替代；设备名称独占首行，长名称省略。群聊使用实际在线成员数（含自己），仅自己在线及退出、移出、解散分别显示对应文字。

桌面聊天接收外部文件拖放时，以白底、蓝色描边和 Lucide 文件夹图标覆盖当前聊天内容，明确显示接收方与松手动作。离线及整理文件中的反馈使用对应文案。松手即向锁定的会话发送，并复用聊天文件进度；弹窗覆盖聊天时禁用此拖放区域。

### Cards / Containers

Surface 是无阴影、无默认描边的白色容器，内部内容决定高度。设备卡片、设置组和记录列表共用这一容器；不要将每一行文字再包装成卡片。

### Inputs / Fields

输入框使用 field 底色与 line 描边，焦点为蓝色 2 逻辑像素描边，错误为 danger 描边和可读错误文字。搜索提供清除操作，设置字段在保存过程中禁用。清除与复制等图标操作提供 tooltip。

### Navigation

侧栏在 shell 底上使用白底蓝字表示当前页，未选中为 muted；条目提供选中语义和 tooltip。紧凑侧栏仅显示图标，窄窗口底部导航保留五个短标签。消息未读数与活动传输数来自真实服务状态。

### Device and file identity

DeviceAvatar 默认 44 × 44，蓝色浅底，激活时蓝底白图标。FileGlyph 默认同尺寸，用图标和局部颜色区分文件类型。空状态包含图标、短标题、说明和必要的下一步动作，不能伪造设备、文件或进度填满界面。

## Do's and Don'ts

### Do:
- **Do** 从共享主题和组件构建新页面，使用中文任务标题和一致的 Lucide 图标。
- **Do** 保留键盘焦点、图标 tooltip、可读状态与窄窗口重排。
- **Do** 用真实设备名称、文件名、目的地和结果帮助用户确认操作。

### Don't:
- **Don't** 用状态颜色替代状态文字，或将已送达写成已读。
- **Don't** 为普通内容面板添加装饰性阴影、渐变或入场动画。
- **Don't** 将组件预览里的 HTML/CSS 当作 Flutter 生产实现或测试依据。

未固化的偏差：使用中文系统字体属于原生桌面实现事实，不提升为公共网页的 display 字体规则；主题未显式定义的 Material 状态样式保持框架默认，不从预览近似值生成新的原生 token。

## Diagnostics

设置中的运行日志沿用现有设置分组：说明与保留量在左，查看、打开目录、导出三个带 tooltip 的 Lucide 图标在右，路径可选择。窄宽度将图标移至下一行。

日志查看器是专门的诊断工具窗口，最大宽 1000、高 720，受当前视口约束。顶部保留搜索、级别下拉、刷新、导出与关闭；宽度不足时搜索和级别分行。正文为可展开的紧凑列表，展示中文事件、时间、来源与事件标识，使用颜色和图标双重表达级别；展开后显示可选择的 JSON 与复制按钮。加载、空数据、无匹配、读取错误与写入错误有独立状态。默认显示最近 500 条，实时更新保持数量上限。原始 JSON 使用等宽字体，常规界面继续使用中文系统字体。
