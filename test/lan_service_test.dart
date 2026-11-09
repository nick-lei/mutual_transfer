import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';
import 'package:mutual_transfer/transfer_stream.dart';
import 'package:path/path.dart' as p;

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  late Directory root;
  late LanService sender;
  late LanService receiver;
  late Peer target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nearlink-test-');
    sender = LanService(
      dataDirectory: Directory(p.join(root.path, 'sender')),
      requestedPort: 0,
      discoveryEnabled: false,
      initialName: 'Sender',
    );
    receiver = LanService(
      dataDirectory: Directory(p.join(root.path, 'receiver')),
      requestedPort: 0,
      discoveryEnabled: false,
      initialName: 'Receiver',
    );
    await sender.start();
    await receiver.start();
    expect(sender.error, isNull);
    expect(receiver.error, isNull);
    await receiver.updateSettings(directory: p.join(root.path, 'received'));
    target = await sender.connect('127.0.0.1:${receiver.port}');
  });

  tearDown(() async {
    await sender.close();
    await receiver.close();
    await root.delete(recursive: true);
  });

  Future<LocalFile> fixture(
    String name,
    List<int> data, {
    String? relative,
  }) async {
    final file = File(p.join(root.path, 'source', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
    return LocalFile(
      path: file.path,
      name: name,
      size: data.length,
      relativePath: relative,
    );
  }

  Future<({String id, String token, String offerId})> approvedOffer(
    HttpClient client, {
    int size = 3,
  }) async {
    final id = newId();
    final offerId = newId();
    final request = await client.postUrl(target.uri('/v1/offers'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'id': offerId,
        'peer': sender.info,
        'files': [
          {'id': id, 'path': 'stream.dat', 'size': size},
        ],
      }),
    );
    final response = request.close();
    await waitFor(() => receiver.incoming.isNotEmpty);
    receiver.decide(receiver.incoming.single, true);
    final data =
        jsonDecode(await utf8.decoder.bind(await response).join()) as Map;
    expect(data['capabilities'], contains(streamingIntegrity));
    return (id: id, token: data['token'] as String, offerId: offerId);
  }

  Future<({int status, Map data})> uploadStreaming(
    HttpClient client,
    String id,
    String token,
    List<int> bytes,
  ) async {
    final request = await client.putUrl(
      target.uri('/v1/files/$id').replace(queryParameters: {'token': token}),
    );
    request.headers.set('x-nearlink-integrity', streamingIntegrity);
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    return (
      status: response.statusCode,
      data: jsonDecode(await utf8.decoder.bind(response).join()) as Map,
    );
  }

  Future<int> commit(
    HttpClient client,
    String id,
    String token,
    String hash,
  ) async {
    final request = await client.postUrl(target.uri('/v1/files/$id/commit'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'token': token, 'sha256': hash}));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  test('manual connections keep a forwarded endpoint for messages', () async {
    final endpoint = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final forwardedMessages = <String>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await endpoint.close(force: true);
    });
    endpoint.listen((request) async {
      if (request.uri.path == '/v1/info') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(receiver.info));
        await request.response.close();
      } else if (request.uri.path == '/v1/chat') {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) {
          final frame = jsonDecode(raw as String) as Map;
          if (frame['type'] == 'message') {
            forwardedMessages.add(frame['text'] as String);
            socket.add(jsonEncode({'type': 'ack', 'id': frame['id']}));
          }
        });
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final forwarded = await sender.connect('127.0.0.1:${endpoint.port}');
    expect(forwarded.port, endpoint.port);
    expect(forwarded.id, receiver.id);
    final incoming = await WebSocket.connect(
      'ws://127.0.0.1:${sender.port}/v1/chat',
    );
    sockets.add(incoming);
    incoming.add(jsonEncode({'type': 'hello', 'peer': receiver.info}));
    incoming.add(
      jsonEncode({
        'type': 'message',
        'id': newId(),
        'text': 'Inbound handshake',
      }),
    );
    await waitFor(() => sender.messages.isNotEmpty);
    expect(forwarded.port, endpoint.port);
    await incoming.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sender.sendMessage(forwarded, 'Through the explicit endpoint');
    expect(sender.messages.last.delivery, 'delivered');
    expect(forwardedMessages, ['Through the explicit endpoint']);
    expect(receiver.messages, isEmpty);
  });

  test(
    'an inbound NAT address cannot replace a known return endpoint',
    () async {
      sender.peers.clear();
      final first = await WebSocket.connect(
        'ws://127.0.0.1:${sender.port}/v1/chat',
      );
      final second = await WebSocket.connect(
        'ws://127.0.0.1:${sender.port}/v1/chat',
      );
      addTearDown(() async {
        await first.close();
        await second.close();
      });
      first.add(jsonEncode({'type': 'hello', 'peer': receiver.info}));
      await waitFor(() => sender.peers.containsKey(receiver.id));
      final peer = sender.peers[receiver.id]!;
      expect(peer.manual, isFalse);
      second.add(
        jsonEncode({
          'type': 'hello',
          'peer': {...receiver.info, 'port': sender.port},
        }),
      );
      second.add(
        jsonEncode({'type': 'message', 'id': newId(), 'text': 'NAT hello'}),
      );
      await waitFor(() => sender.messages.isNotEmpty);
      expect(peer.port, receiver.port);
      expect(peer.online, isTrue);
    },
  );

  test('a new peer with a local return endpoint is not shown online', () async {
    sender.peers.clear();
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${sender.port}/v1/chat',
    );
    addTearDown(() => socket.close());
    socket.add(
      jsonEncode({
        'type': 'hello',
        'peer': {...receiver.info, 'port': sender.port},
      }),
    );
    await waitFor(() => sender.peers.containsKey(receiver.id));
    expect(sender.peers[receiver.id]!.online, isFalse);
  });

  test(
    'file sending detects a return endpoint pointing to this device',
    () async {
      final wrongEndpoint = Peer(
        id: receiver.id,
        name: 'Android phone',
        host: '127.0.0.1',
        port: sender.port,
        platform: 'android',
      );
      await sender.sendFiles(wrongEndpoint, [
        await fixture('probe.txt', [1, 2]),
      ]);
      expect(sender.transfers.single.status, TransferStatus.failed);
      expect(sender.transfers.single.error, contains('连接地址指向本机'));
      expect(sender.incoming, isEmpty);
      expect(receiver.incoming, isEmpty);
    },
  );

  test('file sending does not offer files to a different device ID', () async {
    final wrongIdentity = Peer(
      id: newId(),
      name: 'Selected phone',
      host: target.host,
      port: target.port,
    );
    await sender.sendFiles(wrongIdentity, [
      await fixture('probe.txt', [1, 2]),
    ]);
    expect(sender.transfers.single.status, TransferStatus.failed);
    expect(sender.transfers.single.error, contains('与所选设备不一致'));
    expect(receiver.incoming, isEmpty);
    expect(wrongIdentity.online, isFalse);
  });

  test('an active file batch keeps its verified endpoint', () async {
    final file = await fixture('bound-endpoint.txt', [1, 2, 3, 4]);
    final send = sender.sendFiles(target, [file]);
    await waitFor(() => receiver.incoming.isNotEmpty);
    target.port = sender.port;
    receiver.decide(receiver.incoming.single, true);
    await send;
    expect(sender.transfers.single.status, TransferStatus.complete);
    expect(receiver.transfers.single.status, TransferStatus.complete);
    expect(
      await File(p.join(receiver.saveDirectory, file.name)).readAsBytes(),
      [1, 2, 3, 4],
    );
  });

  test(
    'Android default naming preserves a user name across restarts',
    () async {
      final profile = Directory(p.join(root.path, 'default-name'));
      var device = LanService(
        dataDirectory: profile,
        requestedPort: 0,
        discoveryEnabled: false,
        defaultName: 'Android model',
      );
      await device.start();
      expect(device.name, 'Android model');
      await device.updateSettings(deviceName: 'My phone');
      await device.close();
      device = LanService(
        dataDirectory: profile,
        requestedPort: 0,
        discoveryEnabled: false,
        defaultName: 'Android model',
      );
      try {
        await device.start();
        expect(device.name, 'My phone');
      } finally {
        await device.close();
      }
    },
  );

  for (final legacySide in ['sender', 'receiver']) {
    test('streaming negotiation supports legacy $legacySide', () async {
      if (legacySide == 'sender') {
        await sender.close();
        sender = LanService(
          dataDirectory: sender.dataDirectory,
          requestedPort: 0,
          discoveryEnabled: false,
          streamingIntegrityEnabled: false,
        );
        await sender.start();
      } else {
        await receiver.close();
        receiver = LanService(
          dataDirectory: receiver.dataDirectory,
          requestedPort: 0,
          discoveryEnabled: false,
          streamingIntegrityEnabled: false,
        );
        await receiver.start();
      }
      target = await sender.connect('127.0.0.1:${receiver.port}');
      final bytes = List.generate(1024 * 1024 + 17, (i) => i % 251);
      final send = sender.sendFiles(target, [
        await fixture('legacy.bin', bytes),
      ]);
      await waitFor(() => receiver.incoming.isNotEmpty);
      receiver.decide(receiver.incoming.single, true);
      await send;
      expect(
        sender.transfers.single.status,
        TransferStatus.complete,
        reason: sender.transfers.single.error,
      );
      expect(receiver.transfers.single.status, TransferStatus.complete);
      expect(
        await File(receiver.transfers.single.savedPath!).readAsBytes(),
        bytes,
      );
    });
  }

  test(
    'streaming file is published only after authenticated matching commit',
    () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final offer = await approvedOffer(client);
      final upload = await uploadStreaming(client, offer.id, offer.token, [
        1,
        2,
        3,
      ]);
      expect(upload.status, 200);
      expect(upload.data['commitRequired'], true);
      expect(receiver.transfers.single.status, TransferStatus.hashing);
      expect(
        await File(p.join(receiver.saveDirectory, 'stream.dat')).exists(),
        isFalse,
      );
      expect(
        (await Directory(receiver.saveDirectory).list().toList()).single.path,
        endsWith('.part'),
      );
      expect(
        await commit(
          client,
          offer.id,
          'wrong-token',
          upload.data['sha256'] as String,
        ),
        403,
      );
      expect(receiver.transfers.single.status, TransferStatus.hashing);
      expect(
        (await uploadStreaming(client, offer.id, offer.token, [
          1,
          2,
          3,
        ])).status,
        409,
      );
      expect(
        await commit(
          client,
          offer.id,
          offer.token,
          upload.data['sha256'] as String,
        ),
        200,
      );
      expect(receiver.transfers.single.status, TransferStatus.complete);
      expect(await File(receiver.transfers.single.savedPath!).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(
        await commit(
          client,
          offer.id,
          offer.token,
          upload.data['sha256'] as String,
        ),
        409,
      );
    },
  );

  test('wrong streaming commit discards temporary data', () async {
    final completions = <TransferCompletion>[];
    final subscription = receiver.completedTransfers.listen(completions.add);
    addTearDown(subscription.cancel);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final offer = await approvedOffer(client);
    await uploadStreaming(client, offer.id, offer.token, [1, 2, 3]);
    expect(await commit(client, offer.id, offer.token, '0' * 64), 422);
    expect(receiver.transfers.single.status, TransferStatus.failed);
    expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(completions, isEmpty);
  });

  test('a different source address cannot commit a pending transfer', () async {
    final client = HttpClient();
    final foreign = HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) => Socket.startConnect(
        uri.host,
        uri.port,
        sourceAddress: InternetAddress('127.0.0.2'),
      );
    addTearDown(() {
      client.close(force: true);
      foreign.close(force: true);
    });
    final offer = await approvedOffer(client);
    final upload = await uploadStreaming(client, offer.id, offer.token, [
      1,
      2,
      3,
    ]);
    expect(
      await commit(
        foreign,
        offer.id,
        offer.token,
        upload.data['sha256'] as String,
      ),
      403,
    );
    expect(receiver.transfers.single.status, TransferStatus.hashing);
    expect(
      await commit(
        client,
        offer.id,
        offer.token,
        upload.data['sha256'] as String,
      ),
      200,
    );
  });

  test('changed source size fails before sending file content', () async {
    final file = await fixture('changed.dat', [1, 2, 3]);
    await File(file.path).writeAsBytes([1, 2, 3, 4]);
    final send = sender.sendFiles(target, [file]);
    await waitFor(() => receiver.incoming.isNotEmpty);
    receiver.decide(receiver.incoming.single, true);
    await send;
    expect(sender.transfers.single.status, TransferStatus.failed);
    expect(sender.transfers.single.error, contains('文件大小已改变'));
    expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
  });

  test('unconfirmed streaming data expires and is removed', () async {
    await receiver.close();
    receiver = LanService(
      dataDirectory: receiver.dataDirectory,
      requestedPort: 0,
      discoveryEnabled: false,
      commitTimeout: const Duration(milliseconds: 150),
    );
    await receiver.start();
    target = await sender.connect('127.0.0.1:${receiver.port}');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final offer = await approvedOffer(client);
    await uploadStreaming(client, offer.id, offer.token, [1, 2, 3]);
    await waitFor(
      () => receiver.transfers.single.status == TransferStatus.failed,
    );
    expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
  });

  test('cancellation and shutdown remove uncommitted streaming data', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final first = await approvedOffer(client);
    await uploadStreaming(client, first.id, first.token, [1, 2, 3]);
    receiver.cancel(receiver.transfers.first);
    await waitFor(() => receiver.transfers.first.error == '接收已取消');
    expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
    final second = await approvedOffer(client);
    await uploadStreaming(client, second.id, second.token, [1, 2, 3]);
    await receiver.close();
    expect(receiver.transfers.first.status, TransferStatus.cancelled);
    expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
  });

  test(
    'cancelling an active upload aborts its stream and removes partial data',
    () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final offer = await approvedOffer(client, size: 8 * 1024 * 1024);
      final request = await client.putUrl(
        target
            .uri('/v1/files/${offer.id}')
            .replace(queryParameters: {'token': offer.token}),
      );
      request.done.ignore();
      request.contentLength = 8 * 1024 * 1024;
      request.headers.set('x-nearlink-integrity', streamingIntegrity);
      final chunks = StreamController<List<int>>();
      final writing = request
          .addStream(chunks.stream)
          .catchError((Object _) {});
      chunks.add(List.filled(1024 * 1024, 42));
      await waitFor(() => receiver.transfers.single.bytes > 0);
      receiver.cancel(receiver.transfers.single);
      chunks.add(List.filled(1024 * 1024, 42));
      await chunks.close();
      await writing;
      request.abort();
      await waitFor(() => receiver.transfers.single.error != null);
      expect(receiver.transfers.single.status, TransferStatus.cancelled);
      expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
    },
  );

  test(
    'streams binary, empty and nested Unicode files with hashes and no overwrite',
    () async {
      final binary = List<int>.generate(
        2 * 1024 * 1024 + 17,
        (i) => (i * 31) % 256,
      );
      final files = [
        await fixture('archive.bin', binary),
        await fixture('empty.txt', []),
        await fixture(
          '项目.txt',
          utf8.encode('局域网文件传输'),
          relative: '项目/文档/项目.txt',
        ),
      ];
      final sentCompletions = <TransferCompletion>[];
      final receivedCompletions = <TransferCompletion>[];
      final sentSubscription = sender.completedTransfers.listen(
        sentCompletions.add,
      );
      final receivedSubscription = receiver.completedTransfers.listen(
        receivedCompletions.add,
      );
      final send = sender.sendFiles(target, files);
      await waitFor(() => receiver.incoming.isNotEmpty);
      expect(
        receiver.transfers.every((f) => f.status == TransferStatus.waiting),
        isTrue,
      );
      expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
      receiver.decide(receiver.incoming.single, true);
      await send;
      await waitFor(
        () => sentCompletions.isNotEmpty && receivedCompletions.isNotEmpty,
      );
      expect(sentCompletions.single.fileCount, 3);
      expect(receivedCompletions.single.fileCount, 3);
      expect(sentCompletions.single.outgoing, isTrue);
      expect(receivedCompletions.single.outgoing, isFalse);
      final batchId = sender.transfers.first.batchId;
      expect(batchId, isNotNull);
      expect(sender.transfers.map((f) => f.batchId).toSet(), {batchId});
      expect(receiver.transfers.map((f) => f.batchId).toSet(), {batchId});
      expect(
        TransferItem.fromJson(sender.transfers.first.toJson()).batchId,
        batchId,
      );
      final legacy = sender.transfers.first.toJson()..remove('batchId');
      expect(TransferItem.fromJson(legacy).batchId, isNull);
      expect(
        sentCompletions.single.totalBytes,
        files.fold<int>(0, (sum, file) => sum + file.size),
      );
      expect(
        sender.transfers.every((f) => f.status == TransferStatus.complete),
        isTrue,
      );
      expect(
        receiver.transfers.every((f) => f.status == TransferStatus.complete),
        isTrue,
      );
      expect(
        await File(p.join(receiver.saveDirectory, 'archive.bin')).readAsBytes(),
        binary,
      );
      expect(
        await File(p.join(receiver.saveDirectory, 'empty.txt')).length(),
        0,
      );
      expect(
        await File(
          p.join(receiver.saveDirectory, '项目', '文档', '项目.txt'),
        ).readAsString(),
        '局域网文件传输',
      );
      final again = sender.sendFiles(target, [files.first]);
      await waitFor(() => receiver.incoming.isNotEmpty);
      receiver.decide(receiver.incoming.single, true);
      await again;
      await waitFor(
        () => sentCompletions.length == 2 && receivedCompletions.length == 2,
      );
      expect(sentCompletions.last.id, isNot(sentCompletions.first.id));
      expect(sender.transfers.first.batchId, isNot(batchId));
      expect(sentCompletions.last.fileCount, 1);
      final duplicate = File(p.join(receiver.saveDirectory, 'archive (1).bin'));
      expect(await duplicate.exists(), isTrue);
      expect(
        (await sha256.bind(duplicate.openRead()).first).toString(),
        sha256.convert(binary).toString(),
      );
      expect(
        await Directory(
          receiver.saveDirectory,
        ).list(recursive: true).where((e) => e.path.endsWith('.part')).isEmpty,
        isTrue,
      );
      await sentSubscription.cancel();
      await receivedSubscription.cancel();
    },
  );

  test('rejected offer never writes file content', () async {
    final completions = <TransferCompletion>[];
    final sentSubscription = sender.completedTransfers.listen(completions.add);
    final receivedSubscription = receiver.completedTransfers.listen(
      completions.add,
    );
    final send = sender.sendFiles(target, [
      await fixture('declined.txt', [1, 2, 3]),
    ]);
    await waitFor(() => receiver.incoming.isNotEmpty);
    receiver.decide(receiver.incoming.single, false);
    await send;
    expect(sender.transfers.single.status, TransferStatus.rejected);
    expect(receiver.transfers.single.status, TransferStatus.rejected);
    expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(completions, isEmpty);
    await sentSubscription.cancel();
    await receivedSubscription.cancel();
  });

  test('cancelling a pending batch cancels both ends', () async {
    final completions = <TransferCompletion>[];
    final sentSubscription = sender.completedTransfers.listen(completions.add);
    final receivedSubscription = receiver.completedTransfers.listen(
      completions.add,
    );
    addTearDown(sentSubscription.cancel);
    addTearDown(receivedSubscription.cancel);
    final send = sender.sendFiles(target, [
      await fixture('cancel.txt', [1]),
    ]);
    await waitFor(() => receiver.incoming.isNotEmpty);
    sender.cancel(sender.transfers.single);
    await send;
    await waitFor(() => receiver.incoming.isEmpty);
    expect(sender.transfers.single.status, TransferStatus.cancelled);
    expect(receiver.transfers.single.status, TransferStatus.cancelled);
    expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(completions, isEmpty);
  });

  test(
    'partial batch stays silent and a successful retry completes once',
    () async {
      final sent = <TransferCompletion>[];
      final received = <TransferCompletion>[];
      final sentSubscription = sender.completedTransfers.listen(sent.add);
      final receivedSubscription = receiver.completedTransfers.listen(
        received.add,
      );
      addTearDown(sentSubscription.cancel);
      addTearDown(receivedSubscription.cancel);
      final good = await fixture('good.txt', [1, 2, 3]);
      final changed = await fixture('changed.txt', [4]);
      await File(changed.path).writeAsBytes([4, 5]);
      final first = sender.sendFiles(target, [good, changed]);
      await waitFor(() => receiver.incoming.isNotEmpty);
      receiver.decide(receiver.incoming.single, true);
      await first;
      expect(
        sender.transfers.where(
          (item) => item.status == TransferStatus.complete,
        ),
        hasLength(1),
      );
      expect(
        sender.transfers.where((item) => item.status == TransferStatus.failed),
        hasLength(1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
      expect(received, isEmpty);

      final retryFile = await fixture('changed.txt', [4, 5]);
      final retry = sender.sendFiles(target, [retryFile]);
      await waitFor(() => receiver.incoming.isNotEmpty);
      receiver.decide(receiver.incoming.single, true);
      await retry;
      await waitFor(() => sent.isNotEmpty && received.isNotEmpty);
      expect(sent, hasLength(1));
      expect(received, hasLength(1));
      expect(sent.single.fileCount, 1);
      expect(received.single.fileCount, 1);
    },
  );

  test(
    'messages travel in both directions with delivery acknowledgement and deduplication',
    () async {
      await sender.sendMessage(target, 'hello 你好\nsecond line');
      expect(sender.messages.single.delivery, 'delivered');
      expect(receiver.messages.single.text, 'hello 你好\nsecond line');
      final replyTarget = receiver.peers[sender.id]!;
      await receiver.sendMessage(replyTarget, '收到');
      expect(receiver.messages.last.delivery, 'delivered');
      expect(sender.messages.last.text, '收到');
      await sender.sendMessage(
        target,
        sender.messages.first.text,
        retry: sender.messages.first,
      );
      expect(receiver.messages.where((m) => !m.outgoing).length, 1);
    },
  );

  test(
    'history, device identity and offline conversations survive restart',
    () async {
      await sender.sendMessage(target, 'persistent message');
      final originalId = sender.id;
      await sender.close();
      final restored = LanService(
        dataDirectory: sender.dataDirectory,
        requestedPort: 0,
        discoveryEnabled: false,
      );
      try {
        await restored.start();
        expect(restored.id, originalId);
        expect(restored.messages.single.text, 'persistent message');
        expect(restored.peers[target.id]?.name, 'Receiver');
      } finally {
        await restored.close();
      }
    },
  );

  test(
    'last online time survives restart and updates on reconnection',
    () async {
      final recorded = DateTime.utc(2026, 1, 2, 9, 8, 7);
      target
        ..manual = false
        ..lastSeen = recorded;
      await sender.close();
      final restored = LanService(
        dataDirectory: sender.dataDirectory,
        requestedPort: 0,
        discoveryEnabled: false,
      );
      try {
        await restored.start();
        final peer = restored.peers[target.id]!;
        expect(peer.online, isFalse);
        expect(peer.lastSeen, recorded);
        final before = DateTime.now();
        await restored.connect('127.0.0.1:${receiver.port}');
        expect(peer.online, isTrue);
        expect(peer.lastSeen!.isBefore(before), isFalse);
      } finally {
        await restored.close();
      }
      final saved =
          jsonDecode(
                await File(
                  p.join(sender.dataDirectory.path, 'settings.json'),
                ).readAsString(),
              )
              as Map;
      expect(
        DateTime.parse(
          (saved['peers'] as List).single['lastSeen'] as String,
        ).isUtc,
        isTrue,
      );
    },
  );

  for (final value in [null, 'not-a-timestamp']) {
    test(
      'unknown last online time is preserved for legacy value $value',
      () async {
        target.manual = false;
        await sender.close();
        final file = File(p.join(sender.dataDirectory.path, 'settings.json'));
        final saved = jsonDecode(await file.readAsString()) as Map;
        final peer = (saved['peers'] as List).single as Map;
        if (value == null) {
          peer.remove('lastSeen');
        } else {
          peer['lastSeen'] = value;
        }
        await file.writeAsString(jsonEncode(saved));
        final restored = LanService(
          dataDirectory: sender.dataDirectory,
          requestedPort: 0,
          discoveryEnabled: false,
        );
        try {
          await restored.start();
          expect(restored.error, isNull);
          expect(restored.peers[target.id]!.online, isFalse);
          expect(restored.peers[target.id]!.lastSeen, isNull);
        } finally {
          await restored.close();
        }
        final updated = jsonDecode(await file.readAsString()) as Map;
        expect((updated['peers'] as List).single['lastSeen'], isNull);
      },
    );
  }

  test(
    'going offline saves the last observation rather than the timeout',
    () async {
      final recorded = DateTime.now().subtract(const Duration(seconds: 20));
      target
        ..manual = false
        ..lastSeen = recorded;
      await waitFor(() => !target.online);
      expect(target.lastSeen, recorded);
      final file = File(p.join(sender.dataDirectory.path, 'settings.json'));
      await waitFor(() {
        final saved = jsonDecode(file.readAsStringSync()) as Map;
        return (saved['peers'] as List).single['lastSeen'] ==
            recorded.toUtc().toIso8601String();
      });
    },
  );

  test(
    'only a focused visible conversation consumes unread messages',
    () async {
      await sender.sendMessage(target, 'first');
      await sender.sendMessage(target, 'second');
      expect(receiver.unreadCount, 2);
      expect(receiver.unreadConversations.single.count, 2);
      receiver.setMessageView(sender.id, focused: false);
      await sender.sendMessage(target, 'background');
      expect(receiver.unreadCount, 3);
      receiver.setMessageView('another-peer', focused: true);
      expect(receiver.unreadCount, 3);
      receiver.setMessageView(sender.id, focused: true);
      expect(receiver.unreadCount, 0);
      await sender.sendMessage(target, 'currently visible');
      expect(receiver.unreadCount, 0);
      receiver.setMessageView(sender.id, focused: false);
      await sender.sendMessage(target, 'tray message');
      await sender.sendMessage(
        target,
        'tray message',
        retry: sender.messages.last,
      );
      expect(receiver.unreadCount, 1);
      expect(
        receiver.messages.where((m) => m.text == 'tray message'),
        hasLength(1),
      );
    },
  );

  test('unread and read states both survive restarting the receiver', () async {
    await sender.sendMessage(target, 'keep unread');
    final profile = receiver.dataDirectory;
    await receiver.close();
    receiver = LanService(
      dataDirectory: profile,
      requestedPort: 0,
      discoveryEnabled: false,
    );
    await receiver.start();
    expect(receiver.unreadCount, 1);
    receiver.markMessagesRead(peerId: sender.id);
    await receiver.close();
    receiver = LanService(
      dataDirectory: profile,
      requestedPort: 0,
      discoveryEnabled: false,
    );
    await receiver.start();
    expect(receiver.messages.single.read, isTrue);
    expect(receiver.unreadCount, 0);
  });

  test('legacy message records migrate without notifying old history', () {
    final legacy = ChatMessage(
      id: 'old',
      peerId: 'peer',
      text: 'history',
      outgoing: false,
      delivery: 'delivered',
    ).toJson()..remove('read');
    expect(ChatMessage.fromJson(legacy).read, isTrue);
  });

  test(
    'UDP discovery starts on the native platform without fallback',
    () async {
      final discovery = LanService(
        dataDirectory: Directory(p.join(root.path, 'discovery')),
        requestedPort: 0,
      );
      final companion = LanService(
        dataDirectory: Directory(p.join(root.path, 'discovery-companion')),
        requestedPort: 0,
      );
      try {
        await discovery.start();
        await companion.start();
        await waitFor(() => discovery.peers.containsKey(companion.id));
        await waitFor(() => companion.peers.containsKey(discovery.id));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(discovery.running, isTrue);
        expect(discovery.discoveryError, isNull);
        final originalPort = discovery.port;
        await discovery.retryDiscovery();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(discovery.discoveryError, isNull);
        expect(discovery.port, originalPort);
      } finally {
        await discovery.close();
        await companion.close();
      }
    },
  );

  test('self connection and non-IP endpoints are rejected', () async {
    await expectLater(
      sender.connect('127.0.0.1:${sender.port}'),
      throwsFormatException,
    );
    await expectLater(
      sender.connect('https://example.com'),
      throwsFormatException,
    );
    await expectLater(
      sender.connect('127.0.0.1:45878/path'),
      throwsFormatException,
    );
  });

  test('second instance cannot overwrite an active data directory', () async {
    final second = LanService(
      dataDirectory: sender.dataDirectory,
      requestedPort: 0,
      discoveryEnabled: false,
    );
    try {
      await second.start();
      expect(second.running, isFalse);
      expect(second.error, isNotNull);
    } finally {
      await second.close();
    }
    final settings =
        jsonDecode(
              await File(
                p.join(sender.dataDirectory.path, 'settings.json'),
              ).readAsString(),
            )
            as Map;
    expect(settings['id'], sender.id);
  });

  test('unapproved uploads and path traversal are rejected', () async {
    final client = HttpClient();
    try {
      final upload = await client.putUrl(target.uri('/v1/files/${newId()}'));
      upload.contentLength = 0;
      final uploadResponse = await upload.close();
      expect(uploadResponse.statusCode, 403);
      await uploadResponse.drain<void>();
      final offer = await client.postUrl(target.uri('/v1/offers'));
      offer.headers.contentType = ContentType.json;
      offer.write(
        jsonEncode({
          'id': newId(),
          'peer': sender.info,
          'files': [
            {'id': newId(), 'path': '../escape.txt', 'size': 1},
          ],
        }),
      );
      final response = await offer.close();
      expect(response.statusCode, 400);
      await response.drain<void>();
      expect(receiver.incoming, isEmpty);
      expect(await File(p.join(root.path, 'escape.txt')).exists(), isFalse);
    } finally {
      client.close(force: true);
    }
  });

  test('bad digest removes partial files and records failure', () async {
    final client = HttpClient();
    try {
      final fileId = newId();
      final request = await client.postUrl(target.uri('/v1/offers'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'id': newId(),
          'peer': sender.info,
          'files': [
            {'id': fileId, 'path': 'broken.dat', 'size': 3},
          ],
        }),
      );
      final offerResponse = request.close();
      await waitFor(() => receiver.incoming.isNotEmpty);
      receiver.decide(receiver.incoming.single, true);
      final token =
          (jsonDecode(await utf8.decoder.bind(await offerResponse).join())
                  as Map)['token']
              as String;
      final upload = await client.putUrl(
        target
            .uri('/v1/files/$fileId')
            .replace(queryParameters: {'token': token}),
      );
      upload.contentLength = 3;
      upload.headers.set('x-nearlink-sha256', '0' * 64);
      upload.add([1, 2, 3]);
      final response = await upload.close();
      expect(response.statusCode, 422);
      await response.drain<void>();
      expect(receiver.transfers.single.status, TransferStatus.failed);
      expect(await Directory(receiver.saveDirectory).list().isEmpty, isTrue);
    } finally {
      client.close(force: true);
    }
  });

  test(
    'relative path validation blocks Windows device names and alternate streams',
    () {
      for (final path in [
        '../x',
        '/x',
        r'C:\x',
        'a/../../x',
        'a//x',
        'CON.txt',
        'x:stream',
        'a.',
        'a ',
        'NUL',
        'a\\b',
      ]) {
        expect(
          () => validateRelativePath(path),
          throwsFormatException,
          reason: path,
        );
      }
      expect(
        validateRelativePath('项目/files/a.txt'),
        p.join('项目', 'files', 'a.txt'),
      );
    },
  );
}
