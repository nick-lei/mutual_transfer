import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String formatBytes(num bytes, {bool speed = false}) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 || value >= 100 ? 0 : 1)} ${units[index]}${speed ? '/s' : ''}';
}

class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.platform = 'Windows',
    this.manual = false,
    this.remark = '',
    this.capabilities = const [],
    this.online = true,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? (online ? DateTime.now() : null);
  final String id;
  String name;
  String host;
  int port;
  String platform;
  bool manual;
  String remark;
  List<String> capabilities;
  String get displayName => remark.isEmpty ? name : remark;
  bool get supportsGroups => capabilities.contains('lan-groups-v1');
  bool online;
  DateTime? lastSeen;
  Uri uri(String path) =>
      Uri(scheme: 'http', host: host, port: port, path: path);
  String get address => '$host:$port';
}

class LocalFile {
  LocalFile({
    required this.path,
    required this.name,
    required this.size,
    String? relativePath,
  }) : relativePath = relativePath ?? name;
  final String path;
  final String name;
  final int size;
  final String relativePath;

  static Future<List<LocalFile>> fromPaths(List<String> paths) async {
    final files = <LocalFile>[];
    final seen = <String>{};
    for (final path in paths) {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await for (final entity in Directory(
          path,
        ).list(recursive: true, followLinks: false)) {
          if (entity is File && seen.add(p.normalize(entity.absolute.path))) {
            files.add(
              LocalFile(
                path: entity.path,
                name: p.basename(entity.path),
                size: await entity.length(),
                relativePath: p
                    .join(p.basename(path), p.relative(entity.path, from: path))
                    .replaceAll('\\', '/'),
              ),
            );
          }
          if (files.length > 1000) {
            throw const FormatException('单次最多发送 1000 个文件');
          }
        }
      } else if (type == FileSystemEntityType.file &&
          seen.add(p.normalize(File(path).absolute.path))) {
        files.add(
          LocalFile(
            path: path,
            name: p.basename(path),
            size: await File(path).length(),
          ),
        );
      }
    }
    if (files.length > 1000) throw const FormatException('单次最多发送 1000 个文件');
    return files;
  }
}

enum TransferStatus {
  waiting,
  hashing,
  queued,
  transferring,
  complete,
  rejected,
  cancelled,
  failed,
}

class TransferItem {
  TransferItem({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.name,
    required this.size,
    required this.outgoing,
    this.sourcePath,
    this.groupId,
    this.batchId,
    String? relativePath,
    DateTime? createdAt,
    this.status = TransferStatus.waiting,
  }) : createdAt = createdAt ?? DateTime.now(),
       relativePath = relativePath ?? name;
  final String id;
  final String peerId;
  final String peerName;
  final String name;
  final int size;
  final bool outgoing;
  final String? sourcePath;
  final String? groupId;
  final String? batchId;
  final String relativePath;
  final DateTime createdAt;
  String get conversationId => groupId == null ? peerId : 'group:$groupId';
  TransferStatus status;
  int bytes = 0;
  double bytesPerSecond = 0;
  String? savedPath;
  String? error;
  bool get active => [
    TransferStatus.waiting,
    TransferStatus.hashing,
    TransferStatus.queued,
    TransferStatus.transferring,
  ].contains(status);
  double get progress => size == 0
      ? (status == TransferStatus.complete ? 1 : 0)
      : (bytes / size).clamp(0, 1);
  String get statusLabel => switch (status) {
    TransferStatus.waiting => outgoing ? '等待对方接收' : '等待确认',
    TransferStatus.hashing => '正在校验',
    TransferStatus.queued => '队列中',
    TransferStatus.transferring => outgoing ? '正在发送' : '正在接收',
    TransferStatus.complete => '已完成',
    TransferStatus.rejected => '已拒绝',
    TransferStatus.cancelled => '已取消',
    TransferStatus.failed => '传输失败',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'peerId': peerId,
    'peerName': peerName,
    'name': name,
    'size': size,
    'outgoing': outgoing,
    'sourcePath': sourcePath,
    'groupId': groupId,
    'batchId': batchId,
    'relativePath': relativePath,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'savedPath': savedPath,
    'error': error,
  };
  factory TransferItem.fromJson(Map<String, dynamic> json) {
    final item = TransferItem(
      id: json['id'] as String,
      peerId: json['peerId'] as String,
      peerName: json['peerName'] as String,
      name: json['name'] as String,
      size: json['size'] as int,
      outgoing: json['outgoing'] as bool,
      sourcePath: json['sourcePath'] as String?,
      groupId: json['groupId'] as String?,
      batchId: json['batchId'] as String?,
      relativePath: json['relativePath'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: TransferStatus.values.byName(json['status'] as String),
    );
    item.savedPath = json['savedPath'] as String?;
    item.error = json['error'] as String?;
    if (item.active) {
      item.status = TransferStatus.failed;
      item.error = '上次传输已中断';
    }
    if (item.status == TransferStatus.complete) item.bytes = item.size;
    return item;
  }
}

class TransferCompletion {
  const TransferCompletion({
    required this.id,
    required this.outgoing,
    required this.peerName,
    required this.fileCount,
    required this.totalBytes,
    this.recipientCount = 1,
  });

