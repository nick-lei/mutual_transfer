import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'logging/app_log.dart';

typedef DiscoverySocketFactory =
    Future<RawDatagramSocket> Function(InternetAddress address, int port);

class _DiscoverySender {
  _DiscoverySender(this.socket, this.address, this.target, this.interfaceName);
  final RawDatagramSocket socket;
  final InternetAddress address, target;
  final String interfaceName;
  bool failed = false;
}

class LanDiscovery {
  LanDiscovery({
    required this.log,
    required this.info,
    required this.onPeer,
    required this.onChanged,
    required this.onAddresses,
    DiscoverySocketFactory? bindSocket,
    Future<List<NetworkInterface>> Function()? listInterfaces,
    this.retryDelay = const Duration(seconds: 5),
  }) : _bindSocket = bindSocket ?? _bind,
       _listInterfaces = listInterfaces ?? _interfaces;

  static const port = 45877;
  static final group = InternetAddress('239.255.77.77');
  static final broadcast = InternetAddress('255.255.255.255');
  final AppLog log;
  final Map<String, dynamic> Function() info;
  final void Function(Map<String, dynamic> data, String host) onPeer;
  final void Function() onChanged;
  final void Function(List<String>) onAddresses;
  final DiscoverySocketFactory _bindSocket;
  final Future<List<NetworkInterface>> Function() _listInterfaces;
  final Duration retryDelay;
  final List<_DiscoverySender> _senders = [];
  final Set<String> _seen = {};
  RawDatagramSocket? _receiver;
  Future<void>? _operation;
  Timer? _retryTimer;
  DateTime? _lastScan;
  Object? _lastFailure;
  String? error;
  bool retrying = false;
  bool _closed = false, _announced = false;
  int _generation = 0;

  static Future<RawDatagramSocket> _bind(InternetAddress address, int port) =>
      RawDatagramSocket.bind(
        address,
        port,
        reuseAddress: port == LanDiscovery.port,
        reusePort:
            port == LanDiscovery.port &&
            !Platform.isWindows &&
            !Platform.isAndroid,
      );

  static Future<List<NetworkInterface>> _interfaces() =>
      NetworkInterface.list(type: InternetAddressType.IPv4);

  Future<void> retry() {
    if (_closed) return Future.value();
    return _operation ??= _restart().whenComplete(() => _operation = null);
  }

