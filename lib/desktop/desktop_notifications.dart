import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications_windows/flutter_local_notifications_windows.dart';
import 'package:path/path.dart' as p;

import '../lan_service.dart';
import '../models.dart';

abstract interface class NotificationPlatform {
  Future<void> initialize(void Function(String id, String action) onAction);
  Future<bool> isAllowed();
  Future<void> showOffer(IncomingOffer offer, {required bool sound});
  Future<void> showTest({required bool sound});
  Future<void> showCompletion(
    TransferCompletion completion, {
    required bool sound,
  });
  Future<void> showMessages(
    String peerId,
    String name,
    int count,
    String preview, {
    required bool sound,
  });
  Future<void> playMessageSound();
  Future<void> dismiss(String id);
  Future<void> openSettings();
  void dispose();
}

class WindowsNotificationPlatform implements NotificationPlatform {
  WindowsNotificationPlatform(Directory directory) {
    final digest = sha256
        .convert(
          utf8.encode(p.normalize(directory.absolute.path).toLowerCase()),
        )
        .toString();
    final standard = p.join(
      Platform.environment['LOCALAPPDATA'] ?? directory.parent.path,
      'NearLink',
    );
    appId = p.equals(directory.absolute.path, standard)
        ? 'NearLink.Desktop'
        : 'NearLink.Profile.${digest.substring(0, 16)}';
    guid =
        '${digest.substring(0, 8)}-${digest.substring(8, 12)}-'
        '${digest.substring(12, 16)}-${digest.substring(16, 20)}-'
        '${digest.substring(20, 32)}';
  }

  late final String appId, guid;
  FlutterLocalNotificationsWindows? _plugin;
  static const _native = MethodChannel('nearlink/lifecycle');

  int _tag(String id) => id == 'test'
      ? 0
      : int.parse(
              sha256.convert(utf8.encode(id)).toString().substring(0, 7),
              radix: 16,
            ) +
            1;

  String _payload(String id, String action) =>
      jsonEncode({'id': id, 'action': action});

