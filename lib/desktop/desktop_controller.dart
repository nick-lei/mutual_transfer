import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../screenshot/screenshot_controller.dart';
import '../logging/app_log.dart';
import '../lan_service.dart';
import '../models.dart';

abstract interface class StartupRegistration {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

class WindowsStartupRegistration implements StartupRegistration {
  WindowsStartupRegistration() {
    launchAtStartup.setup(
      appName: 'NearLink',
      appPath: '"${Platform.resolvedExecutable}"',
      args: ['--autostart'],
    );
  }

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<void> setEnabled(bool enabled) async {
    final success = enabled
        ? await launchAtStartup.enable()
        : await launchAtStartup.disable();
    if (!success || await isEnabled() != enabled) {
      throw StateError('Windows startup registration failed');
    }
  }
}

class DesktopController extends ChangeNotifier
    with WindowListener, TrayListener {
  DesktopController(
    this.dataDirectory, {
    required this.startup,
    required this.onExit,
    this.screenshots,
    this.log,
    this.service,
  });

  final Directory dataDirectory;
  final StartupRegistration startup;
  final Future<void> Function() onExit;
  final ScreenshotController? screenshots;
  final AppLog? log;
  final LanService? service;
  final _conversations = StreamController<String>.broadcast();
  Stream<String> get conversations => _conversations.stream;
  final _incomingOffers = StreamController<String>.broadcast();
  Stream<String> get incomingOffers => _incomingOffers.stream;
  StreamSubscription<void>? _serviceSubscription;
  String? _traySnapshot;
  bool _traySyncing = false, _trayResync = false;
  Future<void>? _traySyncFuture;
  bool isForeground = false;
  bool? sidebarCollapsed;
  bool closeToTray = true;
  bool startAtLogin = false;
  bool ready = false;
  bool trayReady = false;
  bool updating = false;
  String? settingsError;
  String? trayError;
  bool _exiting = false;
  bool _hiding = false;
  Future<void>? _exitFuture;
  static const _lifecycle = MethodChannel('nearlink/lifecycle');

  Future<void> initialize() async {
    _lifecycle.setMethodCallHandler((call) async {
      if (call.method == 'openConversation' && call.arguments is String) {
        final peerId = call.arguments as String;
        await showWindow();
        _conversations.add(peerId);
        return;
      }
      if (call.method == 'markMessagesRead') {
        service?.markMessagesRead();
        return;
      }
      if (call.method == 'openIncomingOffer' && call.arguments is String) {
        await _openIncomingOffer(call.arguments as String);
        return;
      }
      if (call.method != 'exitForUpdate') throw MissingPluginException();
      log?.info('desktop', 'exit_for_update', '收到安装程序的退出请求');
      await exitApp();
    });
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      final file = File(p.join(dataDirectory.path, 'desktop.json'));
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        sidebarCollapsed = json['sidebarCollapsed'] as bool?;
        closeToTray = json['closeToTray'] as bool? ?? true;
      }
    } catch (error, stack) {
      log?.warning(
        'desktop',
        'preferences_read_failed',
        '窗口偏好读取失败',
        error: error,
        stack: stack,
      );
      settingsError = '窗口偏好读取失败，已使用默认设置。';
    }
    try {
      startAtLogin = await startup.isEnabled();
    } catch (error, stack) {
      log?.warning(
        'desktop',
        'startup_read_failed',
        '开机自启状态读取失败',
        error: error,
        stack: stack,
      );
      settingsError = '无法读取开机自启状态，请重试。';
    }
    try {
      await trayManager.setIcon('windows/runner/resources/app_icon.ico');
      await trayManager.setToolTip('邻传 NearLink');
      trayReady = true;
      await _updateTrayMenu();
      screenshots?.addListener(_onScreenshotChanged);
    } catch (error, stack) {
      log?.warning(
        'desktop',
        'tray_initialize_failed',
        '任务托盘初始化失败',
        error: error,
        stack: stack,
      );
      trayReady = false;
      trayError = '任务托盘不可用，关闭窗口将退出邻传。';
      try {
        await trayManager.destroy();
      } catch (_) {}
    }
    ready = true;
    _serviceSubscription = service?.changes.listen((_) => _scheduleTraySync());
    _scheduleTraySync();
    notifyListeners();
  }

  Future<void> _savePreferences({bool? collapsed, bool? tray}) async {
    await dataDirectory.create(recursive: true);
    final file = File(p.join(dataDirectory.path, 'desktop.json.tmp'));
    await file.writeAsString(
      jsonEncode({
        'sidebarCollapsed': collapsed ?? sidebarCollapsed,
        'closeToTray': tray ?? closeToTray,
      }),
      flush: true,
    );
    await file.rename(p.join(dataDirectory.path, 'desktop.json'));
  }

  Future<void> _update(Future<void> Function() action) async {
    if (updating || _exiting) return;
    updating = true;
    settingsError = null;
    notifyListeners();
    try {
      await action();
    } catch (error, stack) {
      log?.warning(
        'desktop',
        'preferences_write_failed',
        '窗口设置保存失败',
        error: error,
        stack: stack,
      );
      settingsError = '设置未能保存，请检查本机配置目录或 Windows 启动项后重试。';
      rethrow;
    } finally {
      updating = false;
      notifyListeners();
    }
  }

  Future<void> setSidebarCollapsed(bool value) => _update(() async {
    await _savePreferences(collapsed: value);
    sidebarCollapsed = value;
  });

  Future<void> setCloseToTray(bool value) => _update(() async {
    await _savePreferences(tray: value);
    closeToTray = value;
  });

  Future<void> setStartAtLogin(bool value) => _update(() async {
    await startup.setEnabled(value);
    startAtLogin = value;
    log?.info(
      'desktop',
      'startup_changed',
      '开机自启设置已更新',
      fields: {'enabled': value},
    );
  });

  Future<void> showWindow() async {
    if (_exiting) return;
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openIncomingOffer(String id) async {
    await showWindow();
    if (!_exiting) _incomingOffers.add(id);
  }

  Future<void> showInbox({bool inspectable = false}) async {
    _scheduleTraySync();
    await _traySyncFuture;
    final visible = await _lifecycle.invokeMethod<bool>('showTrayInbox', {
      'inspectable': inspectable,
    });
    log?.info(
      'desktop',
      'tray_inbox_opened',
      '已打开托盘未读列表',
      fields: {'visible': visible, 'unread': service?.unreadCount},
    );
  }

  void _setForeground(bool value) {
    if (isForeground == value || _exiting) return;
    isForeground = value;
    notifyListeners();
  }

  @override
  void onWindowFocus() => _setForeground(true);
  @override
  void onWindowBlur() => _setForeground(false);
  @override
  void onWindowMinimize() => _setForeground(false);

  @override
  void onWindowClose() {
    unawaited(handleWindowClose());
  }

  Future<void> handleWindowClose() async {
    if (_exiting || _hiding) return;
    if (screenshots?.capturing == true) {
      screenshots?.onCancel?.call();
      return;
    }
    if (closeToTray && trayReady) {
      _hiding = true;
      _setForeground(false);
      try {
        await windowManager.hide();
      } finally {
        _hiding = false;
      }
    } else {
      await exitApp();
    }
  }

  Future<void> exitApp() => _exitFuture ??= _performExit();

  Future<void> _performExit() async {
    _exiting = true;
    await _serviceSubscription?.cancel();
    screenshots?.removeListener(_onScreenshotChanged);
    try {
      await onExit();
    } finally {
      try {
        if (trayReady) await trayManager.destroy();
      } finally {
        trayReady = false;
        await windowManager.destroy();
      }
    }
  }

  void _onScreenshotChanged() => unawaited(_refreshTrayMenu());

  void _scheduleTraySync() {
    if (service == null || !trayReady || _exiting) return;
    _trayResync = true;
    if (!_traySyncing) _traySyncFuture = _syncTrayInbox();
  }

  Future<void> _syncTrayInbox() async {
    _traySyncing = true;
    try {
      while (_trayResync && !_exiting) {
        _trayResync = false;
        final pending = service!.incoming
            .where((offer) => !offer.decision.isCompleted)
            .toList();
        final entries = [
          for (final offer in pending)
            {
              'type': 'file',
              'offerId': offer.id,
              'name': offer.peer.displayName,
              'count': offer.files.length,
              'preview':
                  '待接收 · ${offer.files.firstOrNull?.name ?? ''}${offer.files.length > 1 ? ' 等 ${offer.files.length} 个文件' : ''} · ${formatBytes(offer.size)}',
            },
          ...service!.unreadConversations.map(
            (entry) => {
              'type': 'message',
              'peerId': entry.peerId,
              'name': service!.conversationName(entry.peerId),
              'count': entry.count,
              'preview': String.fromCharCodes(
                service!
                    .messagePreview(entry.latest)
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .runes
                    .take(100),
              ),
            },
          ),
        ];
        final snapshot = jsonEncode(entries);
        if (snapshot == _traySnapshot) continue;
        final count = service!.unreadCount;
        await trayManager.setToolTip(
          count == 0 && pending.isEmpty
              ? '邻传 NearLink'
              : '邻传 · ${[if (pending.isNotEmpty) '${pending.length} 个文件请求待处理', if (count > 0) '$count 条未读消息'].join(' · ')}',
        );
        await _updateTrayMenu();
        // tray_manager reapplies its base icon when changing the tooltip.
        final attention = await _lifecycle.invokeMapMethod<String, dynamic>(
          'updateTrayInbox',
          {'entries': entries},
        );
        _traySnapshot = snapshot;
        if (attention != null) {
          log?.info(
            'desktop',
            'attention_updated',
            '桌面待处理提醒已更新',
            fields: {
              'pendingOffers': pending.length,
              'unreadMessages': count,
              ...attention,
            },
          );
        }
      }
    } catch (error, stack) {
      log?.warning(
        'desktop',
        'tray_inbox_failed',
        '托盘待处理提醒更新失败',
        error: error,
        stack: stack,
      );
    } finally {
      _traySyncing = false;
    }
  }

  Future<void> _refreshTrayMenu() async {
    try {
      if (trayReady && !_exiting) await _updateTrayMenu();
    } catch (_) {}
  }

  Future<void> _updateTrayMenu() => trayManager.setContextMenu(
    Menu(
      items: [
        for (final offer in service?.incoming ?? <IncomingOffer>[])
          if (!offer.decision.isCompleted)
            MenuItem(
              key: 'offer:${offer.id}',
              label: '${offer.peer.displayName} · ${offer.files.length} 个文件待接收',
            ),
        if (service?.incoming.any((offer) => !offer.decision.isCompleted) ==
            true)
          MenuItem.separator(),
        if ((service?.unreadCount ?? 0) > 0) ...[
          for (final entry in service!.unreadConversations)
            MenuItem(
              key: 'chat:${entry.peerId}',
              label:
                  '${service!.conversationName(entry.peerId)} (${entry.count})',
            ),
          MenuItem(key: 'read-all', label: '全部标为已读'),
          MenuItem.separator(),
        ],
        MenuItem(key: 'show', label: '显示邻传'),
        if (screenshots != null)
          MenuItem(
            key: 'capture',
            label: '截图',
            disabled: !screenshots!.ready || screenshots!.capturing,
          ),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出邻传'),
      ],
    ),
  );

  @override
  void onTrayIconMouseDown() => unawaited(showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key?.startsWith('offer:') == true) {
      unawaited(_openIncomingOffer(menuItem.key!.substring(6)));
      return;
    }
    if (menuItem.key?.startsWith('chat:') == true) {
      unawaited(() async {
        await showWindow();
        _conversations.add(menuItem.key!.substring(5));
      }());
      return;
    }
    switch (menuItem.key) {
      case 'read-all':
        service?.markMessagesRead();
      case 'show':
        unawaited(showWindow());
      case 'capture':
        unawaited(screenshots?.capture());
      case 'exit':
        unawaited(exitApp());
    }
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    _conversations.close();
    _incomingOffers.close();
    _lifecycle.setMethodCallHandler(null);
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    screenshots?.removeListener(_onScreenshotChanged);
    super.dispose();
  }
}
