import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/desktop/desktop_controller.dart';
import 'package:mutual_transfer/main.dart';
import 'package:mutual_transfer/models.dart';
import 'package:mutual_transfer/ui/desktop_title_bar.dart';

import 'ui_fixtures.dart';
import 'desktop_fixtures.dart';

const captureUi = bool.fromEnvironment('CAPTURE_UI');
final captureKey = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!Platform.isWindows) return;
    final chinese = FontLoader('Microsoft YaHei UI')
      ..addFont(
        File(
          r'C:\Windows\Fonts\msyh.ttc',
        ).readAsBytes().then(ByteData.sublistView),
      );
    final latin = FontLoader('Segoe UI')
      ..addFont(
        File(
          r'C:\Windows\Fonts\segoeui.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await Future.wait([chinese.load(), latin.load(), icons.load()]);
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async =>
              call.method == 'isMaximized' || call.method == 'isFullScreen'
              ? false
              : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Future<void> show(
    WidgetTester tester,
    UiFixtureService service, {
    Size size = const Size(1440, 920),
    double textScale = 1,
    DesktopController? desktop,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: NearLinkApp(service: service, desktop: desktop),
      ),
    );
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> navigate(WidgetTester tester, int page) async {
    final item = find.byKey(ValueKey('nav-$page'));
    if (item.evaluate().isNotEmpty) {
      await tester.tap(item);
    } else {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(['发送', '设备', '消息', '记录', '设置'][page]),
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!captureUi) return;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('.impeccable/review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> finish(WidgetTester tester, UiFixtureService service) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await service.close();
  }

  for (final width in [1440.0, 440.0]) {
    testWidgets('device cleanup previews, cancels and confirms at $width', (
      tester,
    ) async {
      final service = UiFixtureService();
      await show(
        tester,
        service,
        size: Size(width, 920),
        textScale: width == 440 ? 1.3 : 1,
      );
      await navigate(tester, 1);
      final clear = find.byKey(const ValueKey('clear-offline-devices'));
      await tester.tap(clear);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('清理离线设备'), findsOneWidget);
      expect(find.text('将移除以下 1 台无使用记录的离线设备。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'devices-cleanup-dialog-${width.toInt()}');
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(service.peers.containsKey('home'), isTrue);
      await tester.tap(clear);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(
        find.byKey(const ValueKey('confirm-clear-offline-devices')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.clearedPeerIds, ['home']);
      expect(service.messages, hasLength(4));
      expect(service.transfers, hasLength(3));
      expect(tester.widget<IconButton>(clear).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await finish(tester, service);
    });
  }

  for (final width in [1440.0, 440.0]) {
    testWidgets('offline devices show last online time at $width', (
      tester,
    ) async {
      final service = UiFixtureService();
      service.peers['home']!.lastSeen = DateTime(2020, 1, 2, 9, 8, 7);
      await show(
        tester,
        service,
        size: Size(width, 920),
        textScale: width == 440 ? 1.3 : 1,
      );
      await navigate(tester, 1);
      final label = find.byKey(const ValueKey('last-seen-home'));
      await tester.ensureVisible(label);
      await tester.pump();
      expect(find.text('最后在线：'), findsOneWidget);
      expect(find.text('2020-01-02 09:08'), findsOneWidget);
      expect(find.byTooltip('最后在线：2020-01-02 09:08:07'), findsOneWidget);
      expect(find.byKey(const ValueKey('last-seen-laptop')), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, 'devices-last-seen-${width.toInt()}');
      service.peers['home']!.lastSeen = null;
      service.emit();
      await tester.pump();
      expect(find.text('暂无记录'), findsOneWidget);
      await finish(tester, service);
    });
  }

  for (final width in [1440.0, 440.0]) {
    testWidgets('chat file cards share live history at $width', (tester) async {
      final service = UiFixtureService();
      await show(
        tester,
        service,
        size: Size(width, 920),
        textScale: width == 440 ? 1.3 : 1,
      );
      await navigate(tester, 2);
      await tester.tap(find.byKey(const ValueKey('conversation-studio')));
      await tester.pump(const Duration(seconds: 1));
      final card = find.byKey(const ValueKey('chat-file-active'));
      final progress = find.byKey(const ValueKey('chat-progress-active'));
      expect(card, findsOneWidget);
      expect(find.text('品牌素材包.zip'), findsOneWidget);
      expect(find.text('正在发送'), findsOneWidget);
      expect(
        tester.getRect(progress).left,
        greaterThan(tester.getRect(card).left),
      );
      expect(
        tester.getRect(progress).right,
        lessThan(tester.getRect(card).right),
      );
      await capture(tester, 'chat-files-desktop-${width.toInt()}');
      service.transfers.first.status = TransferStatus.complete;
      service.emit();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('已发送'),
        -200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('messages-studio')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('已发送'), findsOneWidget);
      expect(progress, findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester, service);
    });
  }

  for (final width in [1440.0, 440.0]) {
    for (final outgoing in [true, false]) {
      testWidgets(
        'completion prompt outgoing=$outgoing fits $width and opens history',
        (tester) async {
          final previousShadows = debugDisableShadows;
          debugDisableShadows = false;
          try {
            final service = UiFixtureService();
            await show(
              tester,
              service,
              size: Size(width, 760),
              textScale: width == 440 ? 1.3 : 1,
            );
            final completion = TransferCompletion(
              id: 'ui-complete',
              outgoing: outgoing,
              peerName: '小林的工作站',
              fileCount: 14,
              totalBytes: 1503238553,
            );
            service.completionEvents.add(completion);
            await tester.pumpAndSettle();
            expect(find.text(completion.title), findsOneWidget);
            expect(find.text(completion.summary), findsOneWidget);
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              'completion-${outgoing ? 'sent' : 'received'}-${width.toInt()}',
            );
            await tester.tap(find.byTooltip('查看记录'));
            await tester.pumpAndSettle();
            expect(find.text('搜索文件或设备'), findsOneWidget);
            await finish(tester, service);
          } finally {
            debugDisableShadows = previousShadows;
          }
        },
      );
    }
  }

  for (final width in [1440.0, 720.0, 440.0]) {
    testWidgets('group conversations and member editor fit $width', (
      tester,
    ) async {
      final service = UiFixtureService();
      final group = service.addGroupFixture();
      await show(
        tester,
        service,
        size: Size(width, 920),
        textScale: width == 440 ? 1.3 : 1,
      );
      await navigate(tester, 2);
      await tester.tap(
        find.byKey(ValueKey('conversation-${group.conversationId}')),
      );
      await tester.pumpAndSettle();
      expect(service.unreadFor(group.conversationId), 0);
      expect(service.unreadFor('laptop'), 2);
      expect(find.text('已送达 1/2', findRichText: true), findsNothing);
      expect(find.textContaining('已送达 1/2'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        '群里的草稿',
      );
      await capture(tester, 'groups-chat-${width.toInt()}');
      await tester.tap(find.byTooltip('群组详情'));
      await tester.pumpAndSettle();
      expect(find.text('成员 3'), findsOneWidget);
      await capture(tester, 'groups-details-${width.toInt()}');
      await tester.tap(find.byTooltip('编辑群组'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-member-laptop')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-group')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('group-name-input')),
        '设计与产品交付协作小组',
      );
      await capture(tester, 'groups-editor-${width.toInt()}');
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('给 设计协作小组 发文件'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
      await capture(tester, 'groups-chat-attachment-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await finish(tester, service);
    });
  }

  for (final width in [1440.0, 720.0, 440.0]) {
    testWidgets('conversation device right-click edits remark at $width', (
      tester,
    ) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        final service = UiFixtureService();
        service.peers['studio']!.online = false;
        service.peers['studio']!.remark = '设计同事';
        await show(
          tester,
          service,
          size: Size(width, 920),
          textScale: width == 440 ? 1.3 : 1,
        );
        await navigate(tester, 2);
        if (width == 1440) {
          await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('message-input')),
            '保留当前草稿',
          );
        }
        final unread = service.unreadFor('studio');
        await tester.tap(
          find.byKey(const ValueKey('conversation-studio')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('修改备注'), findsOneWidget);
        expect(find.byKey(const ValueKey('remark-input')), findsNothing);
        expect(service.unreadFor('studio'), unread);
        await capture(tester, 'conversation-context-menu-${width.toInt()}');
        await tester.tap(find.text('修改备注'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('remark-input')))
              .controller!
              .text,
          '设计同事',
        );
        await tester.enterText(
          find.byKey(const ValueKey('remark-input')),
          '小林的工作站',
        );
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        service.emit();
        await tester.pumpAndSettle();
        expect(service.peers['studio']!.displayName, '小林的工作站');
        expect(find.text('小林的工作站'), findsOneWidget);
        expect(service.unreadFor('studio'), unread);
        if (width == 1440) {
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('message-input')))
                .controller!
                .text,
            '保留当前草稿',
          );
          expect(find.byKey(const ValueKey('messages-laptop')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await finish(tester, service);
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }

  testWidgets(
    'conversation context menu dismisses without editing or applying to groups',
    (tester) async {
      final service = UiFixtureService();
      final group = service.addGroupFixture();
      await show(tester, service);
      await navigate(tester, 2);
      final unread = service.unreadCount;
      await tester.tap(
        find.byKey(const ValueKey('conversation-studio')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('修改备注'), findsNothing);
      expect(service.peers['studio']!.remark, isEmpty);
      expect(service.unreadCount, unread);
      await tester.tap(
        find.byKey(ValueKey('conversation-${group.conversationId}')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('修改备注'), findsNothing);
      expect(service.unreadCount, unread);
      expect(tester.takeException(), isNull);
      await finish(tester, service);
    },
  );

  testWidgets('device remarks are editable and searchable by either name', (
    tester,
  ) async {
    final service = UiFixtureService();
    await show(tester, service);
    await navigate(tester, 1);
    await tester.tap(find.byKey(const ValueKey('remark-laptop')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('remark-input')),
      '小林的笔记本',
    );
    await capture(tester, 'device-remark-editor');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    service.emit();
    await tester.pumpAndSettle();
    expect(service.peers['laptop']!.displayName, '小林的笔记本');
    expect(find.text('我的笔记本'), findsOneWidget);
    expect(find.text('小林的笔记本'), findsOneWidget);
    await capture(tester, 'device-remarks');
    expect(tester.takeException(), isNull);
    await finish(tester, service);
  });

  for (final width in [1440.0, 720.0, 440.0]) {
    testWidgets(
      'unread badges persist in background across navigation layouts at $width',
      (tester) async {
        final service = UiFixtureService(populated: false);
        final desktop = DesktopController(
          Directory.systemTemp,
          startup: FakeStartupRegistration(),
          onExit: () async {},
        );
        desktop.onWindowFocus();
        service.messages.addAll([
          ChatMessage(
            id: '1',
            peerId: 'laptop',
            text: '第一条消息',
            outgoing: false,
          ),
          ChatMessage(
            id: '2',
            peerId: 'laptop',
            text: '文件已经发过来了',
            outgoing: false,
          ),
          ChatMessage(
            id: '3',
            peerId: 'studio',
            text: '请看一下最新的设计稿',
            outgoing: false,
          ),
        ]);
        await show(
          tester,
          service,
          desktop: desktop,
          size: Size(width, 920),
          textScale: width == 440 ? 1.3 : 1,
        );
        expect(find.byKey(const ValueKey('unread-badge')), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        await capture(tester, 'messages-unread-nav-${width.toInt()}');
        await navigate(tester, 2);
        await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
        await tester.pumpAndSettle();
        expect(service.unreadFor('laptop'), 0);
        expect(service.unreadFor('studio'), 1);
        desktop.onWindowBlur();
        service.messages.add(
          ChatMessage(
            id: '4',
            peerId: 'laptop',
            text: '后台收到的新消息',
            outgoing: false,
          ),
        );
        service.emit();
        await tester.pumpAndSettle();
        expect(service.unreadFor('laptop'), 1);
        expect(service.unreadCount, 2);
        await capture(tester, 'messages-unread-chat-${width.toInt()}');
        desktop.onWindowFocus();
        await tester.pumpAndSettle();
        expect(service.unreadFor('laptop'), 0);
        expect(service.unreadFor('studio'), 1);
        expect(tester.takeException(), isNull);
        await finish(tester, service);
        desktop.dispose();
      },
    );
  }

  testWidgets(
    'tray activation opens the exact pending file request and handles expiry',
    (tester) async {
      final service = UiFixtureService(populated: false);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('tray_manager'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearlink/lifecycle'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async =>
            ['isMaximized', 'isFullScreen', 'isMinimized'].contains(call.method)
            ? false
            : null,
      );
      final desktop = DesktopController(
        Directory.systemTemp,
        service: service,
        startup: FakeStartupRegistration(),
        onExit: () async {},
      );
      await tester.runAsync(desktop.initialize);
      for (final peerId in ['laptop', 'studio']) {
        service.incoming.add(
          IncomingOffer(
            id: 'offer-$peerId',
            peer: service.peers[peerId]!,
            remoteHost: '127.0.0.1',
            files: [
              TransferItem(
                id: peerId,
                peerId: peerId,
                peerName: service.peers[peerId]!.name,
                name: '$peerId.txt',
                size: 1024,
                outgoing: false,
              ),
            ],
          ),
        );
      }
      await show(tester, service, desktop: desktop);
      await navigate(tester, 4);
      await tester.runAsync(
        () => messenger.handlePlatformMessage(
          'nearlink/lifecycle',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('openIncomingOffer', 'offer-studio'),
          ),
          null,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('设计工作站 发来的文件'), findsOneWidget);
      expect(find.text('studio.txt'), findsOneWidget);
      expect(find.byTooltip('收起清单'), findsOneWidget);
      expect(
        service.incoming.every((offer) => !offer.decision.isCompleted),
        isTrue,
      );
      await capture(tester, 'tray-file-opened-request');
      await tester.runAsync(
        () => messenger.handlePlatformMessage(
          'nearlink/lifecycle',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('openIncomingOffer', 'expired-offer'),
          ),
          null,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('该接收请求已失效或已处理。'), findsOneWidget);
      expect(service.incoming.length, 2);
      expect(tester.takeException(), isNull);
      await finish(tester, service);
      desktop.dispose();
      messenger.setMockMethodCallHandler(
        const MethodChannel('tray_manager'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearlink/lifecycle'),
        null,
      );
    },
  );

  for (final width in [1440.0, 440.0]) {
    testWidgets('discovery failure offers working recovery at $width', (
      tester,
    ) async {
      final service = UiFixtureService(discoveryEnabled: true)
        ..discoveryFailure = '发现网络不可达，正在自动重试；也可通过 IP 连接'
        ..discoveryRetryGate = Completer<void>();
      await show(
        tester,
        service,
        size: Size(width, 900),
        textScale: width == 440 ? 1.3 : 1,
      );
      expect(find.text('局域网已就绪'), findsNothing);
      if (width > 740) {
        expect(find.text('需手动连接'), findsOneWidget);
        expect(find.text('可通过 IP 连接'), findsOneWidget);
        expect(find.text('自动发现已开启'), findsNothing);
      }
      expect(find.byTooltip('通过 IP 连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'discovery-warning-${width.toInt()}');
      await tester.tap(find.byTooltip('通过 IP 连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接另一台设备'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('重新检测网络'));
      await tester.pump();
      expect(service.discoveryRetries, 1);
      expect(find.byTooltip('正在重新检测'), findsOneWidget);
      service.discoveryRetryGate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('发现网络不可达'), findsNothing);
      if (width > 740) expect(find.text('局域网已就绪'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, service);
    });
  }

  for (final size in [
    const Size(1440, 920),
    const Size(1000, 760),
    const Size(720, 700),
    const Size(440, 760),
  ]) {
    testWidgets('all five pages and receiving confirmation fit ${size.width}', (
      tester,
    ) async {
      final service = UiFixtureService();
      await show(tester, service, size: size);
      expect(find.text('分享，从这里开始'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final prefix = size.width == 1440
          ? 'desktop'
          : 'width-${size.width.toInt()}';
      await capture(tester, '$prefix-send');
      await navigate(tester, 1);
      expect(find.text('身边的设备'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, '$prefix-devices');
      await tester.ensureVisible(
        find.byKey(const ValueKey('chat-with-laptop')),
      );
      await tester.tap(find.byKey(const ValueKey('chat-with-laptop')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, '$prefix-messages');
      await navigate(tester, 3);
      expect(find.text('搜索文件或设备'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, '$prefix-history');
      await navigate(tester, 4);
      expect(find.byKey(const ValueKey('device-name-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, '$prefix-settings');
      final peer = service.peers['laptop']!;
      final offer = IncomingOffer(
        id: 'offer',
        peer: peer,
        remoteHost: peer.host,
        files: [
          TransferItem(
            id: 'file',
            peerId: peer.id,
            peerName: peer.name,
            name: '活动照片/所有人的合照.jpg',
            size: 6240000,
            outgoing: false,
          ),
        ],
      );
      service.incoming.add(offer);
      service.emit();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getTopLeft(find.widgetWithText(FilledButton, '接收')).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(DesktopTitleBar)).dy,
        ),
      );
      await tester.tap(find.byTooltip('查看清单'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('活动照片/所有人的合照.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, '$prefix-receive');
      await tester.tap(find.widgetWithText(FilledButton, '接收'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(await offer.decision.future, isTrue);
      expect(service.incoming, isEmpty);
      await finish(tester, service);
    });
  }

  for (final size in [
    const Size(1440, 920),
    const Size(720, 760),
    const Size(440, 640),
  ]) {
    testWidgets('incoming review layout and decisions fit ${size.width}', (
      tester,
    ) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        final service = UiFixtureService();
        final peer = service.peers['studio']!..remark = '小林的工作站';
        service.saveDirectory =
            r'C:\Users\NearLink\Downloads\邻传\设计协作小组\本周设计交付与原始素材';
        final offer = IncomingOffer(
          id: 'review-files',
          peer: peer,
          remoteHost: peer.host,
          files: List.generate(
            8,
            (index) => TransferItem(
              id: 'review-file-$index',
              peerId: peer.id,
              peerName: peer.name,
              name: index == 0
                  ? '设计交付/首页交互方案与视觉规范（团队评审最终确认版本）.pdf'
                  : '设计交付/交付文件-${index + 1}.pdf',
              size: (index + 1) * 1048576,
              outgoing: false,
            ),
          ),
        )..groupName = '设计协作小组';
        final next = IncomingOffer(
          id: 'next-review',
          peer: service.peers['laptop']!,
          remoteHost: '127.0.0.1',
          files: [
            TransferItem(
              id: 'next-file',
              peerId: 'laptop',
              peerName: '我的笔记本',
              name: '周末出游合照.jpg',
              size: 6240000,
              outgoing: false,
            ),
          ],
        );
        await show(
          tester,
          service,
          size: size,
          textScale: size.width == 440 ? 1.3 : 1,
        );
        final dropArea = find.byType(DropTarget);
        final originalDropRect = tester.getRect(dropArea);
        final pageScroll = tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView).first,
            )
            .controller!;
        final originalViewport = pageScroll.position.viewportDimension;
        service.incoming.addAll([offer, next]);
        service.emit();
        await tester.pumpAndSettle();
        expect(tester.getRect(dropArea), originalDropRect);
        expect(pageScroll.position.viewportDimension, originalViewport);
        expect(find.text('小林的工作站 发来的文件'), findsOneWidget);
        expect(find.text('8 个文件 · 36.0 MB'), findsOneWidget);
        expect(find.text('还有 1 个请求等待处理'), findsOneWidget);
        expect(find.text('群组 · 设计协作小组'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('incoming-save-directory')),
          findsNothing,
        );
        final banner = tester.getRect(
          find.byKey(const ValueKey('incoming-banner')),
        );
        expect(
          banner.top,
          greaterThan(
            tester.getBottomLeft(find.byType(DesktopTitleBar)).dy + 8,
          ),
        );
        expect(banner.left, greaterThan(8));
        expect(banner.right, lessThan(size.width - 8));
        await capture(
          tester,
          'incoming-overlay-collapsed-${size.width.toInt()}',
        );
        await tester.tap(find.byTooltip('查看清单'));
        await tester.pumpAndSettle();
        expect(tester.getRect(dropArea), originalDropRect);
        expect(pageScroll.position.viewportDimension, originalViewport);
        expect(find.text(offer.files.first.relativePath), findsOneWidget);
        expect(find.byTooltip(service.saveDirectory), findsOneWidget);
        expect(
          find.byKey(const ValueKey('incoming-accept')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'incoming-overlay-expanded-${size.width.toInt()}',
        );
        final fileList = find.byKey(
          const ValueKey('incoming-files-review-files'),
        );
        await tester.scrollUntilVisible(
          find.text(offer.files.last.relativePath),
          100,
          scrollable: find.descendant(
            of: fileList,
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          find.text(offer.files.last.relativePath).hitTestable(),
          findsOneWidget,
        );
        expect(offer.decision.isCompleted, isFalse);
        expect(next.decision.isCompleted, isFalse);
        await tester.tap(find.byTooltip('收起清单'));
        await tester.pumpAndSettle();
        expect(fileList, findsNothing);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: Offset(size.width / 2, size.height - 120),
            scrollDelta: const Offset(0, 140),
          ),
        );
        await tester.pumpAndSettle();
        expect(pageScroll.offset, greaterThan(0));
        expect(
          tester.getRect(find.byKey(const ValueKey('incoming-banner'))),
          banner,
        );
        pageScroll.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('incoming-reject')));
        await tester.pumpAndSettle();
        expect(await offer.decision.future, isFalse);
        expect(next.decision.isCompleted, isFalse);
        expect(find.text('我的笔记本 发来的文件'), findsOneWidget);
        expect(find.byTooltip('查看清单'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('incoming-accept')));
        await tester.pumpAndSettle();
        expect(await next.decision.future, isTrue);
        expect(find.byKey(const ValueKey('incoming-banner')), findsNothing);
        expect(tester.getRect(dropArea), originalDropRect);
        expect(pageScroll.position.viewportDimension, originalViewport);
        expect(tester.takeException(), isNull);
        await finish(tester, service);
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }

  for (final width in [1440.0, 440.0]) {
    testWidgets('incoming overlay preserves chat layout and input at $width', (
      tester,
    ) async {
      final service = UiFixtureService();
      await show(tester, service, size: Size(width, 760));
      await navigate(tester, 2);
      await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('message-input'));
      final originalInput = tester.getRect(input);
      final offer = IncomingOffer(
        id: 'chat-overlay',
        peer: service.peers['studio']!,
        remoteHost: '127.0.0.1',
        files: [
          TransferItem(
            id: 'chat-overlay-file',
            peerId: 'studio',
            peerName: '设计工作站',
            name: '设计稿.pdf',
            size: 1024,
            outgoing: false,
          ),
        ],
      );
      service.incoming.add(offer);
      service.emit();
      await tester.pumpAndSettle();
      expect(tester.getRect(input), originalInput);
      await tester.tap(input);
      await tester.enterText(input, '收到，稍后接收文件');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.sentMessages.single, (
        peerId: 'laptop',
        text: '收到，稍后接收文件',
      ));
      expect(offer.decision.isCompleted, isFalse);
      expect(find.byKey(const ValueKey('incoming-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, service);
    });
  }

  testWidgets(
    'message drafts stay with their device and Enter sends only to that device',
    (tester) async {
      final service = UiFixtureService(populated: false);
      await show(tester, service);
      await navigate(tester, 2);
      await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        '给笔记本的草稿',
      );
      await tester.tap(find.byKey(const ValueKey('conversation-studio')));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('message-input')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        '给工作站的消息',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(service.sentMessages.single, (peerId: 'studio', text: '给工作站的消息'));
      await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('message-input')))
            .controller!
            .text,
        '给笔记本的草稿',
      );
      await finish(tester, service);
    },
  );

  testWidgets(
    'Enter confirms active Chinese composition without sending the draft',
    (tester) async {
      final service = UiFixtureService(populated: false);
      await show(tester, service);
      await navigate(tester, 2);
      await tester.tap(find.byKey(const ValueKey('conversation-laptop')));
      await tester.pump();
      final input = find.byKey(const ValueKey('message-input'));
      await tester.showKeyboard(input);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你好',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(service.sentMessages, isEmpty);
      expect(tester.widget<TextField>(input).controller!.text, '你好');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你好',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(service.sentMessages.single, (peerId: 'laptop', text: '你好'));
      await finish(tester, service);
    },
  );

  testWidgets(
    'dropped files require explicit recipient, and an offline recipient cannot send',
    (tester) async {
      final service = UiFixtureService(populated: false);
      final directory = Directory.systemTemp.createTempSync('nearlink-ui-');
      final file = File('${directory.path}/hello.txt')
        ..writeAsStringSync('hello');
      await show(tester, service);
      await tester.runAsync(() async {
        tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(file.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('hello.txt'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('send-files')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('recipient-studio')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('send-files')))
            .onPressed,
        isNotNull,
      );
      service.peers['studio']!.online = false;
      service.emit();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('send-files')))
            .onPressed,
        isNull,
      );
      expect(service.sentBatches, isEmpty);
      service.peers['studio']!.online = true;
      service.emit();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send-files')));
      await tester.pump();
      expect(service.sentBatches.single.peerId, 'studio');
      expect(service.sentBatches.single.files.single.path, file.path);
      await finish(tester, service);
      directory.deleteSync(recursive: true);
    },
  );

  testWidgets(
    'history filters and settings edit work at increased text scale',
    (tester) async {
      final service = UiFixtureService();
      await show(tester, service, size: const Size(440, 820), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await navigate(tester, 3);
      await tester.tap(find.byKey(const ValueKey('history-filter-3')));
      await tester.pump();
      expect(find.text('项目交付文档.pdf'), findsOneWidget);
      expect(find.text('品牌素材包.zip'), findsNothing);
      expect(tester.takeException(), isNull);
      await navigate(tester, 4);
      await tester.enterText(
        find.byKey(const ValueKey('device-name-input')),
        '新的设备名称',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('save-settings')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-settings')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(service.name, '新的设备名称');
      expect(tester.takeException(), isNull);
      await finish(tester, service);
    },
  );

  testWidgets(
    'sidebar collapse and lifecycle settings work across window sizes',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('tray_manager'),
            (_) async => null,
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('tray_manager'),
              null,
            );
      });
      for (final width in [1200.0, 720.0, 440.0]) {
        final service = UiFixtureService();
        final startup = FakeStartupRegistration();
        final directory = Directory.systemTemp.createTempSync(
          'nearlink-desktop-ui-',
        );
        final desktop = DesktopController(
          directory,
          startup: startup,
          onExit: () async {},
        );
        await tester.runAsync(desktop.initialize);
        await show(
          tester,
          service,
          size: Size(width, 900),
          textScale: width == 440 ? 1.3 : 1,
          desktop: desktop,
        );
        if (width == 1200) {
          expect(find.byTooltip('收起侧边栏'), findsOneWidget);
          await tester.runAsync(() async {
            await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump();
          expect(desktop.sidebarCollapsed, isTrue);
          expect(find.byTooltip('展开侧边栏'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture(tester, 'desktop-collapsed');
          await tester.runAsync(() async {
            await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump();
          expect(desktop.sidebarCollapsed, isFalse);
        }
        await navigate(tester, 4);
        await tester.ensureVisible(find.text('退出邻传'));
        await tester.pumpAndSettle();
        expect(find.text('收起到任务托盘'), findsOneWidget);
        expect(find.text('退出邻传'), findsOneWidget);
        expect(
          tester
              .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
              .groupValue,
          isTrue,
        );
        await tester.tap(find.text('退出邻传'));
        await tester.pumpAndSettle();
        for (var attempt = 0; desktop.updating && attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(desktop.settingsError, isNull);
        expect(desktop.closeToTray, isFalse);
        expect(
          tester
              .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
              .groupValue,
          isFalse,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('start-at-login')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('start-at-login')));
        await tester.pumpAndSettle();
        expect(startup.enabled, isTrue);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('启动与关闭'));
        await tester.pumpAndSettle();
        await capture(tester, 'lifecycle-settings-${width.toInt()}');
        await finish(tester, service);
        desktop.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
