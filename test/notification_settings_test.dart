import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/desktop/desktop_notifications.dart';
import 'package:mutual_transfer/desktop/notification_settings.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/ui/app_theme.dart';

import 'notification_fixtures.dart';

void main() {
  const captureUi = bool.fromEnvironment('CAPTURE_UI');
  setUpAll(() async {
    if (!captureUi || !Platform.isWindows) return;
    final font = FontLoader('Microsoft YaHei UI')
      ..addFont(
        File(
          r'C:\Windows\Fonts\msyh.ttc',
        ).readAsBytes().then(ByteData.sublistView),
      );
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await Future.wait([font.load(), icons.load()]);
  });
  for (final size in [const Size(800, 600), const Size(320, 720)]) {
    testWidgets('notification controls fit $size with large text', (
      tester,
    ) async {
      late Directory directory;
      late LanService service;
      final platform = FakeNotificationPlatform();
      late DesktopNotifications controller;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'nearlink-notice-ui-',
        );
        service = LanService(dataDirectory: directory, discoveryEnabled: false);
        controller = DesktopNotifications(
          service,
          platform: platform,
          isForeground: () async => true,
          showWindow: () async {},
        );
        await controller.initialize();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: nearLinkTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: NotificationSettings(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('发送测试通知'), findsOneWidget);
      if (captureUi) {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.impeccable/review/notifications-completion-${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.byTooltip('发送测试通知'));
      await tester.tap(find.byTooltip('发送测试通知'));
      await tester.pump();
      expect(platform.tests, 1);
      await tester.ensureVisible(
        find.byKey(const ValueKey('completion-notifications')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('completion-notifications')),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (controller.updating && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
      expect(controller.completionEnabled, isFalse);
      expect(controller.enabled, isTrue);
      await tester.runAsync(() => controller.update(completionSound: false));
      await tester.runAsync(() => controller.update(enabled: false));
      await tester.pump();
      expect(controller.enabled, isFalse);
      final soundSwitch = tester.widget<Switch>(
        find.byKey(const ValueKey('notification-sound')),
      );
      expect(soundSwitch.onChanged, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await controller.close();
        controller.dispose();
        await service.close();
        await directory.delete(recursive: true);
      });
    });
  }
}
