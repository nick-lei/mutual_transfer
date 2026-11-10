part of 'workspace.dart';

extension _GroupWorkspace on _WorkspaceState {
  Peer? _groupPeer(LanGroup? group) => group == null
      ? null
      : (Peer(
          id: group.conversationId,
          name: group.name,
          host: '',
          port: 0,
          platform: 'Group',
        )..online = group.activeFor(service.id) && group.members.length > 1);

  Widget _groupAvatar({double size = 40}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(LucideIcons.users, color: green, size: size * .48),
  );

  Widget _conversationAvatar(Peer peer, {bool active = false}) =>
      peer.platform == 'Group'
      ? _groupAvatar()
      : DeviceAvatar(peer.platform, size: 40, active: active);

  Widget _conversationPresence(Peer peer) {
    final group = service.groupForConversation(peer.id);
    final available = _forwardTargetOnline(peer);
    final String label;
    if (group == null) {
      label = available ? '在线' : '离线';
    } else if (group.dissolved) {
      label = '已解散';
    } else if (group.left) {
      label = '已退出';
    } else if (!group.contains(service.id)) {
      label = '已移出';
    } else {
      final count = service.groupPeers(group).where((p) => p.online).length + 1;
      label = count == 1 ? '仅你在线' : '$count 人在线';
    }
    final color = available ? green : muted;
    return Tooltip(
      message: group == null
          ? available
                ? '在线，可以发送消息和文件'
                : '离线，可查看历史消息'
          : _groupStatus(group),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: available ? green : Colors.transparent,
              border: available ? null : Border.all(color: muted),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            key: ValueKey('conversation-presence-${peer.id}'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _groupStatus(LanGroup group) {
    if (group.dissolved) return '群组已解散 · 可查看历史消息';
    if (group.left) {
      if (group.pendingSync.isNotEmpty) return '已退出 · 等待同步群主';
      return group.contains(service.id)
          ? '已退出 · 群主已添加，可重新加入'
          : '已退出群组 · 可查看历史消息';
    }
    if (!group.contains(service.id)) return '已移出群组 · 可查看历史消息';
    final count = service.groupPeers(group).where((p) => p.online).length + 1;
    return '${group.members.length} 位成员 · $count 人在线';
  }

  Future<void> _editRemark(Peer peer) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: '设备备注',
        label: '备注名',
        initial: peer.remark,
        allowEmpty: true,
        detail: '仅自己可见 · ${peer.name}',
        hint: '留空恢复设备名称',
      ),
    );
    if (value != null && mounted) {
      await _guard(() => service.setPeerRemark(peer, value));
    }
  }

