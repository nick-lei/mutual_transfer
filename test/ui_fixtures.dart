import 'dart:async';
import 'dart:io';

import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';

// Synthetic data for UI tests and review captures only. Never used by the app.
class UiFixtureService extends LanService {
  final completionEvents = StreamController<TransferCompletion>.broadcast();
  @override
  Stream<TransferCompletion> get completedTransfers => completionEvents.stream;
  UiFixtureService({bool populated = true, super.discoveryEnabled = false})
    : super(dataDirectory: Directory.systemTemp) {
    name = '我的电脑';
    saveDirectory = r'C:\Users\NearLink\Downloads\邻传';
    addresses = ['192.168.1.16'];
    for (final peer in [
      Peer(id: 'laptop', name: '我的笔记本', host: '192.168.1.24', port: 45878),
      Peer(id: 'studio', name: '设计工作站', host: '192.168.1.28', port: 45878),
      Peer(id: 'home', name: '家里的电脑', host: '192.168.1.32', port: 45878)
        ..online = false,
    ]) {
      peers[peer.id] = peer;
    }
    if (populated) {
      transfers.addAll([
        TransferItem(
            id: 'active',
            peerId: 'studio',
            peerName: '设计工作站',
            name: '品牌素材包.zip',
            size: 180 * 1024 * 1024,
            outgoing: true,
            status: TransferStatus.transferring,
          )
          ..bytes = 64 * 1024 * 1024
          ..bytesPerSecond = 12 * 1024 * 1024,
        TransferItem(
          id: 'received',
          peerId: 'laptop',
          peerName: '我的笔记本',
          name: '周末出游合照.jpg',
          size: 6240000,
          outgoing: false,
          status: TransferStatus.complete,
        )..savedPath = r'C:\Users\NearLink\Downloads\邻传\周末出游合照.jpg',
        TransferItem(
          id: 'failed',
          peerId: 'studio',
          peerName: '设计工作站',
          name: '项目交付文档.pdf',
          size: 4200000,
          outgoing: true,
          status: TransferStatus.failed,
        )..error = '连接已中断，请确认对方在线后重新发送。',
      ]);
      messages.addAll([
        ChatMessage(
          id: 'm1',
          peerId: 'laptop',
          text: '周末的照片整理好了，发到这台电脑吧。',
          outgoing: false,
        ),
        ChatMessage(
          id: 'm2',
          peerId: 'laptop',
          text: '好，原图直接发给你，目录也一起保留。',
          outgoing: true,
          delivery: 'delivered',
        ),
        ChatMessage(
          id: 'm3',
          peerId: 'laptop',
          text: '收到！晚点再挑几张放进相册。',
          outgoing: false,
        ),
        ChatMessage(
          id: 'm4',
          peerId: 'studio',
          text: '这版素材已经更新，可以开始交付了。',
          outgoing: false,
        ),
      ]);
    }
  }
  final events = StreamController<void>.broadcast();
  final List<({String peerId, String text})> sentMessages = [];
  final List<({String peerId, List<LocalFile> files})> sentBatches = [];
  String? discoveryFailure;
  bool checkingDiscovery = false;
  int discoveryRetries = 0;
  Completer<void>? discoveryRetryGate;
  @override
  String? get discoveryError => discoveryFailure;
  @override
  bool get retryingDiscovery => checkingDiscovery;
  @override
  Future<void> retryDiscovery() async {
    discoveryRetries++;
    checkingDiscovery = true;
    emit();
    await discoveryRetryGate?.future;
    discoveryFailure = null;
    checkingDiscovery = false;
    emit();
  }

  @override
  Stream<void> get changes => events.stream;
  @override
  bool get running => true;
  void emit() => events.add(null);
  LanGroup addGroupFixture() {
    peers['laptop']!.remark = '小林的笔记本';
    peers['laptop']!.capabilities = ['lan-groups-v1'];
    peers['studio']!.capabilities = ['lan-groups-v1'];
    final group = LanGroup(
      id: '1234567890abcdef1234567890abcdef',
      name: '设计协作小组',
      ownerId: id,
      members: [
        GroupMember(id: id, name: name, host: primaryAddress, port: port),
        ...peers.values.take(2).map(GroupMember.fromPeer),
      ],
    );
    groups[group.id] = group;
    messages.addAll([
      ChatMessage(
        id: 'group-1',
        peerId: 'laptop',
        senderName: '我的笔记本',
        groupId: group.id,
        text: '新版图标和素材已经整理好了，大家看一下。',
        outgoing: false,
      ),
      ChatMessage(
        id: 'group-2',
        peerId: id,
        groupId: group.id,
        text: '收到，定稿文件稍后在群里一起发。',
        outgoing: true,
        delivery: 'failed',
        recipients: {'laptop': 'delivered', 'studio': 'failed'},
      ),
    ]);
    return group;
  }

  @override
  void refresh() => emit();
  @override
  void decide(IncomingOffer offer, bool accept) {
    super.decide(offer, accept);
    emit();
  }

  @override
  Future<void> sendMessage(Peer peer, String text, {ChatMessage? retry}) async {
    sentMessages.add((peerId: peer.id, text: text));
    messages.add(
      ChatMessage(
        id: newId(),
        peerId: peer.id,
        text: text,
        outgoing: true,
        delivery: 'delivered',
      ),
    );
    emit();
  }

  @override
  Future<void> sendFiles(
    Peer peer,
    List<LocalFile> files, {
    String? groupId,
  }) async {
    sentBatches.add((peerId: peer.id, files: List.of(files)));
    emit();
  }

  @override
  Future<void> updateSettings({String? deviceName, String? directory}) async {
    if (deviceName != null && deviceName.trim().isEmpty) {
      throw const FormatException('设备名称不能为空');
    }
    name = deviceName?.trim() ?? name;
    saveDirectory = directory ?? saveDirectory;
    emit();
  }

  @override
  Future<Peer> connect(String input) async {
    if (input.trim().isEmpty) throw const FormatException('请输入设备地址');
    return peers['laptop']!;
  }

  @override
  Future<void> close() async {
    await completionEvents.close();
    await super.close();
    await events.close();
  }
}
