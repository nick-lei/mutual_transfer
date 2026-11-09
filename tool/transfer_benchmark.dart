import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';

Future<void> main(List<String> args) async {
  String? option(String key) => args
      .where((value) => value.startsWith('$key='))
      .map((value) => value.substring(key.length + 1))
      .firstOrNull;
  final sizeMiB = int.parse(option('--size-mib') ?? '256');
  final runs = int.parse(option('--runs') ?? '3');
  if (sizeMiB < 1 || runs < 1) throw ArgumentError('Invalid benchmark size');
  final root = await Directory.systemTemp.createTemp('nearlink-benchmark-');
  final sender = LanService(
    dataDirectory: Directory(p.join(root.path, 'sender')),
    requestedPort: 0,
    discoveryEnabled: false,
  );
  final receiver = LanService(
    dataDirectory: Directory(p.join(root.path, 'receiver')),
    requestedPort: 0,
    discoveryEnabled: false,
  );
  StreamSubscription<void>? accept;
  try {
    final source = File(p.join(root.path, 'payload.bin'));
    final chunk = Uint8List.fromList(
      List<int>.generate(
        1024 * 1024,
        (index) => (index * 31 + index ~/ 251) % 256,
      ),
    );
    final output = await source.open(mode: FileMode.write);
    try {
      for (var i = 0; i < sizeMiB; i++) {
        await output.writeFrom(chunk);
      }
    } finally {
      await output.close();
    }
    final expectedHash = (await sha256.bind(source.openRead()).first)
        .toString();
    await sender.start();
    await receiver.start();
    await receiver.updateSettings(directory: p.join(root.path, 'received'));
    final peer = await sender.connect('127.0.0.1:${receiver.port}');
    accept = receiver.changes.listen((_) {
      for (final offer in receiver.incoming.toList()) {
        receiver.decide(offer, true);
      }
    });
    final results = <Map<String, Object>>[];
    for (var run = 0; run < runs; run++) {
      final watch = Stopwatch()..start();
      int? firstByteMs;
      var peakRss = ProcessInfo.currentRss;
      final sampler = Timer.periodic(const Duration(milliseconds: 5), (_) {
        if (receiver.transfers.isNotEmpty &&
            receiver.transfers.first.bytes > 0) {
          firstByteMs ??= watch.elapsedMilliseconds;
        }
        if (ProcessInfo.currentRss > peakRss) peakRss = ProcessInfo.currentRss;
      });
      try {
        await sender
            .sendFiles(peer, [
              LocalFile(
                path: source.path,
                name: 'payload.bin',
                size: sizeMiB * 1024 * 1024,
              ),
            ])
            .timeout(const Duration(minutes: 5));
      } finally {
        watch.stop();
        sampler.cancel();
      }
      final item = receiver.transfers.first;
      if (item.status != TransferStatus.complete ||
          sender.transfers.first.status != TransferStatus.complete) {
        throw StateError(
          'Transfer failed: ${sender.transfers.first.error} / ${item.error}',
        );
      }
      final saved = File(item.savedPath!);
      final actualHash = (await sha256.bind(saved.openRead()).first).toString();
      if (actualHash != expectedHash) throw StateError('Digest mismatch');
      final result = <String, Object>{
        'run': run + 1,
        'elapsedMs': watch.elapsedMilliseconds,
        'firstByteMs': firstByteMs ?? watch.elapsedMilliseconds,
        'mebibytesPerSecond': sizeMiB * 1000000 / watch.elapsedMicroseconds,
        'peakRssMiB': peakRss / (1024 * 1024),
        'sha256Verified': true,
      };
      results.add(result);
      stdout.writeln(jsonEncode(result));
      await saved.delete();
      sender.clearHistory();
      receiver.clearHistory();
    }
    final report = {
      'time': DateTime.now().toUtc().toIso8601String(),
      'environment':
          'Same-process IPv4 loopback; generated binary fixture; warm OS cache; Dart ${Platform.version}',
      'sizeMiB': sizeMiB,
      'runs': results,
    };
    final path = option('--output');
    if (path != null) {
      final reportFile = File(path);
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
    }
  } finally {
    await accept?.cancel();
    await sender.close();
    await receiver.close();
    await root.delete(recursive: true);
  }
}