  Future<void> _editGroup([LanGroup? group, bool asRecipient = false]) async {
    final target = await showDialog<LanGroup>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GroupEditor(service: service, group: group),
    );
    if (target == null || !mounted) return;
    if (asRecipient) {
      _prepareSend(_groupPeer(target)!);
    } else {
      _openConversation(_groupPeer(target)!);
    }
    if (target.pendingSync.isNotEmpty) {
      _toast('${target.pendingSync.length} 位成员暂未同步，可在群组详情重试');
    }
  }

  Future<void> _pickGroupRecipient() async {
    final groups = service.groups.values
        .where((g) => g.activeFor(service.id) && g.members.length > 1)
        .toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Row(
          children: [
            const Expanded(child: Text('发送到群组')),
            IconButton(
              tooltip: '新建群组',
              onPressed: () => Navigator.pop(dialogContext, 'new'),
              icon: const Icon(LucideIcons.userPlus, size: 20),
            ),
          ],
        ),
        children: [
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有可用群组', style: TextStyle(color: muted)),
            ),
          for (final group in groups)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(dialogContext, group.conversationId),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _groupAvatar(),
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_groupStatus(group)),
              ),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'new') {
      await _editGroup(null, true);
      return;
    }
    _selectSendRecipient(selected);
  }

  Future<bool> _confirmGroupAction(LanGroup group) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            group.ownerId == service.id
                ? '解散「${group.name}」？'
                : '退出「${group.name}」？',
          ),
          content: Text(
            group.ownerId == service.id
                ? '成员将无法继续在此群组发送消息和文件，历史记录会保留。'
                : '退出后不再接收此群的新消息，历史记录会保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(group.ownerId == service.id ? '解散群组' : '退出群组'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _groupDetails(LanGroup original) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StreamBuilder<void>(
        stream: service.changes,
        builder: (_, _) {
          final group = service.groups[original.id] ?? original;
          final active = group.activeFor(service.id);
          final owner = group.ownerId == service.id;
          final files = service.transfers
              .where((f) => f.groupId == group.id)
              .toList();
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: (MediaQuery.sizeOf(dialogContext).height * .82)
                    .clamp(0.0, 640.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _groupAvatar(size: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _groupStatus(group),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (owner && active)
                            IconButton(
                              tooltip: '编辑群组',
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                unawaited(_editGroup(group));
                              },
                              icon: const Icon(LucideIcons.pencil, size: 18),
                            ),
                          IconButton(
                            tooltip: '关闭群组详情',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(LucideIcons.x, size: 19),
                          ),
                        ],
                      ),
                      if (group.pendingSync.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.cloudOff,
                                size: 16,
                                color: amber,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  group.left
                                      ? '退出结果待通知群主'
                                      : '${group.pendingSync.length} 位成员待同步',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '重新同步群组',
                                onPressed: () =>
                                    _guard(() => service.syncGroup(group)),
                                icon: const Icon(
                                  LucideIcons.refreshCw,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      TabBar(
                        tabs: [
                          Tab(text: '成员 ${group.members.length}'),
                          Tab(text: '文件记录 ${files.length}'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            ListView(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              children: [
                                for (final member in group.members)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: DeviceAvatar(
                                      member.platform,
                                      size: 36,
                                    ),
                                    title: Text(
                                      member.id == service.id
                                          ? '${service.name}（我）'
                                          : service
                                                    .peers[member.id]
                                                    ?.displayName ??
                                                member.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      member.id == group.ownerId
                                          ? '群主'
                                          : service.peers[member.id]?.online ==
                                                true
                                          ? '在线'
                                          : '离线',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                    trailing: member.id == service.id
                                        ? null
                                        : IconButton(
                                            tooltip: '发私信',
                                            onPressed: () {
                                              final peer =
                                                  service.peers[member.id];
                                              if (peer != null) {
                                                Navigator.pop(dialogContext);
                                                _openConversation(peer);
                                              }
                                            },
                                            icon: const Icon(
                                              LucideIcons.messageCircle,
                                              size: 18,
                                            ),
                                          ),
                                  ),
                              ],
                            ),
                            files.isEmpty
                                ? const Center(
                                    child: Text(
                                      '还没有群文件',
                                      style: TextStyle(color: muted),
                                    ),
                                  )
                                : ListView(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    children: [
                                      for (final file in files)
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: const Icon(
                                            LucideIcons.file,
                                            size: 24,
                                            color: blue,
                                          ),
                                          title: Text(
                                            file.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${service.peers[file.peerId]?.displayName ?? file.peerName} · ${file.statusLabel}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: muted,
                                            ),
                                          ),
                                          trailing: file.savedPath != null
                                              ? IconButton(
                                                  tooltip: '打开文件位置',
                                                  onPressed: () => _openFolder(
                                                    p.dirname(file.savedPath!),
                                                  ),
                                                  icon: const Icon(
                                                    LucideIcons.folderOpen,
                                                    size: 18,
                                                  ),
                                                )
                                              : null,
                                        ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                      if (!active &&
                          group.left &&
                          !group.dissolved &&
                          group.contains(service.id))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () =>
                                _guard(() => service.rejoinGroup(group)),
                            icon: const Icon(LucideIcons.userPlus, size: 16),
                            label: const Text('重新加入群组'),
                          ),
                        ),
                      if (active)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: danger,
                            ),
                            onPressed: () async {
                              if (!await _confirmGroupAction(group) ||
                                  !mounted ||
                                  !dialogContext.mounted) {
                                return;
                              }
                              Navigator.pop(dialogContext);
                              await _guard(
                                () => owner
                                    ? service.updateGroup(group, dissolve: true)
                                    : service.leaveGroup(group),
                              );
                            },
                            icon: Icon(
                              owner ? LucideIcons.trash2 : LucideIcons.logOut,
                              size: 16,
                            ),
                            label: Text(owner ? '解散群组' : '退出群组'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _groupDelivery(ChatMessage message) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    children: [
      TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28),
        ),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('消息送达情况'),
            children: [
              for (final entry in message.recipients.entries)
                ListTile(
                  title: Text(
                    service.peers[entry.key]?.displayName ?? '群成员',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    switch (entry.value) {
                      'delivered' => '已送达',
                      'pending' => '发送中',
                      'removed' => '已移出群组',
                      _ => '未送达',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      color: entry.value == 'delivered' ? green : muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        child: Text(
          '${timeLabel(message.time)} · ${message.delivery == 'pending' ? '发送中' : '已送达 ${message.deliveredCount}/${message.recipients.length}'}',
          style: TextStyle(
            fontSize: 11,
            color: message.delivery == 'failed' ? danger : muted,
          ),
        ),
      ),
      if (message.delivery == 'failed' &&
          service.groups[message.groupId]?.activeFor(service.id) == true)
        IconButton(
          tooltip: '重试未送达成员',
          onPressed: () => _guard(
            () => service.sendGroupMessage(
              service.groups[message.groupId]!,
              message.text,
              retry: message,
            ),
          ),
          icon: const Icon(LucideIcons.rotateCcw, size: 14),
          visualDensity: VisualDensity.compact,
        ),
    ],
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.detail,
    this.hint,
    this.allowEmpty = false,
  });
  final String title, label, initial;
  final String? detail, hint;
  final bool allowEmpty;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    if (widget.allowEmpty || controller.text.trim().isNotEmpty) {
      Navigator.pop(context, controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.detail != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                widget.detail!,
                style: const TextStyle(fontSize: 13, color: muted),
              ),
            ),
          TextField(
            key: const ValueKey('remark-input'),
            autofocus: true,
            controller: controller,
            maxLength: 32,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: widget.allowEmpty || controller.text.trim().isNotEmpty
            ? submit
            : null,
        child: const Text('保存'),
      ),
    ],
  );
}

class _GroupEditor extends StatefulWidget {
  const _GroupEditor({required this.service, this.group});
  final LanService service;
  final LanGroup? group;
  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  bool busy = false;
  String? error;
  late final title = TextEditingController(text: widget.group?.name ?? '');
  final search = TextEditingController();
  late final selected =
      widget.group?.members
          .where((m) => m.id != widget.service.id)
          .map((m) => m.id)
          .toSet() ??
      <String>{};
  @override
  void dispose() {
    title.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final members = selected
          .map((id) => widget.service.peers[id])
          .whereType<Peer>()
          .toList();
      final group =
          widget.group ?? await widget.service.createGroup(title.text, members);
      if (widget.group != null) {
        await widget.service.updateGroup(
          group,
          title: title.text,
          members: members,
        );
      }
      if (mounted) Navigator.pop(context, group);
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = failure is FormatException ? failure.message : '保存失败，请稍后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers =
        widget.service.peers.values
            .where(
              (p) => '${p.displayName} ${p.name} ${p.address}'
                  .toLowerCase()
                  .contains(search.text.trim().toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => a.online == b.online
                ? a.displayName.compareTo(b.displayName)
                : a.online
                ? -1
                : 1,
          );
    final valid =
        !busy &&
        title.text.trim().isNotEmpty &&
        (widget.group != null || selected.isNotEmpty);
    return PopScope(
      canPop: !busy,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: (MediaQuery.sizeOf(context).height * .86).clamp(
              0.0,
              640.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.group == null ? '新建群组' : '编辑群组',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '取消',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('group-name-input'),
                  controller: title,
                  enabled: !busy,
                  autofocus: true,
                  maxLength: 32,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '群组名称',
                    hintText: '为这个群取个名字',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: search,
                  enabled: !busy,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '搜索设备或备注',
                    prefixIcon: Icon(LucideIcons.search, size: 17),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      '选择成员',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${selected.length + 1} / 32',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: peers.isEmpty
                      ? const Center(
                          child: Text(
                            '没有匹配的设备',
                            style: TextStyle(color: muted),
                          ),
                        )
                      : ListView.builder(
                          itemCount: peers.length,
                          itemBuilder: (_, i) {
                            final peer = peers[i];
                            final checked = selected.contains(peer.id);
                            final eligible =
                                checked ||
                                (peer.online &&
                                    peer.supportsGroups &&
                                    selected.length < 31);
                            return CheckboxListTile(
                              key: ValueKey('group-member-${peer.id}'),
                              contentPadding: EdgeInsets.zero,
                              value: checked,
                              onChanged: eligible && !busy
                                  ? (value) => setState(() {
                                      if (value == true) {
                                        selected.add(peer.id);
                                      } else {
                                        selected.remove(peer.id);
                                      }
                                    })
                                  : null,
                              secondary: DeviceAvatar(peer.platform, size: 36),
                              title: Text(
                                peer.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                !peer.supportsGroups
                                    ? '需要升级邻传以使用群组'
                                    : !peer.online
                                    ? '设备离线'
                                    : peer.remark.isEmpty
                                    ? peer.platform
                                    : peer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(fontSize: 12, color: danger),
                    ),
                  ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '包含当前设备',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                    FilledButton(
                      key: const ValueKey('save-group'),
                      onPressed: valid ? save : null,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.group == null ? '创建群组' : '保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
