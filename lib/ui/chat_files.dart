part of 'workspace.dart';

typedef _ChatEntry = ({
  DateTime time,
  ChatMessage? message,
  TransferItem? file,
});

extension _ChatFiles on _WorkspaceState {
  bool _chatDropVisible(BuildContext dropContext, String peerId) =>
      mounted &&
      _page == 2 &&
      _chatPeerId == peerId &&
      !_choosingForward &&
      ModalRoute.of(dropContext)?.isCurrent != false;

  Future<void> _dropConversationFiles(
    String targetId,
    List<String> paths,
  ) async {
    if (_pickingChat) return;
    _setPickingChat(true);
    try {
      await _guard(() async {
        final files = await LocalFile.fromPaths(paths);
        if (!mounted) return;
        if (files.isEmpty) {
          throw const FormatException('没有可发送的文件，请确认文件仍在原位置');
        }
        // Disk enumeration may outlive a conversation change or presence update.
        final group = service.groupForConversation(targetId);
        final peer = service.peers[targetId] ?? _groupPeer(group);
        if (peer == null || !_forwardTargetOnline(peer)) {
          throw const FormatException('接收方已离线，请上线后重新拖入文件');
        }
        unawaited(
          _guard(
            () => group == null
                ? service.sendFiles(peer, files)
                : service.sendGroupFiles(group, files),
          ),
        );
        if (_chatPeerId == targetId) _scrollConversation();
      });
    } finally {
      if (mounted) _setPickingChat(false);
    }
  }

