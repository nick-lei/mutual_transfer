import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'lan_discovery.dart';
import 'logging/app_log.dart';
import 'models.dart';
import 'transfer_stream.dart';

part 'group_service.dart';

class IncomingOffer {
  IncomingOffer({
    required this.id,
    required this.peer,
    required this.files,
    required this.remoteHost,
  });
  final String id;
  final Peer peer;
  final List<TransferItem> files;
  final String remoteHost;
  final String token = newId();
  final Completer<bool> decision = Completer<bool>();
  bool accepted = false;
  DateTime lastActivity = DateTime.now();
  bool _completionNotified = false;
  int get size => files.fold(0, (sum, file) => sum + file.size);
  String? groupName;
}

class _PendingReceive {
  _PendingReceive(
    this.offer,
    this.item,
    this.partial,
    this.destination,
    this.hash,
    this.elapsedMs,
  );
  final IncomingOffer offer;
  final TransferItem item;
  final File partial;
  final String destination, hash;
  final int elapsedMs;
  Timer? timer;
  bool committing = false;
}

class LanService {
  LanService({
    required this.dataDirectory,
    this.requestedPort = 45878,
    this.discoveryEnabled = true,
    this.initialName,
    this.defaultName,
    this.initialSaveDirectory,
    this.streamingIntegrityEnabled = true,
    this.commitTimeout = const Duration(minutes: 2),
    AppLog? log,
  }) : log = log ?? AppLog(dataDirectory),
       _ownsLog = log == null;
  final Directory dataDirectory;
  final int requestedPort;
  final bool discoveryEnabled;
  final String? initialName;
  final String? defaultName;
  final String? initialSaveDirectory;
  final bool streamingIntegrityEnabled;
  final Duration commitTimeout;
  final AppLog log;
  final bool _ownsLog;
  final Map<String, _PendingReceive> _pendingReceives = {};
  final Set<Future<void>> _activeReceives = {};
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  final _completedTransfers = StreamController<TransferCompletion>.broadcast();
  Stream<TransferCompletion> get completedTransfers =>
      _completedTransfers.stream;
  final Map<String, Peer> peers = {};
  final List<TransferItem> transfers = [];
  final List<ChatMessage> messages = [];
  final Map<String, LanGroup> groups = {};
  final Set<String> _groupOperations = {};
  bool _syncingGroups = false;
  DateTime? _lastGroupSync;
  LanGroup? groupForConversation(String? key) =>
      key != null && key.startsWith('group:') ? groups[key.substring(6)] : null;
  String conversationName(String key) =>
      groupForConversation(key)?.name ?? peers[key]?.displayName ?? '未知设备';
  String messagePreview(ChatMessage message) =>
      message.groupId != null && !message.outgoing
      ? '${peers[message.peerId]?.displayName ?? message.senderName ?? '群成员'}：${message.text}'
      : message.text;
  String? _viewedConversation;
  int unreadFor(String peerId) => messages
      .where(
        (message) =>
            message.conversationId == peerId &&
            !message.outgoing &&
            !message.read,
      )
      .length;
  int get unreadCount =>
      messages.where((message) => !message.outgoing && !message.read).length;
  List<UnreadConversation> get unreadConversations {
    final grouped = <String, List<ChatMessage>>{};
    for (final message in messages) {
      if (!message.outgoing && !message.read) {
        (grouped[message.conversationId] ??= []).add(message);
      }
    }
    return grouped.entries
        .map(
          (entry) => UnreadConversation(
            peerId: entry.key,
            count: entry.value.length,
            latest: entry.value.last,
          ),
        )
        .toList()
      ..sort((a, b) => b.latest.time.compareTo(a.latest.time));
  }

  void setMessageView(String? peerId, {required bool focused}) {
    _viewedConversation = focused ? peerId : null;
    if (_viewedConversation != null) {
      markMessagesRead(peerId: _viewedConversation);
    }
  }

  void markMessagesRead({String? peerId}) {
    var changed = false;
    for (final message in messages) {
      if (!message.outgoing &&
          !message.read &&
          (peerId == null || message.conversationId == peerId)) {
        message.read = true;
        changed = true;
      }
    }
    if (changed) _notify(persist: true);
  }

  final List<IncomingOffer> incoming = [];
  final Map<String, IncomingOffer> _offers = {};
  final Map<String, WebSocket> _sockets = {};
  final Map<String, Completer<void>> _acks = {};
  final Map<String, HttpClientRequest> _requests = {};
  final Map<String, ({Peer peer, String offerId})> _outgoingOffers = {};
  final Set<String> _cancelled = {};
  final Set<String> _reservedPaths = {};
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..autoUncompress = false;
  HttpServer? _server;
  late final _discovery = LanDiscovery(
    log: log,
    info: () => info,
    onPeer: (data, host) => _upsert(data, host),
    onChanged: _notify,
    onAddresses: (values) {
      addresses = values
        ..sort((a, b) => _addressPriority(a).compareTo(_addressPriority(b)));
    },
  );
  Timer? _heartbeat;
  Timer? _saveTimer;
  DateTime? _lastPresenceSave;
  Future<void> _saveQueue = Future.value();
  RandomAccessFile? _instanceLock;
  bool _ownsDirectory = false;
  bool _closed = false;
  bool _probing = false;
  String id = newId();
  String name = Platform.localHostname;
  String saveDirectory = '';
  List<String> addresses = [];
  String? error;
  String? get discoveryError => _discovery.error;
  bool get retryingDiscovery => _discovery.retrying;
  int get port => _server?.port ?? requestedPort;
  bool get running => _server != null;
  String get primaryAddress =>
      addresses.isEmpty ? '127.0.0.1' : addresses.first;
  String get platform =>
      Platform.isWindows ? 'Windows' : Platform.operatingSystem;
  Map<String, dynamic> get info => {
    'app': 'nearlink',
    'version': 1,
    'id': id,
    'name': name,
    'port': port,
    'platform': platform,
    'capabilities': [
      if (streamingIntegrityEnabled) streamingIntegrity,
      'lan-groups-v1',
    ],
  };