  Future<void> _restart() async {
    retrying = true;
    onChanged();
    _retryTimer?.cancel();
    _retryTimer = null;
    final generation = ++_generation;
    _disposeSockets();
    try {
      final interfaces = await _listInterfaces();
      if (_closed) return;
      _lastScan = DateTime.now();
      final addresses = interfaces
          .expand((interface) => interface.addresses)
          .where(
            (address) =>
                address.type == InternetAddressType.IPv4 &&
                !address.isLoopback &&
                !address.address.startsWith('169.254.'),
          )
          .map((address) => address.address)
          .toSet()
          .toList();
      onAddresses(addresses);
      if (addresses.isEmpty) {
        throw const SocketException('没有可用的局域网 IPv4 地址');
      }
      final receiver = await _bindSocket(InternetAddress.anyIPv4, port);
      if (_closed) {
        receiver.close();
        return;
      }
      _receiver = receiver;
      receiver.writeEventsEnabled = false;
      for (final interface in interfaces) {
        if (!interface.addresses.any((a) => addresses.contains(a.address))) {
          continue;
        }
        try {
          receiver.joinMulticast(group, interface);
        } catch (failure) {
          _logFailure('join_failed', failure, {
            'interface': interface.name,
            'target': group.address,
          });
        }
      }
      receiver.listen(
        (event) {
          if (_closed || generation != _generation) return;
          if (event == RawSocketEvent.read) _read(receiver);
        },
        onError: (Object failure) {
          if (_closed || generation != _generation || _receiver == null) return;
          _lastFailure = failure;
          _receiver = null;
          receiver.close();
          _logFailure('receive_failed', failure, {'port': port});
          _updateHealth();
        },
        onDone: () {
          if (_closed || generation != _generation || _receiver == null) return;
          _receiver = null;
          _updateHealth();
        },
      );
      // Separate sockets keep an asynchronous route error on one adapter or
      // broadcast transport from invalidating working multicast discovery.
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!addresses.contains(address.address)) continue;
          for (final target in [group, broadcast]) {
            RawDatagramSocket? socket;
            try {
              socket = await _bindSocket(address, 0);
              if (_closed) {
                socket.close();
                return;
              }
              socket
                ..writeEventsEnabled = false
                ..readEventsEnabled = false;
              if (target == group) {
                socket.multicastHops = 1;
                socket.setRawOption(
                  RawSocketOption(
                    RawSocketOption.levelIPv4,
                    RawSocketOption.IPv4MulticastInterface,
                    address.rawAddress,
                  ),
                );
              } else {
                socket.broadcastEnabled = true;
              }
              final sender = _DiscoverySender(
                socket,
                address,
                target,
                interface.name,
              );
              _senders.add(sender);
              socket.listen(
                (_) {},
                onError: (Object failure) {
                  if (!_closed && generation == _generation) {
                    _senderFailed(sender, failure);
                  }
                },
                onDone: () {
                  if (!_closed && generation == _generation && !sender.failed) {
                    _senderFailed(sender, const SocketException.closed());
                  }
                },
              );
            } catch (failure) {
              socket?.close();
              _lastFailure = failure;
              _logFailure('channel_start_failed', failure, {
                'interface': interface.name,
                'localAddress': address.address,
                'target': target.address,
              });
            }
          }
        }
      }
      _announce();
    } catch (failure, stack) {
      _lastFailure = failure;
      _logFailure('start_failed', failure, {'port': port}, stack: stack);
    } finally {
      retrying = false;
      if (!_closed) _updateHealth();
    }
  }

  void _read(RawDatagramSocket socket) {
    try {
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        final current = packet!;
        if (current.data.length > 4096) continue;
        try {
          final data = jsonDecode(utf8.decode(current.data));
          if (data is! Map<String, dynamic> ||
              data['app'] != 'nearlink' ||
              data['version'] != 1 ||
              data['id'] == info()['id']) {
            continue;
          }
          onPeer(data, current.address.address);
          _updateHealth();
          if (_seen.add(data['id'] as String)) _announce();
        } catch (_) {
          // Unrelated or malformed datagrams do not affect discovery health.
        }
      }
    } catch (failure) {
      _lastFailure = failure;
      if (identical(_receiver, socket)) _receiver = null;
      socket.close();
      _logFailure('receive_failed', failure, {'port': port});
      _updateHealth();
    }
  }

  void _senderFailed(_DiscoverySender sender, Object failure) {
    if (sender.failed) return;
    sender.failed = true;
    sender.socket.close();
    _lastFailure = failure;
    _logFailure('channel_send_failed', failure, {
      'interface': sender.interfaceName,
      'localAddress': sender.address.address,
      'target': sender.target.address,
    });
    if (!retrying) _updateHealth();
  }

  void _announce() {
    if (_closed || _receiver == null) return;
    final bytes = utf8.encode(jsonEncode(info()));
    for (final sender in _senders.where((sender) => !sender.failed).toList()) {
      try {
        sender.socket.send(bytes, sender.target, port);
      } catch (failure) {
        _senderFailed(sender, failure);
      }
    }
  }

  void refresh() {
    if (_closed || retrying) return;
    if (_retryTimer == null &&
        (_receiver == null ||
            (_lastScan != null &&
                DateTime.now().difference(_lastScan!) >=
                    const Duration(seconds: 30)))) {
      unawaited(retry());
    } else {
      _announce();
    }
  }

  void _updateHealth() {
    if (_closed) return;
    final available =
        _receiver != null && _senders.any((sender) => !sender.failed);
    final previous = error;
    error = available ? null : _failureMessage();
    if (available) {
      _retryTimer?.cancel();
      _retryTimer = null;
      if (!_announced || previous != null) {
        _announced = true;
        log.info(
          'discovery',
          previous == null ? 'started' : 'recovered',
          previous == null ? '自动发现已启动' : '自动发现已恢复',
          fields: {'channels': _senders.where((s) => !s.failed).length},
        );
      }
    } else if (!retrying && _retryTimer == null) {
      _retryTimer = Timer(retryDelay, () {
        _retryTimer = null;
        unawaited(retry());
      });
    }
    onChanged();
  }

  String _failureMessage() {
    final failure = _lastFailure;
    final code = failure is SocketException ? failure.osError?.errorCode : null;
    final reason = switch (code) {
      1232 || 10050 || 10051 || 10065 || 101 => '发现网络不可达',
      10048 || 98 => '发现端口被占用',
      10013 || 13 => '系统限制了自动发现',
      _ => '自动发现暂不可用',
    };
    return '$reason，正在自动重试；也可通过 IP 连接';
  }

  void _logFailure(
    String event,
    Object failure,
    Map<String, Object?> fields, {
    StackTrace? stack,
  }) {
    log.warning(
      'discovery',
      event,
      '自动发现通道异常',
      error: failure,
      stack: stack,
      fields: {
        ...fields,
        if (failure is SocketException) 'errorCode': failure.osError?.errorCode,
      },
    );
  }

  void _disposeSockets() {
    _receiver?.close();
    _receiver = null;
    for (final sender in _senders) {
      sender.socket.close();
    }
    _senders.clear();
  }

  Future<void> close() async {
    _closed = true;
    _generation++;
    _retryTimer?.cancel();
    _disposeSockets();
    await _operation;
  }
}
