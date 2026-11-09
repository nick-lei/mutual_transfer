import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/android/android_host.dart';
import 'package:mutual_transfer/app.dart';
import 'package:mutual_transfer/desktop/desktop_notifications.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';
import 'package:mutual_transfer/ui/desktop_title_bar.dart';

import 'ui_fixtures.dart';
import 'notification_fixtures.dart';

const captureAndroid = bool.fromEnvironment('CAPTURE_ANDROID_UI');
final androidCaptureKey = GlobalKey();

class ChatFileFixtureService extends UiFixtureService {
  final retried = <String>[];

  @override
  Future<void> sendFiles(
    Peer peer,
    List<LocalFile> files, {
    String? groupId,
  }) async {
    await super.sendFiles(peer, files, groupId: groupId);
    transfers.insertAll(0, [
      for (final file in files)
        TransferItem(
          id: newId(),
          peerId: peer.id,
          peerName: peer.name,
          name: file.name,
          size: file.size,
          outgoing: true,
          sourcePath: file.path,
          groupId: groupId,
        ),
    ]);
    emit();
  }

  @override
  Future<void> retry(TransferItem item) async => retried.add(item.id);

  @override
  void cancel(TransferItem item) {
    super.cancel(item);
    emit();
  }
}

class MobileFixtureHost extends AndroidHost {
  MobileFixtureHost(super.service);
  final shared = StreamController<AndroidSharedContent>.broadcast();
  final opened = <String>[];
  final exported = <String>[];
  final forwarded = <String>[];
  @override
  Stream<AndroidSharedContent> get sharedContent => shared.stream;
  @override
  Future<void> openFile(String path) async => opened.add(path);
  @override
  Future<bool> exportFile(String path) async {
    exported.add(path);
    return true;
  }

  @override
  Future<void> shareFile(String path) async => forwarded.add(path);
  @override
  Future<void> close() async {
    await shared.close();
    await super.close();
  }
}

