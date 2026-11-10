import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/desktop/desktop_notifications.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';

import 'notification_fixtures.dart';
import 'ui_fixtures.dart';

void main() {
  late Directory directory;
  late UiFixtureService service;
  late FakeNotificationPlatform platform;
  late DesktopNotifications controller;
  var foreground = false, windowShown = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'nearlink-notifications-',
    );
    service = _IsolatedService(directory);
    platform = FakeNotificationPlatform();
    foreground = false;
    windowShown = 0;
    controller = DesktopNotifications(
      service,
      platform: platform,
      isForeground: () async => foreground,
      showWindow: () async {
        windowShown++;
      },
    );
    await controller.initialize();
  });

  tearDown(() async {
    await controller.close();
    controller.dispose();
    await service.close();
    await directory.delete(recursive: true);
  });

  IncomingOffer offer(String id) => IncomingOffer(
    id: id,
    peer: service.peers.values.first,
    remoteHost: '127.0.0.1',
    files: [
      TransferItem(
        id: 'file-$id',
        peerId: 'laptop',
        peerName: '我的笔记本',
        name: '文件.txt',
        size: 100,
        outgoing: false,
      ),
    ],
  );

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  TransferCompletion completion(String id, {bool outgoing = true}) =>
      TransferCompletion(
        id: id,
        outgoing: outgoing,
        peerName: '小林的工作站',
        fileCount: 14,
        totalBytes: 1503238553,
      );

  test(
    'batch completions notify once, throttle sounds and open history',
    () async {
      service.completionEvents.add(completion('sent'));
      service.completionEvents.add(completion('received', outgoing: false));
      await settle();
      expect(platform.completions, hasLength(2));
      expect(platform.completions.map((entry) => entry.sound), [true, false]);
      expect(platform.completions.first.completion.title, '全部发送完成');
      expect(platform.completions.last.completion.title, '接收完成');
      for (var i = 0; i < 10; i++) {
        service.emit();
      }
      await settle();
      expect(platform.completions, hasLength(2));
      var historyOpened = 0;
      final subscription = controller.historyOpened.listen(
        (_) => historyOpened++,
      );
      platform.onAction!('transfer:received', 'accept');
      await settle();
      expect(windowShown, 0);
      platform.onAction!('transfer:received', 'open');
      await settle();
      expect(windowShown, 1);
      expect(historyOpened, 1);
      expect(platform.dismissed, contains('transfer:received'));
      await subscription.cancel();
    },
  );

  test(
    'foreground completion uses optional sound without desktop toast',
    () async {
      foreground = true;
      service.completionEvents.add(completion('one'));
      service.completionEvents.add(completion('two', outgoing: false));
      await settle();
      expect(platform.completions, isEmpty);
      expect(platform.messageSounds, 1);
      await controller.update(completionSound: false);
      service.completionEvents.add(completion('muted'));
      await settle();
      expect(platform.messageSounds, 1);
    },
  );

  test(
    'mixed group outcome notifies once and respects completion settings',
    () async {
      const result = TransferCompletion(
        id: 'group-mixed',
        outgoing: true,
        peerName: '设计协作',
        fileCount: 2,
        totalBytes: 100,
        recipientCount: 2,
        rejectedRecipientCount: 1,
      );
      service.completionEvents.add(result);
      await settle();
      expect(platform.completions, hasLength(1));
      expect(platform.completions.single.completion.title, '群文件发送结束');
      expect(
        platform.completions.single.completion.summary,
        '完成 1 位 · 拒收 1 位\n设计协作 · 2 个文件',
      );
      expect(platform.completions.single.sound, isTrue);
      await controller.update(completionEnabled: false, completionSound: false);
      service.completionEvents.add(result);
      await settle();
      expect(platform.completions, hasLength(1));
    },
  );

  test(
    'completion preferences are independent, clear notices and do not replay',
    () async {
      service.completionEvents.add(completion('one'));
      await settle();
      await controller.update(completionEnabled: false, completionSound: false);
      expect(platform.dismissed, contains('transfer:one'));
      expect(controller.enabled, isTrue);
      expect(controller.messageSound, isTrue);
      service.completionEvents.add(completion('disabled'));
      await settle();
      expect(platform.completions, hasLength(1));
      await controller.update(completionEnabled: true);
      await settle();
      expect(platform.completions, hasLength(1));
      service.completionEvents.add(completion('new'));
      await settle();
      expect(platform.completions, hasLength(2));
      expect(platform.completions.last.sound, isFalse);
    },
  );

  test(
    'blocked completion notices and restored history are not replayed',
    () async {
      platform.allowed = false;
      service.completionEvents.add(completion('blocked'));
      await settle();
      platform.allowed = true;
      await controller.refresh();
      service.transfers.add(
        TransferItem(
          id: 'historical',
          peerId: 'laptop',
          peerName: 'Laptop',
          name: 'old.zip',
          size: 10,
          outgoing: true,
          status: TransferStatus.complete,
        ),
      );
      service.emit();
      await settle();
      expect(platform.completions, isEmpty);
      service.completionEvents.add(completion('fresh'));
      await settle();
      expect(platform.completions.single.completion.id, 'fresh');
    },
  );

  test(
    'group notices use group identity and sender remark, opening only that conversation',
    () async {
      final group = service.addGroupFixture();
      service.emit();
      await settle();
      expect(platform.messageNotifications.single.peerId, group.conversationId);
      expect(platform.messageNames.single, group.name);
      expect(platform.messagePreviews.single, startsWith('小林的笔记本：'));
      final opened = <String>[];
      final subscription = controller.conversations.listen(opened.add);
      platform.onAction!('chat:${group.conversationId}', 'open');
      await settle();
      expect(opened, [group.conversationId]);
      expect(service.unreadFor(group.conversationId), 1);
      await subscription.cancel();
    },
  );

  test(
    'one background notification per offer despite frequent service updates',
    () async {
      service.incoming.add(offer('one'));
      service.emit();
      await settle();
      for (var i = 0; i < 20; i++) {
        service.emit();
      }
      await settle();
      expect(platform.shown, ['one']);
      service.incoming.clear();
      service.emit();
      await settle();
      expect(platform.dismissed, contains('one'));
    },
  );

  test(
    'foreground offers stay in app and are not replayed on later updates',
    () async {
      foreground = true;
      service.incoming.add(offer('one'));
      service.emit();
      await settle();
      foreground = false;
      service.emit();
      await settle();
      expect(platform.shown, isEmpty);
    },
  );

  test(
    'click opens the exact request and action buttons decide only that request',
    () async {
      final first = offer('one'), second = offer('two');
      service.incoming.addAll([first, second]);
      service.emit();
      await settle();
      final opened = <String>[];
      final subscription = controller.opened.listen(opened.add);
      platform.onAction!('two', 'open');
      await settle();
      expect(windowShown, 1);
      expect(opened, ['two']);
      expect(second.decision.isCompleted, isFalse);
      platform.onAction!('two', 'accept');
      await settle();
      expect(await second.decision.future, isTrue);
      expect(first.decision.isCompleted, isFalse);
      platform.onAction!('one', 'reject');
      await settle();
      expect(await first.decision.future, isFalse);
      await subscription.cancel();
    },
  );

  test(
    'stale or repeated actions never accept another pending request',
    () async {
      final pending = offer('other');
      service.incoming.add(pending);
      platform.onAction!('expired', 'accept');
      platform.onAction!('other', 'unknown');
      await settle();
      expect(pending.decision.isCompleted, isFalse);
      expect(windowShown, 1);
    },
  );

  test('cleanup failures cannot block activation or later offers', () async {
    final first = offer('one');
    service.incoming.add(first);
    service.emit();
    await settle();
    platform.dismissFails = true;
    final opened = <String>[];
    final subscription = controller.opened.listen(opened.add);
    platform.onAction!('one', 'open');
    await settle();
    expect(windowShown, 1);
    expect(opened, ['one']);
    platform.onAction!('one', 'accept');
    await settle();
    expect(await first.decision.future, isTrue);
    service.incoming.add(offer('two'));
    service.emit();
    await settle();
    expect(platform.shown, ['one', 'two']);
    final attempts = platform.dismissed.length;
    for (var i = 0; i < 20; i++) {
      service.emit();
    }
    await settle();
    expect(platform.dismissed.length, attempts);
    await subscription.cancel();
  });

  test(
    'disable clears notices and sound preference persists across restart',
    () async {
      service.incoming.add(offer('one'));
      service.emit();
      await settle();
      await controller.update(
        enabled: false,
        sound: false,
        completionEnabled: false,
        completionSound: false,
      );
      expect(platform.dismissed, contains('one'));
      service.incoming.add(offer('two'));
      service.emit();
      await settle();
      expect(platform.shown, ['one']);
      await controller.close();
      controller.dispose();
      platform = FakeNotificationPlatform();
      controller = DesktopNotifications(
        service,
        platform: platform,
        isForeground: () async => false,
        showWindow: () async {},
      );
      await controller.initialize();
      expect(controller.enabled, isFalse);
      expect(controller.sound, isFalse);
      expect(controller.completionEnabled, isFalse);
      expect(controller.completionSound, isFalse);
      await controller.update(enabled: true);
      await settle();
      expect(platform.shown, containsAll(['one', 'two']));
      expect(platform.sounds, everyElement(isFalse));
    },
  );

  test('system-disabled notifications recover after a refresh', () async {
    platform.allowed = false;
    service.incoming.add(offer('one'));
    service.emit();
    await settle();
    expect(platform.shown, isEmpty);
    expect(controller.allowed, isFalse);
    platform.allowed = true;
    await controller.refresh();
    await settle();
    expect(platform.shown, ['one']);
  });

  test(
    'background message notifications aggregate per sender and open that conversation',
    () async {
      service.messages.addAll([
        ChatMessage(id: 'm1', peerId: 'laptop', text: 'one', outgoing: false),
        ChatMessage(id: 'm2', peerId: 'laptop', text: 'two', outgoing: false),
        ChatMessage(id: 'm3', peerId: 'studio', text: 'three', outgoing: false),
      ]);
      service.emit();
      await settle();
      expect(
        platform.messageNotifications.map((m) => m.count),
        unorderedEquals([2, 1]),
      );
      expect(platform.messageNotifications.where((m) => m.sound), hasLength(1));
      final opened = <String>[];
      final subscription = controller.conversations.listen(opened.add);
      platform.onAction!('chat:laptop', 'open');
      await settle();
      expect(opened, ['laptop']);
      expect(windowShown, 1);
      expect(service.unreadFor('laptop'), 2);
      service.markMessagesRead(peerId: 'studio');
      service.emit();
      await settle();
      expect(platform.dismissed, contains('chat:studio'));
      service.emit();
      await settle();
      expect(platform.messageNotifications, hasLength(2));
      await subscription.cancel();
    },
  );

  test(
    'foreground sound is throttled and its switch silences new messages',
    () async {
      foreground = true;
      service.messages.add(
        ChatMessage(id: 'm1', peerId: 'laptop', text: 'one', outgoing: false),
      );
      service.emit();
      await settle();
      service.messages.add(
        ChatMessage(id: 'm2', peerId: 'studio', text: 'two', outgoing: false),
      );
      service.emit();
      await settle();
      expect(platform.messageNotifications, isEmpty);
      expect(platform.messageSounds, 1);
      await controller.update(messageSound: false, messageEnabled: false);
      service.messages.add(
        ChatMessage(id: 'm3', peerId: 'laptop', text: 'three', outgoing: false),
      );
      service.emit();
      await settle();
      expect(platform.messageSounds, 1);
      final saved = await File(
        '${directory.path}/notifications.json',
      ).readAsString();
      expect(saved, contains('"messageSound":false'));
      expect(saved, contains('"messageEnabled":false'));
    },
  );

  test('already read messages and restored history do not alert', () async {
    service.messages.add(
      ChatMessage(
        id: 'read',
        peerId: 'laptop',
        text: 'visible',
        outgoing: false,
        read: true,
      ),
    );
    service.emit();
    await settle();
    expect(platform.messageNotifications, isEmpty);
    expect(platform.messageSounds, 0);
    service.messages.add(
      ChatMessage(
        id: 'history',
        peerId: 'laptop',
        text: 'unread history',
        outgoing: false,
      ),
    );
    await controller.close();
    controller.dispose();
    platform = FakeNotificationPlatform();
    controller = DesktopNotifications(
      service,
      platform: platform,
      isForeground: () async => false,
      showWindow: () async {},
    );
    await controller.initialize();
    service.emit();
    await settle();
    expect(platform.messageNotifications, isEmpty);
    expect(service.unreadCount, 1);
  });

  test(
    'an offer resolved while native show is pending is removed afterwards',
    () async {
      platform.showGate = Completer<void>();
      service.incoming.add(offer('one'));
      service.emit();
      await settle();
      service.incoming.clear();
      service.emit();
      platform.showGate!.complete();
      await settle();
      expect(platform.dismissed, contains('one'));
    },
  );

  test(
    'test notifications work in foreground and shutdown releases the backend',
    () async {
      foreground = true;
      await controller.test();
      expect(platform.tests, 1);
      await controller.close();
      expect(platform.disposed, isTrue);
      platform.onAction!('test', 'open');
      await settle();
      expect(windowShown, 0);
    },
  );
}

class _IsolatedService extends UiFixtureService {
  _IsolatedService(this.directory) : super(populated: false);
  final Directory directory;
  @override
  Directory get dataDirectory => directory;
}
