import 'dart:convert';
import 'dart:io';

import 'package:mutual_transfer/lan_service.dart';
import 'package:path/path.dart' as p;

// Generated loopback messages for the isolated native unread-inbox smoke test.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart run tool/verify_messages.dart address sender-name count case-name',
    );
    exitCode = 64;
    return;
  }
  final sender = LanService(
    dataDirectory: Directory(
      p.join('build', 'message-verification', 'sender-${arguments[3]}'),
    ),
    requestedPort: 0,
    discoveryEnabled: false,
    initialName: arguments[1],
  );
  try {
    await sender.start();
    final peer = await sender.connect(arguments[0]);
    for (var index = 1; index <= int.parse(arguments[2]); index++) {
      await sender.sendMessage(peer, '${arguments[1]}：第 $index 条未读消息，核对托盘提醒。');
    }
    stdout.writeln(
      jsonEncode({
        'sender': arguments[1],
        'peerId': sender.id,
        'sent': sender.messages.length,
        'delivered': sender.messages.every(
          (message) => message.delivery == 'delivered',
        ),
      }),
    );
  } finally {
    await sender.close();
  }
}