void main() {
  const pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  FutureOr<Object?> Function(MethodCall)? pickResult;
  setUp(() {
    pickResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pickerChannel,
          (call) async => pickResult?.call(call),
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pickerChannel, null);
  });
  setUpAll(() async {
    if (!captureAndroid) return;
    final font = FontLoader('Roboto')
      ..addFont(
        File(
          r'C:\Windows\Fonts\msyh.ttc',
        ).readAsBytes().then(ByteData.sublistView),
      );
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    final numerals = FontLoader('Segoe UI')
      ..addFont(
        File(
          r'C:\Windows\Fonts\segoeui.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await Future.wait([font.load(), icons.load(), numerals.load()]);
  });
  Future<({UiFixtureService service, MobileFixtureHost host})> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    UiFixtureService? fixtureService,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final service = fixtureService ?? UiFixtureService();
    final host = MobileFixtureHost(service);
    late DesktopNotifications notifications;
    await tester.runAsync(() async {
      notifications =
          DesktopNotifications(
              service,
              platform: FakeNotificationPlatform(),
              isForeground: () async => host.foreground,
              showWindow: () async {},
            )
            ..ready = true
            ..available = true
            ..allowed = true;
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: androidCaptureKey,
        child: NearLinkApp(
          service: service,
          android: host,
          notifications: notifications,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {
        await host.close();
        await notifications.close();
        notifications.dispose();
        await service.close();
      });
    });
    return (service: service, host: host);
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(name),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          androidCaptureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '.impeccable/review/android-widget-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [390.0, 320.0]) {
    testWidgets('Android device cleanup confirms at $width', (tester) async {
      final fixture = await show(
        tester,
        size: Size(width, 844),
        scale: width == 320 ? 1.3 : 1,
      );
      await tab(tester, '设备');
      await tester.tap(find.byKey(const ValueKey('clear-offline-devices')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('清理离线设备'), findsOneWidget);
      expect(find.text('将移除以下 1 台无使用记录的离线设备。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (captureAndroid) {
        await capture(tester, 'devices-cleanup-dialog-${width.toInt()}');
      }
      await tester.tap(
        find.byKey(const ValueKey('confirm-clear-offline-devices')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(fixture.service.clearedPeerIds, ['home']);
      expect(fixture.service.messages, hasLength(4));
      expect(fixture.service.transfers, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 320.0]) {
    testWidgets('Android offline devices show last online time at $width', (
      tester,
    ) async {
      final service = UiFixtureService();
      service.peers['home']!.lastSeen = DateTime(2020, 1, 2, 9, 8, 7);
      await show(
        tester,
        fixtureService: service,
        size: Size(width, 844),
        scale: width == 320 ? 1.3 : 1,
      );
      await tab(tester, '设备');
      final label = find.byKey(const ValueKey('last-seen-home'));
      await tester.ensureVisible(label);
      await tester.pump();
      expect(find.text('最后在线：'), findsOneWidget);
      expect(find.text('2020-01-02 09:08'), findsOneWidget);
      expect(find.byTooltip('最后在线：2020-01-02 09:08:07'), findsOneWidget);
      expect(find.byKey(const ValueKey('last-seen-laptop')), findsNothing);
      expect(tester.takeException(), isNull);
      if (captureAndroid) {
        await capture(tester, 'devices-last-seen-${width.toInt()}');
      }
      service.peers['home']!.lastSeen = null;
      service.emit();
      await tester.pump();
      expect(find.text('暂无记录'), findsOneWidget);
    });
  }

  Future<void> flushFiles(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<File> pickerFile(WidgetTester tester) async {
    late Directory directory;
    late File file;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('nearlink-chat-files-');
      file = await File(
        '${directory.path}/项目说明.txt',
      ).writeAsString('chat file fixture');
    });
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    pickResult = (call) {
      expect(call.method, 'any');
      expect((call.arguments as Map)['allowMultipleSelection'], isTrue);
      expect((call.arguments as Map)['withData'], isFalse);
      return [
        {'name': '项目说明.txt', 'path': file.path, 'size': 17},
      ];
    };
    return file;
  }

  testWidgets(
    'chat picks files directly, preserves drafts and the send queue',
    (tester) async {
      final file = await pickerFile(tester);
      final service = ChatFileFixtureService();
      final fixture = await show(tester, fixtureService: service);
      fixture.host.shared.add(AndroidSharedContent(paths: [file.path]));
      await flushFiles(tester);
      await tab(tester, '消息');
      await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        '保留这段草稿',
      );
      await tester.tap(find.byTooltip('在此会话中添加文件'));
      await flushFiles(tester);
      expect(service.sentBatches.single.peerId, 'laptop');
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('message-input')))
            .controller!
            .text,
        '保留这段草稿',
      );
      expect(
        find.byKey(ValueKey('chat-file-${service.transfers.first.id}')),
        findsOneWidget,
      );
      expect(find.text('等待对方接收'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('草稿 · 保留这段草稿'), findsOneWidget);
      await tab(tester, '发送');
      expect(find.text('已选 1 个文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling the chat picker keeps conversation and draft', (
    tester,
  ) async {
    final fixture = await show(tester);
    await tab(tester, '消息');
    await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('message-input')),
      '取消选文件',
    );
    await tester.tap(find.byTooltip('给 我的笔记本 发文件'));
    await tester.pump();
    expect(fixture.service.sentBatches, isEmpty);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('message-input')))
          .controller!
          .text,
      '取消选文件',
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('changing chat while picking never redirects the recipient', (
    tester,
  ) async {
    final file = await pickerFile(tester);
    final gate = Completer<Object?>();
    pickResult = (_) => gate.future;
    final service = ChatFileFixtureService();
    await show(tester, fixtureService: service);
    await tab(tester, '消息');
    await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
    await tester.pump();
    await tester.tap(find.byTooltip('在此会话中添加文件'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('conversation-studio')));
    await tester.pump();
    gate.complete([
      {'name': '项目说明.txt', 'path': file.path, 'size': 17},
    ]);
    await flushFiles(tester);
    expect(service.sentBatches.single.peerId, 'laptop');
    expect(
      find.byKey(ValueKey('chat-file-${service.transfers.first.id}')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('messages-studio')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'chat updates real transfer progress, completes and opens file actions',
    (tester) async {
      final service = ChatFileFixtureService();
      final fixture = await show(tester, fixtureService: service);
      await tab(tester, '消息');
      await tester.tap(find.byKey(const ValueKey('conversation-studio')));
      await tester.pump(const Duration(milliseconds: 300));
      final active = service.transfers.first;
      final progress = find.byKey(const ValueKey('chat-progress-active'));
      expect(
        tester.widget<LinearProgressIndicator>(progress).value,
        closeTo(64 / 180, .001),
      );
      active.bytes = active.size ~/ 2;
      service.emit();
      await tester.pump();
      expect(tester.widget<LinearProgressIndicator>(progress).value, .5);
      if (captureAndroid) await capture(tester, 'chat-file-progress');
      await tester.tap(find.byTooltip('重新发送'));
      await tester.pump();
      expect(service.retried, ['failed']);
      await tester.tap(find.byTooltip('取消本批传输'));
      await tester.pump();
      expect(active.status, TransferStatus.cancelled);
      expect(find.byKey(const ValueKey('chat-progress-active')), findsNothing);
      active.status = TransferStatus.complete;
      active.bytes = active.size;
      service.emit();
      await tester.pump();
      expect(find.text('已发送'), findsOneWidget);
      await tester.tap(find.byTooltip('返回会话列表'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
      await tester.pump();
      final received = find.byKey(const ValueKey('chat-file-received'));
      await tester.ensureVisible(received);
      await tester.tap(
        find.descendant(of: received, matching: find.byTooltip('打开文件')),
      );
      await flushFiles(tester);
      // Fixture paths do not exist, and opening reports that without navigation.
      expect(fixture.host.opened, isEmpty);
      expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
      expect(find.text('文件已被移动或删除，请重新发送'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('incoming file can be accepted in its conversation', (
    tester,
  ) async {
    final fixture = await show(tester);
    final service = fixture.service;
    final peer = service.peers['laptop']!;
    final file = TransferItem(
      id: 'inline-incoming',
      peerId: peer.id,
      peerName: peer.name,
      name: '接收测试.zip',
      size: 2048,
      outgoing: false,
    );
    final offer = IncomingOffer(
      id: 'inline-offer',
      peer: peer,
      files: [file],
      remoteHost: peer.host,
    );
    service.transfers.insert(0, file);
    service.incoming.add(offer);
    service.emit();
    await flushFiles(tester);
    await tester.tap(find.byTooltip('收起接收提醒'));
    await tester.pump();
    await tab(tester, '消息');
    await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('接收此批 1 个文件'));
    await tester.pump();
    expect(await offer.decision.future, isTrue);
    expect(find.text('队列中'), findsOneWidget);
    file.status = TransferStatus.complete;
    file.bytes = file.size;
    service.emit();
    await tester.pump();
    expect(find.text('已接收'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('chat-progress-inline-incoming')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'group chat shows separate recipient outcomes without direct-chat files',
    (tester) async {
      final service = ChatFileFixtureService();
      final group = service.addGroupFixture();
      service.transfers.insertAll(0, [
        for (final peer in service.groupPeers(group))
          TransferItem(
            id: 'group-file-${peer.id}',
            peerId: peer.id,
            peerName: peer.name,
            name: '群组方案.pdf',
            size: 2048,
            outgoing: true,
            groupId: group.id,
            status: peer.id == 'laptop'
                ? TransferStatus.complete
                : TransferStatus.failed,
          ),
      ]);
      await show(tester, fixtureService: service);
      await tab(tester, '消息');
      await tester.tap(
        find.byKey(ValueKey('conversation-${group.conversationId}')),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('发送给 设计工作站'), findsOneWidget);
      expect(find.text('发送给 小林的笔记本'), findsOneWidget);
      expect(find.text('已发送'), findsOneWidget);
      expect(find.text('传输失败'), findsOneWidget);
      expect(find.text('周末出游合照.jpg'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(1024, 768)]) {
    testWidgets('file chat fits $size at 1.3x text', (tester) async {
      final service = ChatFileFixtureService();
      final fixture = await show(
        tester,
        size: size,
        scale: 1.3,
        fixtureService: service,
      );
      if (size.width >= 840) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('消息'),
          ),
        );
      } else {
        await tab(tester, '消息');
      }
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('conversation-studio')));
      await tester.pump(const Duration(milliseconds: 300));
      final peer = fixture.service.peers['studio']!;
      final file = TransferItem(
        id: 'large-type',
        peerId: peer.id,
        peerName: peer.name,
        name: '一个很长的项目交付文件名称_最终确认版本_20261109.zip',
        size: 2048,
        outgoing: false,
      );
      service.transfers.insert(0, file);
      service.incoming.add(
        IncomingOffer(
          id: 'large-type-offer',
          peer: peer,
          files: [file],
          remoteHost: peer.host,
        ),
      );
      service.emit();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('收起接收提醒'));
      await tester.pump(const Duration(milliseconds: 300));
      if (captureAndroid) {
        await capture(tester, 'chat-files-${size.width.toInt()}');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capture Android layout fixtures, not device evidence', (
    tester,
  ) async {
    final fixture = await show(tester);
    await capture(tester, 'send');
    await tab(tester, '消息');
    await capture(tester, 'messages');
    await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
    await tester.pump();
    await capture(tester, 'chat');
    await tester.binding.handlePopRoute();
    await tester.pump();
    for (final entry in {
      '设备': 'devices',
      '记录': 'history',
      '设置': 'settings',
    }.entries) {
      await tab(tester, entry.key);
      await capture(tester, entry.value);
    }
    final originalName = fixture.service.name;
    fixture.service.name = '这是一台设备名称很长的安卓手机_用于检查大字号和小屏幕下的名称排版';
    fixture.service.emit();
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pump();
    await capture(tester, 'settings-small-large-type');
    tester.view.physicalSize = const Size(1024, 768);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pump();
    await capture(tester, 'settings-tablet');
    tester.view.physicalSize = const Size(390, 844);
    fixture.service.name = originalName;
    fixture.service.emit();
    await tester.pumpAndSettle();
    for (final entry in {
      '接收与保存': 'settings-receiving',
      '通知与声音': 'settings-notifications',
      '连接信息': 'settings-connection',
      '诊断与日志': 'settings-diagnostics',
    }.entries) {
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      await tester.pump(const Duration(milliseconds: 400));
      await capture(tester, entry.value);
      if (entry.key == '通知与声音') {
        await tester.ensureVisible(find.text('传输完成提示音'));
        await capture(tester, '${entry.value}-bottom');
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tab(tester, '发送');
    fixture.host.shared.add(
      const AndroidSharedContent(text: '这是从其他应用分享进来的文字。'),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('android-peer-laptop')),
    );
    await tester.tap(find.byKey(const ValueKey('android-peer-laptop')));
    await capture(tester, 'staged');
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pump();
    await capture(tester, 'small-large-type');
    tester.view.physicalSize = const Size(1024, 768);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('消息'),
      ),
    );
    await tester.pump();
    await capture(tester, 'tablet');
    final peer = fixture.service.peers['laptop']!;
    fixture.service.incoming.add(
      IncomingOffer(
        id: 'mobile-offer',
        peer: peer,
        remoteHost: peer.host,
        files: [
          TransferItem(
            id: 'mobile-file',
            peerId: peer.id,
            peerName: peer.name,
            name: '项目素材.zip',
            size: 4219000,
            outgoing: false,
          ),
        ],
      ),
    );
    fixture.service.emit();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的笔记本 发来文件'));
    await tester.pump();
    await capture(tester, 'receive');
    expect(tester.takeException(), isNull);
  }, skip: !captureAndroid);

  testWidgets('phone has native navigation and omits Windows chrome', (
    tester,
  ) async {
    await show(tester);
    expect(find.byType(DesktopTitleBar), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('照片与视频'), findsOneWidget);
    await tab(tester, '设置');
    expect(find.text('接收与保存'), findsOneWidget);
    expect(find.text('后台接收'), findsNothing);
    await tester.tap(find.text('接收与保存'));
    await tester.pumpAndSettle();
    expect(find.text('后台接收'), findsOneWidget);
    expect(find.text('开机自启'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incoming file review requires an explicit decision', (
    tester,
  ) async {
    final fixture = await show(tester);
    final peer = fixture.service.peers['laptop']!;
    final offer = IncomingOffer(
      id: 'mobile-offer',
      peer: peer,
      remoteHost: peer.host,
      files: [
        TransferItem(
          id: 'mobile-file',
          peerId: peer.id,
          peerName: peer.name,
          name: '项目素材.zip',
          size: 4219000,
          outgoing: false,
        ),
      ],
    );
    fixture.service.incoming.add(offer);
    fixture.service.emit();
    await tester.pumpAndSettle();
    expect(offer.decision.isCompleted, isFalse);
    await tester.tap(find.text('我的笔记本 发来文件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('项目素材.zip'), findsOneWidget);
    expect(offer.decision.isCompleted, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, '接收'));
    await tester.pump(const Duration(seconds: 1));
    expect(await offer.decision.future, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android Back leaves the chat before leaving messages', (
    tester,
  ) async {
    await show(tester);
    await tab(tester, '消息');
    await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('conversation-laptop')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('照片与视频'), findsOneWidget);
  });

  testWidgets('large incoming batches keep decisions visible and expire live', (
    tester,
  ) async {
    final fixture = await show(tester, size: const Size(320, 640), scale: 1.3);
    final peer = fixture.service.peers['laptop']!;
    final offer = IncomingOffer(
      id: 'large-mobile-offer',
      peer: peer,
      remoteHost: peer.host,
      files: List.generate(
        50,
        (index) => TransferItem(
          id: 'photo-$index',
          peerId: peer.id,
          peerName: peer.name,
          name: '照片-$index.jpg',
          size: 4219000,
          outgoing: false,
        ),
      ),
    );
    fixture.service.incoming.add(offer);
    fixture.service.emit();
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的笔记本 发来文件'));
    await tester.pumpAndSettle();
    final accept = find.widgetWithText(FilledButton, '接收');
    expect(accept.hitTestable(), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, '拒绝').hitTestable(),
      findsOneWidget,
    );
    expect(tester.getRect(accept).bottom, lessThanOrEqualTo(640));
    if (captureAndroid) await capture(tester, 'receive-large');
    offer.decision.complete(false);
    fixture.service.emit();
    await tester.pumpAndSettle();
    expect(find.text('该请求已处理或已过期'), findsOneWidget);
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every staged file can be inspected and removed', (tester) async {
    late Directory directory;
    late List<String> paths;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'nearlink-mobile-queue-',
      );
      paths = await Future.wait(
        List.generate(12, (index) async {
          final file = File('${directory.path}/selected-$index.txt');
          await file.writeAsString('test file $index');
          return file.path;
        }),
      );
    });
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    final fixture = await show(tester);
    fixture.host.shared.add(AndroidSharedContent(paths: paths));
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.text('已选 12 个文件').evaluate().isNotEmpty) break;
    }
    final summary = find.byKey(const ValueKey('android-file-summary'));
    expect(summary.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('android-peer-laptop')).hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(summary);
    await tester.pumpAndSettle();
    await tester.tap(summary);
    await tester.pumpAndSettle();
    final queue = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byTooltip('移除 selected-11.txt'),
      200,
      scrollable: queue,
    );
    await tester.pumpAndSettle();
    if (captureAndroid) await capture(tester, 'queue');
    await tester.tap(find.byTooltip('移除 selected-11.txt'));
    await tester.pump();
    expect(find.text('已选 11 个文件'), findsNWidgets(2));
    expect(find.text('selected-11.txt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press offers device remark from conversations', (
    tester,
  ) async {
    await show(tester);
    await tab(tester, '消息');
    await tester.longPress(find.byKey(const ValueKey('conversation-laptop')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('修改备注'), findsOneWidget);
    await tester.tap(find.text('修改备注'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('设备备注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system shared text waits for recipient and explicit send', (
    tester,
  ) async {
    final fixture = await show(tester);
    fixture.host.shared.add(const AndroidSharedContent(text: '从浏览器分享的链接'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.service.sentMessages, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('android-send')))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('android-peer-laptop')),
    );
    await tester.tap(find.byKey(const ValueKey('android-peer-laptop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('android-send')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.service.sentMessages.single, (
      peerId: 'laptop',
      text: '从浏览器分享的链接',
    ));
    expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
    expect(find.text('从浏览器分享的链接'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    if (captureAndroid) await capture(tester, 'shared-message');
  });

  testWidgets('received file actions use Android open export and share', (
    tester,
  ) async {
    final fixture = await show(tester);
    await tab(tester, '记录');
    for (final action in ['打开文件', '另存到手机', '分享']) {
      await tester.tap(find.text('周末出游合照.jpg'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(action));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(fixture.host.opened, hasLength(1));
    expect(fixture.host.exported, fixture.host.opened);
    expect(fixture.host.forwarded, fixture.host.opened);
  });

  testWidgets('background chat does not consume unread messages', (
    tester,
  ) async {
    final fixture = await show(tester);
    await tab(tester, '消息');
    await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
    await tester.pump();
    fixture.host.didChangeAppLifecycleState(AppLifecycleState.paused);
    fixture.service.messages.add(
      ChatMessage(
        id: 'background-message',
        peerId: 'laptop',
        text: '后台新消息',
        outgoing: false,
        read: false,
      ),
    );
    fixture.service.emit();
    await tester.pump();
    expect(fixture.service.unreadFor('laptop'), 1);
    fixture.host.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.service.unreadFor('laptop'), 0);
  });

  testWidgets(
    'settings details retain notifications and received-file routing',
    (tester) async {
      await show(tester);
      await tab(tester, '设置');
      await tester.tap(find.text('通知与声音'));
      await tester.pumpAndSettle();
      expect(find.text('文件接收通知'), findsOneWidget);
      expect(find.text('消息提示音'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('接收与保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('接收的文件'));
      await tester.pumpAndSettle();
      expect(find.text('周末出游合照.jpg'), findsOneWidget);
      expect(find.text('品牌素材包.zip'), findsNothing);
      expect(find.text('项目交付文档.pdf'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history keeps individual files visible with the original filters',
    (tester) async {
      final fixture = await show(tester);
      fixture.service.transfers.clear();
      for (var i = 0; i < 3; i++) {
        fixture.service.transfers.add(
          TransferItem(
            id: 'batched-$i',
            peerId: 'laptop',
            peerName: '我的笔记本',
            batchId: 'real-session',
            name: '批次文件-$i.txt',
            size: 100,
            outgoing: false,
            status: i == 2 ? TransferStatus.failed : TransferStatus.complete,
          ),
        );
      }
      fixture.service.transfers.add(
        TransferItem(
          id: 'legacy',
          peerId: 'laptop',
          peerName: '我的笔记本',
          name: '旧记录.txt',
          size: 10,
          outgoing: false,
          status: TransferStatus.complete,
        ),
      );
      fixture.service.emit();
      await tab(tester, '记录');
      expect(find.byType(ExpansionTile), findsNothing);
      for (var i = 0; i < 3; i++) {
        expect(find.text('批次文件-$i.txt'), findsOneWidget);
      }
      expect(find.text('旧记录.txt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('android-history-filter-3')));
      await tester.pumpAndSettle();
      expect(find.text('旧记录.txt'), findsNothing);
      expect(find.text('批次文件-2.txt'), findsOneWidget);
      expect(find.text('批次文件-0.txt'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('android-history-filter-2')));
      await tester.pumpAndSettle();
      expect(find.text('批次文件-2.txt'), findsNothing);
      expect(find.text('批次文件-0.txt'), findsOneWidget);
      expect(find.text('旧记录.txt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapsed incoming requests remain reachable and new requests expand',
    (tester) async {
      final fixture = await show(tester);
      final peer = fixture.service.peers['laptop']!;
      IncomingOffer offer(String id) => IncomingOffer(
        id: id,
        peer: peer,
        remoteHost: peer.host,
        files: [
          TransferItem(
            id: 'file-$id',
            peerId: peer.id,
            peerName: peer.name,
            name: '$id.txt',
            size: 1,
            outgoing: false,
          ),
        ],
      );
      final first = offer('first');
      fixture.service.incoming.add(first);
      fixture.service.emit();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('收起接收提醒'));
      await tester.pumpAndSettle();
      expect(find.text('我的笔记本 发来文件'), findsNothing);
      await tester.tap(find.byTooltip('展开接收请求'));
      await tester.pumpAndSettle();
      expect(find.text('我的笔记本 发来文件'), findsOneWidget);
      await tester.tap(find.byTooltip('收起接收提醒'));
      first.decision.complete(false);
      fixture.service.incoming.add(offer('second'));
      fixture.service.emit();
      await tester.pumpAndSettle();
      expect(find.text('我的笔记本 发来文件'), findsOneWidget);
    },
  );

  testWidgets(
    'conversation time and composer fit a small phone with IME insets',
    (tester) async {
      await show(tester, size: const Size(320, 640), scale: 1.3);
      await tab(tester, '消息');
      expect(
        find.byKey(const ValueKey('conversation-time-laptop')),
        findsOneWidget,
      );
      expect(find.text('会话'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        '第一行\n第二行\n第三行\n第四行',
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('发送消息').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('message-input'))).bottom,
        lessThanOrEqualTo(360),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(780, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('all mobile pages fit $size with large text', (tester) async {
      await show(tester, size: size, scale: 1.3);
      final rail = size.width >= 840;
      expect(find.byType(NavigationRail), rail ? findsOneWidget : findsNothing);
      for (final label in ['消息', '设备', '记录', '设置', '发送']) {
        if (rail) {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationRail),
              matching: find.text(label),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
        } else {
          await tab(tester, label);
        }
        expect(tester.takeException(), isNull, reason: '$size: $label');
      }
    });
  }
}
