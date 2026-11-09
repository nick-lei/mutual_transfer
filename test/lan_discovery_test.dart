import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/lan_discovery.dart';
import 'package:mutual_transfer/logging/app_log.dart';

class TestInterface extends Fake implements NetworkInterface {
  TestInterface(this.name, String ip) : addresses = [InternetAddress(ip)];
  @override
  final String name;
  @override
  final List<InternetAddress> addresses;
}

class TestSocket extends Fake implements RawDatagramSocket {
  final events = StreamController<RawSocketEvent>();
  final packets = Queue<Datagram>();
  final sent = <InternetAddress>[];
  final options = <RawSocketOption>[];
  bool closed = false;
  Object? sendFailure;
  @override
  bool writeEventsEnabled = true;
  @override
  bool readEventsEnabled = true;
  @override
  bool broadcastEnabled = false;
  @override
  int multicastHops = 1;
  @override
  void setRawOption(RawSocketOption option) => options.add(option);
  @override
  void joinMulticast(InternetAddress group, [NetworkInterface? interface]) {}
  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    if (sendFailure != null) throw sendFailure!;
    sent.add(address);
    return buffer.length;
  }

  @override
  Datagram? receive() => packets.isEmpty ? null : packets.removeFirst();
  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(events.close());
  }
}

const unreachable = SocketException(
  'The network location cannot be reached',
  osError: OSError('The network location cannot be reached', 1232),
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory directory;
  late AppLog log;
  late LanDiscovery discovery;
  late List<TestSocket> sockets;
  late List<NetworkInterface> interfaces;
  late List<Map<String, dynamic>> peers;
  late List<String> addresses;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nearlink-discovery-');
    log = AppLog(directory);
    await log.initialize();
    sockets = [];
    interfaces = [TestInterface('WLAN', '192.168.1.12')];
    peers = [];
    addresses = [];
    discovery = LanDiscovery(
      log: log,
      info: () => {'app': 'nearlink', 'version': 1, 'id': 'this-device'},
      onPeer: (data, host) => peers.add({...data, 'host': host}),
      onChanged: () {},
      onAddresses: (value) => addresses = value,
      listInterfaces: () async => interfaces,
      bindSocket: (address, port) async {
        final socket = TestSocket();
        sockets.add(socket);
        return socket;
      },
      retryDelay: const Duration(milliseconds: 30),
    );
  });

  tearDown(() async {
    await discovery.close();
    await log.close();
    await directory.delete(recursive: true);
  });

  test('a Windows 1232 broadcast error leaves multicast available', () async {
    await discovery.retry();
    expect(sockets.length, 3);
    final multicast = sockets[1];
    final broadcast = sockets[2];
    expect(multicast.options.single.value, [192, 168, 1, 12]);
    expect(multicast.sent.single.address, '239.255.77.77');
    broadcast.events.addError(unreachable);
    await settle();
    expect(broadcast.closed, isTrue);
    expect(discovery.error, isNull);
    discovery.refresh();
    expect(multicast.sent.length, 2);
    expect(addresses, ['192.168.1.12']);
    await log.flush();
    final contents = await File(log.currentPath).readAsString();
    expect(contents, contains('"errorCode":1232'));
    expect(contents, contains('"interface":"WLAN"'));
    expect(contents, contains('"target":"255.255.255.255"'));
  });

  test('failure of one adapter does not disable another adapter', () async {
    interfaces.add(TestInterface('VPN', '10.0.0.2'));
    await discovery.retry();
    expect(sockets.length, 5);
    sockets[3].events.addError(unreachable);
    sockets[4].events.addError(unreachable);
    await settle();
    expect(discovery.error, isNull);
    expect(sockets[1].closed, isFalse);
    expect(sockets[2].closed, isFalse);
  });

  test(
    'all send routes failing report the reason and manual retry recovers',
    () async {
      await discovery.retry();
      final original = List.of(sockets);
      sockets[1].events.addError(unreachable);
      sockets[2].events.addError(unreachable);
      await settle();
      expect(discovery.error, contains('发现网络不可达'));
      await discovery.retry();
      expect(discovery.error, isNull);
      expect(original.every((socket) => socket.closed), isTrue);
      expect(sockets.length, 6);
      await log.flush();
      expect(
        await File(log.currentPath).readAsString(),
        contains('"recovered"'),
      );
    },
  );

  test(
    'receive failure automatically rebinds without restarting the app',
    () async {
      await discovery.retry();
      sockets.first.events.addError(unreachable);
      await settle();
      expect(discovery.error, isNotNull);
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (discovery.error != null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(discovery.error, isNull);
      expect(sockets.length, 6);
      expect(sockets.take(3).every((socket) => socket.closed), isTrue);
    },
  );

  test(
    'retry re-enumerates interfaces after connectivity is restored',
    () async {
      interfaces.clear();
      await discovery.retry();
      expect(discovery.error, isNotNull);
      expect(sockets, isEmpty);
      interfaces.add(TestInterface('Ethernet', '192.168.2.8'));
      await discovery.retry();
      expect(discovery.error, isNull);
      expect(addresses, ['192.168.2.8']);
    },
  );

  test(
    'synchronous send failures enter recovery without escaping refresh',
    () async {
      await discovery.retry();
      sockets[1].sendFailure = unreachable;
      sockets[2].sendFailure = unreachable;
      discovery.refresh();
      expect(discovery.error, contains('发现网络不可达'));
      expect(sockets.skip(1).every((socket) => socket.closed), isTrue);
    },
  );

  test(
    'closing during interface enumeration does not open sockets later',
    () async {
      final gate = Completer<List<NetworkInterface>>();
      await discovery.close();
      discovery = LanDiscovery(
        log: log,
        info: () => {},
        onPeer: (_, _) {},
        onChanged: () {},
        onAddresses: (_) {},
        listInterfaces: () => gate.future,
        bindSocket: (_, _) async {
          final socket = TestSocket();
          sockets.add(socket);
          return socket;
        },
      );
      final starting = discovery.retry();
      final closing = discovery.close();
      gate.complete(interfaces);
      await Future.wait([starting, closing]);
      expect(sockets, isEmpty);
      expect(discovery.retrying, isFalse);
    },
  );

  test(
    'concurrent retries share one operation and close releases sockets',
    () async {
      final first = discovery.retry();
      final second = discovery.retry();
      expect(identical(first, second), isTrue);
      await first;
      expect(sockets.length, 3);
      await discovery.close();
      expect(sockets.every((socket) => socket.closed), isTrue);
      await discovery.retry();
      expect(sockets.length, 3);
    },
  );

  test(
    'malformed and own announcements are ignored; new peers get a reply',
    () async {
      await discovery.retry();
      final receiver = sockets.first;
      for (final data in [
        'invalid json',
        jsonEncode({'app': 'nearlink', 'version': 1, 'id': 'this-device'}),
        jsonEncode({'app': 'other', 'version': 1, 'id': 'other-device'}),
        jsonEncode({'app': 'nearlink', 'version': 1, 'id': 'other-device'}),
      ]) {
        receiver.packets.add(
          Datagram(utf8.encode(data), InternetAddress('192.168.1.20'), 45877),
        );
      }
      receiver.events.add(RawSocketEvent.read);
      await settle();
      expect(peers.single['id'], 'other-device');
      expect(peers.single['host'], '192.168.1.20');
      expect(sockets[1].sent.length, 2);
      expect(discovery.error, isNull);
    },
  );
}
