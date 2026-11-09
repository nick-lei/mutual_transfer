part of 'lan_service.dart';

extension GroupService on LanService {
  Future<void> setPeerRemark(Peer peer, String value) async {
    value = value.trim();
    if (value.length > 32) throw const FormatException('备注最多 32 个字符');
    if (!identical(peers[peer.id], peer)) throw const FormatException('设备不存在');
    peer.remark = value;
    await _persist();
    _notify();
  }

  GroupMember get _selfMember => GroupMember(
    id: id,
    name: name,
    host: primaryAddress,
    port: port,
    platform: platform,
  );

  List<Peer> groupPeers(LanGroup group) => group.members
      .where((m) => m.id != id)
      .map(
        (m) =>
            peers[m.id] ??
            (Peer(
              id: m.id,
              name: m.name,
              host: m.host,
              port: m.port,
              platform: m.platform,
              capabilities: const ['lan-groups-v1'],
              online: false,
            )),
      )
      .toList();

  void _requireGroupSender(String groupId, String senderId) {
    final group = groups[groupId];
    if (group == null || !group.activeFor(id) || !group.contains(senderId)) {
      throw const FormatException('群组已退出、已解散或成员身份已变更');
    }
  }

  void _validateGroup(LanGroup group) {
    final validId = RegExp(r'^[a-f0-9]{32}$');
    if (!validId.hasMatch(group.id) ||
        !validId.hasMatch(group.ownerId) ||
        group.name.trim().isEmpty ||
        group.name.length > 32 ||
        group.revision < 1 ||
        group.members.isEmpty ||
        group.members.length > 32 ||
        !group.contains(group.ownerId) ||
        group.members.map((m) => m.id).toSet().length != group.members.length) {
      throw const FormatException('无效的群组信息');
    }
    for (final member in group.members) {
      if (!validId.hasMatch(member.id) ||
          member.name.isEmpty ||
          member.name.length > 64 ||
          member.port < 1 ||
          member.port > 65535 ||
          InternetAddress.tryParse(member.host)?.type !=
              InternetAddressType.IPv4) {
        throw const FormatException('无效的群成员信息');
      }
    }
  }

