import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../desktop/desktop_notifications.dart';
import '../lan_service.dart';
import '../models.dart';

class AndroidPaths {
  const AndroidPaths(
    this.dataDirectory,
    this.receiveDirectory,
    this.deviceName,
  );
  final String dataDirectory, receiveDirectory, deviceName;

  static const channel = MethodChannel('nearlink/android');
  static Future<AndroidPaths> load() async {
    final values = (await channel.invokeMapMethod<String, dynamic>('paths'))!;
    return AndroidPaths(
      values['dataDirectory'] as String,
      values['receiveDirectory'] as String,
      values['deviceName'] as String,
    );
  }
}

class AndroidSharedContent {
  const AndroidSharedContent({
    this.paths = const [],
    this.text = '',
    this.error,
  });
  factory AndroidSharedContent.fromMap(Map<dynamic, dynamic> values) =>
      AndroidSharedContent(
        paths: (values['paths'] as List? ?? []).cast<String>(),
        text: values['text'] as String? ?? '',
        error: values['error'] as String?,
      );
  final List<String> paths;
  final String text;
  final String? error;
}

class AndroidHost extends ChangeNotifier with WidgetsBindingObserver {
  AndroidHost(this.service, {this.channel = AndroidPaths.channel});
  final LanService service;
  final MethodChannel channel;
  final _shared = StreamController<AndroidSharedContent>.broadcast();
  final List<Map<dynamic, dynamic>> _pendingNotificationActions = [];
  bool _ready = false;
  Stream<AndroidSharedContent> get sharedContent => _shared.stream;
  void Function(String, String)? onNotificationAction;
  StreamSubscription<void>? _subscription;
  bool foreground = true, backgroundEnabled = false, updating = false;
  String? error;
  int _active = -1;
  bool _closed = false;

