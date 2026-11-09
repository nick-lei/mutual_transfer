import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/desktop/desktop_controller.dart';
import 'package:mutual_transfer/screenshot/screenshot_controller.dart';
import 'package:tray_manager/tray_manager.dart';

import 'desktop_fixtures.dart';
import 'ui_fixtures.dart';
import 'package:mutual_transfer/models.dart';
import 'package:mutual_transfer/lan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FakeStartupRegistration startup;
  late DesktopController controller;
  late List<String> calls;
  var trayFails = false;
  var minimized = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nearlink-desktop-');
    startup = FakeStartupRegistration();
    calls = [];
    trayFails = false;
    minimized = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      calls.add('window.${call.method}');
      return call.method == 'isMinimized' ? minimized : null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
      call,
    ) async {
      calls.add('tray.${call.method}');
      if (trayFails && call.method == 'setIcon') {
        throw PlatformException(code: 'tray', message: 'Unavailable');
      }
      return null;
    });
    controller = DesktopController(
      directory,
      startup: startup,
      onExit: () async => calls.add('service.close'),
    );
  });

  tearDown(() async {
    controller.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('tray_manager'),
      null,
    );
    await directory.delete(recursive: true);
  });

  test(
    'close hides to tray without stopping service; explicit exit cleans up once',
    () async {
      await controller.initialize();
      calls.clear();
      await controller.handleWindowClose();
      expect(calls, ['window.hide']);
      minimized = true;
      await controller.showWindow();
      expect(calls.sublist(1), [
        'window.isMinimized',
        'window.restore',
        'window.show',
        'window.focus',
      ]);
      calls.clear();
      await Future.wait([controller.exitApp(), controller.exitApp()]);
      expect(calls, ['service.close', 'tray.destroy', 'window.destroy']);
    },
  );

  test(
    'installer exit request bypasses close-to-tray and performs normal cleanup',
    () async {
      await controller.initialize();
      expect(controller.closeToTray, isTrue);
      calls.clear();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      await messenger.handlePlatformMessage(
        'nearlink/lifecycle',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('exitForUpdate'),
        ),
        null,
      );
      expect(calls, ['service.close', 'tray.destroy', 'window.destroy']);
      expect(controller.trayReady, isFalse);
    },
  );

  test(
    'sidebar and close preferences survive restart; startup comes from Windows registration',
    () async {
      await controller.initialize();
      expect(controller.sidebarCollapsed, isNull);
      expect(controller.closeToTray, isTrue);
      await controller.setSidebarCollapsed(true);
      await controller.setCloseToTray(false);
      await controller.setStartAtLogin(true);
      expect(startup.changes, [true]);
      controller.dispose();
      startup.enabled = false;
      controller = DesktopController(
        directory,
        startup: startup,
        onExit: () async => calls.add('service.close'),
      );
      await controller.initialize();
      expect(controller.sidebarCollapsed, isTrue);
      expect(controller.closeToTray, isFalse);
      expect(controller.startAtLogin, isFalse);
      calls.clear();
      await controller.handleWindowClose();
      expect(calls, ['service.close', 'tray.destroy', 'window.destroy']);
    },
  );

  test(
    'unavailable tray falls back to exit so the process cannot become inaccessible',
    () async {
      trayFails = true;
      await controller.initialize();
      expect(controller.trayReady, isFalse);
      expect(controller.trayError, isNotNull);
      calls.clear();
      await controller.handleWindowClose();
      expect(calls, ['service.close', 'window.destroy']);
    },
  );

  test(
    'failed writes and startup registration preserve the effective preferences',
    () async {
      await controller.initialize();
      await Directory('${directory.path}/desktop.json.tmp').create();
      await expectLater(
        controller.setCloseToTray(false),
        throwsA(isA<FileSystemException>()),
      );
      expect(controller.closeToTray, isTrue);
      expect(controller.settingsError, isNotNull);
      startup.fail = true;
      await expectLater(controller.setStartAtLogin(true), throwsStateError);
      expect(controller.startAtLogin, isFalse);
      expect(controller.updating, isFalse);
      expect(controller.settingsError, isNotNull);
    },
  );

  test('corrupt preferences do not prevent tray initialization', () async {
    await File('${directory.path}/desktop.json').writeAsString('{invalid');
    await controller.initialize();
    expect(controller.ready, isTrue);
    expect(controller.trayReady, isTrue);
    expect(controller.closeToTray, isTrue);
    expect(controller.settingsError, isNotNull);
  });

  test('tray menu restores or exits through the same lifecycle', () async {
    await controller.initialize();
    calls.clear();
    controller.onTrayMenuItemClick(MenuItem(key: 'show', label: '显示邻传'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['window.isMinimized', 'window.show', 'window.focus']);
    calls.clear();
    controller.onTrayMenuItemClick(MenuItem(key: 'exit', label: '退出邻传'));
    await controller.exitApp();
    expect(calls, ['service.close', 'tray.destroy', 'window.destroy']);
  });

  test(
    'tray inbox aggregates senders and routes a selected peer without clearing other unread messages',
    () async {
      controller.dispose();
      final service = UiFixtureService(populated: false);
      final inboxUpdates = <Map<dynamic, dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearlink/lifecycle'),
        (call) async {
          if (call.method == 'updateTrayInbox') {
            inboxUpdates.add(call.arguments as Map);
          }
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('nearlink/lifecycle'),
          null,
        ),
      );
      controller = DesktopController(
        directory,
        service: service,
        startup: startup,
        onExit: () async {},
      );
      await controller.initialize();
      service.messages.addAll([
        ChatMessage(id: '1', peerId: 'laptop', text: 'first', outgoing: false),
        ChatMessage(id: '2', peerId: 'laptop', text: 'second', outgoing: false),
        ChatMessage(id: '3', peerId: 'studio', text: 'third', outgoing: false),
      ]);
      service.emit();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final entries = inboxUpdates.last['entries'] as List;
      expect(entries.map((entry) => entry['count']), unorderedEquals([2, 1]));
      expect(
        entries.map((entry) => entry['name']),
        containsAll(['我的笔记本', '设计工作站']),
      );
      final opened = <String>[];
      final subscription = controller.conversations.listen(opened.add);
      await messenger.handlePlatformMessage(
        'nearlink/lifecycle',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('openConversation', 'laptop'),
        ),
        null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(opened, ['laptop']);
      expect(service.unreadCount, 3);
      controller.onWindowFocus();
      expect(controller.isForeground, isTrue);
      controller.onWindowBlur();
      expect(controller.isForeground, isFalse);
      service.markMessagesRead();
      service.emit();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(inboxUpdates.last['entries'], isEmpty);
      await subscription.cancel();
      controller.dispose();
      await service.close();
      controller = DesktopController(
        directory,
        startup: startup,
        onExit: () async {},
      );
    },
  );

  test(
    'tray groups messages by group identity with local remark previews',
    () async {
      controller.dispose();
      final service = UiFixtureService(populated: false);
      final group = service.addGroupFixture();
      final updates = <Map<dynamic, dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearlink/lifecycle'),
        (call) async {
          if (call.method == 'updateTrayInbox') {
            updates.add(call.arguments as Map);
          }
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('nearlink/lifecycle'),
          null,
        ),
      );
      controller = DesktopController(
        directory,
        service: service,
        startup: startup,
        onExit: () async {},
      );
      await controller.initialize();
      await controller.showInbox();
      final entries = updates.last['entries'] as List;
      expect(entries.single['peerId'], group.conversationId);
      expect(entries.single['name'], group.name);
      expect(entries.single['preview'], startsWith('小林的笔记本：'));
      final opened = <String>[];
      final subscription = controller.conversations.listen(opened.add);
      await messenger.handlePlatformMessage(
        'nearlink/lifecycle',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('openConversation', group.conversationId),
        ),
        null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(opened, [group.conversationId]);
      expect(service.unreadCount, 1);
      await subscription.cancel();
      controller.dispose();
      await service.close();
      controller = DesktopController(
        directory,
        startup: startup,
        onExit: () async {},
      );
    },
  );

  test('tooltip refresh cannot overwrite the unread tray icon', () async {
    controller.dispose();
    final service = UiFixtureService(populated: false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var visibleIcon = 'normal';
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
      call,
    ) async {
      if (call.method == 'setToolTip') visibleIcon = 'normal';
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('nearlink/lifecycle'),
      (call) async {
        if (call.method == 'updateTrayInbox') {
          final entries = (call.arguments as Map)['entries'] as List;
          visibleIcon = entries.isEmpty ? 'normal' : 'unread';
          return {'trayIconApplied': true, 'trayBlinking': entries.isNotEmpty};
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('nearlink/lifecycle'),
        null,
      ),
    );
    controller = DesktopController(
      directory,
      service: service,
      startup: startup,
      onExit: () async {},
    );
    await controller.initialize();
    await controller.showInbox();
    expect(visibleIcon, 'normal');
    for (var index = 0; index < 2; index++) {
      service.messages.add(
        ChatMessage(
          id: 'unread-$index',
          peerId: 'laptop',
          text: 'hello',
          outgoing: false,
        ),
      );
      service.emit();
      await controller.showInbox();
      expect(visibleIcon, 'unread');
    }
    service.markMessagesRead();
    await controller.showInbox();
    expect(visibleIcon, 'normal');
    controller.dispose();
    await service.close();
    controller = DesktopController(
      directory,
      startup: startup,
      onExit: () async {},
    );
  });

  test(
    'file requests remain in tray after messages are read and route by offer identity',
    () async {
      controller.dispose();
      final service = UiFixtureService(populated: false);
      final updates = <Map<dynamic, dynamic>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearlink/lifecycle'),
        (call) async {
          if (call.method == 'updateTrayInbox') {
            updates.add(call.arguments as Map);
          }
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('nearlink/lifecycle'),
          null,
        ),
      );
      controller = DesktopController(
        directory,
        service: service,
        startup: startup,
        onExit: () async {},
      );
      await controller.initialize();
      IncomingOffer offer(String id, String peerId) => IncomingOffer(
        id: id,
        peer: service.peers[peerId]!,
        remoteHost: '127.0.0.1',
        files: [
          TransferItem(
            id: '$id-file',
            peerId: peerId,
            peerName: service.peers[peerId]!.name,
            name: '$id.txt',
            size: 318464,
            outgoing: false,
          ),
        ],
      );
      final first = offer('first', 'laptop'),
          second = offer('second', 'studio');
      service.incoming.addAll([first, second]);
      service.messages.add(
        ChatMessage(
          id: 'unread',
          peerId: 'laptop',
          text: 'hello',
          outgoing: false,
        ),
      );
      service.emit();
      await controller.showInbox();
      var entries = updates.last['entries'] as List;
      expect(entries.map((entry) => entry['type']), [
        'file',
        'file',
        'message',
      ]);
      expect(entries[0]['preview'], contains('first.txt'));
      expect(entries[0]['count'], 1);
      expect(entries[1]['offerId'], 'second');
      await messenger.handlePlatformMessage(
        'nearlink/lifecycle',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('markMessagesRead'),
        ),
        null,
      );
      await controller.showInbox();
      entries = updates.last['entries'] as List;
      expect(entries.map((entry) => entry['offerId']), ['first', 'second']);
      expect(service.unreadCount, 0);
      expect(first.decision.isCompleted, isFalse);
      expect(second.decision.isCompleted, isFalse);
      final opened = <String>[];
      final subscription = controller.incomingOffers.listen(opened.add);
      await messenger.handlePlatformMessage(
        'nearlink/lifecycle',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('openIncomingOffer', 'second'),
        ),
        null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(opened, ['second']);
      controller.onTrayMenuItemClick(
        MenuItem(key: 'offer:first', label: 'file'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(opened, ['second', 'first']);
      expect(service.incoming.length, 2);
      service.decide(first, false);
      await controller.showInbox();
      expect((updates.last['entries'] as List).single['offerId'], 'second');
      service.decide(second, true);
      await controller.showInbox();
      expect(updates.last['entries'], isEmpty);
      await subscription.cancel();
      controller.dispose();
      await service.close();
      controller = DesktopController(
        directory,
        startup: startup,
        onExit: () async {},
      );
    },
  );

  test(
    'closing an active screenshot cancels it before changing window visibility',
    () async {
      controller.dispose();
      final screenshots = ScreenshotController(directory)..capturing = true;
      screenshots.onCancel = () => calls.add('capture.cancel');
      controller = DesktopController(
        directory,
        startup: startup,
        screenshots: screenshots,
        onExit: () async {},
      );
      await controller.initialize();
      calls.clear();
      await controller.handleWindowClose();
      expect(calls, ['capture.cancel']);
      screenshots.capturing = false;
      await controller.handleWindowClose();
      expect(calls.last, 'window.hide');
      controller.dispose();
      screenshots.dispose();
      controller = DesktopController(
        directory,
        startup: startup,
        onExit: () async {},
      );
    },
  );
}