  Future<Map<String, dynamic>> _postGroup(
    Peer peer,
    String path,
    Map<String, dynamic> body,
  ) async {
    HttpClientRequest? request;
    try {
      final endpoint = await _verifyPeerEndpoint(peer);
      request = await _client
          .postUrl(endpoint.uri(path))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'peer': info, ...body}));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final data = await _readJson(response);
      peer
        ..online = true
        ..lastSeen = DateTime.now();
      if (response.statusCode != 200) {
        throw FormatException('${data['error'] ?? '群组请求失败'}');
      }
      return data;
    } catch (error) {
      request?.abort();
      if (error is SocketException ||
          error is TimeoutException ||
          error is HttpException) {
        peer.online = false;
      }
      rethrow;
    }
  }

  Future<LanGroup> createGroup(String title, List<Peer> members) async {
    final unique = {for (final peer in members) peer.id: peer}.values.toList();
    if (unique.isEmpty ||
        unique.length > 31 ||
        unique.any((p) => p.id == id || !p.online || !p.supportsGroups)) {
      throw const FormatException('请选择 1 至 31 台在线且支持群组的设备');
    }
    final group = LanGroup(
      id: newId(),
      name: title.trim(),
      ownerId: id,
      members: [_selfMember, ...unique.map(GroupMember.fromPeer)],
    );
    _validateGroup(group);
    groups[group.id] = group;
    group.pendingSync.addAll(unique.map((p) => p.id));
    await _persist();
    _notify();
    await syncGroup(group);
    return group;
  }

  Future<void> updateGroup(
    LanGroup group, {
    String? title,
    List<Peer>? members,
    bool dissolve = false,
  }) async {
    if (group.ownerId != id ||
        !group.activeFor(id) ||
        !_groupOperations.add(group.id)) {
      throw const FormatException('仅群主可以修改，请等待当前操作完成');
    }
    try {
      final nextMembers = members == null
          ? group.members
          : [
              _selfMember,
              ...{
                for (final peer in members) peer.id: peer,
              }.values.where((p) => p.id != id).map(GroupMember.fromPeer),
            ];
      if (members != null &&
          members.any(
            (p) => !group.contains(p.id) && (!p.online || !p.supportsGroups),
          )) {
        throw const FormatException('新成员需要在线并支持群组');
      }
      final next = LanGroup(
        id: group.id,
        name: title?.trim() ?? group.name,
        ownerId: id,
        members: nextMembers,
        revision: group.revision + 1,
        dissolved: dissolve,
      );
      _validateGroup(next);
      group.pendingSync.addAll(
        [
          ...group.members,
          ...nextMembers,
        ].where((m) => m.id != id).map((m) => m.id),
      );
      group.name = next.name;
      group.members = nextMembers;
      group.revision = next.revision;
      group.dissolved = dissolve;
      await _persist();
      _notify();
      await syncGroup(group);
    } finally {
      _groupOperations.remove(group.id);
    }
  }

  Future<void> syncGroup(LanGroup group) async {
    if (group.ownerId != id) {
      if (group.left) {
        final owner = peers[group.ownerId];
        if (owner == null) throw const FormatException('群主暂时不可用');
        await _postGroup(owner, '/v1/groups/leave', {'groupId': group.id});
        group.pendingSync.clear();
        await _persist();
        _notify();
      }
      return;
    }
    final revision = group.revision;
    final snapshot = group.toJson();
    final targets = group.pendingSync.toList();
    for (var offset = 0; offset < targets.length; offset += 4) {
      await Future.wait(
        targets.skip(offset).take(4).map((target) async {
          try {
            final peer = peers[target];
            if (peer == null) throw const FormatException('成员地址不可用');
            await _postGroup(peer, '/v1/groups', {'group': snapshot});
            if (group.revision == revision) group.pendingSync.remove(target);
          } catch (error) {
            log.warning(
              'group',
              'sync_failed',
              '群成员信息同步失败',
              fields: {'groupId': group.id, 'peerId': target},
              error: error,
            );
          }
        }),
      );
    }
    await _persist();
    _notify();
  }

  Future<void> leaveGroup(LanGroup group) async {
    if (group.ownerId == id) throw const FormatException('群主请使用解散群组');
    group.left = true;
    group.pendingSync.add(group.ownerId);
    markMessagesRead(peerId: group.conversationId);
    await _persist();
    _notify();
    try {
      await syncGroup(group);
    } catch (_) {
      /* Persisted for explicit retry. */
    }
  }

  Future<void> rejoinGroup(LanGroup group) async {
    if (!group.left || group.dissolved || !group.contains(id)) {
      throw const FormatException('请先由群主重新添加此设备');
    }
    final owner = peers[group.ownerId];
    if (owner == null) throw const FormatException('群主暂时不可用');
    final result = await _postGroup(owner, '/v1/groups/join', {
      'groupId': group.id,
    });
    final next = LanGroup.fromJson(
      Map<String, dynamic>.from(result['group'] as Map),
    );
    _validateGroup(next);
    if (next.id != group.id ||
        next.ownerId != group.ownerId ||
        !next.activeFor(id)) {
      throw const FormatException('群成员信息已变更，请联系群主');
    }
    groups[group.id] = next;
    await _persist();
    _notify();
  }

  Future<void> _handleGroupRequest(HttpRequest request) async {
    final data = await _readJson(request);
    final sender = _upsert(
      Map<String, dynamic>.from(data['peer'] as Map),
      request.connectionInfo!.remoteAddress.address,
    );
    if (sender.id == id) throw const FormatException('不能向自己发送群组请求');
    if (request.uri.path == '/v1/groups') {
      final next = LanGroup.fromJson(
        Map<String, dynamic>.from(data['group'] as Map),
      );
      _validateGroup(next);
      final existing = groups[next.id];
      if (sender.id != next.ownerId ||
          (existing != null && existing.ownerId != sender.id) ||
          (existing == null && !next.contains(id))) {
        throw const FormatException('仅群主可以同步成员名单');
      }
      if (existing == null || next.revision > existing.revision) {
        next.left = existing?.left ?? false;
        groups[next.id] = next;
        for (final member in next.members.where((m) => m.id != id)) {
          peers.putIfAbsent(
            member.id,
            () => Peer(
              id: member.id,
              name: member.name,
              host: member.host,
              port: member.port,
              platform: member.platform,
              capabilities: const ['lan-groups-v1'],
              online: false,
            ),
          );
        }
        if (!next.activeFor(id)) markMessagesRead(peerId: next.conversationId);
        await _persist();
        _notify();
      }
      await _json(request.response, 200, {'ok': true});
      return;
    }
    final groupId = data['groupId'] as String;
    final group = groups[groupId];
    if (request.uri.path == '/v1/groups/join') {
      if (group == null ||
          group.ownerId != id ||
          group.dissolved ||
          !group.contains(sender.id)) {
        throw const FormatException('请先由群主重新添加此设备');
      }
      await _json(request.response, 200, {'group': group.toJson()});
      return;
    }
    if (request.uri.path == '/v1/groups/leave') {
      if (group == null || group.ownerId != id) {
        throw const FormatException('该设备不是群主');
      }
      if (group.contains(sender.id) && !group.dissolved) {
        await updateGroup(
          group,
          members: groupPeers(group).where((p) => p.id != sender.id).toList(),
        );
      }
      await _json(request.response, 200, {'ok': true});
      return;
    }
    _requireGroupSender(groupId, sender.id);
    final text = data['text'] as String;
    final messageId = data['id'] as String;
    if (text.trim().isEmpty ||
        text.length > 16000 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(messageId)) {
      throw const FormatException('无效的群消息');
    }
    if (!messages.any(
      (m) => m.id == messageId && m.peerId == sender.id && m.groupId == groupId,
    )) {
      messages.add(
        ChatMessage(
          id: messageId,
          peerId: sender.id,
          groupId: groupId,
          senderName: sender.name,
          text: text,
          outgoing: false,
          delivery: 'delivered',
          read: _viewedConversation == group!.conversationId,
        ),
      );
      await _persist();
      _notify();
    }
    await _json(request.response, 200, {'ok': true});
  }

  Future<void> sendGroupMessage(
    LanGroup group,
    String text, {
    ChatMessage? retry,
  }) async {
    _requireGroupSender(group.id, id);
    text = text.trim();
    if (text.isEmpty || text.length > 16000) {
      throw const FormatException('消息长度应为 1 至 16000 字符');
    }
    if (retry?.delivery == 'pending') return;
    final message =
        retry ??
        ChatMessage(
          id: newId(),
          peerId: id,
          groupId: group.id,
          senderName: name,
          text: text,
          outgoing: true,
          recipients: {
            for (final m in group.members.where((m) => m.id != id))
              m.id: 'pending',
          },
        );
    if (retry != null && (retry.groupId != group.id || !retry.outgoing)) {
      throw const FormatException('无效的重试消息');
    }
    if (retry == null) messages.add(message);
    message.delivery = 'pending';
    final targets = message.recipients.keys
        .where((id) => message.recipients[id] != 'delivered')
        .toList();
    for (final target in targets) {
      message.recipients[target] = group.contains(target)
          ? 'pending'
          : 'removed';
    }
    _notify(persist: true);
    for (var offset = 0; offset < targets.length; offset += 4) {
      await Future.wait(
        targets.skip(offset).take(4).map((target) async {
          if (!group.contains(target)) return;
          try {
            final peer = peers[target];
            if (peer == null) throw const FormatException('成员不可用');
            if (group.ownerId == id && group.pendingSync.contains(target)) {
              await _postGroup(peer, '/v1/groups', {'group': group.toJson()});
              group.pendingSync.remove(target);
            }
            await _postGroup(peer, '/v1/group-messages', {
              'id': message.id,
              'groupId': group.id,
              'text': message.text,
            });
            message.recipients[target] = 'delivered';
          } catch (_) {
            message.recipients[target] = 'failed';
          }
          _notify(persist: true);
        }),
      );
    }
    message.delivery = message.deliveredCount == message.recipients.length
        ? 'delivered'
        : 'failed';
    await _persist();
    _notify();
  }

  Future<void> sendGroupFiles(LanGroup group, List<LocalFile> files) async {
    _requireGroupSender(group.id, id);
    if (files.isEmpty || files.length > 1000) {
      throw const FormatException('文件队列无效');
    }
    final targets = groupPeers(group);
    var completedTargets = 0;
    // Three concurrent receiver sessions avoid multiplying large-file disk reads without bound.
    for (var offset = 0; offset < targets.length; offset += 3) {
      await Future.wait(
        targets.skip(offset).take(3).map((peer) async {
          try {
            if (!peer.online) await connect(peer.address);
            if (group.ownerId == id && group.pendingSync.contains(peer.id)) {
              await _postGroup(peer, '/v1/groups', {'group': group.toJson()});
              group.pendingSync.remove(peer.id);
            }
            final items = await _sendFileBatch(peer, files, groupId: group.id);
            if (items.every((file) => file.status == TransferStatus.complete)) {
              completedTargets++;
            }
          } catch (error) {
            transfers.insertAll(
              0,
              files.map(
                (file) => TransferItem(
                  id: newId(),
                  peerId: peer.id,
                  peerName: peer.name,
                  groupId: group.id,
                  name: file.name,
                  relativePath: file.relativePath,
                  size: file.size,
                  sourcePath: file.path,
                  outgoing: true,
                  status: TransferStatus.failed,
                )..error = '$error',
              ),
            );
          }
        }),
      );
    }
    await _persist();
    _notify();
    if (targets.isNotEmpty && completedTargets == targets.length) {
      _emitTransferCompletion(
        TransferCompletion(
          id: newId(),
          outgoing: true,
          peerName: group.name,
          fileCount: files.length,
          totalBytes: files.fold(0, (sum, file) => sum + file.size),
          recipientCount: targets.length,
        ),
      );
    }
  }
}
