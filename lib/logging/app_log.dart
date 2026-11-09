import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

enum LogLevel { info, warning, error }

class LogEntry {
  LogEntry({
    required this.id,
    required this.time,
    required this.level,
    required this.component,
    required this.event,
    required this.message,
    this.fields = const {},
    this.error,
    this.stack,
  });
  final String id;
  final DateTime time;
  final LogLevel level;
  final String component, event, message;
  final Map<String, Object?> fields;
  final String? error, stack;

  Map<String, Object?> toJson() => {
    'id': id,
    'time': time.toUtc().toIso8601String(),
    'level': level.name,
    'component': component,
    'event': event,
    'message': message,
    if (fields.isNotEmpty) 'fields': fields,
    if (error != null) 'error': error,
    if (stack != null) 'stack': stack,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    id: json['id'] as String,
    time: DateTime.parse(json['time'] as String),
    level: LogLevel.values.byName(json['level'] as String),
    component: json['component'] as String,
    event: json['event'] as String,
    message: json['message'] as String,
    fields: Map<String, Object?>.from(json['fields'] as Map? ?? {}),
    error: json['error'] as String?,
    stack: json['stack'] as String?,
  );
}

String _safeString(String value, [int limit = 2048]) {
  final redacted = value.replaceAllMapped(
    RegExp(r'([?&]token=)[^&\s]+', caseSensitive: false),
    (match) => '${match[1]}[redacted]',
  );
  return redacted.length > limit
      ? '${redacted.substring(0, limit)}...'
      : redacted;
}

Object? _safeValue(String key, Object? value, [int depth = 0]) {
  if (RegExp(
    r'token|password|authorization|secret|^text$|^body$',
    caseSensitive: false,
  ).hasMatch(key)) {
    return '[redacted]';
  }
  if (value == null || value is bool || value is num) return value;
  if (depth >= 3) return '[truncated]';
  if (value is Map) {
    return Map.fromEntries(
      value.entries
          .take(40)
          .map(
            (entry) => MapEntry(
              _safeString('${entry.key}', 128),
              _safeValue('${entry.key}', entry.value, depth + 1),
            ),
          ),
    );
  }
  if (value is Iterable) {
    return value
        .take(30)
        .map((value) => _safeValue('', value, depth + 1))
        .toList();
  }
  return _safeString('$value');
}

List<File> _logFiles(String directory, int archiveCount) => [
  for (var index = archiveCount; index >= 1; index--)
    File(p.join(directory, 'nearlink.$index.jsonl')),
  File(p.join(directory, 'nearlink.jsonl')),
];

Future<List<LogEntry>> _readRecent(
  String directory,
  int archiveCount,
  int limit,
) async {
  final entries = <String, LogEntry>{};
  for (final file in _logFiles(directory, archiveCount)) {
    if (!await file.exists()) continue;
    await for (final line
        in file
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      try {
        final entry = LogEntry.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        );
        entries[entry.id] = entry;
        if (entries.length > limit) entries.remove(entries.keys.first);
      } catch (_) {
        // An interrupted final line must not hide the remaining diagnostics.
      }
    }
  }
  return entries.values.toList().reversed.toList();
}

class AppLog {
  AppLog(
    Directory dataDirectory, {
    this.maxFileBytes = 4 * 1024 * 1024,
    this.archiveCount = 4,
    this.flushInterval = const Duration(milliseconds: 250),
  }) : assert(maxFileBytes > 0),
       assert(archiveCount >= 1),
       assert(flushInterval > Duration.zero),
       directory = Directory(p.join(dataDirectory.path, 'logs'));

