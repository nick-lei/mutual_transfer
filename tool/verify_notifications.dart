import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';

// Sends generated loopback data to an isolated native receiver for UI verification.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/verify_notifications.dart address case-name',
    );
    exitCode = 64;
    return;
  }
  final directory = Directory(
    p.join('build', 'notification-verification', 'sender-${arguments[1]}'),
  );
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, 'notification-${arguments[1]}.txt'));
  await file.writeAsString('NearLink local notification verification.\n' * 32);
  final sender = LanService(
    dataDirectory: directory,
    requestedPort: 0,
    discoveryEnabled: false,
    initialName: '通知验证设备',
  );
  try {
    await sender.start();
    final peer = await sender.connect(arguments.first);
    stdout.writeln(
      'Waiting for the native receiver to decide: ${arguments[1]}',
    );
    await sender.sendFiles(peer, await LocalFile.fromPaths([file.path]));
    final transfer = sender.transfers.last;
    stdout.writeln(
      jsonEncode({
        'case': arguments[1],
        'status': transfer.status.name,
        'bytes': transfer.bytes,
        'size': transfer.size,
        'error': transfer.error,
      }),
    );
    if (transfer.status != TransferStatus.complete &&
        transfer.status != TransferStatus.rejected) {
      exitCode = 1;
    }
  } finally {
    await sender.close();
  }
}