  @override
  Future<void> initialize(
    void Function(String id, String action) onAction,
  ) async {
    final plugin = _plugin ??= FlutterLocalNotificationsWindows();
    final initialized = await plugin.initialize(
      settings: WindowsInitializationSettings(
        appName: '邻传 NearLink',
        appUserModelId: appId,
        guid: guid,
        iconPath: p.join(
          p.dirname(Platform.resolvedExecutable),
          'data',
          'flutter_assets',
          'windows',
          'runner',
          'resources',
          'app_icon.ico',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        try {
          final data =
              jsonDecode(response.payload ?? '') as Map<String, dynamic>;
          if (data['id'] is String && data['action'] is String) {
            onAction(data['id'] as String, data['action'] as String);
          }
        } on FormatException {
          // Ignore activations that do not belong to this app's notification flow.
        } on TypeError {
          // Windows can retain notifications from an earlier app version.
        }
      },
    );
    if (!initialized) {
      throw StateError('Windows notification registration failed');
    }
    await _native.invokeMethod<void>('clearNotification', {'appId': appId});
  }

  @override
  Future<bool> isAllowed() async =>
      await _native.invokeMethod<bool>('notificationsAllowed', {
        'appId': appId,
      }) ??
      false;

  @override
  Future<void> showOffer(
    IncomingOffer offer, {
    required bool sound,
  }) => _plugin!.show(
    id: _tag(offer.id),
    title:
        '${offer.peer.displayName}${offer.groupName == null ? '' : ' · ${offer.groupName}'} 想发来 ${offer.files.length} 个文件',
    body:
        '${formatBytes(offer.size)} · ${offer.files.first.name}'
        '${offer.files.length > 1 ? ' 等' : ''}',
    payload: _payload(offer.id, 'open'),
    notificationDetails: WindowsNotificationDetails(
      audio: sound ? null : WindowsNotificationAudio.silent(),
      actions: [
        WindowsAction(content: '接收', arguments: _payload(offer.id, 'accept')),
        WindowsAction(content: '拒绝', arguments: _payload(offer.id, 'reject')),
      ],
    ),
  );

  @override
  Future<void> showTest({required bool sound}) => _plugin!.show(
    id: 0,
    title: '邻传通知已就绪',
    body: '文件请求、传输完成或未读消息将在这里提醒你。',
    payload: _payload('test', 'open'),
    notificationDetails: WindowsNotificationDetails(
      audio: sound ? null : WindowsNotificationAudio.silent(),
    ),
  );

  @override
  Future<void> showMessages(
    String peerId,
    String name,
    int count,
    String preview, {
    required bool sound,
  }) => _plugin!.show(
    id: _tag('chat:$peerId'),
    title: '$name · $count 条未读消息',
    body: String.fromCharCodes(preview.runes.take(180)),
    payload: _payload('chat:$peerId', 'open'),
    notificationDetails: WindowsNotificationDetails(
      audio: sound ? null : WindowsNotificationAudio.silent(),
    ),
  );

  @override
  Future<void> showCompletion(
    TransferCompletion completion, {
    required bool sound,
  }) => _plugin!.show(
    id: _tag('transfer:${completion.id}'),
    title: completion.title,
    body: completion.summary,
    payload: _payload('transfer:${completion.id}', 'open'),
    notificationDetails: WindowsNotificationDetails(
      audio: sound ? null : WindowsNotificationAudio.silent(),
      actions: [
        WindowsAction(
          content: '查看记录',
          arguments: _payload('transfer:${completion.id}', 'open'),
        ),
      ],
    ),
  );

  @override
  Future<void> playMessageSound() =>
      _native.invokeMethod<void>('playMessageSound');

  @override
  Future<void> dismiss(String id) => _native.invokeMethod<void>(
    'clearNotification',
    {'appId': appId, 'tag': _tag(id).toString()},
  );

  @override
  Future<void> openSettings() async {
    await Process.start('explorer.exe', ['ms-settings:notifications']);
  }

  @override
  void dispose() {
    _plugin?.dispose();
    _plugin = null;
  }
}

class DesktopNotifications extends ChangeNotifier {
  DesktopNotifications(
    this.service, {
    required this.platform,
    required this.isForeground,
    required this.showWindow,
  });

  final LanService service;
  final NotificationPlatform platform;
  final Future<bool> Function() isForeground;
  final Future<void> Function() showWindow;
  final _opened = StreamController<String>.broadcast();
  Stream<String> get opened => _opened.stream;
  final _conversations = StreamController<String>.broadcast();
  Stream<String> get conversations => _conversations.stream;
  final _historyOpened = StreamController<void>.broadcast();
  Stream<void> get historyOpened => _historyOpened.stream;
  final Set<String> _completionShown = {};
  StreamSubscription<TransferCompletion>? _completionSubscription;
  Future<void> _completionQueue = Future.value();
  DateTime? _lastCompletionSound;
  final Set<String> _messageSeen = {}, _messageShown = {};
  bool _messageBaseline = false;
  DateTime? _lastMessageSound;
  final Set<String> _seen = {}, _shown = {};
  StreamSubscription<void>? _subscription;
  bool enabled = true, sound = true, ready = false, available = false;
  bool messageEnabled = true, messageSound = true;
  bool completionEnabled = true, completionSound = true;
  bool updating = false, testing = false;
  bool? allowed;
  String? error;
  bool _closed = false, _syncing = false, _resync = false;
  Future<void>? _syncFuture;

