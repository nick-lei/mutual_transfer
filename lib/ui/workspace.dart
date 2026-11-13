import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../desktop/desktop_controller.dart';
import '../desktop/file_clipboard.dart';
import '../android/android_host.dart';
import '../desktop/desktop_settings.dart';
import '../desktop/desktop_notifications.dart';
import '../desktop/notification_settings.dart';
import '../lan_service.dart';
import '../logging/log_settings.dart';
import '../models.dart';
import '../screenshot/screenshot_controller.dart';
import '../screenshot/screenshot_settings.dart';
import 'components.dart';
import 'desktop_title_bar.dart';
import 'transfer_file_card.dart';

part 'group_workspace.dart';
part 'android_workspace.dart';
part 'chat_files.dart';
part 'chat_forward_page.dart';

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.service,
    this.screenshots,
    this.desktop,
    this.notifications,
    this.android,
  });
  final LanService service;
  final ScreenshotController? screenshots;
  final DesktopController? desktop;
  final DesktopNotifications? notifications;
  final AndroidHost? android;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  void _updateAndroid(VoidCallback action) => setState(action);
  late final StreamSubscription<void> _subscription;
  StreamSubscription<String>? _screenshotSubscription;
  StreamSubscription<String>? _notificationSubscription;
  StreamSubscription<String>? _trayOfferSubscription;
  StreamSubscription<String>? _conversationSubscription;
  StreamSubscription<String>? _messageNotificationSubscription;
  StreamSubscription<TransferCompletion>? _completionSubscription;
  StreamSubscription<void>? _completionHistorySubscription;
  StreamSubscription<AndroidSharedContent>? _sharedSubscription;
  final _sharedText = TextEditingController();
  String? _incomingOfferId;
  final _message = TextEditingController();
  final _historySearch = TextEditingController();
  final _deviceSearch = TextEditingController();
  final _deviceName = TextEditingController();
  final _chatScroll = ScrollController();
  final _pageScroll = ScrollController();
  final _incomingScroll = ScrollController();
  final List<LocalFile> _files = [];
  final Map<String, String> _drafts = {};
  String? _sendPeerId, _chatPeerId;
  int _page = 0, _historyFilter = 0, _directionFilter = 0, _deviceFilter = 0;
  bool _dragging = false, _picking = false, _incomingExpanded = false;
  bool _saving = false, _settingsDirty = false;
  bool _pickingChat = false;
  bool _choosingForward = false;
  String? _chatDragPeerId;
  void _setPickingChat(bool picking) => setState(() => _pickingChat = picking);
  void _setChatDragPeer(String? id) {
    if (!mounted || _chatDragPeerId == id) return;
    // Disabling a native drop target can synchronously report an exit in build.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setChatDragPeer(id);
      });
      return;
    }
    setState(() => _chatDragPeerId = id);
  }

  String _directory = '';
  String? _settingsError;
  bool? _sidebarCollapsed;
  bool _androidIncomingCollapsed = false;
  String? _androidPendingId;
  LanService get service => widget.service;
  List<Peer> get online =>
      service.peers.values.where((peer) => peer.online).toList();
  int _comparePeerAvailability(Peer a, Peer b) {
    final aOnline = _forwardTargetOnline(a);
    final bOnline = _forwardTargetOnline(b);
    return aOnline == bOnline
        ? 0
        : aOnline
        ? -1
        : 1;
  }

  Peer? get recipient =>
      service.peers[_sendPeerId] ??
      _groupPeer(service.groupForConversation(_sendPeerId));
  Peer? get chatPeer =>
      service.peers[_chatPeerId] ??
      _groupPeer(service.groupForConversation(_chatPeerId));
  int get activeCount => service.transfers.where((file) => file.active).length;
  int _unreadFor(String id) => service.unreadFor(id);
  int get unread => service.unreadCount;
  static const _labels = ['快速发送', '附近设备', '消息', '传输记录', '设置'];
  static const _icons = [
    LucideIcons.send,
    LucideIcons.radar,
    LucideIcons.messagesSquare,
    LucideIcons.history,
    LucideIcons.settings2,
  ];

  @override
  void initState() {
    super.initState();
    _syncSettings();
    _completionSubscription = service.completedTransfers.listen(
      _showTransferCompletion,
    );
    _completionHistorySubscription = widget.notifications?.historyOpened.listen(
      (_) {
        if (mounted) _navigate(3);
      },
    );
    widget.desktop?.addListener(_desktopChanged);
    widget.android?.addListener(_desktopChanged);
    _sharedSubscription = widget.android?.sharedContent.listen(_receiveShared);
    _conversationSubscription = widget.desktop?.conversations.listen((id) {
      final peer =
          service.peers[id] ?? _groupPeer(service.groupForConversation(id));
      if (mounted && peer != null) _openConversation(peer);
    });
    _messageNotificationSubscription = widget.notifications?.conversations
        .listen((id) {
          final peer =
              service.peers[id] ?? _groupPeer(service.groupForConversation(id));
          if (mounted && peer != null) _openConversation(peer);
        });
    _syncMessageView();
    _notificationSubscription = widget.notifications?.opened.listen(
      _openIncomingOffer,
    );
    _trayOfferSubscription = widget.desktop?.incomingOffers.listen(
      _openIncomingOffer,
    );
    _screenshotSubscription = widget.screenshots?.stagedFiles.stream.listen((
      path,
    ) {
      unawaited(_addPaths([path]));
    });
    _subscription = service.changes.listen((_) {
      if (!mounted) return;
      final followTail =
          _chatScroll.hasClients && _chatScroll.position.extentAfter < 100;
      _syncMessageView();
      setState(() {
        if (!_settingsDirty && !_saving) _syncSettings();
      });
      if (followTail) _scrollConversation();
    });
  }

  void _syncSettings() {
    _deviceName.text = service.name;
    _directory = service.saveDirectory;
  }

  void _desktopChanged() {
    if (mounted) {
      _syncMessageView();
      setState(() {});
    }
  }

  void _toggleSidebar(bool compact) {
    final desktop = widget.desktop;
    if (desktop == null) {
      setState(() => _sidebarCollapsed = !compact);
    } else {
      unawaited(_guard(() => desktop.setSidebarCollapsed(!compact)));
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _screenshotSubscription?.cancel();
    _notificationSubscription?.cancel();
    _trayOfferSubscription?.cancel();
    _conversationSubscription?.cancel();
    _messageNotificationSubscription?.cancel();
    _completionSubscription?.cancel();
    _completionHistorySubscription?.cancel();
    _sharedSubscription?.cancel();
    service.setMessageView(null, focused: false);
    widget.desktop?.removeListener(_desktopChanged);
    widget.android?.removeListener(_desktopChanged);
    _sharedText.dispose();
    for (final controller in [
      _message,
      _historySearch,
      _deviceSearch,
      _deviceName,
    ]) {
      controller.dispose();
    }
    _chatScroll.dispose();
    _pageScroll.dispose();
    _incomingScroll.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _showTransferCompletion(TransferCompletion completion) {
    if (!mounted ||
        widget.desktop?.isForeground == false ||
        widget.android?.foreground == false) {
      return;
    }
    final historyAction = IconButton(
      tooltip: '查看记录',
      color: blue,
      onPressed: () {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _navigate(3);
      },
      icon: const Icon(LucideIcons.history, size: 20),
    );
    final closeAction = IconButton(
      tooltip: '关闭',
      color: muted,
      onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      icon: const Icon(LucideIcons.x, size: 18),
    );
    final title = Text(
      completion.title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: ValueKey('transfer-completion-${completion.id}'),
        backgroundColor: Colors.white,
        elevation: 6,
        duration: const Duration(seconds: 6),
        width: MediaQuery.sizeOf(context).width > 680 ? 560 : null,
        content: completion.hasIssues
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.circleAlert,
                        color: amber,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: title),
                      closeAction,
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        for (final result in completion.recipientResults)
                          Text(
                            result,
                            style: const TextStyle(
                              fontSize: 13,
                              color: ink,
                              height: 1.6,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${completion.fileCount} 个文件 · ${completion.peerName}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                        historyAction,
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(LucideIcons.circleCheck, color: green, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 4),
                        Text(
                          completion.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  historyAction,
                  closeAction,
                ],
              ),
      ),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, stack) {
      service.log.warning(
        'ui',
        'action_failed',
        '操作未完成',
        error: e,
        stack: stack,
      );
      _toast(e is FormatException ? e.message : e.toString());
    }
  }

  void _navigate(int page) {
    setState(() {
      _page = page;
      _chatDragPeerId = null;
    });
    _syncMessageView();
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
  }

  void _openIncomingOffer(String id) {
    if (!mounted) return;
    if (!service.incoming.any(
      (offer) => offer.id == id && !offer.decision.isCompleted,
    )) {
      _toast('该接收请求已失效或已处理。');
      return;
    }
    if (widget.android != null) {
      unawaited(_androidReviewOffer(id));
      return;
    }
    setState(() {
      _page = 0;
      _incomingOfferId = id;
      _incomingExpanded = true;
    });
    _syncMessageView();
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
  }

  void _syncMessageView() => service.setMessageView(
    _page == 2 ? _chatPeerId : null,
    focused:
        !_choosingForward &&
        (widget.android?.foreground ?? widget.desktop?.isForeground ?? true),
  );

  void _openConversation(Peer peer) {
    if (_chatPeerId != null) _drafts[_chatPeerId!] = _message.text;
    setState(() {
      _chatPeerId = peer.id;
      _chatDragPeerId = null;
      _message.text = _drafts[peer.id] ?? '';
      _page = 2;
    });
    _syncMessageView();
    _scrollConversation();
  }

  void _scrollConversation() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chatScroll.hasClients) {
          _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
        }
      });

  void _prepareSend(Peer peer) {
    setState(() => _sendPeerId = peer.id);
    _navigate(0);
  }

  void _selectSendRecipient(String key) => setState(() => _sendPeerId = key);

  Future<void> _addPaths(List<String> paths) async {
    if (_picking) return;
    setState(() => _picking = true);
    await _guard(() async {
      final added = await LocalFile.fromPaths(paths);
      if (!mounted) return;
      final existing = _files.map((f) => f.path).toSet();
      if (_files.length +
              added.where((f) => !existing.contains(f.path)).length >
          1000) {
        throw const FormatException('单次最多发送 1000 个文件');
      }
      setState(() {
        _files.addAll(added.where((f) => existing.add(f.path)));
        _page = 0;
      });
      _syncMessageView();
      if (added.isEmpty) _toast('没有可发送的文件');
    });
    if (mounted) setState(() => _picking = false);
  }

  Future<void> _pickFiles({
    bool folder = false,
    FileType type = FileType.any,
  }) async {
    if (_picking) return;
    await _guard(() async {
      if (folder) {
        final directory = await FilePicker.getDirectoryPath(
          dialogTitle: '选择要发送的文件夹',
        );
        if (directory != null && mounted) await _addPaths([directory]);
      } else {
        final result = await FilePicker.pickFiles(
          type: type,
          allowMultiple: true,
          dialogTitle: '选择要发送的文件',
        );
        if (result != null && mounted) {
          await _addPaths(result.paths.whereType<String>().toList());
        }
      }
    });
  }

  void _sendFiles() {
    final peer = recipient;
    if (peer == null || !peer.online || _files.isEmpty || _picking) return;
    final batch = List<LocalFile>.of(_files);
    setState(() => _files.clear());
    final group = service.groupForConversation(peer.id);
    unawaited(
      _guard(
        () => group == null
            ? service.sendFiles(peer, batch)
            : service.sendGroupFiles(group, batch),
      ),
    );
  }

  void _sendMessage() {
    final peer = chatPeer;
    if (peer == null || !peer.online || _message.text.trim().isEmpty) return;
    final text = _message.text;
    setState(() {
      _message.clear();
      _drafts.remove(peer.id);
    });
    final group = service.groupForConversation(peer.id);
    unawaited(
      _guard(
        () => group == null
            ? service.sendMessage(peer, text)
            : service.sendGroupMessage(group, text),
      ),
    );
    _scrollConversation();
  }

  Future<void> _openFolder([String? folder]) => _guard(() async {
    if (widget.android != null) {
      _navigate(3);
      return;
    }
    final path = folder ?? service.saveDirectory;
    if (path.isEmpty) return;
    await Directory(path).create(recursive: true);
    await Process.start(
      Platform.isWindows
          ? 'explorer.exe'
          : Platform.isMacOS
          ? 'open'
          : 'xdg-open',
      [path],
    );
  });

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('已复制');
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (widget.android != null) return _androidWorkspace(box);
      final mobile = box.maxWidth < 640;
      final compact =
          mobile ||
          (widget.desktop?.sidebarCollapsed ??
              _sidebarCollapsed ??
              box.maxWidth < 900);
      final sidebarWidth = mobile
          ? 64.0
          : compact
          ? 76.0
          : 208.0;
      return Scaffold(
        body: Column(
          children: [
            DesktopTitleBar(
              leadingWidth: sidebarWidth,
              compactBrand: compact,
              closeToTray:
                  widget.desktop?.closeToTray == true &&
                  widget.desktop?.trayReady == true,
              navigationToggle: mobile
                  ? null
                  : IconButton(
                      key: const ValueKey('toggle-sidebar'),
                      tooltip: compact ? '展开侧边栏' : '收起侧边栏',
                      onPressed: widget.desktop?.updating == true
                          ? null
                          : () => _toggleSidebar(compact),
                      icon: Icon(
                        compact
                            ? LucideIcons.panelLeftOpen
                            : LucideIcons.panelLeftClose,
                        size: 19,
                      ),
                    ),
              actions: [
                if (widget.screenshots != null)
                  ListenableBuilder(
                    listenable: widget.screenshots!,
                    builder: (context, _) => IconButton(
                      tooltip: widget.screenshots!.registered
                          ? '截图 · ${widget.screenshots!.hotkey.label}'
                          : '截图',
                      onPressed:
                          widget.screenshots!.ready &&
                              !widget.screenshots!.capturing
                          ? widget.screenshots!.capture
                          : null,
                      icon: const Icon(LucideIcons.scan, size: 18),
                    ),
                  ),
                if (box.maxWidth >= 740) _networkStatus(),
                if (box.maxWidth >= 740) const SizedBox(width: 12),
                IconButton(
                  tooltip: '打开接收文件夹',
                  onPressed: service.saveDirectory.isEmpty
                      ? null
                      : () => _openFolder(),
                  icon: const Icon(LucideIcons.folderOpen, size: 18),
                ),
              ],
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  mobile ? _labels[_page] : '让分享，近一点',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  if (!mobile) _sidebar(compact),
                  Expanded(
                    child: Column(
                      children: [
                        if (service.error != null ||
                            service.discoveryError != null)
                          _networkNotice(),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _page == 2
                                    ? _chatPage()
                                    : Scrollbar(
                                        controller: _pageScroll,
                                        child: SingleChildScrollView(
                                          controller: _pageScroll,
                                          padding: EdgeInsets.fromLTRB(
                                            mobile ? 18 : 32,
                                            mobile ? 22 : 28,
                                            mobile ? 18 : 32,
                                            32,
                                          ),
                                          child: Align(
                                            alignment: Alignment.topCenter,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 1200,
                                              ),
                                              child: switch (_page) {
                                                0 => _sendPage(),
                                                1 => _devicesPage(),
                                                3 => _historyPage(),
                                                _ => _settingsPage(),
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              if (service.incoming.isNotEmpty)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: _incomingBanner(),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: mobile
            ? NavigationBar(
                height: 68,
                selectedIndex: _page,
                onDestinationSelected: _navigate,
                backgroundColor: Colors.white,
                indicatorColor: blueTint,
                labelTextStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 11, color: ink),
                ),
                destinations: List.generate(
                  5,
                  (i) => NavigationDestination(
                    icon: _navigationIcon(i, false, size: 20),
                    label: ['发送', '设备', '消息', '记录', '设置'][i],
                  ),
                ),
              )
            : null,
      );
    },
  );

  Widget _sidebar(bool compact) => Container(
    width: compact ? 76 : 208,
    color: shell,
    padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 24, compact ? 12 : 16, 20),
    child: Column(
      children: [
        for (var i = 0; i < 4; i++) ...[
          _navItem(i, compact),
          const SizedBox(height: 8),
        ],
        const Spacer(),
        if (!compact) ...[
          Material(
            color: Colors.white.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _navigate(4),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.monitor, color: blue, size: 17),
                        const SizedBox(width: 8),
                        const Text(
                          '这台设备',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      !service.running
                          ? '正在准备连接'
                          : service.addresses.isEmpty
                          ? '未连接局域网'
                          : service.discoveryError != null ||
                                !service.discoveryEnabled
                          ? '可通过 IP 连接'
                          : '自动发现已开启',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _navItem(4, compact),
      ],
    ),
  );

  Widget _navItem(int index, bool compact) {
    final selected = _page == index;
    final badge = index == 2
        ? unread
        : index == 3
        ? activeCount
        : 0;
    return Tooltip(
      message: badge > 0
          ? '${_labels[index]} · $badge 条${index == 2 ? '未读消息' : '进行中'}'
          : _labels[index],
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('nav-$index'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => _navigate(index),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 14,
                vertical: 14,
              ),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  _navigationIcon(index, selected, showBadge: compact),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _labels[index],
                        style: TextStyle(
                          fontSize: 14,
                          color: selected ? blue : muted,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (badge > 0) _badge(badge, message: index == 2),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navigationIcon(
    int index,
    bool selected, {
    bool showBadge = true,
    double size = 21,
  }) {
    final count = index == 2
        ? unread
        : index == 3
        ? activeCount
        : 0;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(_icons[index], size: size, color: selected ? blue : muted),
          if (showBadge && count > 0)
            Positioned(
              top: -9,
              right: -13,
              child: _badge(count, message: index == 2),
            ),
        ],
      ),
    );
  }

  Widget _badge(int count, {bool message = true}) => Semantics(
    label: '$count 条${message ? '未读消息' : '进行中'}',
    child: Container(
      key: ValueKey(message ? 'unread-badge' : 'transfer-badge'),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: message ? danger : blue,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    ),
  );

  Widget _networkStatus() {
    final (label, color) = !service.running
        ? (service.error == null ? '正在准备' : '网络未就绪', muted)
        : service.addresses.isEmpty
        ? ('未连接局域网', amber)
        : service.discoveryError != null
        ? ('需手动连接', amber)
        : service.retryingDiscovery
        ? ('正在检测网络', muted)
        : !service.discoveryEnabled
        ? ('手动连接模式', muted)
        : ('局域网已就绪', green);
    return Tooltip(
      message: service.discoveryError ?? label,
      child: StatusPill(label, color: color),
    );
  }

  Widget _networkNotice() => Container(
    width: double.infinity,
    color: const Color(0xFFFFF3DC),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: [
        const Icon(LucideIcons.circleAlert, size: 18, color: amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            service.error ?? service.discoveryError!,
            style: const TextStyle(fontSize: 12, color: amber, height: 1.55),
          ),
        ),
        if (service.discoveryError != null && service.running) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: '通过 IP 连接',
            onPressed: _connectDialog,
            icon: const Icon(LucideIcons.link, size: 18),
          ),
          IconButton(
            tooltip: service.retryingDiscovery ? '正在重新检测' : '重新检测网络',
            onPressed: service.retryingDiscovery
                ? null
                : () => unawaited(service.retryDiscovery()),
            icon: service.retryingDiscovery
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw, size: 18),
          ),
        ],
      ],
    ),
  );

  Widget _incomingBanner() {
    final offer =
        service.incoming
            .where((offer) => offer.id == _incomingOfferId)
            .firstOrNull ??
        service.incoming.first;
    void decide(bool accept) {
      setState(() => _incomingExpanded = false);
      service.decide(offer, accept);
    }

    final mobile = MediaQuery.sizeOf(context).width < 640;
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 24, 16, mobile ? 16 : 24, 8),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Container(
            key: const ValueKey('incoming-banner'),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: ink.withValues(alpha: .12),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 16 : 20,
              vertical: 16,
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final summary = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: mint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        LucideIcons.fileDown,
                        color: green,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: offer.peer.displayName,
                            child: Text(
                              '${offer.peer.displayName} 发来的文件',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${offer.files.length} 个文件 · ${formatBytes(offer.size)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                              if (service.incoming.length > 1)
                                Text(
                                  '还有 ${service.incoming.length - 1} 个请求等待处理',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: green,
                                  ),
                                ),
                            ],
                          ),
                          if (offer.groupName != null) ...[
                            const SizedBox(height: 4),
                            Tooltip(
                              message: offer.groupName!,
                              child: Text(
                                '群组 · ${offer.groupName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('incoming-details-toggle'),
                      tooltip: _incomingExpanded ? '收起清单' : '查看清单',
                      isSelected: _incomingExpanded,
                      selectedIcon: const Icon(LucideIcons.chevronUp, size: 18),
                      icon: const Icon(LucideIcons.chevronDown, size: 18),
                      onPressed: () => setState(
                        () => _incomingExpanded = !_incomingExpanded,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('incoming-reject'),
                      onPressed: () => decide(false),
                      child: const Text('拒绝', style: TextStyle(color: muted)),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('incoming-accept'),
                      onPressed: () => decide(true),
                      icon: const Icon(LucideIcons.check, size: 17),
                      label: const Text('接收'),
                    ),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (box.maxWidth /
                            MediaQuery.textScalerOf(context).scale(1) >
                        680)
                      Row(
                        children: [
                          Expanded(child: summary),
                          const SizedBox(width: 20),
                          actions,
                        ],
                      )
                    else ...[
                      summary,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                    if (_incomingExpanded) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 6),
                        child: Divider(height: 1),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (MediaQuery.sizeOf(context).height * .2)
                              .clamp(80.0, 160.0),
                        ),
                        child: Scrollbar(
                          controller: _incomingScroll,
                          thumbVisibility: true,
                          thickness: 4,
                          radius: const Radius.circular(4),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: ListView.separated(
                              key: ValueKey('incoming-files-${offer.id}'),
                              controller: _incomingScroll,
                              primary: false,
                              padding: const EdgeInsets.only(right: 10),
                              shrinkWrap: true,
                              itemCount: offer.files.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final file = offer.files[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        LucideIcons.file,
                                        size: 18,
                                        color: muted,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Tooltip(
                                          message: file.relativePath,
                                          child: Text(
                                            file.relativePath,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        formatBytes(file.size),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.folderOpen,
                            size: 16,
                            color: muted,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '保存至',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Tooltip(
                              message: service.saveDirectory,
                              child: Text(
                                service.saveDirectory,
                                key: const ValueKey('incoming-save-directory'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _sendPage() {
    final recent = [
      ...service.transfers.where((f) => f.active),
      ...service.transfers.where((f) => !f.active),
    ].take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          '分享，从这里开始',
          '文件、照片，或一整个文件夹。选好，发给身边的设备。',
          action: OutlinedButton.icon(
            onPressed: () => _openFolder(),
            icon: const Icon(LucideIcons.folderOpen, size: 17),
            label: const Text('收到的文件'),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 660
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _dropArea()),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: box.maxWidth > 1000 ? 350 : 280,
                      child: _receiverPanel(),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _dropArea(),
                    const SizedBox(height: 16),
                    _receiverPanel(),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _sendFooter(),
        const SizedBox(height: 30),
        SectionTitle(
          '传输动态',
          count: activeCount > 0 ? activeCount : null,
          action: TextButton.icon(
            onPressed: () => _navigate(3),
            icon: const Icon(LucideIcons.arrowUpRight, size: 15),
            label: const Text('全部记录'),
          ),
        ),
        if (recent.isEmpty)
          const Surface(
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            child: EmptyState(
              icon: LucideIcons.arrowLeftRight,
              label: '准备好，开始第一次分享',
              detail: '发送和接收的进度会出现在这里。',
              height: 160,
            ),
          )
        else
          for (final item in recent)
            _transferCard(item, key: ValueKey('recent-transfer-${item.id}')),
      ],
    );
  }

  Widget _dropArea() => DropTarget(
    onDragEntered: (_) => setState(() => _dragging = true),
    onDragExited: (_) => setState(() => _dragging = false),
    onDragDone: (details) {
      setState(() => _dragging = false);
      unawaited(_addPaths(details.files.map((f) => f.path).toList()));
    },
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : uiMotion,
      constraints: const BoxConstraints(minHeight: 330),
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: _dragging ? const Color(0xFFD9E6FF) : blueTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: _files.isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _dragging ? LucideIcons.download : LucideIcons.files,
                    size: 30,
                    color: blue,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _picking
                      ? '正在整理文件…'
                      : _dragging
                      ? '松开，加入待发送'
                      : '把文件拖到这里',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  '支持多文件和文件夹，保留原有目录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _picking ? null : _pickFiles,
                      icon: const Icon(LucideIcons.plus, size: 18),
                      label: const Text('选择文件'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: BorderSide.none,
                      ),
                      onPressed: _picking
                          ? null
                          : () => _pickFiles(folder: true),
                      icon: const Icon(LucideIcons.folderPlus, size: 18),
                      label: const Text('选择文件夹'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '待发送 · ${_files.length} 个文件',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '继续添加',
                      onPressed: _picking ? null : _pickFiles,
                      icon: const Icon(LucideIcons.plus, size: 18),
                    ),
                    IconButton(
                      tooltip: '清空待发送队列',
                      onPressed: _picking
                          ? null
                          : () => setState(() => _files.clear()),
                      icon: const Icon(LucideIcons.listX, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _files.length,
                    itemBuilder: (context, i) {
                      final file = _files[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            FileGlyph(file.name, size: 38),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.relativePath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    formatBytes(file.size),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '移除 ${file.name}',
                              onPressed: () =>
                                  setState(() => _files.removeAt(i)),
                              icon: const Icon(LucideIcons.x, size: 16),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (_picking)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
    ),
  );

  Widget _receiverPanel() {
    final peers = [...online, ..._sendGroupPeers];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 330),
      child: Surface(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              '发送给谁',
              count: peers.length,
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '新建群组',
                    onPressed: () => _editGroup(null, true),
                    icon: const Icon(LucideIcons.userPlus, size: 17),
                  ),
                  IconButton(
                    tooltip: '刷新附近设备',
                    onPressed: service.refresh,
                    icon: const Icon(LucideIcons.refreshCw, size: 17),
                  ),
                ],
              ),
            ),
            if (peers.isEmpty) ...[
              const SizedBox(height: 16),
              const Icon(LucideIcons.radar, size: 30, color: blue),
              const SizedBox(height: 16),
              const Text(
                '还没有发现其他设备',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '在另一台设备打开邻传，并连接到同一局域网。',
                style: TextStyle(fontSize: 13, color: muted, height: 1.7),
              ),
              const SizedBox(height: 18),
            ] else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 216),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: peers.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final peer = peers[i];
                    final group = service.groupForConversation(peer.id);
                    final selected = _sendPeerId == peer.id;
                    return Semantics(
                      selected: selected,
                      button: true,
                      child: Material(
                        color: selected ? blueTint : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          key: ValueKey('recipient-${peer.id}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _selectSendRecipient(peer.id),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                if (group != null)
                                  _groupAvatar(size: 38)
                                else
                                  DeviceAvatar(
                                    peer.platform,
                                    size: 38,
                                    active: selected,
                                  ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        peer.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: selected ? blue : ink,
                                        ),
                                      ),
                                      Text(
                                        group != null
                                            ? '群聊 · ${_groupStatus(group)}'
                                            : peer.remark.isEmpty
                                            ? peer.platform
                                            : peer.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  selected
                                      ? LucideIcons.circleCheck
                                      : LucideIcons.circle,
                                  size: 18,
                                  color: selected ? blue : muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _connectDialog,
              icon: const Icon(LucideIcons.link, size: 16),
              label: const Text('找不到？手动连接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendFooter() {
    final peer = recipient;
    final ready = _files.isNotEmpty && peer?.online == true && !_picking;
    final total = _files.fold<int>(0, (sum, file) => sum + file.size);
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _files.isEmpty
              ? '选好文件，再选接收方'
              : '${_files.length} 个文件 · ${formatBytes(total)}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          peer == null
              ? '由你决定，分享给谁。'
              : '${peer.online ? '发送至' : '设备已离线：'} ${peer.displayName}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: peer != null && !peer.online ? amber : muted,
          ),
        ),
      ],
    );
    final button = FilledButton.icon(
      key: const ValueKey('send-files'),
      onPressed: ready ? _sendFiles : null,
      icon: const Icon(LucideIcons.send, size: 17),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 210),
        child: Text(
          peer == null ? '发送文件' : '发送给 ${peer.displayName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    return Surface(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth < 560
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [summary, const SizedBox(height: 16), button],
              )
            : Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 20),
                  button,
                ],
              ),
      ),
    );
  }

  Widget _devicesPage() {
    final query = _deviceSearch.text.trim().toLowerCase();
    final peers =
        service.peers.values
            .where(
              (peer) =>
                  (_deviceFilter == 0 ||
                      (_deviceFilter == 1 ? peer.online : !peer.online)) &&
                  (peer.name.toLowerCase().contains(query) ||
                      peer.displayName.toLowerCase().contains(query) ||
                      peer.address.contains(query)),
            )
            .toList()
          ..sort((a, b) {
            final availability = _comparePeerAvailability(a, b);
            return availability != 0 ? availability : a.name.compareTo(b.name);
          });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          '身边的设备',
          '自己的电脑，或同事的工作站。找到它，就能开始分享。',
          action: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              IconButton(
                key: const ValueKey('clear-offline-devices'),
                tooltip: '清理无记录的离线设备',
                onPressed: service.unusedOfflinePeers.isEmpty
                    ? null
                    : _confirmClearOfflineDevices,
                icon: const Icon(LucideIcons.trash2, size: 19),
              ),
              OutlinedButton.icon(
                onPressed: service.refresh,
                icon: const Icon(LucideIcons.refreshCw, size: 17),
                label: const Text('刷新'),
              ),
              FilledButton.icon(
                onPressed: _connectDialog,
                icon: const Icon(LucideIcons.plus, size: 17),
                label: const Text('连接设备'),
              ),
            ],
          ),
        ),
        TextField(
          controller: _deviceSearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '搜索设备名称或地址',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            suffixIcon: _deviceSearch.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除设备搜索',
                    onPressed: () => setState(() => _deviceSearch.clear()),
                    icon: const Icon(LucideIcons.x, size: 17),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            3,
            (i) => ChoiceChip(
              label: Text(
                [
                  '全部设备',
                  '在线 ${online.length}',
                  '离线 ${service.peers.length - online.length}',
                ][i],
              ),
              selected: _deviceFilter == i,
              labelStyle: TextStyle(
                fontFamily: 'Microsoft YaHei UI',
                fontSize: 13,
                color: _deviceFilter == i ? blue : muted,
                fontWeight: _deviceFilter == i
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
              onSelected: (_) => setState(() => _deviceFilter = i),
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (peers.isEmpty)
          Surface(
            child: EmptyState(
              icon: LucideIcons.radar,
              label: query.isNotEmpty
                  ? '没有找到这台设备'
                  : _deviceFilter == 2
                  ? '没有离线设备'
                  : '让另一台设备也打开邻传',
              detail: query.isNotEmpty
                  ? '试试设备名称或 IP 地址的其他部分。'
                  : '连接到同一个局域网，设备就会出现在这里。找不到时，可以输入地址连接。',
              action: TextButton.icon(
                onPressed: _connectDialog,
                icon: const Icon(LucideIcons.link, size: 16),
                label: const Text('手动连接'),
              ),
              height: 280,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 1000
                  ? 3
                  : box.maxWidth >= 650
                  ? 2
                  : 1;
              final width = (box.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: peers
                    .map(
                      (peer) =>
                          SizedBox(width: width, child: _deviceCard(peer)),
                    )
                    .toList(),
              );
            },
          ),
        const SizedBox(height: 30),
        const SectionTitle('这台设备'),
        Surface(
          child: Row(
            children: [
              DeviceAvatar(service.platform, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${service.platform} · ${service.primaryAddress}:${service.port}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑本机信息',
                onPressed: () => _navigate(4),
                icon: const Icon(LucideIcons.pencil, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _deviceCard(Peer peer) => Surface(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DeviceAvatar(peer.platform, size: 48),
            const Spacer(),
            IconButton(
              key: ValueKey('remark-${peer.id}'),
              tooltip: '设置设备备注',
              onPressed: () => _editRemark(peer),
              icon: const Icon(LucideIcons.pencil, size: 16),
            ),
            StatusPill(
              peer.online ? '在线' : '离线',
              color: peer.online ? green : muted,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          peer.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          peer.remark.isEmpty ? peer.platform : peer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          peer.address,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 6),
        if (!peer.online)
          PeerLastSeen(
            key: ValueKey('last-seen-${peer.id}'),
            lastSeen: peer.lastSeen,
          )
        else
          SizedBox(height: MediaQuery.textScalerOf(context).scale(12) * 1.5),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: ValueKey('send-to-${peer.id}'),
              onPressed: peer.online ? () => _prepareSend(peer) : null,
              icon: const Icon(LucideIcons.send, size: 16),
              label: const Text('发文件'),
            ),
            TextButton.icon(
              key: ValueKey('chat-with-${peer.id}'),
              onPressed: () => _openConversation(peer),
              icon: const Icon(LucideIcons.messageCircle, size: 16),
              label: Text(peer.online ? '发消息' : '查看消息'),
            ),
          ],
        ),
      ],
    ),
  );
  List<TransferItem> get _filteredTransfers {
    final query = _historySearch.text.trim().toLowerCase();
    return service.transfers
        .where(
          (file) =>
              (_historyFilter == 0 ||
                  (_historyFilter == 1
                      ? file.active
                      : _historyFilter == 2
                      ? file.status == TransferStatus.complete
                      : !file.active &&
                            file.status != TransferStatus.complete)) &&
              (_directionFilter == 0 ||
                  (_directionFilter == 1 ? file.outgoing : !file.outgoing)) &&
              (file.name.toLowerCase().contains(query) ||
                  file.peerName.toLowerCase().contains(query) ||
                  (service.peers[file.peerId]?.displayName
                          .toLowerCase()
                          .contains(query) ??
                      false)),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Widget _historyPage() {
    final items = _filteredTransfers;
    final groups = <String, List<TransferItem>>{};
    for (final item in items) {
      groups
          .putIfAbsent(dayLabel(item.createdAt.toLocal()), () => [])
          .add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          '每一次分享，都有迹可循',
          '查看传输进度、找回收到的文件，或重新发送未完成的任务。',
          action: OutlinedButton.icon(
            onPressed: service.transfers.any((f) => !f.active)
                ? _confirmClear
                : null,
            icon: const Icon(LucideIcons.listX, size: 17),
            label: const Text('清理记录'),
          ),
        ),
        TextField(
          controller: _historySearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '搜索文件或设备',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            suffixIcon: _historySearch.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除记录搜索',
                    onPressed: () => setState(() => _historySearch.clear()),
                    icon: const Icon(LucideIcons.x, size: 17),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            4,
            (i) => ChoiceChip(
              key: ValueKey('history-filter-$i'),
              label: Text(['全部记录', '进行中', '已完成', '未完成'][i]),
              selected: _historyFilter == i,
              labelStyle: TextStyle(
                fontFamily: 'Microsoft YaHei UI',
                fontSize: 13,
                color: _historyFilter == i ? blue : muted,
                fontWeight: _historyFilter == i
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
              onSelected: (_) => setState(() => _historyFilter = i),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          children: List.generate(
            3,
            (i) => TextButton(
              onPressed: () => setState(() => _directionFilter = i),
              style: TextButton.styleFrom(
                foregroundColor: _directionFilter == i ? ink : muted,
              ),
              child: Text(
                ['全部方向', '我发送的', '我收到的'][i],
                style: TextStyle(
                  fontWeight: _directionFilter == i
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (items.isEmpty)
          Surface(
            child: EmptyState(
              icon: LucideIcons.history,
              label: service.transfers.isEmpty ? '还没有传输记录' : '没有符合条件的记录',
              detail: service.transfers.isEmpty
                  ? '完成一次分享后，就可以在这里找到它。'
                  : '换个关键词，或者调整上方的筛选条件。',
              action: service.transfers.isEmpty
                  ? TextButton(
                      onPressed: () => _navigate(0),
                      child: const Text('去发送文件'),
                    )
                  : TextButton(
                      onPressed: () => setState(() {
                        _historyFilter = 0;
                        _directionFilter = 0;
                        _historySearch.clear();
                      }),
                      child: const Text('重置筛选'),
                    ),
              height: 260,
            ),
          )
        else
          for (final group in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${group.key == '今天' || group.key == '昨天' ? '${group.key} · ' : ''}${dateLabel(group.value.first.createdAt)} · ${group.value.length} 条记录',
                style: const TextStyle(
                  fontSize: 13,
                  color: muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            for (final item in group.value)
              _transferCard(item, key: ValueKey('history-record-${item.id}')),
            const SizedBox(height: 22),
          ],
      ],
    );
  }

  Widget _transferCard(TransferItem item, {required Key key}) =>
      TransferFileCard(
        key: key,
        filePath: item.outgoing ? item.sourcePath : _forwardFilePath(item),
        onCopy: (path) => _guard(() async {
          await WindowsFileClipboard.copyFile(path);
          if (mounted) _toast('文件已复制');
        }),
        child: _transferRow(item),
      );

  String _transferPeerLabel(TransferItem item) =>
      '${item.outgoing ? '发送至' : '来自'} ${service.peers[item.peerId]?.displayName ?? item.peerName}'
      '${item.groupId == null ? '' : ' · 群聊 ${service.groups[item.groupId]?.name ?? '群文件'}'}';

  Widget _transferRow(TransferItem item) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 600;
      final hasError = item.error != null && !item.active;
      final metadata = Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          Text(
            formatBytes(item.size),
            style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
          ),
          if (item.active && item.bytesPerSecond > 0)
            Text(
              formatBytes(item.bytesPerSecond, speed: true),
              style: const TextStyle(fontSize: 12, color: blue, height: 1.5),
            ),
        ],
      );
      final status = StatusPill(
        item.statusLabel,
        dot: false,
        color: item.status == TransferStatus.complete
            ? green
            : item.active
            ? blue
            : item.status == TransferStatus.failed
            ? danger
            : amber,
      );
      Widget? action;
      if (item.active &&
          (item.outgoing || item.status != TransferStatus.waiting)) {
        action = IconButton(
          tooltip: item.outgoing ? '取消本批传输' : '取消接收',
          onPressed: () => service.cancel(item),
          icon: const Icon(LucideIcons.x, size: 17),
        );
      } else if (item.status == TransferStatus.complete &&
          !item.outgoing &&
          item.savedPath != null) {
        action = IconButton(
          tooltip: '打开所在目录',
          onPressed: () => _openFolder(p.dirname(item.savedPath!)),
          icon: const Icon(LucideIcons.folderOpen, size: 18),
        );
      } else if (item.outgoing &&
          !item.active &&
          item.status != TransferStatus.complete) {
        action = IconButton(
          tooltip: '重新发送',
          onPressed: () => _guard(() => service.retry(item)),
          icon: const Icon(LucideIcons.rotateCcw, size: 18),
        );
      }
      return Padding(
        key: ValueKey('transfer-row-${item.id}'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileGlyph(item.name, size: compact ? 36 : 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _transferPeerLabel(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: ink),
                      ),
                      if (hasError) ...[const SizedBox(height: 8), metadata],
                      if (compact) ...[
                        const SizedBox(height: 8),
                        Row(children: [status, const Spacer(), ?action]),
                      ],
                      if (item.active) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value:
                                item.status == TransferStatus.hashing ||
                                    item.status == TransferStatus.waiting
                                ? null
                                : item.progress,
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.status == TransferStatus.transferring
                              ? '${formatBytes(item.bytes)} / ${formatBytes(item.size)}'
                              : item.statusLabel,
                          style: const TextStyle(fontSize: 11, color: blue),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      status,
                      if (action != null) ...[
                        const SizedBox(height: 6),
                        action,
                      ],
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: compact ? 0 : 58),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: hasError
                        ? Text(
                            item.error!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: danger,
                              height: 1.5,
                            ),
                          )
                        : metadata,
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: '记录时间',
                    child: Text(
                      transferTimestampLabel(item.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _chatPage() => LayoutBuilder(
    builder: (context, box) {
      final wide = widget.android != null
          ? MediaQuery.sizeOf(context).width >= 840
          : box.maxWidth >= 760;
      final peers =
          [
            ...service.peers.values,
            ...service.groups.values.map(_groupPeer).whereType<Peer>(),
          ]..sort((a, b) {
            final availability = _comparePeerAvailability(a, b);
            if (availability != 0) return availability;
            final aTime = _conversationSummary(a).time;
            final bTime = _conversationSummary(b).time;
            if (aTime != null && bTime != null) return bTime.compareTo(aTime);
            if (aTime != null) return -1;
            if (bTime != null) return 1;
            return a.name.compareTo(b.name);
          });
      return Padding(
        padding: widget.android != null
            ? EdgeInsets.zero
            : EdgeInsets.fromLTRB(
                box.maxWidth < 600 ? 18 : 32,
                28,
                box.maxWidth < 600 ? 18 : 32,
                24,
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.android == null)
              Row(
                children: [
                  const Expanded(child: PageHeading('消息', '发一段文字，或者把文件一起带过去。')),
                  IconButton(
                    key: const ValueKey('create-group'),
                    tooltip: '新建群组',
                    onPressed: () => _editGroup(),
                    icon: const Icon(LucideIcons.usersRound, size: 20),
                  ),
                ],
              ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 260, child: _conversationList(peers)),
                        const SizedBox(width: 20),
                        Expanded(child: _conversationPanel(showBack: false)),
                      ],
                    )
                  : _chatPeerId == null
                  ? _conversationList(peers)
                  : _conversationPanel(showBack: true),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _showDeviceContextMenu(Peer peer, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final edit = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      items: const [
        PopupMenuItem(
          value: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.pencil, size: 16, color: muted),
              SizedBox(width: 10),
              Text('修改备注', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
    if (mounted && edit == true) await _editRemark(peer);
  }

  Widget _conversationList(List<Peer> peers) => widget.android != null
      ? _androidConversations(peers)
      : Surface(
          padding: EdgeInsets.all(widget.android != null ? 4 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 2, 14),
                child: Row(
                  children: [
                    const Text(
                      '会话',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '连接新设备',
                      onPressed: _connectDialog,
                      icon: const Icon(LucideIcons.plus, size: 17),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: peers.isEmpty
                    ? SingleChildScrollView(
                        child: EmptyState(
                          icon: LucideIcons.messagesSquare,
                          label: '对话从连接开始',
                          detail: '先找到一台设备，就能互发文字和链接。',
                          action: TextButton(
                            onPressed: () => _navigate(1),
                            child: const Text('查看附近设备'),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: peers.length,
                        separatorBuilder: (_, i) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final peer = peers[i];
                          final summary = _conversationSummary(peer);
                          final draft = _drafts[peer.id] ?? '';
                          final active = _chatPeerId == peer.id;
                          final unread = _unreadFor(peer.id);
                          return _conversationFileTarget(
                            peer,
                            Material(
                              color: active ? blueTint : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                key: ValueKey('conversation-${peer.id}'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _openConversation(peer),
                                onLongPress: widget.android != null
                                    ? () => _androidDeviceActions(peer)
                                    : null,
                                onSecondaryTapUp:
                                    service.peers.containsKey(peer.id)
                                    ? (details) => unawaited(
                                        _showDeviceContextMenu(
                                          peer,
                                          details.globalPosition,
                                        ),
                                      )
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      _conversationAvatar(peer, active: active),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              peer.displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Row(
                                              children: [
                                                _conversationPresence(peer),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    draft.isNotEmpty
                                                        ? '草稿 · $draft'
                                                        : summary.preview,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: draft.isNotEmpty
                                                          ? blue
                                                          : active
                                                          ? const Color(
                                                              0xff53617a,
                                                            )
                                                          : muted,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (unread > 0) ...[
                                        const SizedBox(width: 6),
                                        _badge(unread),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );

  Widget _conversationPanel({required bool showBack}) {
    final peer = chatPeer;
    if (peer == null) {
      return const Surface(
        child: Center(
          child: SingleChildScrollView(
            child: EmptyState(
              icon: LucideIcons.messageCircle,
              label: '选一台设备，聊两句',
              detail: '文字、链接和临时灵感，都可以直接发给对方。',
            ),
          ),
        ),
      );
    }
    final group = service.groupForConversation(peer.id);
    final entries = _conversationEntries(peer.id);
    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(
        widget.android != null && showBack ? 0 : 16,
      ),
      child: ColoredBox(
        color: widget.android != null ? canvas : Colors.white,
        child: Column(
          children: [
            Padding(
              padding: widget.android != null
                  ? const EdgeInsets.fromLTRB(4, 4, 4, 8)
                  : const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  if (showBack) ...[
                    IconButton(
                      tooltip: '返回会话列表',
                      onPressed: () {
                        _drafts[peer.id] = _message.text;
                        setState(() => _chatPeerId = null);
                        _syncMessageView();
                      },
                      icon: const Icon(LucideIcons.arrowLeft, size: 19),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (widget.android == null || !showBack)
                    _conversationAvatar(peer),
                  SizedBox(width: widget.android != null && showBack ? 0 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.android != null ? 16 : 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          group != null
                              ? _groupStatus(group)
                              : peer.online
                              ? (peer.remark.isNotEmpty
                                    ? '${peer.name} · 在线'
                                    : '在线 · 局域网直连')
                              : '离线 · 可查看历史消息',
                          maxLines: widget.android != null ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: _forwardTargetOnline(peer) ? green : muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '给 ${peer.displayName} 发文件',
                    onPressed: _forwardTargetOnline(peer) && !_pickingChat
                        ? () => _pickConversationFiles(peer)
                        : null,
                    icon: const Icon(LucideIcons.folderUp, size: 19),
                  ),
                  IconButton(
                    tooltip: group == null ? '设置设备备注' : '群组详情',
                    onPressed: () => group == null
                        ? _editRemark(peer)
                        : _groupDetails(group),
                    icon: Icon(
                      group == null ? LucideIcons.pencil : LucideIcons.users,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: SingleChildScrollView(
                        child: EmptyState(
                          icon: LucideIcons.messageCircle,
                          label: '还没聊过，从一句你好开始',
                          detail: '消息和链接，直接送到对方的设备。',
                          height: 160,
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: ValueKey('messages-${peer.id}'),
                      controller: _chatScroll,
                      padding: EdgeInsets.all(widget.android != null ? 16 : 22),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final entry = entries[i];
                        final message = entry.message;
                        final previous = i > 0 ? entries[i - 1] : null;
                        final showDay =
                            previous == null ||
                            dayLabel(previous.time) != dayLabel(entry.time);
                        final mobile = widget.android != null;
                        final showTime =
                            showDay ||
                            entry.time.difference(previous.time).inMinutes >= 5;
                        final compact =
                            mobile &&
                            !showTime &&
                            message != null &&
                            previous.message?.outgoing == message.outgoing &&
                            previous.message?.peerId == message.peerId;
                        final next = i + 1 < entries.length
                            ? entries[i + 1]
                            : null;
                        final showStatus =
                            !mobile ||
                            next == null ||
                            message == null ||
                            next.message?.outgoing != message.outgoing ||
                            next.message?.peerId != message.peerId ||
                            next.time.difference(entry.time).inMinutes >= 5;
                        return Column(
                          children: [
                            if (mobile ? showTime : showDay)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: 4,
                                  bottom: mobile ? 16 : 22,
                                ),
                                child: Text(
                                  mobile
                                      ? '${dayLabel(entry.time)} ${timeLabel(entry.time)}'
                                      : dayLabel(entry.time),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ),
                            if (message != null)
                              _messageBubble(
                                message,
                                peer,
                                compact: compact,
                                showStatus:
                                    showStatus ||
                                    message.delivery != 'delivered',
                              )
                            else
                              _chatFileBubble(
                                entry.file!,
                                allowDrag: !showBack,
                              ),
                          ],
                        );
                      },
                    ),
            ),
            _composer(peer),
          ],
        ),
      ),
    );
    return _conversationDropTarget(peer, panel);
  }

  Widget _messageBubble(
    ChatMessage message,
    Peer peer, {
    bool compact = false,
    bool showStatus = true,
  }) => LayoutBuilder(
    builder: (context, box) => Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.android != null && !compact ? 4 : 0,
          bottom: widget.android != null ? 8 : 20,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * .88),
          child: Column(
            crossAxisAlignment: message.outgoing
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (message.groupId != null && !message.outgoing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    service.peers[message.peerId]?.displayName ??
                        message.senderName ??
                        '群成员',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.android != null ? 14 : 16,
                  vertical: widget.android != null ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: message.outgoing
                      ? blue
                      : widget.android != null
                      ? Colors.white
                      : canvas,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  message.text,
                  style: TextStyle(
                    fontSize: 14,
                    height: widget.android != null ? 1.5 : 1.7,
                    color: message.outgoing ? Colors.white : ink,
                  ),
                ),
              ),
              if (widget.android == null || message.outgoing)
                SizedBox(height: widget.android != null ? 4 : 6),
              if (message.groupId != null && message.outgoing)
                _groupDelivery(message)
              else if (message.outgoing && message.delivery == 'failed')
                TextButton.icon(
                  onPressed: peer.online
                      ? () => _guard(
                          () => service.sendMessage(
                            peer,
                            message.text,
                            retry: message,
                          ),
                        )
                      : null,
                  icon: const Icon(LucideIcons.rotateCcw, size: 13),
                  label: const Text(
                    '发送失败，点击重试',
                    style: TextStyle(fontSize: 11, color: danger),
                  ),
                )
              else if (widget.android == null ||
                  (message.outgoing && showStatus))
                Text(
                  '${widget.android == null ? timeLabel(message.time) : ''}${message.outgoing
                      ? message.delivery == 'delivered'
                            ? '${widget.android == null ? ' · ' : ''}已送达'
                            : '${widget.android == null ? ' · ' : ''}发送中'
                      : ''}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _composer(Peer peer) => Padding(
    padding: widget.android != null
        ? const EdgeInsets.fromLTRB(4, 8, 12, 10)
        : const EdgeInsets.fromLTRB(16, 12, 16, 14),
    child: Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: '在此会话中添加文件',
              onPressed: peer.online && !_pickingChat
                  ? () => _pickConversationFiles(peer)
                  : null,
              icon: _pickingChat
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.paperclip, size: 20),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (widget.android != null) return KeyEventResult.ignored;
                  final composing = _message.value.composing;
                  if (composing.isValid && !composing.isCollapsed) {
                    return KeyEventResult.ignored;
                  }
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _sendMessage();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const ValueKey('message-input'),
                  controller: _message,
                  enabled: peer.online,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 16000,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onChanged: (value) =>
                      setState(() => _drafts[peer.id] = value),
                  decoration: InputDecoration(
                    hintText: peer.online
                        ? (widget.android != null ? '发消息…' : '发条消息，分享一个想法…')
                        : '设备离线，在线后可发送',
                    counterText: '',
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: '发送消息',
              onPressed: peer.online && _message.text.trim().isNotEmpty
                  ? _sendMessage
                  : null,
              style: IconButton.styleFrom(
                minimumSize: Size.square(widget.android != null ? 48 : 44),
                backgroundColor: blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: line,
              ),
              icon: const Icon(LucideIcons.arrowUp, size: 21),
            ),
          ],
        ),
        if (widget.android == null) const SizedBox(height: 8),
        if (widget.android == null)
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Enter 发送 · Shift + Enter 换行',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
      ],
    ),
  );
  Widget _settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading('按你的习惯来', '设备怎么称呼，文件放在哪里，都由你决定。'),
      const SectionTitle('设备与接收'),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '设备名称',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '这个名字会显示在其他设备的列表中。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: TextField(
                key: const ValueKey('device-name-input'),
                controller: _deviceName,
                enabled: !_saving,
                maxLength: 64,
                onChanged: (_) => setState(() {
                  _settingsDirty = true;
                  _settingsError = null;
                }),
                decoration: const InputDecoration(
                  hintText: '给这台设备起个容易认出的名字',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              '文件保存位置',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '收到的文件会保存在这里，同名文件会自动编号。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth <
                    320 * MediaQuery.textScalerOf(context).scale(1);
                final path = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(LucideIcons.folder, size: 20, color: muted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        _directory.isEmpty ? '正在准备保存目录…' : _directory,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                );
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '更改保存位置',
                      onPressed: _saving
                          ? null
                          : () => _guard(() async {
                              final directory =
                                  await FilePicker.getDirectoryPath(
                                    dialogTitle: '选择接收文件的保存位置',
                                  );
                              if (directory != null && mounted) {
                                setState(() {
                                  _directory = directory;
                                  _settingsDirty = true;
                                  _settingsError = null;
                                });
                              }
                            }),
                      icon: const Icon(LucideIcons.pencil, size: 18),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: '打开当前文件夹',
                      onPressed: service.saveDirectory.isEmpty
                          ? null
                          : () => _openFolder(),
                      icon: const Icon(LucideIcons.folderOpen, size: 19),
                    ),
                  ],
                );
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFE),
                    border: Border.all(color: line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            path,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: actions,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: path),
                            const SizedBox(width: 16),
                            actions,
                          ],
                        ),
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.userCheck, size: 21, color: green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '接收之前，先问过你',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '每一批文件都需要你确认，其他设备不会直接写入文件。',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_settingsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(
                  _settingsError!,
                  style: const TextStyle(fontSize: 13, color: danger),
                ),
              ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (_settingsDirty)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _syncSettings();
                              _settingsDirty = false;
                              _settingsError = null;
                            }),
                      child: const Text('撤销修改'),
                    ),
                  FilledButton.icon(
                    key: const ValueKey('save-settings'),
                    onPressed: _saving || !_settingsDirty
                        ? null
                        : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.check, size: 17),
                    label: Text(_saving ? '保存中…' : '保存设置'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      if (widget.desktop != null) ...[
        DesktopSettings(controller: widget.desktop!),
        const SizedBox(height: 28),
      ],
      if (widget.screenshots != null) ...[
        ScreenshotSettings(controller: widget.screenshots!),
        const SizedBox(height: 28),
      ],
      if (widget.notifications != null) ...[
        NotificationSettings(controller: widget.notifications!),
        const SizedBox(height: 28),
      ],
      const SectionTitle('连接信息'),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _settingInfo(
              '本机地址',
              '${service.primaryAddress}:${service.port}',
              copy: true,
            ),
            _settingInfo('网络状态', service.running ? '已就绪，可以接收文件和消息' : '服务正在准备'),
            _settingInfo('连接方式', '局域网直连 · 无需账号'),
            if (service.addresses.length > 1)
              _settingInfo('其他地址', service.addresses.skip(1).join('  ')),
            const SizedBox(height: 8),
            const Text(
              '当前传输未加密，请在可信的局域网中使用。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      LogSettings(log: service.log),
      const SizedBox(height: 28),
      const SectionTitle('关于邻传'),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Brand(),
            const SizedBox(height: 18),
            const Text('让文件和想法，在身边自由流动。', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            const Text(
              'Windows · v0.3.11\n明亮外观 · 活力蓝',
              style: TextStyle(fontSize: 12, height: 1.8, color: muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _settingInfo(String label, String value, {bool copy = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth < 520
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            value,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (copy)
                          IconButton(
                            tooltip: '复制本机地址',
                            onPressed: () => _copy(value),
                            icon: const Icon(LucideIcons.copy, size: 17),
                          ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        value,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (copy)
                      IconButton(
                        tooltip: '复制本机地址',
                        onPressed: () => _copy(value),
                        icon: const Icon(LucideIcons.copy, size: 17),
                      ),
                  ],
                ),
        ),
      );

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
      _settingsError = null;
    });
    try {
      await service.updateSettings(
        deviceName: _deviceName.text,
        directory: _directory,
      );
      if (mounted) {
        setState(() {
          _settingsDirty = false;
          _syncSettings();
        });
        _toast('设置已保存');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _settingsError = e is FormatException ? e.message : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _connectDialog() async {
    final input = TextEditingController();
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Future<void> connect() async {
            if (busy) return;
            update(() {
              busy = true;
              error = null;
            });
            try {
              final peer = await service.connect(input.text);
              if (!mounted || !dialogContext.mounted) return;
              setState(() => _sendPeerId = peer.id);
              Navigator.of(dialogContext).pop();
              _toast('已连接 ${peer.displayName}');
            } catch (e) {
              if (dialogContext.mounted) {
                update(() {
                  busy = false;
                  error = e is FormatException
                      ? e.message
                      : '没能连接上，请检查地址并确认对方已打开邻传。';
                });
              }
            }
          }

          return AlertDialog(
            title: const Text('连接另一台设备'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('在对方的设置中找到设备地址，然后输入到这里。'),
                    const SizedBox(height: 20),
                    TextField(
                      controller: input,
                      autofocus: true,
                      enabled: !busy,
                      onSubmitted: (_) => connect(),
                      decoration: InputDecoration(
                        labelText: '设备地址',
                        hintText: '192.168.1.12:45878',
                        errorText: error,
                        errorMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '你的地址：${service.primaryAddress}:${service.port}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : connect,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.link, size: 17),
                label: Text(busy ? '正在连接…' : '连接'),
              ),
            ],
          );
        },
      ),
    );
    // The field remains mounted until the closing route animation finishes.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), input.dispose),
    );
  }

  Future<void> _confirmClearOfflineDevices() async {
    final candidates = service.unusedOfflinePeers;
    if (candidates.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理离线设备'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('将移除以下 ${candidates.length} 台无使用记录的离线设备。'),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final peer in candidates)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              DeviceAvatar(peer.platform, size: 32),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      peer.displayName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      peer.address,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '有备注、手动连接、聊天、传输或群组记录的设备会保留。清理前会自动备份，设备再次上线时仍可发现。',
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-clear-offline-devices'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: const Text('清理设备'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guard(() async {
      final count = await service.clearUnusedOfflinePeers(
        candidates.map((peer) => peer.id),
      );
      _toast(count > 0 ? '已清理 $count 台离线设备' : '设备状态已更新，暂无可清理的设备');
    });
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理已结束的记录？'),
        content: const Text('正在传输的任务会保留，已接收的文件也不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清理记录'),
          ),
        ],
      ),
    );
    if (confirmed == true) service.clearHistory();
  }
}
