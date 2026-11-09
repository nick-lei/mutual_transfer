part of 'workspace.dart';

typedef _ChatEntry = ({
  DateTime time,
  ChatMessage? message,
  TransferItem? file,
});

extension _ChatFiles on _WorkspaceState {
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
      preview: message != null
          ? service.messagePreview(message)
          : peer.online
          ? '在线，可以开始聊天'
          : '设备暂时离线',
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

  Widget _chatFileBubble(TransferItem file) {
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
            child: Material(
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
                            style: TextStyle(fontSize: 12, color: statusColor),
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
                                : () => _openFolder(p.dirname(file.savedPath!)),
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
          ),
        ),
      ),
    );
  }
}
