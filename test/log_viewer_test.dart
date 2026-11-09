import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/logging/app_log.dart';
import 'package:mutual_transfer/logging/log_settings.dart';
import 'package:mutual_transfer/ui/app_theme.dart';

class ViewerLog extends AppLog {
  ViewerLog() : super(Directory.systemTemp);
  bool fail = false;
  List<LogEntry> entries = [
    LogEntry(
      id: 'one',
      time: DateTime(2026, 11, 7, 10, 12),
      level: LogLevel.info,
      component: 'network',
      event: 'service_started',
      message: '局域网服务已启动',
      fields: {'port': 45878},
    ),
    LogEntry(
      id: 'two',
      time: DateTime(2026, 11, 7, 10, 13),
      level: LogLevel.warning,
      component: 'transfer',
      event: 'receive_failed',
      message: '文件接收未完成',
      fields: {'transferId': 'sample-transfer', 'bytes': 1048576},
      error: '连接已中断',
    ),
  ];
  @override
  Future<List<LogEntry>> readRecent({int limit = 500}) async {
    if (fail) throw const FileSystemException('unavailable');
    return entries;
  }
}

void main() {
  setUpAll(() async {
    if (!Platform.isWindows) return;
    await (FontLoader('Microsoft YaHei UI')..addFont(
          File(
            r'C:\Windows\Fonts\msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('Segoe UI')..addFont(
          File(
            r'C:\Windows\Fonts\segoeui.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  final boundaryKey = GlobalKey();
  Future<ViewerLog> show(
    WidgetTester tester, {
    Size size = const Size(1100, 800),
    double textScale = 1,
  }) async {
    final log = ViewerLog();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(log.close);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: nearLinkTheme(),
          home: Scaffold(body: LogViewer(log: log)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('filters, searches, expands details and receives live events', (
    tester,
  ) async {
    final log = await show(tester);
    expect(find.text('局域网服务已启动'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('log-level-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('警告').last);
    await tester.pumpAndSettle();
    expect(find.text('局域网服务已启动'), findsNothing);
    await tester.tap(find.text('文件接收未完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sample-transfer'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('log-search')),
      'does-not-exist',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的日志'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('log-search')), '实时异常');
    log.warning('test', 'live', '实时异常');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ExpansionTile, '实时异常'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows read errors, retries and handles empty logs', (
    tester,
  ) async {
    final log = await show(tester);
    log.fail = true;
    await tester.tap(find.byTooltip('刷新日志'));
    await tester.pumpAndSettle();
    expect(find.text('日志读取失败，请检查日志目录后刷新。'), findsOneWidget);
    log.fail = false;
    await tester.tap(find.byTooltip('刷新日志'));
    await tester.pumpAndSettle();
    expect(find.text('日志读取失败，请检查日志目录后刷新。'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogViewer(
            key: const ValueKey('empty'),
            log: ViewerLog()..entries = [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无运行日志'), findsOneWidget);
  });

  for (final size in [const Size(1100, 800), const Size(440, 760)]) {
    testWidgets('log viewer fits ${size.width} with larger text', (
      tester,
    ) async {
      await show(tester, size: size, textScale: size.width == 440 ? 1.3 : 1);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.impeccable/review/log-viewer-${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
