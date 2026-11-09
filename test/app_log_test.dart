import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/logging/app_log.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppLog log;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nearlink-log-test-');
    log = AppLog(root);
    await log.initialize();
  });
  tearDown(() async {
    await log.close();
    await root.delete(recursive: true);
  });

  test(
    'persists structured errors while redacting nested credentials and message bodies',
    () async {
      log.error(
        'transfer',
        'failed',
        '传输未完成',
        error: const FormatException('Invalid JSON', 'private message body'),
        stack: StackTrace.current,
        fields: {
          'transferId': 'abc',
          'token': 'sensitive-token',
          'nested': {'password': 'secret-value', 'body': 'message body'},
          'url': 'http://127.0.0.1/file?token=query-secret&n=1',
        },
      );
      final entries = await log.readRecent();
      expect(entries.single.level, LogLevel.error);
      expect(entries.single.fields['transferId'], 'abc');
      expect(entries.single.stack, isNotEmpty);
      final saved = await File(log.currentPath).readAsString();
      for (final secret in [
        'sensitive-token',
        'secret-value',
        'message body',
        'query-secret',
      ]) {
        expect(saved, isNot(contains(secret)));
      }
      expect(saved, contains('[redacted]'));
      final parsed = jsonDecode(saved) as Map;
      expect(parsed['error'], 'Invalid JSON');
    },
  );

  test(
    'rotation retains bounded archives, latest entries and exports the full snapshot',
    () async {
      await log.close();
      log = AppLog(root, maxFileBytes: 650, archiveCount: 2);
      await log.initialize();
      for (var i = 0; i < 20; i++) {
        log.info('test', 'event_$i', 'Entry $i');
      }
      await log.flush();
      final files = await log.directory
          .list()
          .where((e) => e.path.endsWith('.jsonl'))
          .cast<File>()
          .toList();
      expect(files.length, 3);
      for (final file in files) {
        expect(await file.length(), lessThanOrEqualTo(650));
      }
      final entries = await log.readRecent(limit: 3);
      expect(entries.map((e) => e.event), ['event_19', 'event_18', 'event_17']);
      final exported = p.join(root.path, 'export.jsonl');
      await log.export(exported);
      final snapshot = await File(exported).readAsLines();
      expect(snapshot.length, greaterThan(entries.length));
      expect((jsonDecode(snapshot.last) as Map)['event'], 'event_19');
      await expectLater(
        log.export(log.currentPath),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('malformed trailing lines do not hide valid records', () async {
    log.info('test', 'valid', 'Valid');
    await log.flush();
    await File(
      log.currentPath,
    ).writeAsString('{incomplete', mode: FileMode.append);
    expect((await log.readRecent()).single.event, 'valid');
  });

  test(
    'export failure completes and does not poison subsequent logging',
    () async {
      await expectLater(
        log.export(p.join(root.path, 'missing', 'export.jsonl')),
        throwsA(isA<FileSystemException>()),
      );
      log.info('test', 'after_export_failure', 'Still usable');
      expect((await log.readRecent()).single.event, 'after_export_failure');
    },
  );

  test(
    'restart separates an interrupted final line from new records',
    () async {
      log.info('test', 'before_restart', 'Before');
      await log.close();
      await File(
        log.currentPath,
      ).writeAsString('{incomplete', mode: FileMode.append);
      log = AppLog(root);
      await log.initialize();
      log.info('test', 'after_restart', 'After');
      expect((await log.readRecent()).map((e) => e.event), [
        'after_restart',
        'before_restart',
      ]);
    },
  );

  test('disk write errors are exposed without throwing into callers', () async {
    await log.directory.delete(recursive: true);
    await File(log.directory.path).writeAsString('blocked');
    log.info('test', 'write', 'Cannot persist yet');
    await log.flush();
    expect(log.storageError, isNotNull);
    await File(log.directory.path).delete();
    await log.directory.create();
    await log.flush();
    expect(log.storageError, isNull);
    expect((await log.readRecent()).single.event, 'write');
  });

  test('close flushes buffered records and overflow accounting', () async {
    for (var i = 0; i < 1100; i++) {
      log.info('test', 'write', '$i');
    }
    await log.close();
    final lines = await File(log.currentPath).readAsLines();
    expect(lines.length, 1001);
    expect((jsonDecode(lines.last) as Map)['fields']['dropped'], 100);
  });
}
