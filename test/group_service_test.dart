import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';
import 'package:path/path.dart' as p;

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Group condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory root;
  late LanService a, b, c;
  Future<LanService> start(String folder, {int port = 0}) async {
    final service = LanService(
      dataDirectory: Directory(p.join(root.path, folder)),
      requestedPort: port,
      discoveryEnabled: false,
      initialName: folder,
    );
    await service.start();
    expect(service.error, isNull);
    await service.updateSettings(
      directory: p.join(root.path, '$folder-received'),
    );
    return service;
  }

  Future<Peer> connect(LanService from, LanService to) =>
      from.connect('127.0.0.1:${to.port}');
  Future<int> post(
    LanService from,
    LanService to,
    String path,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${to.port}$path'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'peer': from.info, ...body}));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  Future<LanGroup> create() async =>
      a.createGroup('设计协作', [await connect(a, b), await connect(a, c)]);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nearlink-groups-');
    a = await start('owner');
    b = await start('member-b');
    c = await start('member-c');
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await c.close();
    await root.delete(recursive: true);
  });

  test(
    'remarks survive rediscovery and restart and never leave local profile',
    () async {
      final peer = await connect(a, b);
      await a.setPeerRemark(peer, '小林的工作站');
      await b.updateSettings(deviceName: 'DESKTOP-B');
      await connect(a, b);
      expect(peer.displayName, '小林的工作站');
      expect(peer.name, 'DESKTOP-B');
      final group = await create();
      expect(group.members.firstWhere((m) => m.id == b.id).name, 'DESKTOP-B');
      expect(jsonEncode(a.info), isNot(contains('小林')));
      await a.close();
      a = await start('owner');
      expect(a.peers[b.id]!.displayName, '小林的工作站');
      expect(a.groups[group.id]!.name, '设计协作');
      await a.setPeerRemark(a.peers[b.id]!, '');
      expect(a.peers[b.id]!.displayName, 'DESKTOP-B');
      await expectLater(
        a.setPeerRemark(a.peers[b.id]!, 'x' * 33),
        throwsFormatException,
      );
    },
  );

  test(
    'three peers share real group messages, independent direct unread and dedup',
    () async {
      final group = await create();
      expect(group.pendingSync, isEmpty);
      expect(b.groups[group.id]!.members.length, 3);
      await a.sendGroupMessage(group, '群里看一下最新素材');
      expect(a.messages.single.deliveredCount, 2);
      expect(b.messages.single.groupId, group.id);
      expect(c.unreadFor(group.conversationId), 1);
      await a.sendMessage(a.peers[b.id]!, '这是一条私信');
      expect(b.unreadFor(a.id), 1);
      b.setMessageView(group.conversationId, focused: true);
      expect(b.unreadFor(group.conversationId), 0);
      expect(b.unreadFor(a.id), 1);
      final bg = b.groups[group.id]!;
      await b.sendGroupMessage(bg, '收到，我补一下封面');
      expect(b.messages.last.deliveredCount, 2);
      expect(b.peers[c.id]!.online, true);
      expect(c.messages.last.senderName, b.name);
      final incoming = c.messages.last;
      expect(
        await post(b, c, '/v1/group-messages', {
          'groupId': group.id,
          'id': incoming.id,
          'text': incoming.text,
        }),
        200,
      );
      expect(c.messages.where((m) => m.id == incoming.id).length, 1);
    },
  );

  test(
    'members communicate with owner offline; retry sends only failed recipients',
    () async {
      final group = await create();
      await a.close();
      await b.sendGroupMessage(b.groups[group.id]!, '群主离线时依然能发给在线成员');
      final message = b.messages.single;
      expect(message.delivery, 'failed');
      expect(message.recipients[c.id], 'delivered');
      expect(message.recipients[a.id], 'failed');
      expect(c.messages.length, 1);
      a = await start('owner');
      await connect(b, a);
      await b.sendGroupMessage(
        b.groups[group.id]!,
        message.text,
        retry: message,
      );
      expect(message.delivery, 'delivered');
      expect(c.messages.length, 1);
      expect(a.messages.single.text, message.text);
      await b.close();
      b = await start('member-b');
      expect(b.messages.single.recipients.values, everyElement('delivered'));
    },
  );

  test(
    'owner edits membership, rejects outsiders and stale snapshots, then dissolves',
    () async {
      final group = await a.createGroup('小组', [await connect(a, b)]);
      final stale = group.toJson();
      expect(
        await post(c, b, '/v1/groups', {
          'group': {...stale, 'ownerId': c.id},
        }),
        400,
      );
      expect(
        await post(c, b, '/v1/group-messages', {
          'groupId': group.id,
          'id': newId(),
          'text': '非成员消息',
        }),
        400,
      );
      await a.updateGroup(
        group,
        title: '新设计小组',
        members: [a.peers[b.id]!, await connect(a, c)],
      );
      expect(c.groups[group.id]!.name, '新设计小组');
      await a.updateGroup(group, members: [a.peers[c.id]!]);
      expect(b.groups[group.id]!.activeFor(b.id), false);
      await expectLater(
        b.sendGroupMessage(b.groups[group.id]!, '已移出的成员'),
        throwsFormatException,
      );
      expect(await post(a, b, '/v1/groups', {'group': stale}), 200);
      expect(b.groups[group.id]!.activeFor(b.id), false);
      await a.updateGroup(group, dissolve: true);
      expect(c.groups[group.id]!.dissolved, true);
      await expectLater(
        c.sendGroupMessage(c.groups[group.id]!, '已解散'),
        throwsFormatException,
      );
    },
  );

  test(
    'offline leave stays inactive across restart and retries when owner returns',
    () async {
      final group = await create();
      await a.close();
      await b.leaveGroup(b.groups[group.id]!);
      expect(b.groups[group.id]!.pendingSync, contains(a.id));
      await b.close();
      b = await start('member-b');
      expect(b.groups[group.id]!.activeFor(b.id), false);
      a = await start('owner');
      await connect(b, a);
      await b.syncGroup(b.groups[group.id]!);
      expect(a.groups[group.id]!.contains(b.id), false);
      expect(b.groups[group.id]!.pendingSync, isEmpty);
    },
  );

  test(
    'legacy peers cannot join groups, and invalid names do not mutate membership',
    () async {
      final peer = await connect(a, b);
      peer.capabilities = [];
      await expectLater(a.createGroup('旧版测试', [peer]), throwsFormatException);
      expect(a.groups, isEmpty);
      await connect(a, b);
      final group = await a.createGroup('合法名称', [peer]);
      await expectLater(
        a.updateGroup(group, title: ' '),
        throwsFormatException,
      );
      expect(group.name, '合法名称');
      expect(group.revision, 1);
      await expectLater(a.createGroup('x' * 33, [peer]), throwsFormatException);
    },
  );

  test('leaving persists locally and owner removes membership', () async {
    final group = await create();
    await b.leaveGroup(b.groups[group.id]!);
    expect(a.groups[group.id]!.contains(b.id), false);
    expect(c.groups[group.id]!.contains(b.id), false);
    expect(b.groups[group.id]!.activeFor(b.id), false);
    await b.close();
    b = await start('member-b');
    expect(b.groups[group.id]!.left, true);
    final member = await connect(a, b);
    await a.updateGroup(group, members: [member, a.peers[c.id]!]);
    expect(b.groups[group.id]!.left, true);
    await b.rejoinGroup(b.groups[group.id]!);
    expect(b.groups[group.id]!.activeFor(b.id), true);
    await b.sendGroupMessage(b.groups[group.id]!, '我重新加入了');
    expect(c.messages.single.text, '我重新加入了');
  });

  test(
    'group files retain context and each receiver independently confirms',
    () async {
      final sent = <TransferCompletion>[];
      final received = <TransferCompletion>[];
      final sentSubscription = a.completedTransfers.listen(sent.add);
      final receivedSubscription = b.completedTransfers.listen(received.add);
      final group = await create();
      final file = File(p.join(root.path, 'source.txt'));
      await file.writeAsString('group-file-content');
      final send = a.sendGroupFiles(group, [
        LocalFile(
          path: file.path,
          name: 'source.txt',
          size: await file.length(),
        ),
      ]);
      await until(() => b.incoming.isNotEmpty && c.incoming.isNotEmpty);
      expect(b.incoming.single.groupName, '设计协作');
      b.markMessagesRead();
      expect(b.incoming, hasLength(1));
      b.decide(b.incoming.single, true);
      c.decide(c.incoming.single, false);
      await send;
      expect(b.transfers.single.status, TransferStatus.complete);
      expect(b.transfers.single.groupId, group.id);
      expect(
        await File(b.transfers.single.savedPath!).readAsString(),
        'group-file-content',
      );
      expect(c.transfers.single.status, TransferStatus.rejected);
      expect(
        a.transfers.where((f) => f.status == TransferStatus.complete).length,
        1,
      );
      expect(a.transfers.every((f) => f.groupId == group.id), true);
      await until(() => received.isNotEmpty);
      expect(sent, isEmpty);
      expect(received.single.outgoing, isFalse);
      await sentSubscription.cancel();
      await receivedSubscription.cancel();
    },
  );

  test(
    'all group recipients complete with one aggregated sender notice',
    () async {
      final group = await create();
      final sent = <TransferCompletion>[];
      final received = <TransferCompletion>[];
      final subscriptions = [
        a.completedTransfers.listen(sent.add),
        b.completedTransfers.listen(received.add),
        c.completedTransfers.listen(received.add),
      ];
      final file = File(p.join(root.path, 'group-batch.txt'));
      await file.writeAsString('group completion');
      final send = a.sendGroupFiles(
        group,
        await LocalFile.fromPaths([file.path]),
      );
      await until(() => b.incoming.isNotEmpty && c.incoming.isNotEmpty);
      b.decide(b.incoming.single, true);
      c.decide(c.incoming.single, true);
      await send;
      await until(() => sent.isNotEmpty && received.length == 2);
      expect(sent, hasLength(1));
      expect(sent.single.recipientCount, 2);
      expect(sent.single.fileCount, 1);
      expect(sent.single.peerName, group.name);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
}
