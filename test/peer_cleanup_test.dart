import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LanService service;

  Peer addPeer(String name, {bool online = false, bool manual = false}) {
    final peer = Peer(
      id: newId(),
      name: name,
      host: '127.0.0.1',
      port: 1,
      online: online,
      manual: manual,
    );
    service.peers[peer.id] = peer;
    return peer;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nearlink-cleanup-');
    service = LanService(
      dataDirectory: root,
      requestedPort: 0,
      discoveryEnabled: false,
    );
    await service.start();
    expect(service.error, isNull);
  });
  tearDown(() async {
    await service.close();
    await root.delete(recursive: true);
  });

  test(
    'cleanup backs up devices and preserves every referenced peer and file',
    () async {
      final unused = addPeer('temporary');
      final online = addPeer('online', online: true);
      final manual = addPeer('manual', manual: true);
      final remarked = addPeer('remarked');
      final chat = addPeer('chat');
      final transfer = addPeer('transfer');
      final member = addPeer('member');
      final pendingSync = addPeer('pending-sync');
      final incoming = addPeer('incoming');
      service.messages.add(
        ChatMessage(
          id: newId(),
          peerId: chat.id,
          text: 'keep',
          outgoing: false,
        ),
      );
      final received = await File(
        p.join(root.path, 'received.txt'),
      ).writeAsString('keep this file');
      service.transfers.add(
        TransferItem(
          id: newId(),
          peerId: transfer.id,
          peerName: transfer.name,
          name: 'received.txt',
          size: 14,
          outgoing: false,
          status: TransferStatus.complete,
        )..savedPath = received.path,
      );
      final group = LanGroup(
        id: newId(),
        name: 'keep group',
        ownerId: service.id,
        members: [GroupMember.fromPeer(member)],
        pendingSync: {pendingSync.id},
      );
      service.groups[group.id] = group;
      service.incoming.add(
        IncomingOffer(
          id: newId(),
          peer: incoming,
          files: [],
          remoteHost: incoming.host,
        ),
      );
      await service.setPeerRemark(remarked, '常用设备');
      final history = File(p.join(root.path, 'history.json'));
      final historyBefore = await history.readAsBytes();
      final originalId = service.id;
      expect(service.unusedOfflinePeers.map((peer) => peer.id), [unused.id]);
      expect(
        await service.clearUnusedOfflinePeers(service.peers.keys.toList()),
        1,
      );
      expect(service.peers.containsKey(unused.id), isFalse);
      for (final peer in [
        online,
        manual,
        remarked,
        chat,
        transfer,
        member,
        pendingSync,
        incoming,
      ]) {
        expect(service.peers.containsKey(peer.id), isTrue, reason: peer.name);
      }
      expect(await history.readAsBytes(), historyBefore);
      expect(await received.readAsString(), 'keep this file');
      expect(service.messages, hasLength(1));
      expect(service.transfers, hasLength(1));
      expect(service.groups, hasLength(1));
      final backups = await Directory(
        p.join(root.path, 'backups'),
      ).list().toList();
      expect(backups, hasLength(1));
      final backedUp =
          jsonDecode(await (backups.single as File).readAsString()) as Map;
      expect(
        (backedUp['peers'] as List).any((peer) => peer['id'] == unused.id),
        isTrue,
      );
      expect(backedUp['id'], originalId);
      final settings =
          jsonDecode(
                await File(p.join(root.path, 'settings.json')).readAsString(),
              )
              as Map;
      expect(
        (settings['peers'] as List).any((peer) => peer['id'] == unused.id),
        isFalse,
      );
      expect(settings['id'], originalId);
    },
  );

  test(
    'cleanup rechecks reconnecting peers and never adds new preview candidates',
    () async {
      final peer = addPeer('previewed');
      final preview = service.unusedOfflinePeers
          .map((peer) => peer.id)
          .toList();
      final unpreviewed = addPeer('not-previewed');
      final clearing = service.clearUnusedOfflinePeers(preview);
      peer.online = true;
      expect(await clearing, 0);
      expect(service.peers.keys, containsAll([peer.id, unpreviewed.id]));
      peer.online = false;
      service.messages.add(
        ChatMessage(
          id: newId(),
          peerId: peer.id,
          text: 'new record',
          outgoing: true,
        ),
      );
      expect(await service.clearUnusedOfflinePeers(preview), 0);
      expect(service.peers.keys, containsAll([peer.id, unpreviewed.id]));
    },
  );

  test('backup failure aborts cleanup without removing a device', () async {
    final peer = addPeer('keep if backup fails');
    await File(p.join(root.path, 'backups')).writeAsString('occupied');
    await expectLater(
      service.clearUnusedOfflinePeers([peer.id]),
      throwsA(isA<FileSystemException>()),
    );
    expect(service.peers[peer.id], same(peer));
    final settings =
        jsonDecode(
              await File(p.join(root.path, 'settings.json')).readAsString(),
            )
            as Map;
    expect(
      (settings['peers'] as List).any((entry) => entry['id'] == peer.id),
      isTrue,
    );
  });

  test(
    'storage failure aborts cleanup without losing the in-memory device',
    () async {
      final peer = addPeer('keep if storage fails');
      final blocker = await Directory(
        p.join(root.path, 'settings.json.tmp'),
      ).create();
      try {
        await expectLater(
          service.clearUnusedOfflinePeers([peer.id]),
          throwsA(isA<FileSystemException>()),
        );
        expect(service.peers[peer.id], same(peer));
      } finally {
        await blocker.delete();
      }
    },
  );

  test(
    'offline maintenance respects the running profile lock and backs up before applying',
    () async {
      final unused = addPeer('unused');
      final remarked = addPeer('real device');
      await service.setPeerRemark(remarked, '保留');
      final settingsFile = File(p.join(root.path, 'settings.json'));
      final before = await settingsFile.readAsBytes();
      final script = p.absolute('tool', 'cleanup_offline_devices.ps1');
      Future<ProcessResult> run({bool apply = false}) =>
          Process.run('powershell.exe', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            script,
            '-DataDirectory',
            root.path,
            if (apply) '-Apply',
          ]);
      final locked = await run(apply: true);
      expect(locked.exitCode, isNot(0));
      expect(await settingsFile.readAsBytes(), before);
      await service.close();
      final original = await settingsFile.readAsBytes();
      final preview = await run();
      expect(preview.exitCode, 0, reason: '${preview.stderr}');
      expect((jsonDecode(preview.stdout as String) as Map)['Eligible'], 1);
      expect(await settingsFile.readAsBytes(), original);
      final applied = await run(apply: true);
      expect(applied.exitCode, 0, reason: '${applied.stderr}');
      final report = jsonDecode(applied.stdout as String) as Map;
      expect(report['Removed'], 1);
      expect(await File(report['Backup'] as String).readAsBytes(), original);
      final config = jsonDecode(await settingsFile.readAsString()) as Map;
      expect((config['peers'] as List).map((peer) => peer['id']), [
        remarked.id,
      ]);
      expect((config['peers'] as List).single['remark'], '保留');
      expect(
        (config['peers'] as List).any((peer) => peer['id'] == unused.id),
        isFalse,
      );
    },
    skip: !Platform.isWindows,
  );
}