  Widget _conversationDropTarget(Peer peer, Widget child) {
    if (widget.android != null) return child;
    return Builder(
      builder: (dropContext) {
        final visible = _chatDropVisible(dropContext, peer.id);
        final available = _forwardTargetOnline(peer);
        final hovering = visible && _chatDragPeerId == peer.id;
        final ready = available && !_pickingChat;
        final color = available ? blue : muted;
        void enter(DropEventDetails _) {
          if (_chatDropVisible(dropContext, peer.id)) _setChatDragPeer(peer.id);
        }

        return DropTarget(
          key: ValueKey('chat-drop-${peer.id}'),
          enable: visible,
          onDragEntered: enter,
          onDragUpdated: enter,
          onDragExited: (_) => _setChatDragPeer(null),
          onDragDone: (details) {
            _setChatDragPeer(null);
            if (!_chatDropVisible(dropContext, peer.id)) return;
            if (!available || !_forwardTargetOnline(peer)) {
              _toast('接收方已离线，请上线后重新拖入文件');
              return;
            }
            if (_pickingChat) {
              _toast('正在整理文件，请稍候再拖入');
              return;
            }
            unawaited(
              _dropConversationFiles(
                peer.id,
                details.files.map((file) => file.path).toList(),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (hovering)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      key: ValueKey('chat-drop-feedback-${peer.id}'),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ready
                                  ? LucideIcons.folderUp
                                  : LucideIcons.circleAlert,
                              size: 36,
                              color: color,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              available
                                  ? _pickingChat
                                        ? '正在整理文件，请稍候'
                                        : '发送给 ${peer.displayName}'
                                  : '${peer.displayName} 已离线',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              ready ? '松开发送' : '请稍后重新拖入',
                              style: const TextStyle(
                                fontSize: 13,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<_ChatEntry> _conversationEntries(String id) {
    final entries = <_ChatEntry>[
      for (final message in service.messages)
        if (message.conversationId == id)
          (time: message.time, message: message, file: null),
      // Transfer records own the live progress and remain the single source of truth.
      for (final file in service.transfers)
        if (file.conversationId == id)
          (time: file.createdAt, message: null, file: file),
    ];
    // The original index preserves batch order when timestamps are identical.
    final indexed = entries.indexed.toList()
      ..sort((a, b) {
        final order = a.$2.time.compareTo(b.$2.time);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    return indexed.map((entry) => entry.$2).toList();
  }

  ({DateTime? time, String preview}) _conversationSummary(Peer peer) {
    ChatMessage? message;
    TransferItem? file;
    for (final candidate in service.messages) {
      if (candidate.conversationId == peer.id &&
          (message == null || !candidate.time.isBefore(message.time))) {
        message = candidate;
      }
    }
    for (final candidate in service.transfers) {
      if (candidate.conversationId == peer.id &&
          (file == null || candidate.createdAt.isAfter(file.createdAt))) {
        file = candidate;
      }
    }
    if (file != null &&
        (message == null || !file.createdAt.isBefore(message.time))) {
      return (time: file.createdAt, preview: '[文件] ${file.name}');
    }
    return (
      time: message?.time,
      preview: message != null ? service.messagePreview(message) : '暂无消息',
    );
  }

  Future<void> _pickConversationFiles(Peer peer) async {
    if (_pickingChat || !peer.online) return;
    _setPickingChat(true);
    try {
      await _guard(() async {
        final result = await FilePicker.pickFiles(
          allowMultiple: true,
          withData: false,
          dialogTitle: '给 ${peer.displayName} 发送文件',
        );
        if (result == null || !mounted) return;
        final files = await LocalFile.fromPaths(
          result.paths.whereType<String>().toList(),
        );
        if (!mounted) return;
        if (files.isEmpty) {
          _toast('没有可发送的文件');
          return;
        }
        final group = service.groupForConversation(peer.id);
        // Capture the recipient before opening the picker; changing chats must
        // never redirect a pending selection to a different device.
        unawaited(
          _guard(
            () => group == null
                ? service.sendFiles(peer, files)
                : service.sendGroupFiles(group, files),
          ),
        );
        if (_chatPeerId == peer.id) _scrollConversation();
      });
    } finally {
      if (mounted) _setPickingChat(false);
    }
  }

  Future<void> _openChatFile(TransferItem file) => _guard(() async {
    final path = file.outgoing ? file.sourcePath : file.savedPath;
    if (path == null || !await File(path).exists()) {
      throw const FormatException('文件已被移动或删除，请重新发送');
    }
    if (widget.android != null) {
      await widget.android!.openFile(path);
    } else if (Platform.isWindows) {
      await Process.start('explorer.exe', [path]);
    } else {
      await Process.start(Platform.isMacOS ? 'open' : 'xdg-open', [path]);
    }
  });

  String? _forwardFilePath(TransferItem file) =>
      file.status == TransferStatus.complete
      ? file.outgoing
            ? file.sourcePath
            : file.savedPath
      : null;

  bool _forwardTargetOnline(Peer peer) {
    final group = service.groupForConversation(peer.id);
    return group == null
        ? service.peers[peer.id]?.online == true
        : group.activeFor(service.id) &&
              service.groupPeers(group).any((member) => member.online);
  }

  bool _canForwardTo(TransferItem file, Peer peer) =>
      _forwardFilePath(file) != null &&
      peer.id != file.conversationId &&
      _forwardTargetOnline(peer);

  Future<void> _forwardChatFile(
    TransferItem file,
    String targetId,
  ) => _guard(() async {
    final path = _forwardFilePath(file);
    if (path == null) throw const FormatException('文件传输完成后才可转发');
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('文件已被移动或删除，无法转发');
    }
    final localFile = LocalFile(
      path: path,
      name: file.name,
      size: await File(path).length(),
    );
    if (!mounted) return;
    // Resolve again after disk I/O; never use a stale recipient or redirect it.
    final group = service.groupForConversation(targetId);
    final peer = service.peers[targetId] ?? _groupPeer(group);
    if (peer == null || !_canForwardTo(file, peer)) {
      throw const FormatException('目标设备当前不可用，请选择其他在线设备');
    }
    _openConversation(peer);
    unawaited(
      _guard(
        () => group == null
            ? service.sendFiles(peer, [localFile])
            : service.sendGroupFiles(group, [localFile]),
      ),
    );
  });

  Future<void> _chooseForwardRecipient(TransferItem file) async {
    if (_choosingForward) return;
    _choosingForward = true;
    _syncMessageView();
    String? targetId;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      targetId = await (widget.android != null
          ? _mobileForwardRecipient(file)
          : _desktopForwardRecipient(file));
    } finally {
      _choosingForward = false;
      if (mounted) _syncMessageView();
    }
    if (targetId != null && mounted) await _forwardChatFile(file, targetId);
  }

  List<Peer> _forwardRecipients(TransferItem file, {String query = ''}) {
    final search = query.trim().toLowerCase();
    return [
          ...service.peers.values,
          ...service.groups.values.map(_groupPeer).whereType<Peer>(),
        ]
        .where(
          (peer) =>
              peer.id != file.conversationId &&
              [
                peer.displayName,
                peer.name,
                peer.address,
              ].any((value) => value.toLowerCase().contains(search)),
        )
        .toList()
      ..sort((a, b) {
        final availability = _comparePeerAvailability(a, b);
        return availability != 0
            ? availability
            : a.displayName.compareTo(b.displayName);
      });
  }

  Future<String?> _desktopForwardRecipient(
    TransferItem file,
  ) => showDialog<String>(
    context: context,
    builder: (dialogContext) => StreamBuilder<void>(
      stream: service.changes,
      builder: (context, _) {
        final peers = _forwardRecipients(file);
        return AlertDialog(
          key: const ValueKey('forward-file-dialog'),
          title: const Text('转发文件'),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatBytes(file.size),
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 16),
                if (peers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('暂无其他设备', style: TextStyle(color: muted)),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .4,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: peers.map((peer) {
                          final online = _forwardTargetOnline(peer);
                          final group = service.groupForConversation(peer.id);
                          return ListTile(
                            key: ValueKey('forward-recipient-${peer.id}'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            leading: _conversationAvatar(peer),
                            title: Text(
                              peer.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              online
                                  ? group == null
                                        ? '在线'
                                        : '群聊 · ${group.members.length} 位成员'
                                  : group == null
                                  ? '离线'
                                  : '暂无在线成员',
                            ),
                            trailing: Icon(
                              online ? LucideIcons.forward : LucideIcons.circle,
                              size: 18,
                              color: online ? blue : muted,
                            ),
                            enabled: online,
                            onTap: online
                                ? () => Navigator.pop(dialogContext, peer.id)
                                : null,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
        );
      },
    ),
  );

  Widget _conversationFileTarget(
    Peer peer,
    Widget child, {
    double radius = 12,
  }) => DragTarget<TransferItem>(
    key: ValueKey('forward-target-${peer.id}'),
    onWillAcceptWithDetails: (details) => _canForwardTo(details.data, peer),
    onAcceptWithDetails: (details) =>
        unawaited(_forwardChatFile(details.data, peer.id)),
    builder: (context, accepted, rejected) {
      final hovered = accepted.isNotEmpty || rejected.isNotEmpty;
      final ready = accepted.isNotEmpty && _canForwardTo(accepted.first!, peer);
      return MouseRegion(
        cursor: hovered
            ? ready
                  ? SystemMouseCursors.copy
                  : SystemMouseCursors.forbidden
            : MouseCursor.defer,
        child: Stack(
          children: [
            child,
            if (hovered)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: ValueKey('forward-hover-${peer.id}'),
                    decoration: BoxDecoration(
                      color: (ready ? blue : danger).withValues(alpha: .05),
                      border: Border.all(
                        color: ready ? blue : danger,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(radius),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _draggableChatFile(
    TransferItem file,
    Widget child, {
    required bool enabled,
  }) {
    if (!enabled || _forwardFilePath(file) == null) return child;
    final preview = Transform.translate(
      offset: const Offset(16, 16),
      child: Material(
        key: const ValueKey('chat-file-drag-preview'),
        elevation: 6,
        shadowColor: ink.withValues(alpha: .18),
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 240,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FileGlyph(file.name),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.forward, size: 18, color: blue),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.android != null) {
      return LongPressDraggable<TransferItem>(
        key: ValueKey('chat-file-drag-${file.id}'),
        data: file,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: preview,
        childWhenDragging: Opacity(opacity: .45, child: child),
        child: child,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<TransferItem>(
        key: ValueKey('chat-file-drag-${file.id}'),
        data: file,
        maxSimultaneousDrags: 1,
        allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: preview,
        childWhenDragging: Opacity(opacity: .45, child: child),
        child: child,
      ),
    );
  }

  Widget _chatFileBubble(TransferItem file, {required bool allowDrag}) {
    final offer = service.incoming
        .where(
          (offer) =>
              !offer.decision.isCompleted &&
              offer.files.any((item) => item.id == file.id),
        )
        .firstOrNull;
    final complete = file.status == TransferStatus.complete;
    final failed = file.status == TransferStatus.failed;
    final statusColor = complete
        ? green
        : failed
        ? danger
        : file.active
        ? blue
        : amber;
    final canOpen =
        complete &&
        (file.outgoing ? file.sourcePath != null : file.savedPath != null);
    return LayoutBuilder(
      builder: (context, box) => Align(
        alignment: file.outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: SizedBox(
            width: (box.maxWidth * .92).clamp(0, 320),
            child: _draggableChatFile(
              file,
              Material(
                key: ValueKey('chat-file-${file.id}'),
                color: file.outgoing
                    ? blueTint
                    : widget.android != null
                    ? Colors.white
                    : canvas,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (file.groupId != null) ...[
                        Text(
                          '${file.outgoing ? '发送给' : '来自'} ${service.peers[file.peerId]?.displayName ?? file.peerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                        const SizedBox(height: 8),
                      ],
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: canOpen ? () => _openChatFile(file) : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FileGlyph(file.name),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: file.name,
                                    child: Text(
                                      file.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
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
                          ],
                        ),
                      ),
                      if (file.active) ...[
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          key: ValueKey('chat-progress-${file.id}'),
                          value:
                              file.status == TransferStatus.hashing ||
                                  file.status == TransferStatus.waiting
                              ? null
                              : file.progress,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                          backgroundColor: line,
                          color: blue,
                        ),
                        if (file.status == TransferStatus.transferring) ...[
                          const SizedBox(height: 7),
                          Text(
                            '${(file.progress * 100).floor()}% · ${formatBytes(file.bytes)} / ${formatBytes(file.size)}'
                            '${file.bytesPerSecond > 0 ? ' · ${formatBytes(file.bytesPerSecond, speed: true)}' : ''}',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ],
                      if (file.error != null && !file.active) ...[
                        const SizedBox(height: 10),
                        Text(
                          file.error!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: danger),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            complete
                                ? LucideIcons.circleCheck
                                : failed
                                ? LucideIcons.circleAlert
                                : file.active
                                ? LucideIcons.arrowRightLeft
                                : LucideIcons.circleX,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              complete
                                  ? file.outgoing
                                        ? '已发送'
                                        : '已接收'
                                  : file.statusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: statusColor,
                              ),
                            ),
                          ),
                          if (offer != null) ...[
                            IconButton(
                              tooltip: '拒绝此批 ${offer.files.length} 个文件',
                              color: danger,
                              onPressed: () => service.decide(offer, false),
                              icon: const Icon(LucideIcons.x, size: 19),
                            ),
                            IconButton(
                              tooltip: '接收此批 ${offer.files.length} 个文件',
                              color: green,
                              onPressed: () => service.decide(offer, true),
                              icon: const Icon(LucideIcons.check, size: 19),
                            ),
                          ] else if (file.active)
                            IconButton(
                              tooltip: file.outgoing ? '取消本批传输' : '取消接收',
                              onPressed: () => service.cancel(file),
                              icon: const Icon(LucideIcons.x, size: 18),
                            )
                          else if (file.outgoing && !complete)
                            IconButton(
                              tooltip: '重新发送',
                              onPressed:
                                  service.peers[file.peerId]?.online == true
                                  ? () => _guard(() => service.retry(file))
                                  : null,
                              icon: const Icon(LucideIcons.rotateCcw, size: 18),
                            ),
                          if (canOpen)
                            IconButton(
                              key: ValueKey('forward-file-${file.id}'),
                              tooltip: '转发文件',
                              onPressed: () => _chooseForwardRecipient(file),
                              icon: const Icon(LucideIcons.forward, size: 18),
                            ),
                          if (canOpen)
                            IconButton(
                              tooltip: '打开文件',
                              onPressed: () => _openChatFile(file),
                              icon: const Icon(
                                LucideIcons.externalLink,
                                size: 18,
                              ),
                            ),
                          if (complete && !file.outgoing)
                            IconButton(
                              tooltip: widget.android != null
                                  ? '更多文件操作'
                                  : '打开所在目录',
                              onPressed: widget.android != null
                                  ? () => _androidFileActions(file)
                                  : file.savedPath == null
                                  ? null
                                  : () =>
                                        _openFolder(p.dirname(file.savedPath!)),
                              icon: Icon(
                                widget.android != null
                                    ? LucideIcons.ellipsis
                                    : LucideIcons.folderOpen,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              enabled: allowDrag,
            ),
          ),
        ),
      ),
    );
  }
}
