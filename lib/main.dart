import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'android/android_bootstrap.dart';
import 'desktop/desktop_controller.dart';
import 'desktop/desktop_notifications.dart';
import 'lan_service.dart';
import 'logging/app_log.dart';
import 'screenshot/screenshot_controller.dart';

export 'app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await runAndroid();
    return;
  }
  String? option(String key) => args
      .where((a) => a.startsWith('$key='))
      .map((a) => a.substring(key.length + 1))
      .firstOrNull;
  final appData =
      Platform.environment['LOCALAPPDATA'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  final dataDirectory = Directory(
    option('--data-dir') ?? p.join(appData, 'NearLink'),
  );
  final log = AppLog(dataDirectory);
  FlutterError.onError = (details) {
    log.error(
      'flutter',
      'framework_error',
      '界面运行异常',
      error: details.exception,
      stack: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.error('app', 'unhandled_error', '程序运行异常', error: error, stack: stack);
    return true;
  };
  log.info(
    'app',
    'launch',
    '邻传启动',
    fields: {'version': '0.3.6', 'os': Platform.operatingSystemVersion},
  );
  final service = LanService(
    dataDirectory: dataDirectory,
    log: log,
    requestedPort: int.tryParse(option('--port') ?? '') ?? 45878,
    initialName: option('--name'),
    discoveryEnabled: !args.contains('--no-discovery'),
  );
  await windowManager.ensureInitialized();
  final screenshots = ScreenshotController(service.dataDirectory, log: log);
  DesktopNotifications? notifications;
  final desktop = DesktopController(
    service.dataDirectory,
    startup: WindowsStartupRegistration(),
    service: service,
    screenshots: screenshots,
    log: log,
    onExit: () async {
      try {
        try {
          await notifications?.close();
        } finally {
          await service.close();
        }
      } finally {
        log.info('app', 'exit', '邻传已退出');
        await log.close();
      }
    },
  );
  await windowManager.setPreventClose(true);
  await desktop.initialize();
  if (!args.contains('--no-notifications')) {
    notifications = DesktopNotifications(
      service,
      platform: WindowsNotificationPlatform(dataDirectory),
      isForeground: () async =>
          screenshots.capturing ||
          (await windowManager.isVisible() &&
              !await windowManager.isMinimized() &&
              await windowManager.isFocused()),
      showWindow: desktop.showWindow,
    );
    await notifications.initialize();
  }
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 920),
      minimumSize: Size(440, 640),
      center: true,
      title: 'NearLink | 邻传',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      backgroundColor: Colors.white,
    ),
    () async {
      if (!args.contains('--autostart') || !desktop.trayReady) {
        await desktop.showWindow();
      }
    },
  );
  runApp(
    NearLinkApp(
      service: service,
      screenshots: screenshots,
      desktop: desktop,
      notifications: notifications,
    ),
  );
  unawaited(() async {
    await service.start();
    if (service.running) await screenshots.initialize();
    if (service.running && args.contains('--show-inbox')) {
      await desktop.showInbox(inspectable: true);
    }
  }());
}
