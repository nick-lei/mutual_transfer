import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../desktop/desktop_notifications.dart';
import '../lan_service.dart';
import '../logging/app_log.dart';
import 'android_host.dart';

Future<void> runAndroid() async {
  final paths = await AndroidPaths.load();
  final log = AppLog(Directory(paths.dataDirectory));
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
  final service = LanService(
    dataDirectory: Directory(paths.dataDirectory),
    defaultName: paths.deviceName,
    initialSaveDirectory: paths.receiveDirectory,
    log: log,
  );
  final host = AndroidHost(service);
  await host.initialize();
  final notifications = DesktopNotifications(
    service,
    platform: AndroidNotificationPlatform(host),
    isForeground: () async => host.foreground,
    showWindow: host.showApp,
  );
  await notifications.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(
    NearLinkApp(service: service, android: host, notifications: notifications),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await service.start();
    await host.ready();
  });
}