  Future<void> initialize() async {
    try {
      final file = File(
        p.join(service.dataDirectory.path, 'notifications.json'),
      );
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        enabled = data['enabled'] as bool? ?? true;
        sound = data['sound'] as bool? ?? true;
        messageEnabled = data['messageEnabled'] as bool? ?? true;
        messageSound = data['messageSound'] as bool? ?? true;
        completionEnabled = data['completionEnabled'] as bool? ?? enabled;
        completionSound = data['completionSound'] as bool? ?? sound;
      }
    } catch (exception, stack) {
      _report('preferences_read_failed', '通知设置读取失败，已使用默认设置。', exception, stack);
    }
    await refresh();
    if (service.running) {
      _messageSeen.addAll(service.messages.map((message) => message.id));
      _messageBaseline = true;
    }
    ready = true;
    _subscription = service.changes.listen((_) => _scheduleSync());
    _completionSubscription = service.completedTransfers.listen((completion) {
      _completionQueue = _completionQueue
          .then((_) => _showCompletion(completion))
          .catchError((Object exception, StackTrace stack) {
            _report('completion_failed', '传输完成通知发送失败。', exception, stack);
          });
    });
    _scheduleSync();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_closed || updating) return;
    updating = true;
    error = null;
    notifyListeners();
    try {
      if (!available) {
        await platform.initialize(
          (id, action) => unawaited(_activate(id, action)),
        );
        available = true;
      }
      allowed = await platform.isAllowed();
      if (allowed == true) {
        _seen.removeWhere((id) => !_shown.contains(id));
        _scheduleSync();
      }
    } catch (exception, stack) {
      _report('initialize_failed', '桌面通知暂不可用，请重新检测。', exception, stack);
    } finally {
      updating = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> update({
    bool? enabled,
    bool? sound,
    bool? messageEnabled,
    bool? messageSound,
    bool? completionEnabled,
    bool? completionSound,
  }) async {
    if (updating || _closed) return;
    updating = true;
    error = null;
    notifyListeners();
    try {
      await service.dataDirectory.create(recursive: true);
      final file = File(
        p.join(service.dataDirectory.path, 'notifications.json.tmp'),
      );
      await file.writeAsString(
        jsonEncode({
          'enabled': enabled ?? this.enabled,
          'sound': sound ?? this.sound,
          'messageEnabled': messageEnabled ?? this.messageEnabled,
          'messageSound': messageSound ?? this.messageSound,
          'completionEnabled': completionEnabled ?? this.completionEnabled,
          'completionSound': completionSound ?? this.completionSound,
        }),
        flush: true,
      );
      await file.rename(
        p.join(service.dataDirectory.path, 'notifications.json'),
      );
      this.enabled = enabled ?? this.enabled;
      this.sound = sound ?? this.sound;
      this.messageEnabled = messageEnabled ?? this.messageEnabled;
      this.messageSound = messageSound ?? this.messageSound;
      this.completionEnabled = completionEnabled ?? this.completionEnabled;
      this.completionSound = completionSound ?? this.completionSound;
      if (!this.completionEnabled) {
        for (final id in _completionShown.toList()) {
          await _dismissCompletion(id);
        }
      }
      if (!this.enabled) {
        for (final id in [..._shown, 'test']) {
          await _dismiss(id);
        }
      } else if (enabled == true) {
        _seen.clear();
        _scheduleSync();
      }
      if (!this.messageEnabled) {
        for (final peerId in _messageShown.toList()) {
          await _dismissChat(peerId);
        }
      }
    } catch (exception, stack) {
      _report('preferences_write_failed', '通知设置未能保存，请重试。', exception, stack);
      rethrow;
    } finally {
      updating = false;
      if (!_closed) notifyListeners();
    }
  }

  void _scheduleSync() {
    if (_closed) return;
    _resync = true;
    if (!_syncing) _syncFuture = _syncLoop();
  }

  Future<void> _showCompletion(TransferCompletion completion) async {
    if (_closed || !available) return;
    final foreground = await isForeground();
    if (_closed) return;
    final now = DateTime.now();
    final playSound =
        completionSound &&
        (_lastCompletionSound == null ||
            now.difference(_lastCompletionSound!) >=
                const Duration(seconds: 2));
    if (foreground || !completionEnabled) {
      if (playSound) {
        await platform.playMessageSound();
        _lastCompletionSound = now;
      }
      return;
    }
    allowed = await platform.isAllowed();
    if (_closed || !completionEnabled || allowed != true) return;
    await platform.showCompletion(completion, sound: playSound);
    if (playSound) _lastCompletionSound = now;
    _completionShown.add(completion.id);
    if (_closed || !completionEnabled) {
      await _dismissCompletion(completion.id);
    }
    while (_completionShown.length > 32) {
      await _dismissCompletion(_completionShown.first);
    }
    service.log.info(
      'notifications',
      'completion_notified',
      completion.title,
      fields: {'batchId': completion.id, 'files': completion.fileCount},
    );
  }

  Future<void> _dismissCompletion(String id) async {
    _completionShown.remove(id);
    await _dismiss('transfer:$id');
  }

  Future<void> _syncLoop() async {
    _syncing = true;
    try {
      while (_resync && !_closed) {
        _resync = false;
        await _sync();
        await _syncMessages();
      }
    } catch (exception, stack) {
      _report('show_failed', '通知发送失败，请重新检测或发送测试通知。', exception, stack);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncMessages() async {
    if (!service.running || _closed) return;
    if (!_messageBaseline) {
      _messageSeen.addAll(service.messages.map((message) => message.id));
      _messageBaseline = true;
      return;
    }
    final unread = service.unreadConversations;
    final peers = unread.map((entry) => entry.peerId).toSet();
    for (final peerId in _messageShown.difference(peers).toList()) {
      await _dismissChat(peerId);
    }
    final fresh = service.messages
        .where(
          (message) => !message.outgoing && !_messageSeen.contains(message.id),
        )
        .toList();
    _messageSeen.addAll(service.messages.map((message) => message.id));
    _messageSeen.retainAll(
      service.messages.map((message) => message.id).toSet(),
    );
    final newPeers = fresh
        .where((message) => !message.read)
        .map((message) => message.conversationId)
        .toSet();
    if (newPeers.isEmpty || !available || _closed) return;
    final foreground = await isForeground();
    final now = DateTime.now();
    final soundDue =
        messageSound &&
        (_lastMessageSound == null ||
            now.difference(_lastMessageSound!) >= const Duration(seconds: 2));
    var sounded = false;
    if (!foreground && messageEnabled) {
      allowed = await platform.isAllowed();
      if (allowed == true) {
        for (final entry in unread.where(
          (entry) => newPeers.contains(entry.peerId),
        )) {
          if (_closed ||
              !messageEnabled ||
              service.unreadFor(entry.peerId) == 0) {
            continue;
          }
          final playSound = soundDue && !sounded;
          await platform.showMessages(
            entry.peerId,
            service.conversationName(entry.peerId),
            service.unreadFor(entry.peerId),
            service.messagePreview(entry.latest),
            sound: playSound,
          );
          _messageShown.add(entry.peerId);
          if (playSound) {
            sounded = true;
            _lastMessageSound = now;
          }
          service.log.info(
            'notifications',
            'message_notified',
            '已发送未读消息通知',
            fields: {'peerId': entry.peerId, 'unread': entry.count},
          );
          if (service.unreadFor(entry.peerId) == 0) {
            await _dismissChat(entry.peerId);
          }
        }
      }
    } else if (soundDue && fresh.any((message) => !message.read)) {
      // Foreground messages in other conversations still deserve one audible cue.
      await platform.playMessageSound();
      _lastMessageSound = now;
    }
  }

  Future<void> _dismissChat(String peerId) async {
    _messageShown.remove(peerId);
    await _dismiss('chat:$peerId');
  }

  Future<void> _sync() async {
    final current = service.incoming
        .where((offer) => !offer.decision.isCompleted)
        .toList();
    final active = current.map((offer) => offer.id).toSet();
    _seen.retainAll(active);
    for (final id in _shown.difference(active).toList()) {
      await _dismiss(id);
    }
    if (!enabled || !available || _closed) return;
    final fresh = current.where((offer) => !_seen.contains(offer.id)).toList();
    if (fresh.isEmpty) return;
    _seen.addAll(fresh.map((offer) => offer.id));
    if (await isForeground() || _closed || !enabled) return;
    allowed = await platform.isAllowed();
    if (allowed != true) {
      notifyListeners();
      return;
    }
    for (final offer in fresh) {
      if (_closed ||
          !enabled ||
          offer.decision.isCompleted ||
          !service.incoming.contains(offer)) {
        continue;
      }
      await platform.showOffer(offer, sound: sound);
      _shown.add(offer.id);
      service.log.info(
        'notifications',
        'offer_notified',
        '已发送文件接收通知',
        fields: {
          'offerId': offer.id,
          'peerId': offer.peer.id,
          'files': offer.files.length,
        },
      );
      if (!enabled ||
          _closed ||
          offer.decision.isCompleted ||
          !service.incoming.contains(offer)) {
        await _dismiss(offer.id);
      }
    }
  }

  Future<void> _activate(String id, String action) async {
    if (_closed || !['open', 'accept', 'reject'].contains(action)) return;
    try {
      if (id.startsWith('transfer:')) {
        if (action != 'open') return;
        await showWindow();
        if (!_closed) _historyOpened.add(null);
        await _dismissCompletion(id.substring(9));
        return;
      }
      if (id.startsWith('chat:')) {
        if (action != 'open') return;
        final peerId = id.substring(5);
        await showWindow();
        if (!_closed) _conversations.add(peerId);
        await _dismissChat(peerId);
        return;
      }
      if (id == 'test') {
        await showWindow();
        await _dismiss(id);
        return;
      }
      final offer = service.incoming
          .where((offer) => offer.id == id && !offer.decision.isCompleted)
          .firstOrNull;
      if (offer != null && action != 'open') {
        service.decide(offer, action == 'accept');
      }
      if (action == 'open' || offer == null) {
        await showWindow();
        if (!_closed) _opened.add(id);
      }
      await _dismiss(id);
    } catch (exception, stack) {
      _report('activation_failed', '通知操作未完成，请打开邻传处理接收请求。', exception, stack);
    }
  }

  Future<void> test() async {
    if (testing || !available || !enabled || _closed) return;
    testing = true;
    error = null;
    notifyListeners();
    try {
      allowed = await platform.isAllowed();
      if (allowed == true) await platform.showTest(sound: sound);
    } catch (exception, stack) {
      _report('test_failed', '测试通知发送失败，请检查 Windows 通知设置。', exception, stack);
    } finally {
      testing = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> openSettings() async {
    try {
      await platform.openSettings();
    } catch (exception, stack) {
      _report('settings_open_failed', '无法打开 Windows 通知设置。', exception, stack);
    }
  }

  Future<void> testMessageSound() async {
    if (!available || testing || _closed) return;
    testing = true;
    notifyListeners();
    try {
      await platform.playMessageSound();
    } catch (exception, stack) {
      _report('sound_failed', '提示音播放失败，请检查 Windows 音量设置。', exception, stack);
    } finally {
      testing = false;
      if (!_closed) notifyListeners();
    }
  }

  void _report(
    String event,
    String message,
    Object exception,
    StackTrace stack,
  ) {
    service.log.warning(
      'notifications',
      event,
      message,
      error: exception,
      stack: stack,
    );
    if (!_closed) {
      error = message;
      notifyListeners();
    }
  }

  Future<void> _dismiss(String id) async {
    _shown.remove(id);
    try {
      await platform.dismiss(id);
    } catch (exception, stack) {
      service.log.warning(
        'notifications',
        'dismiss_failed',
        '通知清理失败',
        error: exception,
        stack: stack,
      );
    }
  }

  Future<void> _dismissAll() async {
    for (final id in _completionShown.toList()) {
      await _dismissCompletion(id);
    }
    for (final id in [..._shown, 'test']) {
      await _dismiss(id);
    }
    for (final peerId in _messageShown.toList()) {
      await _dismissChat(peerId);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _completionSubscription?.cancel();
    await _completionQueue;
    await _syncFuture;
    try {
      if (available) await _dismissAll();
    } catch (exception, stack) {
      service.log.warning(
        'notifications',
        'dismiss_failed',
        '通知清理失败',
        error: exception,
        stack: stack,
      );
    } finally {
      platform.dispose();
      await _opened.close();
      await _conversations.close();
      await _historyOpened.close();
    }
  }
}