  void _notify({bool persist = false}) {
    if (!_closed) _changes.add(null);
    if (persist && !_closed) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), () {
        unawaited(_persist());
      });
    }
  }

  Future<void> start() async {
    try {
      await dataDirectory.create(recursive: true);
      _instanceLock = await File(
        p.join(dataDirectory.path, '.instance.lock'),
      ).open(mode: FileMode.append);
      await _instanceLock!.lock(FileLock.exclusive);
      _ownsDirectory = true;
    } catch (_) {
      await _instanceLock?.close();
      _instanceLock = null;
      error = '无法使用本地配置目录，可能已有邻传实例正在运行';
      _notify();
      return;
    }
    await log.initialize();
    log.info(
      'network',
      'service_starting',
      '正在启动局域网服务',
      fields: {'requestedPort': requestedPort},
    );
    final userHome =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        dataDirectory.path;
    saveDirectory =
        initialSaveDirectory ?? p.join(userHome, 'Downloads', 'NearLink');
    if (defaultName != null) name = defaultName!;
    try {
      final configFile = File(p.join(dataDirectory.path, 'settings.json'));
      if (await configFile.exists()) {
        final config =
            jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
        id = config['id'] as String;
        name = config['name'] as String;
        saveDirectory = config['saveDirectory'] as String;
        for (final raw in (config['peers'] as List? ?? [])) {
          final data = Map<String, dynamic>.from(raw as Map);
          final peer = Peer(
            id: data['id'] as String,
            name: data['name'] as String,
            host: data['host'] as String,
            port: data['port'] as int,
            platform: data['platform'] as String,
            manual: data['manual'] as bool,
            remark: data['remark'] as String? ?? '',
            capabilities: (data['capabilities'] as List? ?? []).cast<String>(),
            online: false,
            lastSeen: DateTime.tryParse('${data['lastSeen'] ?? ''}'),
          );
          peers[peer.id] = peer;
        }
        for (final raw in (config['groups'] as List? ?? [])) {
          final group = LanGroup.fromJson(
            Map<String, dynamic>.from(raw as Map),
            local: true,
          );
          groups[group.id] = group;
        }
      }
      final historyFile = File(p.join(dataDirectory.path, 'history.json'));
      if (await historyFile.exists()) {
        final history =
            jsonDecode(await historyFile.readAsString())
                as Map<String, dynamic>;
        transfers.addAll(
          (history['transfers'] as List).map(
            (e) => TransferItem.fromJson(Map<String, dynamic>.from(e as Map)),
          ),
        );
        messages.addAll(
          (history['messages'] as List).map(
            (e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
          ),
        );
      }
    } catch (e, stack) {
      error = '部分本地记录未能读取';
      log.warning(
        'storage',
        'records_read_failed',
        error!,
        error: e,
        stack: stack,
      );
    }
    if (initialName != null) name = initialName!;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      addresses = interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where((a) => !a.startsWith('169.254.'))
          .toSet()
          .toList();
      addresses.sort(
        (a, b) => _addressPriority(a).compareTo(_addressPriority(b)),
      );
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, requestedPort);
      } on SocketException {
        if (requestedPort == 0) rethrow;
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      _server!.listen(
        (request) {
          unawaited(_handle(request));
        },
        onError: (Object e) {
          error = '网络服务异常：$e';
          log.error('network', 'server_error', '网络服务异常', error: e);
          _notify();
        },
      );
      log.info(
        'network',
        'service_started',
        '局域网服务已启动',
        fields: {
          'port': port,
          'addresses': addresses,
          'streamingIntegrity': streamingIntegrityEnabled,
        },
      );
      if (discoveryEnabled) await _discovery.retry();
      _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
        refresh();
        final now = DateTime.now();
        if (!_syncingGroups &&
            (_lastGroupSync == null ||
                now.difference(_lastGroupSync!).inSeconds >= 30)) {
          _lastGroupSync = now;
          _syncingGroups = true;
          unawaited(
            Future.wait(
              groups.values
                  .where((g) => g.pendingSync.isNotEmpty)
                  .toList()
                  .map((g) => syncGroup(g).catchError((Object _) {})),
            ).whenComplete(() => _syncingGroups = false),
          );
        }
        var presenceChanged = false;
        for (final peer in peers.values) {
          final lastSeen = peer.lastSeen;
          if (peer.online && _sockets.containsKey(peer.id)) {
            peer.lastSeen = now;
          } else if (peer.online &&
              (lastSeen == null || now.difference(lastSeen).inSeconds > 16)) {
            peer.online = false;
            presenceChanged = true;
          }
        }
        for (final offer in _offers.values) {
          if (offer.accepted &&
              now.difference(offer.lastActivity).inMinutes >= 10 &&
              !offer.files.any(
                (f) =>
                    f.status == TransferStatus.transferring ||
                    f.status == TransferStatus.hashing,
              )) {
            for (final file in offer.files.where((f) => f.active)) {
              file
                ..status = TransferStatus.failed
                ..error = '发送方长时间无响应';
            }
          }
        }
        _offers.removeWhere(
          (_, offer) =>
              offer.decision.isCompleted && offer.files.every((f) => !f.active),
        );
        _notify(
          persist:
              presenceChanged ||
              (peers.values.any((peer) => peer.online) &&
                  (_lastPresenceSave == null ||
                      now.difference(_lastPresenceSave!).inSeconds >= 30)),
        );
      });
    } catch (e, stack) {
      error = '无法启动网络服务：$e';
      log.error(
        'network',
        'service_start_failed',
        '无法启动网络服务',
        error: e,
        stack: stack,
      );
    }
    await _persist();
    _notify();
  }

  int _addressPriority(String ip) => ip.startsWith('192.168.')
      ? 0
      : ip.startsWith('10.')
      ? 1
      : 2;

  Future<void> retryDiscovery() async {
    if (_closed || !running || !discoveryEnabled) return;
    await _discovery.retry();
    refresh();
  }

  void refresh() {
    if (_closed) return;
    if (discoveryEnabled) _discovery.refresh();
    if (!_probing) {
      _probing = true;
      unawaited(
        Future.wait(
          peers.values.where((p) => p.manual).toList().map((peer) async {
            try {
              await connect(peer.address);
            } catch (_) {
              peer.online = false;
            }
          }),
        ).whenComplete(() {
          _probing = false;
          _notify();
        }),
      );
    }
  }

  bool _isLocalEndpoint(String host, int endpointPort) =>
      endpointPort == port &&
      (host == '0.0.0.0' ||
          (InternetAddress.tryParse(host)?.isLoopback ?? false) ||
          addresses.contains(host));

  Peer _upsert(Map<String, dynamic> data, String host, {bool manual = false}) {
    final peerId = data['id'];
    final peerName = data['name'];
    final peerPort = data['port'];
    if (peerId is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(peerId) ||
        peerName is! String ||
        peerName.isEmpty ||
        peerName.length > 64 ||
        peerPort is! int ||
        peerPort < 1 ||
        peerPort > 65535) {
      throw const FormatException('无效的设备信息');
    }
    if (peerId == id) throw const FormatException('这是当前设备，请连接另一台设备');
    final existing = peers[peerId];
    final localEndpoint = _isLocalEndpoint(host, peerPort);
    // NAT can make an incoming packet appear to originate at our own listener.
    final preserveEndpoint =
        existing != null &&
        ((existing.manual && !manual) ||
            (localEndpoint && !_isLocalEndpoint(existing.host, existing.port)));
    final endpointHost = preserveEndpoint ? existing.host : host;
    final endpointPort = preserveEndpoint ? existing.port : peerPort;
    final endpointOnline = !_isLocalEndpoint(endpointHost, endpointPort);
    final changed =
        existing == null ||
        existing.online != endpointOnline ||
        existing.name != peerName ||
        existing.host != endpointHost ||
        existing.port != endpointPort ||
        (manual && !existing.manual);
    final peer = peers.putIfAbsent(
      peerId,
      () => Peer(id: peerId, name: peerName, host: host, port: peerPort),
    );
    peer
      ..name = peerName
      ..host = endpointHost
      ..port = endpointPort
      ..platform = '${data['platform'] ?? 'Desktop'}'
      ..lastSeen = DateTime.now()
      ..online = endpointOnline
      ..manual = (manual || peer.manual);
    peer.capabilities = (data['capabilities'] as List? ?? [])
        .whereType<String>()
        .toList();
    if (changed) {
      log.info(
        'discovery',
        'peer_updated',
        '设备连接信息已更新',
        fields: {
          'peerId': peer.id,
          'host': endpointHost,
          'port': endpointPort,
          'manual': peer.manual,
          'localEndpoint': _isLocalEndpoint(endpointHost, endpointPort),
        },
      );
    }
    _notify(persist: changed);
    return peer;
  }

  Future<Peer> _verifyPeerEndpoint(Peer peer) async {
    final endpoint = Peer(
      id: peer.id,
      name: peer.name,
      host: peer.host,
      port: peer.port,
      platform: peer.platform,
      manual: peer.manual,
      remark: peer.remark,
      capabilities: List.of(peer.capabilities),
    );
    Map<String, dynamic> data;
    HttpClientRequest? request;
    try {
      if (_isLocalEndpoint(endpoint.host, endpoint.port)) {
        data = info;
      } else {
        request = await _client.getUrl(endpoint.uri('/v1/info'));
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        data = await _readJson(response);
        if (response.statusCode != 200 ||
            data['app'] != 'nearlink' ||
            data['version'] != 1) {
          throw const FormatException('该地址未运行兼容的邻传服务');
        }
      }
    } catch (_) {
      request?.abort();
      rethrow;
    }
    if (data['id'] != endpoint.id || data['id'] == id) {
      if (peer.host == endpoint.host && peer.port == endpoint.port) {
        peer.online = false;
      }
      final known = peers[peer.id];
      if (known?.address == endpoint.address) known!.online = false;
      log.warning(
        'discovery',
        'peer_endpoint_mismatch',
        '设备连接地址与身份不匹配，已阻止发送',
        fields: {
          'peerId': endpoint.id,
          'actualPeerId': data['id'],
          'host': endpoint.host,
          'port': endpoint.port,
        },
      );
      _notify();
      throw FormatException(
        data['id'] == id
            ? '该设备的连接地址指向本机，请刷新设备或使用对方的 IP 手动连接'
            : '连接地址对应的设备与所选设备不一致，请重新连接',
      );
    }
    return endpoint;
  }

  Future<Peer> connect(String input) async {
    final uri = Uri.tryParse(
      input.trim().contains('://') ? input.trim() : 'http://${input.trim()}',
    );
    if (uri == null ||
        uri.scheme != 'http' ||
        InternetAddress.tryParse(uri.host)?.type != InternetAddressType.IPv4 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('请输入 IPv4 地址，例如 192.168.1.12:45878');
    }
    final target = uri.replace(
      port: uri.hasPort ? uri.port : 45878,
      path: '/v1/info',
    );
    final request = await _client.getUrl(target);
    final response = await request.close().timeout(const Duration(seconds: 8));
    final data = await _readJson(response);
    if (response.statusCode != 200 ||
        data['app'] != 'nearlink' ||
        data['version'] != 1) {
      throw const FormatException('该地址未运行兼容的邻传服务');
    }
    if (data['id'] == id) throw const FormatException('这是当前设备，请连接另一台设备');
    // A manually entered endpoint may forward to a different internal port.
    return _upsert({...data, 'port': target.port}, uri.host, manual: true);
  }

  Future<Map<String, dynamic>> _readJson(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream.timeout(const Duration(seconds: 12))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) throw const FormatException('请求内容过大');
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<void> _json(HttpResponse response, int status, Object data) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/info') {
        await _json(request.response, 200, info);
        return;
      }
      if (request.method == 'GET' &&
          path == '/v1/chat' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        if (_sockets.length >= 32) {
          await _json(request.response, 429, {'error': '会话已满'});
          return;
        }
        final host = request.connectionInfo!.remoteAddress.address;
        final socket = await WebSocketTransformer.upgrade(request);
        _listenSocket(socket, host);
        return;
      }
      if (request.method == 'POST' && path == '/v1/offers') {
        await _receiveOffer(request);
        return;
      }
      if (request.method == 'POST' &&
          (path == '/v1/groups' ||
              path == '/v1/groups/leave' ||
              path == '/v1/groups/join' ||
              path == '/v1/group-messages')) {
        await _handleGroupRequest(request);
        return;
      }
      if (request.method == 'PUT' && path.startsWith('/v1/files/')) {
        final operation = _receiveFile(request);
        _activeReceives.add(operation);
        try {
          await operation;
        } finally {
          _activeReceives.remove(operation);
        }
        return;
      }
      if (request.method == 'POST' &&
          request.uri.pathSegments.length == 4 &&
          path.startsWith('/v1/files/') &&
          path.endsWith('/commit')) {
        final operation = _commitFile(request);
        _activeReceives.add(operation);
        try {
          await operation;
        } finally {
          _activeReceives.remove(operation);
        }
        return;
      }
      if (request.method == 'POST' && path == '/v1/cancel') {
        final data = await _readJson(request);
        final offer = _offers[data['offerId']];
        if (offer == null ||
            offer.remoteHost != request.connectionInfo!.remoteAddress.address) {
          await _json(request.response, 403, {'error': '无效的传输会话'});
          return;
        }
        for (final file in offer.files.where((f) => f.active)) {
          _cancelled.add(file.id);
          file.status = TransferStatus.cancelled;
          await _discardReceive(file.id, TransferStatus.cancelled, '发送方已取消传输');
        }
        if (!offer.decision.isCompleted) offer.decision.complete(false);
        incoming.remove(offer);
        _notify(persist: true);
        await _json(request.response, 200, {'ok': true});
        return;
      }
      await _json(request.response, 404, {'error': '未找到接口'});
    } catch (e, stack) {
      log.warning(
        'network',
        'request_failed',
        '请求处理失败',
        error: e,
        stack: stack,
        fields: {'method': request.method, 'path': request.uri.path},
      );
      try {
        await _json(request.response, e is FormatException ? 400 : 500, {
          'error': e is FormatException ? e.message : '请求处理失败',
        });
      } catch (_) {
        /* The peer may already have disconnected. */
      }
    }
  }

  Future<void> _receiveOffer(HttpRequest request) async {
    if (_offers.values.where((o) => o.files.any((f) => f.active)).length >= 8) {
      await _json(request.response, 429, {'error': '接收队列已满'});
      return;
    }
    final data = await _readJson(request);
    final peerData = Map<String, dynamic>.from(data['peer'] as Map);
    if (peerData['id'] == id) throw const FormatException('不能向自己发送文件');
    final peer = _upsert(
      peerData,
      request.connectionInfo!.remoteAddress.address,
    );
    final groupId = data['groupId'] as String?;
    if (groupId != null) _requireGroupSender(groupId, peer.id);
    final offerId = data['id'] as String;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(offerId) ||
        _offers.containsKey(offerId)) {
      throw const FormatException('重复或无效的传输会话');
    }
    final list = data['files'] as List;
    if (list.isEmpty || list.length > 1000) {
      throw const FormatException('文件数量应为 1 至 1000');
    }
    final items = <TransferItem>[];
    final ids = transfers.map((f) => f.id).toSet();
    for (final raw in list) {
      final file = Map<String, dynamic>.from(raw as Map);
      final relative = file['path'] as String;
      validateRelativePath(relative);
      final fileId = file['id'] as String;
      final size = file['size'] as int;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(fileId) ||
          !ids.add(fileId) ||
          size < 0 ||
          size > 16 * 1024 * 1024 * 1024 * 1024) {
        throw const FormatException('无效的文件信息');
      }
      items.add(
        TransferItem(
          id: fileId,
          peerId: peer.id,
          peerName: peer.name,
          name: relative.split('/').last,
          relativePath: relative,
          size: size,
          outgoing: false,
          groupId: groupId,
          batchId: offerId,
        ),
      );
    }
    final offer = IncomingOffer(
      id: offerId,
      peer: peer,
      files: items,
      remoteHost: request.connectionInfo!.remoteAddress.address,
    )..groupName = groups[groupId]?.name;
    _offers[offer.id] = offer;
    incoming.add(offer);
    transfers.insertAll(0, items);
    log.info(
      'transfer',
      'offer_received',
      '收到文件发送请求',
      fields: {
        'offerId': offer.id,
        'peerId': peer.id,
        'fileCount': items.length,
        'bytes': offer.size,
      },
    );
    _notify(persist: true);
    final accepted = await offer.decision.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        if (!offer.decision.isCompleted) offer.decision.complete(false);
        return false;
      },
    );
    incoming.remove(offer);
    offer.accepted = accepted;
    offer.lastActivity = DateTime.now();
    if (!accepted) {
      for (final file in items.where((f) => f.active)) {
        file.status = TransferStatus.rejected;
      }
    }
    log.info(
      'transfer',
      'offer_resolved',
      accepted ? '接收请求已同意' : '接收请求已拒绝或超时',
      fields: {'offerId': offer.id, 'accepted': accepted},
    );
    _notify(persist: true);
    await _json(
      request.response,
      accepted ? 200 : 409,
      accepted
          ? {
              'token': offer.token,
              'capabilities': [
                if (streamingIntegrityEnabled) streamingIntegrity,
              ],
            }
          : {'error': '对方已拒绝或接收确认已超时'},
    );
  }

  void decide(IncomingOffer offer, bool accept) {
    if (offer.decision.isCompleted) return;
    if (accept) {
      for (final file in offer.files) {
        file.status = TransferStatus.queued;
      }
    }
    offer.decision.complete(accept);
    log.info(
      'transfer',
      accept ? 'offer_accepted' : 'offer_rejected',
      accept ? '已同意接收文件' : '已拒绝接收文件',
      fields: {'offerId': offer.id, 'peerId': offer.peer.id},
    );
    incoming.remove(offer);
    _notify(persist: true);
  }

  Future<String> _reserveDestination(String relative) async {
    final safeRelative = validateRelativePath(relative);
    await Directory(saveDirectory).create(recursive: true);
    final root = await Directory(saveDirectory).resolveSymbolicLinks();
    var parent = root;
    // Validate each existing parent before creating any child directories.
    for (final component
        in p.split(p.dirname(safeRelative)).where((s) => s != '.')) {
      final child = Directory(p.join(parent, component));
      if (!await child.exists()) await child.create();
      parent = await child.resolveSymbolicLinks();
      if (parent != root && !p.isWithin(root, parent)) {
        throw const FormatException('接收路径超出保存目录');
      }
    }
    final destination = p.join(parent, p.basename(safeRelative));
    var candidate = destination;
    var suffix = 1;
    while (_reservedPaths.contains(candidate) ||
        await FileSystemEntity.type(candidate, followLinks: false) !=
            FileSystemEntityType.notFound) {
      candidate = p.join(
        p.dirname(destination),
        '${p.basenameWithoutExtension(destination)} ($suffix)${p.extension(destination)}',
      );
      suffix++;
    }
    _reservedPaths.add(candidate);
    return candidate;
  }

  Future<void> _receiveFile(HttpRequest request) async {
    final fileId = request.uri.pathSegments.last;
    IncomingOffer? matchedOffer;
    TransferItem? matchedItem;
    for (final candidate in _offers.values) {
      for (final file in candidate.files) {
        if (file.id == fileId) {
          matchedOffer = candidate;
          matchedItem = file;
          break;
        }
      }
      if (matchedItem != null) break;
    }
    final offer = matchedOffer;
    final item = matchedItem;
    if (offer == null ||
        item == null ||
        !offer.accepted ||
        request.uri.queryParameters['token'] != offer.token ||
        request.connectionInfo!.remoteAddress.address != offer.remoteHost) {
      await _json(request.response, 403, {'error': '文件未经接收确认'});
      return;
    }
    if (item.status != TransferStatus.queued ||
        request.contentLength != item.size) {
      await _json(request.response, 409, {'error': '文件状态或大小不匹配'});
      return;
    }
    final streaming =
        streamingIntegrityEnabled &&
        request.headers.value('x-nearlink-integrity') == streamingIntegrity;
    final expectedHash = request.headers.value('x-nearlink-sha256');
    if (!streaming &&
        (expectedHash == null ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash))) {
      throw const FormatException('缺少文件校验值');
    }
    String? destination;
    File? partial;
    IOSink? sink;
    TransferDigest? digest;
    var retained = false;
    // Claim the file before asynchronous path reservation to reject duplicate PUTs.
    item.status = TransferStatus.transferring;
    final watch = Stopwatch()..start();
    log.info(
      'transfer',
      'receive_started',
      '开始接收文件',
      fields: {
        'transferId': item.id,
        'peerId': item.peerId,
        'bytes': item.size,
        'integrity': streaming ? streamingIntegrity : 'legacy-sha256',
      },
    );
    try {
      destination = await _reserveDestination(item.relativePath);
      partial = File(
        p.join(p.dirname(destination), '.nearlink-${item.id}.part'),
      );
      sink = partial.openWrite();
      sink.done.ignore();
      digest = TransferDigest();
      final activeDigest = digest;
      var lastUpdate = 0;
      var lastLog = 0;
      await sink.addStream(
        request.timeout(const Duration(seconds: 45)).map((chunk) {
          offer.lastActivity = DateTime.now();
          if (_cancelled.contains(item.id)) throw const HttpException('传输已取消');
          item.bytes += chunk.length;
          if (item.bytes > item.size) throw const FormatException('文件内容超过声明大小');
          activeDigest.addBytes(chunk);
          if (watch.elapsedMilliseconds - lastUpdate > 100) {
            lastUpdate = watch.elapsedMilliseconds;
            item.bytesPerSecond = item.bytes * 1000 / lastUpdate;
            _notify();
          }
          if (watch.elapsedMilliseconds - lastLog >= 5000) {
            lastLog = watch.elapsedMilliseconds;
            log.info(
              'transfer',
              'receive_progress',
              '文件接收进度',
              fields: {
                'transferId': item.id,
                'bytes': item.bytes,
                'totalBytes': item.size,
                'elapsedMs': lastLog,
              },
            );
          }
          return chunk;
        }),
      );
      await sink.close();
      sink = null;
      if (item.bytes != item.size || _cancelled.contains(item.id)) {
        throw const FormatException('文件内容不完整');
      }
      item.status = TransferStatus.hashing;
      _notify();
      final hash = digest.finish();
      if (!streaming && hash != expectedHash) {
        throw const FormatException('文件校验失败');
      }
      final pending = _PendingReceive(
        offer,
        item,
        partial,
        destination,
        hash,
        watch.elapsedMilliseconds,
      );
      if (streaming) {
        _pendingReceives[item.id] = pending;
        pending.timer = Timer(commitTimeout, () {
          unawaited(
            _discardReceive(item.id, TransferStatus.failed, '发送方未完成校验确认'),
          );
        });
        retained = true;
        await _json(request.response, 200, {
          'sha256': hash,
          'commitRequired': true,
        });
      } else {
        await _finalizeReceive(pending);
        await _json(request.response, 200, {'sha256': hash});
      }
    } catch (e, stack) {
      if (item.status == TransferStatus.complete) rethrow;
      _pendingReceives.remove(item.id)?.timer?.cancel();
      retained = false;
      try {
        await sink?.close();
      } catch (_) {
        /* Disk may have become unavailable. */
      }
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {
        /* Preserve the transfer error if partial-file cleanup also fails. */
      }
      item
        ..status = _cancelled.contains(item.id)
            ? TransferStatus.cancelled
            : TransferStatus.failed
        ..error = e.toString();
      log.warning(
        'transfer',
        'receive_failed',
        '文件接收未完成',
        error: e,
        stack: stack,
        fields: {
          'transferId': item.id,
          'bytes': item.bytes,
          'totalBytes': item.size,
          'status': item.status.name,
        },
      );
      _notify(persist: true);
      await _json(request.response, 422, {'error': item.error});
    } finally {
      digest?.closeNative();
      if (!retained && destination != null) _reservedPaths.remove(destination);
    }
  }

  Future<void> _finalizeReceive(_PendingReceive pending) async {
    final item = pending.item;
    if (_cancelled.contains(item.id) || _closed) {
      throw const HttpException('传输已取消');
    }
    if (await FileSystemEntity.type(pending.destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('目标文件已存在，请重试');
    }
    if (_cancelled.contains(item.id) || _closed) {
      throw const HttpException('传输已取消');
    }
    await pending.partial.rename(pending.destination);
    item
      ..savedPath = pending.destination
      ..status = TransferStatus.complete
      ..bytes = item.size;
    log.info(
      'transfer',
      'receive_complete',
      '文件接收与校验完成',
      fields: {
        'transferId': item.id,
        'bytes': item.size,
        'elapsedMs': pending.elapsedMs,
        'sha256': pending.hash,
      },
    );
    final offer = pending.offer;
    if (!offer._completionNotified &&
        offer.files.every((file) => file.status == TransferStatus.complete)) {
      offer._completionNotified = true;
      _emitTransferCompletion(
        TransferCompletion(
          id: offer.id,
          outgoing: false,
          peerName: offer.peer.displayName,
          fileCount: offer.files.length,
          totalBytes: offer.size,
        ),
      );
    }
    _notify(persist: true);
  }

  Future<void> _discardReceive(
    String id,
    TransferStatus status,
    String reason,
  ) async {
    final pending = _pendingReceives.remove(id);
    if (pending == null) return;
    pending.timer?.cancel();
    try {
      if (await pending.partial.exists()) await pending.partial.delete();
    } catch (error, stack) {
      log.error(
        'transfer',
        'partial_cleanup_failed',
        '临时文件清理失败',
        error: error,
        stack: stack,
        fields: {'transferId': id},
      );
    } finally {
      _reservedPaths.remove(pending.destination);
    }
    pending.item
      ..status = status
      ..error = reason;
    log.warning(
      'transfer',
      'receive_discarded',
      reason,
      fields: {'transferId': id, 'bytes': pending.item.bytes},
    );
    _notify(persist: true);
  }

  Future<void> _commitFile(HttpRequest request) async {
    final id = request.uri.pathSegments[2];
    final data = await _readJson(request);
    final pending = _pendingReceives[id];
    if (pending == null || pending.committing) {
      await _json(request.response, 409, {'error': '文件不在待确认状态'});
      return;
    }
    if (data['token'] != pending.offer.token ||
        request.connectionInfo!.remoteAddress.address !=
            pending.offer.remoteHost) {
      await _json(request.response, 403, {'error': '无效的传输会话'});
      return;
    }
    if (data['sha256'] != pending.hash) {
      await _discardReceive(id, TransferStatus.failed, '文件校验失败');
      await _json(request.response, 422, {'error': '文件校验失败'});
      return;
    }
    pending.committing = true;
    pending.timer?.cancel();
    // Remove before awaiting I/O: cancellation marks the transfer, while this
    // operation retains ownership of its temporary file and reservation.
    _pendingReceives.remove(id);
    try {
      await _finalizeReceive(pending);
    } catch (error, stack) {
      try {
        if (await pending.partial.exists()) await pending.partial.delete();
      } catch (cleanupError) {
        log.error(
          'transfer',
          'partial_cleanup_failed',
          '临时文件清理失败',
          error: cleanupError,
          fields: {'transferId': id},
        );
      }
      pending.item
        ..status = _cancelled.contains(id)
            ? TransferStatus.cancelled
            : TransferStatus.failed
        ..error = '$error';
      log.warning(
        'transfer',
        'commit_failed',
        '文件校验确认失败',
        error: error,
        stack: stack,
        fields: {'transferId': id},
      );
      _notify(persist: true);
      await _json(request.response, 422, {'error': pending.item.error});
      return;
    } finally {
      _reservedPaths.remove(pending.destination);
    }
    await _json(request.response, 200, {'sha256': pending.hash});
  }

  Future<void> sendFiles(
    Peer peer,
    List<LocalFile> files, {
    String? groupId,
  }) async {
    final items = await _sendFileBatch(peer, files, groupId: groupId);
    if (items.every((file) => file.status == TransferStatus.complete)) {
      _emitTransferCompletion(
        TransferCompletion(
          id: newId(),
          outgoing: true,
          peerName: peer.displayName,
          fileCount: files.length,
          totalBytes: files.fold(0, (sum, file) => sum + file.size),
        ),
      );
    }
  }

  void _emitTransferCompletion(TransferCompletion completion) {
    if (_closed) return;
    _completedTransfers.add(completion);
    log.info(
      'transfer',
      'batch_complete',
      completion.title,
      fields: {
        'batchId': completion.id,
        'outgoing': completion.outgoing,
        'fileCount': completion.fileCount,
        'bytes': completion.totalBytes,
        'recipients': completion.recipientCount,
      },
    );
  }

  Future<List<TransferItem>> _sendFileBatch(
    Peer peer,
    List<LocalFile> files, {
    String? groupId,
  }) async {
    if (groupId != null) _requireGroupSender(groupId, peer.id);
    if (!peer.online || files.isEmpty || files.length > 1000) {
      throw const FormatException('设备离线或文件队列无效');
    }
    for (final file in files) {
      validateRelativePath(file.relativePath);
    }
    final offerId = newId();
    final items = files
        .map(
          (file) => TransferItem(
            id: newId(),
            peerId: peer.id,
            peerName: peer.name,
            name: file.name,
            size: file.size,
            relativePath: file.relativePath,
            outgoing: true,
            sourcePath: file.path,
            groupId: groupId,
            batchId: offerId,
          ),
        )
        .toList();
    transfers.insertAll(0, items);
    log.info(
      'transfer',
      'offer_sent',
      '请求向设备发送文件',
      fields: {
        'offerId': offerId,
        'peerId': peer.id,
        'fileCount': items.length,
        'bytes': files.fold<int>(0, (sum, file) => sum + file.size),
      },
    );
    for (final item in items) {
      _outgoingOffers[item.id] = (peer: peer, offerId: offerId);
    }
    _notify(persist: true);
    HttpClientRequest? offerRequest;
    Peer? endpoint;
    var offerSubmitted = false;
    try {
      endpoint = await _verifyPeerEndpoint(peer);
      if (items.every((item) => _cancelled.contains(item.id))) return items;
      for (final item in items) {
        _outgoingOffers[item.id] = (peer: endpoint, offerId: offerId);
      }
      offerRequest = await _client.postUrl(endpoint.uri('/v1/offers'));
      for (final item in items) {
        _requests[item.id] = offerRequest;
      }
      offerRequest.headers.contentType = ContentType.json;
      offerRequest.write(
        jsonEncode({
          'id': offerId,
          'peer': info,
          'groupId': ?groupId,
          'files': items
              .map((f) => {'id': f.id, 'path': f.relativePath, 'size': f.size})
              .toList(),
        }),
      );
      offerSubmitted = true;
      final response = await offerRequest.close().timeout(
        const Duration(seconds: 95),
      );
      final result = await _readJson(response);
      if (response.statusCode != 200) {
        for (final item in items.where((f) => f.active)) {
          item
            ..status = response.statusCode == 409
                ? TransferStatus.rejected
                : TransferStatus.failed
            ..error = '${result['error'] ?? '发送请求失败'}';
        }
        return items;
      }
      final token = result['token'] as String;
      final streaming =
          streamingIntegrityEnabled &&
          (result['capabilities'] as List? ?? []).contains(streamingIntegrity);
      for (final item in items) {
        if (!_cancelled.contains(item.id)) item.status = TransferStatus.queued;
      }
      for (final item in items) {
        if (_cancelled.contains(item.id)) continue;
        await _sendFile(endpoint, item, token, streaming: streaming);
      }
      if (items.any(
        (f) =>
            f.status == TransferStatus.failed ||
            f.status == TransferStatus.cancelled,
      )) {
        await _cancelRemote(endpoint, offerId);
      }
    } catch (e, stack) {
      offerRequest?.abort();
      log.warning(
        'transfer',
        'send_batch_failed',
        '发送批次未完成',
        error: e,
        stack: stack,
        fields: {'offerId': offerId, 'peerId': peer.id},
      );
      for (final item in items.where((f) => f.active)) {
        item
          ..status = _cancelled.contains(item.id)
              ? TransferStatus.cancelled
              : TransferStatus.failed
          ..error = e is FormatException ? e.message : '连接中断：$e';
      }
      if (offerSubmitted && endpoint != null) {
        unawaited(_cancelRemote(endpoint, offerId));
      }
    } finally {
      for (final item in items) {
        _requests.remove(item.id);
        _outgoingOffers.remove(item.id);
      }
      _notify(persist: true);
    }
    return items;
  }

  Future<void> _sendFile(
    Peer peer,
    TransferItem item,
    String token, {
    required bool streaming,
  }) async {
    HttpClientRequest? request;
    Timer? watchdog;
    TransferDigest? digest;
    final total = Stopwatch()..start();
    try {
      final file = File(item.sourcePath!);
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file ||
          before.size != item.size) {
        throw const FileSystemException('文件大小已改变，请重新添加');
      }
      String? hash;
      if (!streaming) {
        item.status = TransferStatus.hashing;
        _notify();
        final path = file.path;
        hash = await hashTransferFileInBackground(path);
      }
      if (_cancelled.contains(item.id)) return;
      if (await file.length() != item.size) {
        throw const FileSystemException('文件大小已改变，请重新添加');
      }
      request = await _client.putUrl(
        peer
            .uri('/v1/files/${item.id}')
            .replace(queryParameters: {'token': token}),
      );
      request.done.ignore();
      _requests[item.id] = request;
      request.contentLength = item.size;
      if (streaming) {
        request.headers.set('x-nearlink-integrity', streamingIntegrity);
      } else {
        request.headers.set('x-nearlink-sha256', hash!);
      }
      item.status = TransferStatus.transferring;
      log.info(
        'transfer',
        'send_started',
        '开始发送文件',
        fields: {
          'transferId': item.id,
          'peerId': peer.id,
          'bytes': item.size,
          'integrity': streaming ? streamingIntegrity : 'legacy-sha256',
        },
      );
      final watch = Stopwatch()..start();
      var lastUpdate = 0;
      var lastLog = 0;
      var lastActivity = DateTime.now();
      watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(lastActivity) >=
            const Duration(seconds: 45)) {
          request?.abort(TimeoutException('传输长时间无进展'));
        }
      });
      digest = streaming ? TransferDigest() : null;
      final activeDigest = digest;
      await request.addStream(
        readTransferFile(file.path).map((chunk) {
          if (_cancelled.contains(item.id)) {
            throw const HttpException('传输已取消');
          }
          lastActivity = DateTime.now();
          activeDigest?.addBytes(chunk);
          item.bytes += chunk.length;
          if (watch.elapsedMilliseconds - lastUpdate > 100) {
            lastUpdate = watch.elapsedMilliseconds;
            item.bytesPerSecond = item.bytes * 1000 / lastUpdate;
            _notify();
          }
          if (watch.elapsedMilliseconds - lastLog >= 5000) {
            lastLog = watch.elapsedMilliseconds;
            log.info(
              'transfer',
              'send_progress',
              '文件发送进度',
              fields: {
                'transferId': item.id,
                'bytes': item.bytes,
                'totalBytes': item.size,
                'elapsedMs': lastLog,
              },
            );
          }
          return chunk;
        }),
      );
      watchdog.cancel();
      hash ??= digest!.finish();
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw const FileSystemException('发送期间原文件已改变，请重新添加');
      }
      if (_cancelled.contains(item.id)) throw const HttpException('传输已取消');
      item.status = TransferStatus.hashing;
      _notify();
      final response = await request.close().timeout(
        const Duration(minutes: 5),
      );
      final data = await _readJson(response);
      if (response.statusCode != 200 || data['sha256'] != hash) {
        throw HttpException('${data['error'] ?? '接收端校验失败'}');
      }
      if (streaming) {
        if (data['commitRequired'] != true) {
          throw const HttpException('接收端未完成校验协商');
        }
        request = await _client.postUrl(
          peer.uri('/v1/files/${item.id}/commit'),
        );
        _requests[item.id] = request;
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'token': token, 'sha256': hash}));
        final committed = await request.close().timeout(
          const Duration(seconds: 30),
        );
        final result = await _readJson(committed);
        if (committed.statusCode != 200 || result['sha256'] != hash) {
          throw HttpException('${result['error'] ?? '接收端未确认文件完成'}');
        }
      }
      item
        ..status = TransferStatus.complete
        ..bytes = item.size;
      log.info(
        'transfer',
        'send_complete',
        '文件发送与校验完成',
        fields: {
          'transferId': item.id,
          'peerId': peer.id,
          'bytes': item.size,
          'elapsedMs': total.elapsedMilliseconds,
          'sha256': hash,
        },
      );
    } catch (e, stack) {
      request?.abort();
      item
        ..status = _cancelled.contains(item.id)
            ? TransferStatus.cancelled
            : TransferStatus.failed
        ..error = e.toString();
      log.warning(
        'transfer',
        'send_failed',
        '文件发送未完成',
        error: e,
        stack: stack,
        fields: {
          'transferId': item.id,
          'bytes': item.bytes,
          'totalBytes': item.size,
          'status': item.status.name,
        },
      );
    } finally {
      watchdog?.cancel();
      digest?.closeNative();
      _notify(persist: true);
    }
  }

  Future<void> _cancelRemote(Peer peer, String offerId) async {
    try {
      final request = await _client.postUrl(peer.uri('/v1/cancel'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'offerId': offerId}));
      await (await request.close().timeout(
        const Duration(seconds: 8),
      )).drain<void>();
    } catch (error) {
      log.warning(
        'transfer',
        'remote_cancel_failed',
        '未能通知对方取消传输',
        error: error,
        fields: {'offerId': offerId, 'peerId': peer.id},
      );
    }
  }

  void cancel(TransferItem item) {
    final session = _outgoingOffers[item.id];
    final affected = session == null
        ? [item]
        : transfers
              .where(
                (f) =>
                    _outgoingOffers[f.id]?.offerId == session.offerId &&
                    f.active,
              )
              .toList();
    for (final file in affected) {
      _cancelled.add(file.id);
      _requests[file.id]?.abort();
      file.status = TransferStatus.cancelled;
      unawaited(_discardReceive(file.id, TransferStatus.cancelled, '接收已取消'));
    }
    log.info(
      'transfer',
      'cancel_requested',
      '已取消传输',
      fields: {'transferId': item.id, 'fileCount': affected.length},
    );
    if (session != null) {
      unawaited(_cancelRemote(session.peer, session.offerId));
    }
    _notify(persist: true);
  }

  Future<void> retry(TransferItem item) async {
    final peer = peers[item.peerId];
    if (!item.outgoing ||
        item.sourcePath == null ||
        peer == null ||
        !peer.online) {
      throw const FormatException('设备离线，暂时无法重试');
    }
    if (!await File(item.sourcePath!).exists()) {
      throw const FileSystemException('原文件不存在');
    }
    await sendFiles(peer, [
      LocalFile(
        path: item.sourcePath!,
        name: item.name,
        size: await File(item.sourcePath!).length(),
        relativePath: item.relativePath,
      ),
    ], groupId: item.groupId);
  }

  void _listenSocket(WebSocket socket, String host, {Peer? knownPeer}) {
    Peer? peer = knownPeer;
    socket.pingInterval = const Duration(seconds: 15);
    socket.listen(
      (raw) {
        try {
          if (raw is! String || raw.length > 65536) {
            socket.close(WebSocketStatus.messageTooBig);
            return;
          }
          final data = jsonDecode(raw) as Map<String, dynamic>;
          if (data['type'] == 'hello') {
            final candidate = Map<String, dynamic>.from(data['peer'] as Map);
            if (candidate['id'] == id ||
                (knownPeer != null && candidate['id'] != knownPeer.id)) {
              socket.close();
              return;
            }
            peer = _upsert(candidate, host);
            _sockets[peer!.id] = socket;
          } else if (data['type'] == 'message' && peer != null) {
            final text = data['text'] as String;
            final messageId = data['id'] as String;
            if (text.trim().isEmpty ||
                text.length > 16000 ||
                !RegExp(r'^[a-f0-9]{32}$').hasMatch(messageId)) {
              throw const FormatException('无效的消息');
            }
            if (!messages.any((m) => m.id == messageId)) {
              messages.add(
                ChatMessage(
                  id: messageId,
                  peerId: peer!.id,
                  text: text,
                  outgoing: false,
                  delivery: 'delivered',
                  read: _viewedConversation == peer!.id,
                ),
              );
            }
            socket.add(jsonEncode({'type': 'ack', 'id': messageId}));
            _notify(persist: true);
          } else if (data['type'] == 'ack') {
            _acks.remove('${peer?.id}:${data['id']}')?.complete();
          }
        } catch (error, stack) {
          log.warning(
            'chat',
            'invalid_frame',
            '消息会话收到无效内容',
            error: error,
            stack: stack,
          );
          socket.close(WebSocketStatus.policyViolation);
        }
      },
      onDone: () {
        if (peer != null && identical(_sockets[peer!.id], socket)) {
          _sockets.remove(peer!.id);
        }
        _notify();
      },
      onError: (Object error) {
        log.warning(
          'chat',
          'socket_error',
          '消息连接异常',
          error: error,
          fields: {'peerId': peer?.id},
        );
        if (peer != null && identical(_sockets[peer!.id], socket)) {
          _sockets.remove(peer!.id);
        }
        _notify();
      },
    );
  }

  Future<void> sendMessage(Peer peer, String text, {ChatMessage? retry}) async {
    text = text.trim();
    if (text.isEmpty || text.length > 16000) {
      throw const FormatException('消息长度应为 1 至 16000 字符');
    }
    final message =
        retry ??
        ChatMessage(id: newId(), peerId: peer.id, text: text, outgoing: true);
    if (retry == null) messages.add(message);
    message.delivery = 'pending';
    _notify(persist: true);
    final key = '${peer.id}:${message.id}';
    try {
      var socket = _sockets[peer.id];
      if (socket == null || socket.readyState != WebSocket.open) {
        final endpoint = await _verifyPeerEndpoint(peer);
        socket = await WebSocket.connect(
          endpoint.uri('/v1/chat').replace(scheme: 'ws').toString(),
        ).timeout(const Duration(seconds: 8));
        _listenSocket(socket, endpoint.host, knownPeer: peer);
        _sockets[peer.id] = socket;
        socket.add(jsonEncode({'type': 'hello', 'peer': info}));
      }
      final ack = Completer<void>();
      _acks[key] = ack;
      socket.add(
        jsonEncode({'type': 'message', 'id': message.id, 'text': text}),
      );
      await ack.future.timeout(const Duration(seconds: 10));
      message.delivery = 'delivered';
      log.info(
        'chat',
        'message_delivered',
        '消息已送达',
        fields: {
          'peerId': peer.id,
          'messageId': message.id,
          'characters': text.length,
        },
      );
    } catch (error, stack) {
      message.delivery = 'failed';
      log.warning(
        'chat',
        'message_failed',
        '消息发送失败',
        error: error,
        stack: stack,
        fields: {
          'peerId': peer.id,
          'messageId': message.id,
          'characters': text.length,
        },
      );
    } finally {
      _acks.remove(key);
      _notify(persist: true);
    }
  }

  Future<void> updateSettings({String? deviceName, String? directory}) async {
    if (deviceName != null) {
      if (deviceName.trim().isEmpty || deviceName.trim().length > 64) {
        throw const FormatException('设备名称应为 1 至 64 字符');
      }
      name = deviceName.trim();
    }
    if (directory != null) {
      final folder = await Directory(directory).create(recursive: true);
      final probe = File(p.join(folder.path, '.nearlink-write-${newId()}'));
      await probe.writeAsString('');
      await probe.delete();
      saveDirectory = folder.absolute.path;
    }
    await _persist();
    log.info(
      'settings',
      'updated',
      '设备设置已保存',
      fields: {
        'nameChanged': deviceName != null,
        'directoryChanged': directory != null,
      },
    );
    refresh();
    _notify();
  }

  void clearHistory() {
    transfers.removeWhere((f) => !f.active);
    _notify(persist: true);
  }

  Future<void> _persist() {
    if (!_ownsDirectory) return Future.value();
    _lastPresenceSave = DateTime.now();
    final settings = jsonEncode({
      'id': id,
      'name': name,
      'saveDirectory': saveDirectory,
      'peers': peers.values
          .map(
            (peer) => {
              'id': peer.id,
              'name': peer.name,
              'host': peer.host,
              'port': peer.port,
              'platform': peer.platform,
              'manual': peer.manual,
              'remark': peer.remark,
              'capabilities': peer.capabilities,
              'lastSeen': peer.lastSeen?.toUtc().toIso8601String(),
            },
          )
          .toList(),
      'groups': groups.values.map((g) => g.toJson(local: true)).toList(),
    });
    final history = jsonEncode({
      'transfers': transfers.take(300).map((f) => f.toJson()).toList(),
      'messages': messages
          .skip(messages.length > 1000 ? messages.length - 1000 : 0)
          .map((m) => m.toJson())
          .toList(),
    });
    _saveQueue = _saveQueue
        .catchError((Object _) {})
        .then((_) async {
          await _writeAtomic('settings.json', settings);
          await _writeAtomic('history.json', history);
        })
        .catchError((Object e) {
          error = '本地记录保存失败：$e';
          log.error('storage', 'records_write_failed', '本地记录保存失败', error: e);
          if (!_closed) _changes.add(null);
        });
    return _saveQueue;
  }

  Future<void> _writeAtomic(String name, String contents) async {
    final temporary = File(p.join(dataDirectory.path, '$name.tmp'));
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(p.join(dataDirectory.path, name));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    log.info('network', 'service_stopping', '正在停止局域网服务');
    _heartbeat?.cancel();
    _saveTimer?.cancel();
    for (final offer in incoming) {
      if (!offer.decision.isCompleted) offer.decision.complete(false);
    }
    for (final socket in _sockets.values.toSet()) {
      unawaited(socket.close());
    }
    await _discovery.close();
    for (final item in transfers.where((item) => item.active)) {
      _cancelled.add(item.id);
    }
    _client.close(force: true);
    await _server?.close(force: true);
    _server = null;
    await Future.wait(
      _activeReceives.toList().map(
        (operation) => operation.catchError((Object error) {
          log.warning(
            'transfer',
            'shutdown_receive_interrupted',
            '退出时中断接收请求',
            error: error,
          );
        }),
      ),
    );
    for (final id in _pendingReceives.keys.toList()) {
      await _discardReceive(id, TransferStatus.cancelled, '程序已退出');
    }
    await _persist();
    await _instanceLock?.unlock();
    await _instanceLock?.close();
    _ownsDirectory = false;
    await _completedTransfers.close();
    await _changes.close();
    log.info('network', 'service_stopped', '局域网服务已停止');
    if (_ownsLog) await log.close();
  }
}
