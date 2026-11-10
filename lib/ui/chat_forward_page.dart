part of 'workspace.dart';

extension _ChatForwardPage on _WorkspaceState {
  Future<String?> _mobileForwardRecipient(TransferItem file) async {
    final search = TextEditingController();
    String? selectedId;
    final route = MaterialPageRoute<String>(
      builder: (routeContext) => StatefulBuilder(
        builder: (context, update) => StreamBuilder<void>(
          stream: service.changes,
          builder: (context, _) {
            final peers = _forwardRecipients(file, query: search.text);
            final selected =
                service.peers[selectedId] ??
                _groupPeer(service.groupForConversation(selectedId));
            final canSend = selected != null && _canForwardTo(file, selected);
            return Scaffold(
              key: const ValueKey('forward-file-page'),
              backgroundColor: canvas,
              appBar: AppBar(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  tooltip: '返回',
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: () => Navigator.pop(routeContext),
                ),
                title: const Text('转发文件'),
                titleTextStyle: Theme.of(context).textTheme.titleLarge,
              ),
              body: SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FileGlyph(file.name),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: TextField(
                        key: const ValueKey('forward-recipient-search'),
                        controller: search,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        onChanged: (_) => update(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索设备或群组',
                          prefixIcon: const Icon(LucideIcons.search, size: 20),
                          suffixIcon: search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空搜索',
                                  icon: const Icon(LucideIcons.x, size: 18),
                                  onPressed: () => update(search.clear),
                                ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: peers.isEmpty
                          ? Center(
                              child: Text(
                                search.text.isEmpty ? '暂无其他设备' : '没有匹配的设备',
                                style: const TextStyle(color: muted),
                              ),
                            )
                          : RadioGroup<String>(
                              groupValue: canSend ? selectedId : null,
                              onChanged: (value) {
                                FocusScope.of(context).unfocus();
                                update(() => selectedId = value);
                              },
                              child: ListView.separated(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                itemCount: peers.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final peer = peers[index];
                                  final online = _forwardTargetOnline(peer);
                                  final group = service.groupForConversation(
                                    peer.id,
                                  );
                                  final active =
                                      canSend && selectedId == peer.id;
                                  return Material(
                                    color: active ? blueTint : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    child: ListTile(
                                      key: ValueKey(
                                        'forward-recipient-${peer.id}',
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding: const EdgeInsets.fromLTRB(
                                        12,
                                        8,
                                        4,
                                        8,
                                      ),
                                      leading: _conversationAvatar(peer),
                                      title: Text(
                                        peer.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                      trailing: Radio<String>(
                                        value: peer.id,
                                        enabled: online,
                                      ),
                                      enabled: online,
                                      selected: active,
                                      onTap: online
                                          ? () {
                                              FocusScope.of(context).unfocus();
                                              update(
                                                () => selectedId = peer.id,
                                              );
                                            }
                                          : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: ColoredBox(
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      key: const ValueKey('forward-send'),
                      onPressed: canSend
                          ? () => Navigator.pop(routeContext, selectedId)
                          : null,
                      icon: const Icon(LucideIcons.forward, size: 19),
                      label: const Text('转发'),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    try {
      final result = await Navigator.of(context).push<String>(route);
      // Keep the search controller alive until the reverse transition unmounts it.
      await route.completed;
      return result;
    } finally {
      search.dispose();
    }
  }
}