  final String id, peerName;
  final bool outgoing;
  final int fileCount, totalBytes, recipientCount;

  String get title => outgoing ? '全部发送完成' : '接收完成';
  String get summary =>
      '${outgoing ? '已发送给' : '来自'} $peerName'
      '${recipientCount > 1 ? ' · $recipientCount 位成员' : ''}'
      ' · $fileCount 个文件 · ${formatBytes(totalBytes)}';
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.peerId,
    required this.text,
    required this.outgoing,
    DateTime? time,
    this.delivery = 'pending',
    bool? read,
    this.groupId,
    this.senderName,
    Map<String, String>? recipients,
  }) : time = time ?? DateTime.now(),
       read = read ?? outgoing,
       recipients = recipients ?? {};
  final String id;
  final String peerId;
  final String text;
  final bool outgoing;
  final DateTime time;
  String delivery;
  bool read;
  final String? groupId, senderName;
  final Map<String, String> recipients;
  String get conversationId => groupId == null ? peerId : 'group:$groupId';
  int get deliveredCount =>
      recipients.values.where((s) => s == 'delivered').length;
  Map<String, dynamic> toJson() => {
    'id': id,
    'peerId': peerId,
    'text': text,
    'outgoing': outgoing,
    'time': time.toIso8601String(),
    'delivery': delivery,
    'read': read,
    'groupId': groupId,
    'senderName': senderName,
    'recipients': recipients,
  };
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    peerId: json['peerId'] as String,
    text: json['text'] as String,
    outgoing: json['outgoing'] as bool,
    time: DateTime.parse(json['time'] as String),
    read: json['read'] as bool? ?? true,
    groupId: json['groupId'] as String?,
    senderName: json['senderName'] as String?,
    recipients: (json['recipients'] as Map? ?? {}).map(
      (key, value) => MapEntry(
        key as String,
        value == 'pending' ? 'failed' : value as String,
      ),
    ),
    delivery: json['delivery'] == 'pending'
        ? 'failed'
        : json['delivery'] as String,
  );
}

class GroupMember {
  const GroupMember({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.platform = 'Windows',
  });
  final String id, name, host, platform;
  final int port;
  factory GroupMember.fromPeer(Peer peer) => GroupMember(
    id: peer.id,
    name: peer.name,
    host: peer.host,
    port: peer.port,
    platform: peer.platform,
  );
  factory GroupMember.fromJson(Map<String, dynamic> data) => GroupMember(
    id: data['id'] as String,
    name: data['name'] as String,
    host: data['host'] as String,
    port: data['port'] as int,
    platform: data['platform'] as String? ?? 'Desktop',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'platform': platform,
  };
}

class LanGroup {
  LanGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    this.revision = 1,
    this.dissolved = false,
    this.left = false,
    Set<String>? pendingSync,
  }) : pendingSync = pendingSync ?? {};
  final String id, ownerId;
  String name;
  List<GroupMember> members;
  int revision;
  bool dissolved, left;
  final Set<String> pendingSync;
  String get conversationId => 'group:$id';
  bool contains(String id) => members.any((m) => m.id == id);
  bool activeFor(String id) => !dissolved && !left && contains(id);
  Map<String, dynamic> toJson({bool local = false}) => {
    'id': id,
    'name': name,
    'ownerId': ownerId,
    'revision': revision,
    'members': members.map((m) => m.toJson()).toList(),
    'dissolved': dissolved,
    if (local) 'left': left,
    if (local) 'pendingSync': pendingSync.toList(),
  };
  factory LanGroup.fromJson(Map<String, dynamic> data, {bool local = false}) =>
      LanGroup(
        id: data['id'] as String,
        name: data['name'] as String,
        ownerId: data['ownerId'] as String,
        revision: data['revision'] as int,
        members: (data['members'] as List)
            .map(
              (m) => GroupMember.fromJson(Map<String, dynamic>.from(m as Map)),
            )
            .toList(),
        dissolved: data['dissolved'] == true,
        left: local && data['left'] == true,
        pendingSync: local
            ? (data['pendingSync'] as List? ?? []).cast<String>().toSet()
            : {},
      );
}

class UnreadConversation {
  const UnreadConversation({
    required this.peerId,
    required this.count,
    required this.latest,
  });
  final String peerId;
  final int count;
  final ChatMessage latest;
}

// Every path component is validated before it reaches the receive directory.
String validateRelativePath(String input) {
  if (input.isEmpty ||
      input.length > 1024 ||
      input.contains('\\') ||
      input.startsWith('/')) {
    throw const FormatException('无效的文件路径');
  }
  final parts = input.split('/');
  final reserved = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?$',
    caseSensitive: false,
  );
  for (final part in parts) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(part) ||
        reserved.hasMatch(part)) {
      throw const FormatException('文件名不受支持');
    }
  }
  return p.joinAll(parts);
}
