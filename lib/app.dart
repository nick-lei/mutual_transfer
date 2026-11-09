import 'package:flutter/material.dart';

import 'android/android_host.dart';
import 'desktop/desktop_controller.dart';
import 'desktop/desktop_notifications.dart';
import 'lan_service.dart';
import 'screenshot/screenshot_controller.dart';
import 'screenshot/screenshot_host.dart';
import 'ui/app_theme.dart';
import 'ui/workspace.dart';

class NearLinkApp extends StatelessWidget {
  const NearLinkApp({
    super.key,
    required this.service,
    this.screenshots,
    this.desktop,
    this.notifications,
    this.android,
  });
  final LanService service;
  final ScreenshotController? screenshots;
  final DesktopController? desktop;
  final DesktopNotifications? notifications;
  final AndroidHost? android;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '邻传 NearLink',
    debugShowCheckedModeBanner: false,
    theme: nearLinkTheme(android: android != null),
    builder: screenshots == null
        ? null
        : (context, child) =>
              ScreenshotHost(controller: screenshots!, child: child!),
    home: Workspace(
      service: service,
      screenshots: screenshots,
      desktop: desktop,
      notifications: notifications,
      android: android,
    ),
  );
}