  Future<void> initialize() async {
    final paths = await channel.invokeMapMethod<String, dynamic>('paths');
    backgroundEnabled = paths?['backgroundEnabled'] == true;
    foreground =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;
    channel.setMethodCallHandler((call) async {
      if (_closed) return;
      switch (call.method) {
        case 'sharedContent':
          _shared.add(AndroidSharedContent.fromMap(call.arguments as Map));
        case 'notificationAction':
          final values = call.arguments as Map;
          if (_ready) {
            onNotificationAction?.call(
              values['id'] as String,
              values['action'] as String,
            );
          } else {
            _pendingNotificationActions.add(values);
          }
        case 'backgroundStopped':
          backgroundEnabled = false;
          notifyListeners();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _subscription = service.changes.listen((_) => _syncTransfers());
    await channel.invokeMethod<void>('setForeground', {
      'foreground': foreground,
    });
  }

  Future<void> ready() async {
    _ready = true;
    final pending = await channel.invokeListMethod<dynamic>('ready') ?? [];
    for (final entry in pending) {
      _shared.add(AndroidSharedContent.fromMap(entry as Map));
    }
    for (final action in _pendingNotificationActions) {
      onNotificationAction?.call(
        action['id'] as String,
        action['action'] as String,
      );
    }
    _pendingNotificationActions.clear();
    if (backgroundEnabled && foreground) {
      try {
        await channel.invokeMethod<void>('setBackground', {'enabled': true});
      } catch (exception) {
        error = '后台接收未能启动，请重新开启：$exception';
        backgroundEnabled = false;
        notifyListeners();
      }
    }
  }

  void _syncTransfers() {
    final count = service.transfers
        .where((file) => file.active && file.status != TransferStatus.waiting)
        .length;
    if (_active == count) return;
    _active = count;
    unawaited(
      _quietly(
        () =>
            channel.invokeMethod<void>('setActiveTransfers', {'count': count}),
      ),
    );
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (exception, stack) {
      service.log.warning(
        'android',
        'platform_failed',
        'Android 系统操作未完成',
        error: exception,
        stack: stack,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    unawaited(
      _quietly(
        () => channel.invokeMethod<void>('setForeground', {
          'foreground': foreground,
        }),
      ),
    );
    if (foreground && service.running) service.refresh();
    if (!_closed) notifyListeners();
  }

  Future<bool> requestNotifications() async =>
      await channel.invokeMethod<bool>('requestNotifications') ?? false;

  Future<void> setBackground(bool enabled) async {
    if (updating) return;
    updating = true;
    error = null;
    notifyListeners();
    try {
      if (enabled && !await requestNotifications()) {
        throw const FormatException('请先在系统设置中允许邻传通知。');
      }
      await channel.invokeMethod<void>('setBackground', {'enabled': enabled});
      backgroundEnabled = enabled;
    } catch (exception) {
      error = exception is FormatException
          ? exception.message
          : '后台接收设置未能保存，请重试。';
    } finally {
      updating = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> showApp() => channel.invokeMethod<void>('showApp');
  Future<void> openFile(String path) =>
      channel.invokeMethod<void>('openFile', {'path': path});
  Future<void> shareFile(String path) =>
      channel.invokeMethod<void>('shareFile', {'path': path});
  Future<bool> exportFile(String path) async =>
      await channel.invokeMethod<bool>('exportFile', {'path': path}) ?? false;

  Future<void> close() async {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    channel.setMethodCallHandler(null);
    await _shared.close();
  }
}

class AndroidNotificationPlatform implements NotificationPlatform {
  AndroidNotificationPlatform(this.host);
  final AndroidHost host;

  @override
  Future<void> initialize(
    void Function(String id, String action) onAction,
  ) async {
    host.onNotificationAction = onAction;
    final pending =
        await host.channel.invokeListMethod<dynamic>(
          'initializeNotifications',
        ) ??
        [];
    for (final entry in pending) {
      final values = entry as Map;
      if (host._ready) {
        onAction(values['id'] as String, values['action'] as String);
      } else {
        host._pendingNotificationActions.add(values);
      }
    }
  }

  Future<void> _show(
    String id,
    String title,
    String body,
    String kind,
    bool sound,
  ) => host.channel.invokeMethod<void>('showNotification', {
    'id': id,
    'title': title,
    'body': body,
    'kind': kind,
    'sound': sound,
  });

  @override
  Future<bool> isAllowed() async =>
      await host.channel.invokeMethod<bool>('notificationsAllowed') ?? false;
  @override
  Future<void> showOffer(IncomingOffer offer, {required bool sound}) => _show(
    offer.id,
    '${offer.peer.displayName} 发来 ${offer.files.length} 个文件',
    '${formatBytes(offer.size)} · ${offer.files.first.name}${offer.groupName == null ? '' : ' · ${offer.groupName}'}',
    'files',
    sound,
  );
  @override
  Future<void> showMessages(
    String peerId,
    String name,
    int count,
    String preview, {
    required bool sound,
  }) => _show(
    'chat:$peerId',
    '$name · $count 条未读消息',
    String.fromCharCodes(preview.runes.take(180)),
    'messages',
    sound,
  );
  @override
  Future<void> showCompletion(
    TransferCompletion completion, {
    required bool sound,
  }) => _show(
    'transfer:${completion.id}',
    completion.title,
    completion.summary,
    'completion',
    sound,
  );
  @override
  Future<void> showTest({required bool sound}) =>
      _show('test', '邻传通知已就绪', '文件请求、消息和传输完成会在这里提醒。', 'completion', sound);
  @override
  Future<void> playMessageSound() =>
      host.channel.invokeMethod<void>('playSound');
  @override
  Future<void> dismiss(String id) =>
      host.channel.invokeMethod<void>('dismissNotification', {'id': id});
  @override
  Future<void> openSettings() =>
      host.channel.invokeMethod<void>('notificationSettings');
  @override
  void dispose() => host.onNotificationAction = null;
}
