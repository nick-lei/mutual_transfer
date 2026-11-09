import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';
import 'package:mutual_transfer/transfer_stream.dart';
import 'package:path/path.dart' as p;

void report(String event, Map<String, Object?> fields) {
  stdout.writeln(jsonEncode({'event': event, ...fields}));
}

Future<void> main(List<String> arguments) async {
  final selfTest = arguments.length == 1 && arguments.single == '--self-test';
  final seconds = arguments.length == 2 ? int.tryParse(arguments[1]) : 180;
  if ((!selfTest && (arguments.isEmpty || arguments.length > 2)) ||
      seconds == null ||
      seconds < 1 ||
      seconds > 1800) {
    stderr.writeln(
      'Usage: dart run tool/verify_android_peer.dart address [listen-seconds]\n'
      '       dart run tool/verify_android_peer.dart --self-test',
    );
    exitCode = 64;
    return;
  }

  final root = await Directory(
    p.join('build', 'android-verification'),
  ).create(recursive: true);
  final directory = await root.createTemp('peer-');
  final outgoing = await Directory(
    p.join(directory.absolute.path, 'outgoing'),
  ).create();
  final empty = await File(p.join(outgoing.path, 'empty.bin')).writeAsBytes([]);
  final text = await File(
    p.join(outgoing.path, 'message.txt'),
  ).writeAsString('NearLink Android interoperability verification.\n' * 32);
  final binary = File(p.join(outgoing.path, 'payload-8MiB.bin'));
  final sink = binary.openWrite();
  final chunk = List<int>.generate(64 * 1024, (index) => index % 251);
  for (var index = 0; index < 128; index++) {
    sink.add(chunk);
  }
  await sink.close();
  final paths = [empty.path, text.path, binary.path];
  final expectedHashes = <String, String>{};
  for (final path in paths) {
    expectedHashes[p.basename(path)] = await hashTransferFile(path);
  }
  final service = LanService(
    dataDirectory: Directory(p.join(directory.path, 'state')),
    initialSaveDirectory: p.join(directory.absolute.path, 'received'),
    requestedPort: 0,
    discoveryEnabled: false,
    initialName: 'Android verification peer',
  );
  LanService? loopback;
  StreamSubscription<void>? changes;
  StreamSubscription<void>? loopbackChanges;
  final seenMessages = <String>{};
  final returned = Completer<void>();
  String? pairedId;
  try {
    await service.start();
    if (!service.running) throw StateError(service.error ?? 'Peer not running');
    changes = service.changes.listen((_) {
      // Only the explicitly paired device may send files to this test receiver.
      for (final offer in service.incoming.toList()) {
        if (offer.decision.isCompleted) continue;
        final accept = offer.peer.id == pairedId;
        report('incoming_offer', {
          'accepted': accept,
          'peerId': offer.peer.id,
          'files': offer.files.length,
        });
        service.decide(offer, accept);
      }
      for (final message in service.messages.where((item) => !item.outgoing)) {
        if (seenMessages.add(message.id)) {
          report('incoming_message', {
            'peerId': message.peerId,
            'text': message.text,
          });
        }
      }
      if (!returned.isCompleted &&
          seenMessages.isNotEmpty &&
          expectedHashes.keys.every(
            (name) => service.transfers.any(
              (item) =>
                  !item.outgoing &&
                  item.name == name &&
                  item.status == TransferStatus.complete,
            ),
          )) {
        returned.complete();
      }
    });
    if (selfTest) {
      loopback = LanService(
        dataDirectory: Directory(p.join(directory.path, 'loopback-state')),
        initialSaveDirectory: p.join(directory.absolute.path, 'loopback-files'),
        requestedPort: 0,
        discoveryEnabled: false,
        initialName: 'Loopback verification receiver',
      );
      await loopback.start();
      final receiver = loopback;
      loopbackChanges = receiver.changes.listen((_) {
        for (final offer in receiver.incoming.toList()) {
          if (!offer.decision.isCompleted) {
            receiver.decide(offer, offer.peer.id == service.id);
          }
        }
      });
    }
    final address = selfTest ? '127.0.0.1:${loopback!.port}' : arguments.first;
    final peer = await service.connect(address);
    pairedId = peer.id;
    report('ready', {
      'port': service.port,
      'id': service.id,
      'peerId': peer.id,
      'peerAddress': address,
      'directory': directory.absolute.path,
      'expectedSha256': expectedHashes,
      'discoveryEnabled': false,
    });
    await service.sendMessage(peer, 'NearLink Android verification: hello.');
    await service.sendFiles(peer, await LocalFile.fromPaths(paths));
    if (selfTest) {
      final reversePeer = await loopback!.connect('127.0.0.1:${service.port}');
      await loopback.sendMessage(reversePeer, 'NearLink verification: reply.');
      await loopback.sendFiles(reversePeer, await LocalFile.fromPaths(paths));
    } else {
      report('waiting_for_return', {'seconds': seconds, 'port': service.port});
      final deadline = Timer(Duration(seconds: seconds), () {
        if (!returned.isCompleted) returned.complete();
      });
      try {
        await returned.future;
      } finally {
        deadline.cancel();
      }
      // Allow the final commit response to reach the device before shutdown.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final received = <Map<String, Object?>>[];
    for (final item in service.transfers.where((item) => !item.outgoing)) {
      final hash = item.savedPath == null
          ? null
          : await hashTransferFile(item.savedPath!);
      final expected = expectedHashes[item.name];
      received.add({
        'name': item.name,
        'status': item.status.name,
        'size': item.size,
        'sha256': hash,
        'matchesGeneratedFixture': expected == null ? null : hash == expected,
      });
    }
    final result = {
      'selfTest': selfTest,
      'outgoingMessagesDelivered': service.messages
          .where((item) => item.outgoing)
          .every((item) => item.delivery == 'delivered'),
      'incomingMessages': seenMessages.length,
      'outgoing': service.transfers
          .where((item) => item.outgoing)
          .map((item) => {'name': item.name, 'status': item.status.name})
          .toList(),
      'received': received,
    };
    await File(
      p.join(directory.path, 'result.json'),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    report('result', result);
    if (service.transfers.any(
          (item) => item.status != TransferStatus.complete,
        ) ||
        result['outgoingMessagesDelivered'] != true ||
        seenMessages.isEmpty ||
        expectedHashes.keys.any(
          (name) => !received.any(
            (item) =>
                item['name'] == name &&
                item['matchesGeneratedFixture'] == true &&
                item['status'] == TransferStatus.complete.name,
          ),
        )) {
      exitCode = 1;
    }
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await changes?.cancel();
    await loopbackChanges?.cancel();
    await service.close();
    await loopback?.close();
  }
}