  final Directory directory;
  final int maxFileBytes, archiveCount;
  final Duration flushInterval;
  final _pending = Queue<LogEntry>();
  final _events = StreamController<LogEntry>.broadcast();
  final _changes = StreamController<void>.broadcast();
  Stream<LogEntry> get events => _events.stream;
  Stream<void> get changes => _changes.stream;
  Future<void>? _initialization, _closing;
  Future<void> _writes = Future.value();
  Timer? _timer;
  bool initialized = false, _closed = false;
  int _length = 0, _sequence = 0, _dropped = 0;
  String? storageError;
  String get currentPath => p.join(directory.path, 'nearlink.jsonl');

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await directory.create(recursive: true);
      final file = File(currentPath);
      _length = await file.exists() ? await file.length() : 0;
      if (_length > 0) {
        final reader = await file.open();
        int last;
        try {
          await reader.setPosition(_length - 1);
          last = await reader.readByte();
        } finally {
          await reader.close();
        }
        if (last != 10) {
          await file.writeAsString('\n', mode: FileMode.append);
          _length++;
        }
      }
      initialized = true;
      _schedule();
    } catch (error) {
      _storageFailed(error);
    }
  }

  void info(
    String component,
    String event,
    String message, {
    Map<String, Object?> fields = const {},
  }) => _add(LogLevel.info, component, event, message, fields: fields);

  void warning(
    String component,
    String event,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, Object?> fields = const {},
  }) => _add(
    LogLevel.warning,
    component,
    event,
    message,
    error: error,
    stack: stack,
    fields: fields,
  );

  void error(
    String component,
    String event,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, Object?> fields = const {},
  }) => _add(
    LogLevel.error,
    component,
    event,
    message,
    error: error,
    stack: stack,
    fields: fields,
  );

  void _add(
    LogLevel level,
    String component,
    String event,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, Object?> fields = const {},
  }) {
    if (_closed) return;
    final now = DateTime.now().toUtc();
    final entry = LogEntry(
      id: '$pid-${now.microsecondsSinceEpoch}-${_sequence++}',
      time: now,
      level: level,
      component: _safeString(component, 64),
      event: _safeString(event, 128),
      message: _safeString(message),
      fields: Map.fromEntries(
        fields.entries
            .take(40)
            .map(
              (entry) => MapEntry(
                _safeString(entry.key, 128),
                _safeValue(entry.key, entry.value),
              ),
            ),
      ),
      error: error == null
          ? null
          : _safeString(
              error is FormatException ? error.message : '$error',
              8192,
            ),
      stack: stack == null ? null : _safeString('$stack', 12288),
    );
    if (_pending.length < 1000) {
      _pending.add(entry);
    } else {
      _dropped++;
    }
    _events.add(entry);
    _changes.add(null);
    _schedule();
  }

  void _schedule() {
    if (_closed || !initialized || _pending.isEmpty || _timer != null) return;
    _timer = Timer(flushInterval, () {
      _timer = null;
      unawaited(flush());
    });
  }

  void _storageFailed(Object error) {
    storageError = '日志写入失败：${_safeString('$error', 512)}';
    if (!_closed) _changes.add(null);
  }

  Future<void> _rotate() async {
    for (var index = archiveCount; index >= 1; index--) {
      final destination = File(p.join(directory.path, 'nearlink.$index.jsonl'));
      if (index == archiveCount && await destination.exists()) {
        await destination.delete();
      }
      final source = File(
        index == 1
            ? currentPath
            : p.join(directory.path, 'nearlink.${index - 1}.jsonl'),
      );
      if (await source.exists()) await source.rename(destination.path);
    }
    _length = 0;
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_closed || !initialized) return Future.value();
    _writes = _writes
        .then((_) async {
          while (_pending.isNotEmpty || _dropped > 0) {
            if (_pending.isEmpty && _dropped > 0) {
              final count = _dropped;
              _dropped = 0;
              warning(
                'logging',
                'queue_overflow',
                '日志缓冲区已满，部分记录未写入',
                fields: {'dropped': count},
              );
            }
            final batch = _pending.take(128).toList();
            final bytes = BytesBuilder(copy: false);
            var buffered = 0;
            Future<void> writeBuffer() async {
              if (buffered == 0) return;
              await File(
                currentPath,
              ).writeAsBytes(bytes.takeBytes(), mode: FileMode.append);
              _length += buffered;
              buffered = 0;
            }

            for (final entry in batch) {
              final line = utf8.encode('${jsonEncode(entry.toJson())}\n');
              if (_length + buffered > 0 &&
                  _length + buffered + line.length > maxFileBytes) {
                await writeBuffer();
                await _rotate();
              }
              bytes.add(line);
              buffered += line.length;
            }
            await writeBuffer();
            for (var index = 0; index < batch.length; index++) {
              _pending.removeFirst();
            }
          }
          storageError = null;
        })
        .catchError((Object error) {
          _storageFailed(error);
        });
    return _writes;
  }

  Future<List<LogEntry>> readRecent({int limit = 500}) async {
    await flush();
    final directoryPath = directory.path;
    final count = archiveCount;
    final result = _writes.then(
      (_) => Isolate.run(() => _readRecent(directoryPath, count, limit)),
    );
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> export(String destination) async {
    await flush();
    final target = p.normalize(p.absolute(destination));
    if (p.isWithin(p.absolute(directory.path), target) ||
        target == p.absolute(directory.path)) {
      throw const FileSystemException('请选择日志目录以外的位置');
    }
    // Serialize the snapshot with rotation so no segment disappears while read.
    final operation = _writes.then((_) async {
      RandomAccessFile? output;
      try {
        output = await File(target).open(mode: FileMode.write);
        for (final file in _logFiles(directory.path, archiveCount)) {
          if (await file.exists()) {
            await for (final bytes in file.openRead()) {
              await output.writeFrom(bytes);
            }
          }
        }
      } finally {
        await output?.close();
      }
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _timer?.cancel();
    await flush();
    _timer?.cancel();
    _closed = true;
    await _events.close();
    await _changes.close();
  }
}
