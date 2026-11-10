part of 'workspace.dart';

extension _AndroidWorkspace on _WorkspaceState {
  static const _mobileOrder = [0, 2, 1, 3, 4];
  static const _mobileLabels = ['发送', '消息', '设备', '记录', '设置'];

  Future<void> _receiveShared(AndroidSharedContent content) async {
    if (!mounted) return;
    if (content.error != null) _toast(content.error!);
    if (content.text.isNotEmpty) {
      _updateAndroid(() {
        _sharedText.text = content.text;
        _page = 0;
      });
      _syncMessageView();
    }
    if (content.paths.isNotEmpty) await _addPaths(content.paths);
  }

  Widget _androidWorkspace(BoxConstraints box) {
    final expanded = box.maxWidth >= 840;
    final inChat = _page == 2 && _chatPeerId != null && !expanded;
    final selected = _mobileOrder.indexOf(_page);
    final pending = service.incoming
        .where((o) => !o.decision.isCompleted)
        .toList();
    if (_androidPendingId != pending.firstOrNull?.id) {
      _androidPendingId = pending.firstOrNull?.id;
      _androidIncomingCollapsed = false;
    }
    void back() {
      if (inChat) {
        _drafts[_chatPeerId!] = _message.text;
        _updateAndroid(() => _chatPeerId = null);
        _syncMessageView();
      } else {
        _navigate(0);
      }
    }

    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: Scaffold(
        appBar: inChat
            ? null
            : AppBar(
                backgroundColor: canvas,
                surfaceTintColor: Colors.transparent,
                title: _page == 0
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/brand/app-icon.png',
                            width: 32,
                            height: 32,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '邻传',
                              style: Theme.of(context).textTheme.titleLarge,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      )
                    : Text(_WorkspaceState._labels[_page]),
                titleTextStyle: Theme.of(context).textTheme.titleLarge,
                actions: [
                  if (_page == 1)
                    IconButton(
                      key: const ValueKey('clear-offline-devices'),
                      tooltip: '清理无记录的离线设备',
                      onPressed: service.unusedOfflinePeers.isEmpty
                          ? null
                          : _confirmClearOfflineDevices,
                      icon: const Icon(LucideIcons.trash2),
                    ),
                  if (_page == 0 || _page == 1)
                    IconButton(
                      tooltip: '连接设备',
                      onPressed: _connectDialog,
                      icon: const Icon(LucideIcons.plus),
                    ),
                  if (_page == 2)
                    IconButton(
                      key: const ValueKey('create-group'),
                      tooltip: '新建群组',
                      onPressed: () => _editGroup(),
                      icon: const Icon(LucideIcons.usersRound),
                    ),
                  if (_page == 0 || _page == 1)
                    IconButton(
                      tooltip: '刷新设备',
                      onPressed: service.refresh,
                      icon: const Icon(LucideIcons.refreshCw),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
        body: SafeArea(
          top: inChat,
          bottom: true,
          child: Row(
            children: [
              if (expanded)
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => _navigate(_mobileOrder[i]),
                  backgroundColor: canvas,
                  indicatorColor: blueTint,
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    5,
                    (i) => NavigationRailDestination(
                      icon: _androidNavIcon(_mobileOrder[i]),
                      label: Text(_mobileLabels[i]),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (service.error != null || service.discoveryError != null)
                      Material(
                        color: mint,
                        child: ListTile(
                          leading: const Icon(
                            LucideIcons.wifiOff,
                            color: green,
                          ),
                          title: Text(
                            service.error ?? service.discoveryError!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '重试连接',
                            onPressed: () => _guard(service.retryDiscovery),
                            icon: const Icon(LucideIcons.refreshCw),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _page == 2 ? _chatPage() : _androidPage(),
                          ),
                          if (pending.isNotEmpty)
                            Positioned(
                              top: 8,
                              left: 12,
                              right: 12,
                              child: _androidIncomingNotice(pending),
                            ),
                        ],
                      ),
                    ),
                    if (_page == 0 &&
                        (_files.isNotEmpty || _sharedText.text.isNotEmpty))
                      _androidSendBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: expanded || inChat
            ? null
            : NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (i) => _navigate(_mobileOrder[i]),
                backgroundColor: Colors.white,
                indicatorColor: blueTint,
                destinations: List.generate(
                  5,
                  (i) => NavigationDestination(
                    icon: _androidNavIcon(_mobileOrder[i]),
                    label: _mobileLabels[i],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _androidNavIcon(int page) {
    final count = page == 2
        ? unread
        : page == 3
        ? activeCount
        : 0;
    return Badge(
      backgroundColor: page == 3 ? blue : danger,
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(_WorkspaceState._icons[page], size: 22),
    );
  }

  Widget _androidIncomingNotice(List<IncomingOffer> pending) => Align(
    alignment: Alignment.topRight,
    child: Material(
      color: Colors.white,
      elevation: 5,
      shadowColor: ink.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(8),
      child: _androidIncomingCollapsed
          ? IconButton(
              tooltip: '展开接收请求',
              onPressed: () =>
                  _updateAndroid(() => _androidIncomingCollapsed = false),
              icon: Badge(
                label: Text('${pending.length}'),
                backgroundColor: green,
                child: const Icon(LucideIcons.download, color: green),
              ),
            )
          : ListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              leading: const Icon(LucideIcons.download, color: green, size: 22),
              title: Text(
                '${pending.first.peer.displayName} 发来文件',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${pending.first.files.length} 个 · ${formatBytes(pending.first.size)}${pending.length > 1 ? ' · 另有 ${pending.length - 1} 个请求' : ''}',
                maxLines: 2,
              ),
              trailing: IconButton(
                tooltip: '收起接收提醒',
                onPressed: () =>
                    _updateAndroid(() => _androidIncomingCollapsed = true),
                icon: const Icon(LucideIcons.chevronUp, size: 20),
              ),
              onTap: () => _androidReviewOffer(pending.first.id),
            ),
    ),
  );

  int _androidComparePeers(Peer a, Peer b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    DateTime lastUsed(Peer peer) {
      final times = [
        ...service.messages
            .where((m) => m.conversationId == peer.id)
            .map((m) => m.time),
        ...service.transfers
            .where((f) => f.peerId == peer.id)
            .map((f) => f.createdAt),
      ];
      return times.fold(
        DateTime.fromMillisecondsSinceEpoch(0),
        (latest, time) => time.isAfter(latest) ? time : latest,
      );
    }

    final recent = lastUsed(b).compareTo(lastUsed(a));
    return recent != 0 ? recent : a.displayName.compareTo(b.displayName);
  }

  Widget _androidEmptyDevices({bool searching = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 12),
              child: Icon(LucideIcons.radar, color: blue, size: 28),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    searching ? '没有匹配的设备' : '暂未发现设备',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    searching ? '试试其他名称、备注或地址。' : '让另一台设备打开邻传，并连接同一无线网络。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!searching)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 8),
            child: TextButton.icon(
              onPressed: _connectDialog,
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('输入地址连接'),
            ),
          ),
      ],
    ),
  );

  Widget _androidConversations(List<Peer> peers) => Material(
    color: canvas,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: peers.length,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final peer = peers[i];
              final active = _chatPeerId == peer.id;
              final summary = _conversationSummary(peer);
              final draft = _drafts[peer.id] ?? '';
              final count = _unreadFor(peer.id);
              return _conversationFileTarget(
                peer,
                Material(
                  color: active ? blueTint : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey('conversation-${peer.id}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openConversation(peer),
                    onLongPress: () => _androidDeviceActions(peer),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          _conversationAvatar(peer, active: active),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  peer.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  draft.isNotEmpty
                                      ? '草稿 · $draft'
                                      : summary.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: draft.isNotEmpty ? blue : muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (summary.time != null) ...[
                                Text(
                                  dayLabel(summary.time!) == '今天'
                                      ? timeLabel(summary.time!)
                                      : dayLabel(summary.time!),
                                  key: ValueKey('conversation-time-${peer.id}'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (count > 0)
                                _badge(count)
                              else
                                Icon(
                                  peer.online
                                      ? LucideIcons.circleCheck
                                      : LucideIcons.circle,
                                  size: 18,
                                  color: peer.online ? green : muted,
                                  semanticLabel: peer.online ? '在线' : '离线',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                radius: 8,
              );
            },
          ),
  );

  Widget _androidPage() => RefreshIndicator(
    onRefresh: () async => service.refresh(),
    child: ListView(
      key: ValueKey('android-page-$_page'),
      controller: _pageScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _page == 3
          ? const EdgeInsets.fromLTRB(20, 12, 20, 24)
          : const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: switch (_page) {
              0 => _androidSendPage(),
              1 => _androidDevicesPage(),
              3 => _androidHistoryPage(),
              _ => _androidSettingsPage(),
            },
          ),
        ),
      ],
    ),
  );

  Widget _androidSection(String title, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?action,
      ],
    ),
  );

  Widget _androidSendPage() {
    final peers = online..sort(_androidComparePeers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.wifi, size: 16, color: green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                service.running ? '${peers.length} 台设备在线' : '正在连接局域网…',
                style: const TextStyle(color: muted),
              ),
            ),
          ],
        ),
        _androidSection('发送什么'),
        Row(
          children: [
            Expanded(
              child: _androidPicker(
                LucideIcons.folderOpen,
                '文件',
                () => _pickFiles(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _androidPicker(
                LucideIcons.images,
                '照片与视频',
                () => _pickFiles(type: FileType.media),
              ),
            ),
          ],
        ),
        if (_picking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 12),
          Material(
            color: blueTint,
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              key: const ValueKey('android-file-summary'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: FileGlyph(_files.first.name, size: 36),
              title: Text(
                '已选 ${_files.length} 个文件',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${formatBytes(_files.fold<int>(0, (sum, f) => sum + f.size))} · ${_files.first.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 20),
              onTap: _androidManageFiles,
            ),
          ),
        ],
        if (_sharedText.text.isNotEmpty) ...[
          _androidSection(
            '分享的文字',
            action: IconButton(
              tooltip: '移除文字',
              onPressed: () => _updateAndroid(_sharedText.clear),
              icon: const Icon(LucideIcons.x),
            ),
          ),
          TextField(
            controller: _sharedText,
            minLines: 2,
            maxLines: 3,
            maxLength: 16000,
            decoration: const InputDecoration(counterText: ''),
            onChanged: (_) => _updateAndroid(() {}),
          ),
        ],
        _androidSection(
          '发送给',
          action: IconButton(
            tooltip: '选择群组',
            onPressed: _pickGroupRecipient,
            icon: const Icon(LucideIcons.usersRound, size: 20),
          ),
        ),
        if (recipient != null && !service.peers.containsKey(recipient!.id))
          _androidPeerRow(recipient!, select: true),
        if (peers.isEmpty)
          _androidEmptyDevices()
        else
          ...peers.map((peer) => _androidPeerRow(peer, select: true)),
        if (activeCount > 0) ...[
          _androidSection(
            '正在传输',
            action: IconButton(
              tooltip: '查看全部记录',
              onPressed: () => _navigate(3),
              icon: const Icon(LucideIcons.arrowRight),
            ),
          ),
          ...service.transfers
              .where((f) => f.active)
              .take(3)
              .map(_androidTransferRow),
        ],
      ],
    );
  }

  Future<void> _androidManageFiles() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
      maxWidth: 640,
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, updateSheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('已选 ${_files.length} 个文件'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '清空文件',
                    onPressed: () {
                      _updateAndroid(_files.clear);
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(LucideIcons.trash2, size: 20),
                  ),
                  IconButton(
                    tooltip: '关闭文件清单',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return ListTile(
                    leading: FileGlyph(file.name),
                    title: Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(formatBytes(file.size)),
                    trailing: IconButton(
                      tooltip: '移除 ${file.name}',
                      onPressed: () {
                        _updateAndroid(() => _files.remove(file));
                        updateSheet(() {});
                        if (_files.isEmpty) Navigator.pop(sheetContext);
                      },
                      icon: const Icon(LucideIcons.x, size: 18),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _androidPicker(IconData icon, String label, VoidCallback action) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _picking ? null : action,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              children: [
                Icon(icon, size: 26, color: blue),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _androidPeerRow(Peer peer, {bool select = false}) {
    final selected = select && _sendPeerId == peer.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? blueTint : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          key: ValueKey('android-peer-${peer.id}'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: _conversationAvatar(peer, active: selected),
          title: Text(
            peer.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                peer.platform == 'Group'
                    ? '局域网群组'
                    : '${peer.remark.isNotEmpty ? '${peer.name} · ' : ''}${peer.platform}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (!peer.online && peer.platform != 'Group') ...[
                const SizedBox(height: 4),
                PeerLastSeen(
                  key: ValueKey('last-seen-${peer.id}'),
                  lastSeen: peer.lastSeen,
                ),
              ],
            ],
          ),
          trailing: select
              ? Icon(
                  selected ? LucideIcons.circleCheck : LucideIcons.circle,
                  color: selected ? blue : muted,
                  size: 22,
                )
              : Icon(
                  peer.online ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 18,
                  color: peer.online ? green : muted,
                  semanticLabel: peer.online ? '在线' : '离线',
                ),
          onTap: () => select
              ? _selectSendRecipient(peer.id)
              : _androidDeviceActions(peer),
          onLongPress: () => _androidDeviceActions(peer),
        ),
      ),
    );
  }

  Widget _androidSendBar() {
    final ready = recipient?.online == true && !_picking;
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    recipient?.displayName ?? '请选择接收设备',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _files.isEmpty
                        ? '文字消息'
                        : '${_files.length} 个文件 · ${formatBytes(_files.fold<int>(0, (sum, f) => sum + f.size))}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const ValueKey('android-send'),
              onPressed: ready ? _androidSend : null,
              icon: const Icon(LucideIcons.arrowUp, size: 20),
              label: const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }

  void _androidSend() {
    final peer = recipient;
    if (peer == null || !peer.online) return;
    final text = _sharedText.text.trim();
    final hasFiles = _files.isNotEmpty;
    if (text.isNotEmpty) {
      final group = service.groupForConversation(peer.id);
      unawaited(
        _guard(() async {
          if (group == null) {
            await service.sendMessage(peer, text);
          } else {
            await service.sendGroupMessage(group, text);
          }
          if (mounted) _updateAndroid(_sharedText.clear);
        }),
      );
    }
    if (hasFiles) {
      _sendFiles();
      _navigate(3);
    } else if (text.isNotEmpty) {
      _openConversation(peer);
    }
  }

  Widget _androidDevicesPage() {
    final query = _deviceSearch.text.toLowerCase();
    final peers =
        service.peers.values
            .where(
              (p) => '${p.displayName} ${p.name} ${p.host}'
                  .toLowerCase()
                  .contains(query),
            )
            .toList()
          ..sort(_androidComparePeers);
    final connected = peers.where((p) => p.online).toList();
    final offline = peers.where((p) => !p.online).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _deviceSearch,
          onChanged: (_) => _updateAndroid(() {}),
          decoration: InputDecoration(
            hintText: '搜索设备或备注',
            prefixIcon: const Icon(LucideIcons.search, size: 20),
            suffixIcon: _deviceSearch.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除设备搜索',
                    onPressed: () => _updateAndroid(_deviceSearch.clear),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
          ),
        ),
        _androidSection('在线设备 · ${connected.length}'),
        if (peers.isEmpty)
          _androidEmptyDevices(searching: query.isNotEmpty)
        else if (connected.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('设备在线后即可发送文件。', style: TextStyle(color: muted)),
          ),
        ...connected.map((peer) => _androidPeerRow(peer)),
        if (offline.isNotEmpty) ...[
          _androidSection('最近离线 · ${offline.length}'),
          ...offline.map((peer) => _androidPeerRow(peer)),
        ],
        const SizedBox(height: 16),
        _androidSettingsRow(
          LucideIcons.link,
          '本机连接信息',
          service.name,
          () => _androidSettingsDetail('本机连接信息', _androidConnectionItems),
        ),
      ],
    );
  }

  Future<void> _androidDeviceActions(Peer peer) => _androidSheet([
    ListTile(
      leading: _conversationAvatar(peer),
      title: Text(peer.displayName),
      subtitle: Text(peer.remark.isEmpty ? peer.platform : peer.name),
    ),
    const Divider(),
    ListTile(
      leading: const Icon(LucideIcons.send),
      title: const Text('发送文件'),
      enabled: peer.online,
      onTap: () {
        Navigator.pop(context);
        _prepareSend(peer);
      },
    ),
    ListTile(
      leading: const Icon(LucideIcons.messageCircle),
      title: const Text('发消息'),
      onTap: () {
        Navigator.pop(context);
        _openConversation(peer);
      },
    ),
    if (service.peers.containsKey(peer.id))
      ListTile(
        leading: const Icon(LucideIcons.pencil),
        title: const Text('修改备注'),
        onTap: () {
          Navigator.pop(context);
          unawaited(_editRemark(peer));
        },
      ),
    if (service.groupForConversation(peer.id) case final group?)
      ListTile(
        leading: const Icon(LucideIcons.usersRound),
        title: const Text('群组详情'),
        onTap: () {
          Navigator.pop(context);
          unawaited(_groupDetails(group));
        },
      ),
  ]);

  Widget _androidHistoryPage() {
    final items = _filteredTransfers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _historySearch,
          onChanged: (_) => _updateAndroid(() {}),
          decoration: InputDecoration(
            hintText: '搜索文件或设备',
            prefixIcon: const Icon(LucideIcons.search),
            suffixIcon: _historySearch.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除记录搜索',
                    onPressed: () => _updateAndroid(_historySearch.clear),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            4,
            (i) => ChoiceChip(
              key: ValueKey('android-history-filter-$i'),
              label: Text(['全部', '传输中', '已接收', '失败'][i]),
              selected: _historyFilter == i,
              onSelected: (_) => _updateAndroid(() {
                _historyFilter = i;
                _directionFilter = i == 2 ? 2 : 0;
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          EmptyState(
            icon: LucideIcons.history,
            label: service.transfers.isEmpty ? '这里还没有传输记录' : '没有符合条件的记录',
            detail: service.transfers.isEmpty
                ? '发送和接收的文件都会留在这里。'
                : '换个关键词，或清除筛选条件。',
            action: service.transfers.isEmpty
                ? null
                : TextButton(
                    onPressed: () => _updateAndroid(() {
                      _historyFilter = 0;
                      _directionFilter = 0;
                      _historySearch.clear();
                    }),
                    child: const Text('重置筛选'),
                  ),
          ),
        for (final item in items) _androidTransferRow(item, compact: false),
      ],
    );
  }

  Widget _androidTransferRow(
    TransferItem item, {
    bool compact = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _androidFileActions(item),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FileGlyph(item.name, size: compact ? 32 : 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.outgoing ? '发送给' : '来自'} ${service.peers[item.peerId]?.displayName ?? item.peerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (compact &&
                      !item.outgoing &&
                      item.status == TransferStatus.complete &&
                      item.savedPath != null)
                    IconButton(
                      tooltip: '打开 ${item.name}',
                      onPressed: () => _guard(
                        () => widget.android!.openFile(item.savedPath!),
                      ),
                      icon: const Icon(LucideIcons.externalLink, size: 18),
                    ),
                  IconButton(
                    tooltip: '文件操作',
                    onPressed: () => _androidFileActions(item),
                    icon: const Icon(LucideIcons.ellipsis, size: 20),
                  ),
                ],
              ),
              if (item.active) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: item.status == TransferStatus.transferring
                      ? item.progress
                      : null,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    item.statusLabel,
                    style: TextStyle(
                      color: item.status == TransferStatus.failed
                          ? danger
                          : item.status == TransferStatus.complete
                          ? green
                          : blue,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    formatBytes(item.size),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  Text(
                    item.active && item.bytesPerSecond > 0
                        ? formatBytes(item.bytesPerSecond, speed: true)
                        : '${dayLabel(item.createdAt)} ${timeLabel(item.createdAt)}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _androidFileActions(TransferItem item) => _androidSheet([
    ListTile(
      leading: FileGlyph(item.name),
      title: Text(item.name),
      subtitle: Text('${item.statusLabel} · ${formatBytes(item.size)}'),
    ),
    if (item.error != null)
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(item.error!, style: const TextStyle(color: danger)),
      ),
    const Divider(),
    if (!item.outgoing &&
        item.status == TransferStatus.complete &&
        item.savedPath != null) ...[
      ListTile(
        leading: const Icon(LucideIcons.externalLink),
        title: const Text('打开文件'),
        onTap: () {
          Navigator.pop(context);
          unawaited(_guard(() => widget.android!.openFile(item.savedPath!)));
        },
      ),
      ListTile(
        leading: const Icon(LucideIcons.download),
        title: const Text('另存到手机'),
        onTap: () {
          Navigator.pop(context);
          unawaited(
            _guard(() async {
              if (await widget.android!.exportFile(item.savedPath!)) {
                _toast('文件已保存');
              }
            }),
          );
        },
      ),
      ListTile(
        leading: const Icon(LucideIcons.share2),
        title: const Text('分享'),
        onTap: () {
          Navigator.pop(context);
          unawaited(_guard(() => widget.android!.shareFile(item.savedPath!)));
        },
      ),
    ],
    if (item.active)
      ListTile(
        leading: const Icon(LucideIcons.x, color: danger),
        title: const Text('取消传输'),
        onTap: () {
          Navigator.pop(context);
          service.cancel(item);
        },
      ),
    if (!item.active && item.outgoing && item.status != TransferStatus.complete)
      ListTile(
        leading: const Icon(LucideIcons.rotateCcw),
        title: const Text('重新发送'),
        enabled: service.peers[item.peerId]?.online == true,
        onTap: () {
          Navigator.pop(context);
          unawaited(_guard(() => service.retry(item)));
        },
      ),
  ]);

  Future<void> _androidReviewOffer(String id) async {
    final offer = service.incoming
        .where((o) => o.id == id && !o.decision.isCompleted)
        .firstOrNull;
    if (offer == null) {
      _toast('该请求已处理或已过期');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
        maxWidth: 640,
      ),
      builder: (sheetContext) => StreamBuilder<void>(
        stream: service.changes,
        builder: (context, snapshot) {
          final pending = !offer.decision.isCompleted;
          void decide(bool accept) {
            if (!offer.decision.isCompleted) {
              service.decide(offer, accept);
              if (accept) _navigate(3);
            } else {
              _toast('该请求已处理或已过期');
            }
            Navigator.pop(sheetContext);
          }

          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: _conversationAvatar(offer.peer),
                  title: Text('${offer.peer.displayName} 发来文件'),
                  subtitle: Text(
                    '${offer.files.length} 个文件 · ${formatBytes(offer.size)}',
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: offer.files.length,
                    itemBuilder: (context, index) {
                      final f = offer.files[index];
                      return ListTile(
                        leading: FileGlyph(f.name),
                        title: Text(
                          f.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(formatBytes(f.size)),
                      );
                    },
                  ),
                ),
                if (!pending)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('该请求已处理或已过期', style: TextStyle(color: muted)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pending ? () => decide(false) : null,
                          child: const Text('拒绝'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: pending ? () => decide(true) : null,
                          icon: const Icon(LucideIcons.download, size: 18),
                          label: const Text('接收'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _androidSheet(List<Widget> children) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
          maxWidth: 640,
        ),
        builder: (context) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      );

  Widget _androidSettingsPage() {
    final host = widget.android!;
    final notifications = widget.notifications;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _androidDeviceIdentity(editable: true),
        const SizedBox(height: 16),
        _androidSettingsRow(
          LucideIcons.folderDown,
          '接收与保存',
          '后台接收${host.backgroundEnabled ? '已开启' : '已关闭'}',
          () => _androidSettingsDetail('接收与保存', _androidReceivingItems),
          accent: green,
        ),
        if (notifications != null)
          ListenableBuilder(
            listenable: notifications,
            builder: (context, _) => _androidSettingsRow(
              LucideIcons.bell,
              '通知与声音',
              notifications.allowed != true ? '系统通知尚未开启' : '文件、消息与完成提醒',
              () => _androidSettingsDetail('通知与声音', _androidNotificationItems),
            ),
          ),
        _androidSettingsRow(
          LucideIcons.wifi,
          '连接信息',
          '${online.length} 台设备在线',
          () => _androidSettingsDetail('连接信息', _androidConnectionItems),
        ),
        _androidSettingsRow(
          LucideIcons.scrollText,
          '诊断与日志',
          '查看运行状态、导出日志',
          () => _androidSettingsDetail(
            '诊断与日志',
            () => [
              _androidSettingsRow(
                LucideIcons.scrollText,
                '运行日志',
                null,
                () => showDialog<void>(
                  context: context,
                  builder: (_) => LogViewer(log: service.log),
                ),
              ),
              _androidSettingsRow(
                LucideIcons.download,
                '导出日志',
                null,
                () => exportLogs(context, service.log),
              ),
            ],
          ),
          accent: muted,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/brand/app-icon.png',
                width: 24,
                height: 24,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '邻传 NearLink · 0.3.3',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _androidDeviceIdentity({bool editable = false}) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    child: ListTile(
      key: const ValueKey('android-device-name'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: const DeviceAvatar('Android', size: 48),
      title: Text(
        service.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('这台设备', style: Theme.of(context).textTheme.bodySmall),
      ),
      trailing: editable
          ? const Tooltip(
              message: '修改设备名称',
              child: Icon(LucideIcons.pencil, size: 18, color: muted),
            )
          : null,
      onTap: editable
          ? () async {
              final name = await showDialog<String>(
                context: context,
                builder: (_) => _NameDialog(
                  title: '设备名称',
                  label: '设备名称',
                  initial: service.name,
                  allowEmpty: false,
                ),
              );
              if (name != null) {
                await _guard(() => service.updateSettings(deviceName: name));
              }
            }
          : null,
    ),
  );

  Widget _androidSettingsIcon(IconData icon, Color accent) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: accent == green
          ? mint
          : accent == blue
          ? blueTint
          : canvas,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: accent, size: 21),
  );

  Widget _androidSettingsRow(
    IconData icon,
    String title,
    String? subtitle,
    VoidCallback action, {
    Color accent = blue,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _androidSettingsIcon(icon, accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(LucideIcons.chevronRight, size: 18, color: muted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _androidSettingsGroup(List<Widget> children) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Future<void> _androidSettingsDetail(
    String title,
    List<Widget> Function() items,
  ) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (routeContext) => StreamBuilder<void>(
        stream: service.changes,
        builder: (context, _) => ListenableBuilder(
          listenable: Listenable.merge([
            widget.android!,
            if (widget.notifications != null) widget.notifications!,
          ]),
          builder: (context, _) => Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(routeContext).pop(),
                icon: const Icon(LucideIcons.arrowLeft, size: 20),
              ),
              title: Text(title),
              backgroundColor: canvas,
              surfaceTintColor: Colors.transparent,
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: items(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _androidReceivingItems() {
    final host = widget.android!;
    return [
      _androidSettingsRow(LucideIcons.folderDown, '接收的文件', '查看、打开或另存到手机', () {
        _updateAndroid(() {
          _historyFilter = 2;
          _directionFilter = 2;
          _historySearch.clear();
        });
        Navigator.pop(context);
        _navigate(3);
      }),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 4, 4, 20),
        child: Text(
          '收到的文件保存在邻传内。重要文件请另存到手机，卸载应用会删除应用内的文件。',
          style: TextStyle(color: muted, fontSize: 13, height: 1.6),
        ),
      ),
      _androidSettingsGroup([
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          title: Text('后台接收', style: Theme.of(context).textTheme.bodyLarge),
          subtitle: Text(
            '保持连接，并显示常驻通知',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: host.backgroundEnabled,
          onChanged: host.updating ? null : host.setBackground,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            '部分手机还需要在系统中允许邻传后台运行。',
            style: TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
      if (host.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(host.error!, style: const TextStyle(color: danger)),
        ),
    ];
  }

  List<Widget> _androidConnectionItems() => [
    _androidDeviceIdentity(),
    _androidSection('连接地址'),
    if (service.addresses.isNotEmpty)
      _androidSettingsGroup([
        for (var i = 0; i < service.addresses.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 68, endIndent: 16),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: _androidSettingsIcon(LucideIcons.link, green),
            title: Text(
              '${service.addresses[i]}:${service.port}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            trailing: IconButton(
              tooltip: '复制连接地址',
              onPressed: () => _copy('${service.addresses[i]}:${service.port}'),
              icon: const Icon(LucideIcons.copy, size: 20),
            ),
          ),
        ],
      ]),
    if (service.addresses.isEmpty)
      const Text('尚未获取到连接地址，请检查网络。', style: TextStyle(color: muted)),
  ];

  List<Widget> _androidNotificationItems() {
    final notifications = widget.notifications!;
    return [
      _androidSettingsRow(
        LucideIcons.settings2,
        '系统通知设置',
        notifications.allowed == true ? '系统通知已允许' : '系统通知尚未开启',
        notifications.openSettings,
      ),
      if (notifications.allowed != true)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              await widget.android!.requestNotifications();
              await notifications.refresh();
            },
            icon: const Icon(LucideIcons.bell, size: 18),
            label: const Text('开启通知权限'),
          ),
        ),
      _androidSection('文件接收'),
      _androidSettingsGroup([
        _androidSwitch(
          '文件接收通知',
          notifications.enabled,
          (value) => notifications.update(enabled: value),
          enabled: !notifications.updating,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        _androidSwitch(
          '文件接收提示音',
          notifications.sound,
          (value) => notifications.update(sound: value),
          enabled: !notifications.updating && notifications.enabled,
        ),
      ]),
      _androidSection('消息'),
      _androidSettingsGroup([
        _androidSwitch(
          '消息通知',
          notifications.messageEnabled,
          (value) => notifications.update(messageEnabled: value),
          enabled: !notifications.updating,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        _androidSwitch(
          '消息提示音',
          notifications.messageSound,
          (value) => notifications.update(messageSound: value),
          enabled: !notifications.updating,
        ),
      ]),
      _androidSection('传输完成'),
      _androidSettingsGroup([
        _androidSwitch(
          '传输完成通知',
          notifications.completionEnabled,
          (value) => notifications.update(completionEnabled: value),
          enabled: !notifications.updating,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        _androidSwitch(
          '传输完成提示音',
          notifications.completionSound,
          (value) => notifications.update(completionSound: value),
          enabled: !notifications.updating && notifications.completionEnabled,
        ),
      ]),
      if (notifications.error != null)
        Text(notifications.error!, style: const TextStyle(color: danger)),
    ];
  }

  Widget _androidSwitch(
    String label,
    bool value,
    ValueChanged<bool> change, {
    bool enabled = true,
  }) => SwitchListTile.adaptive(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
    value: value,
    onChanged: enabled ? change : null,
  );
}
