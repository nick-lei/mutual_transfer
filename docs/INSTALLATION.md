# Windows 安装与打包

## 安装与卸载

双击 `NearLink-0.3.3-windows-x64-Setup.exe`。安装向导提供简体中文与英文，默认安装到 `%LOCALAPPDATA%\Programs\NearLink`，可修改目录。安装仅针对当前 Windows 用户，不申请管理员权限。

安装创建开始菜单的程序和卸载入口，并提供桌面快捷方式选项。完成页可立即运行邻传。系统「设置 → 应用 → 已安装的应用」中也会注册「邻传 NearLink」。运行所需的 Flutter 文件、插件与 Visual C++ 运行库随安装包提供。

升级使用固定 AppId，复用此前目录及快捷方式选择。安装器和卸载器会检测当前 Windows 用户、当前会话中的邻传实例，包括收起到任务托盘的实例，并提示「关闭邻传并继续」。确认后先请求正常退出，约 4 秒后仍在运行的旧版或无响应实例会被强制停止，再继续操作。正在进行的传输会中断，未保存的内容可能丢失；点击取消则保留程序运行。

检测同时核对进程名、可执行文件的 NearLink 厂商信息、用户和会话，避免结束同名的其他程序。若权限不足或安装互斥量仍未释放，会停止安装并提示手动退出，不跳过文件占用保护。静默安装或卸载默认不会关闭运行实例；自动部署需要明确传入 `/FORCECLOSENEARLINK=1` 才会请求退出及必要时强制结束。

配置、日志和历史位于 `%LOCALAPPDATA%\NearLink`，默认接收目录位于 `%USERPROFILE%\Downloads\NearLink`。安装器只管理安装目录内的打包文件，不删除用户数据目录或接收目录，也不注册防火墙规则。

## 清理离线设备

Windows 和 Android 的「设备」页面提供垃圾桶图标，提示为「清理无记录的离线设备」。点击后先预览候选设备，确认后只移除当前仍离线、且没有备注、手动连接、聊天、传输或群组关联的设备。没有候选设备时入口不可用；设备在确认期间重新上线或产生记录时会自动保留。清理不改变本机身份、接收目录、聊天和传输历史，也不删除已接收的文件。被移除的设备再次上线时仍可重新发现。

清理前自动保存原配置到应用数据目录的 `backups/devices-before-cleanup-*.json`。Windows 默认在 `%LOCALAPPDATA%\NearLink\backups`；Android 位于应用私有数据目录。备份或保存失败时会提示错误，不将清理视为成功。覆盖安装保留既有设备记录，因此升级后需要在对应设备上执行清理。

维护人员也可以在项目中运行 `tool/cleanup_offline_devices.ps1`，默认仅预览；加 `-Apply` 才写入，`-DataDirectory` 可指定数据目录。脚本必须取得与应用相同的独占数据锁，正在运行的配置会拒绝处理；它只修改设备配置，不重写历史文件。此脚本不随安装包分发，日常使用直接通过程序内入口清理。

## 开机自启

安装不会主动启用自启，仍由「设置 → 启动与关闭」控制。已有 NearLink 自启项在安装或升级后改为新安装路径，同时保留 Windows 的启用/禁用状态。卸载只移除指向当前安装程序的自启项；若用户之后让便携版接管了自启，该项保留。

## 构建

```powershell
flutter build windows --release --no-pub
.\tool\package_windows.ps1 -Version 0.3.3
.\tool\build_installer.ps1 -Version 0.3.3 -PrepareCompiler
```

`tool/prepare_installer.ps1` 固定使用官方 Inno Setup 7.1.1 x64，下载路径为 GitHub 的 `jrsoftware/issrc` 官方发布页，验证 SHA-256 与 Authenticode 签名后准备到项目的 `build/installer-tools`。若已安装编译器，可通过 `-CompilerPath` 指定 `ISCC.exe`，也可使用 PATH 中的编译器。

`build_installer.ps1` 从便携包目录构建，检查核心文件、运行库、图标及可执行文件版本。`-PackageDirectory` 可指定其他打包目录。源脚本为 `windows/installer/nearlink.iss`，AppId 固定，发布新版本不能更换 AppId。

产物：

- `outputs/NearLink-0.3.3-windows-x64-Setup.exe`：可点击安装版。
- `outputs/NearLink-0.3.3-windows-x64.zip`：便携版。

当前安装包未配置发布者代码签名。签名发布需要正式证书和签名流程；下载来源信誉和不同电脑上的系统提示不属于本机安装测试的保证范围。

## 本机安装验证

`tool/verify_installer.ps1` 使用生产安装脚本和独立测试 AppId、快捷方式及安装目录，验证安装文件、卸载注册、快捷方式、运行中保护、新版正常退出、旧版强制退出、同名其他程序保护、覆盖升级、自启迁移、卸载清理和用户数据保留。它会暂时注册当前用户的测试安装并在结束时卸载，保存并恢复原有 NearLink 自启值。测试前需要退出正在运行的邻传；已有同名测试安装或测试快捷方式时拒绝执行。

```powershell
.\tool\verify_installer.ps1
```

同机测试不替代另一台 Windows 电脑的安装、权限、系统信誉和真实局域网验证。
