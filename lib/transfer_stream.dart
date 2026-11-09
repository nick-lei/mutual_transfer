import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'windows_sha256.dart';

const streamingIntegrity = 'streaming-sha256-v1';
const transferBufferBytes = 1024 * 1024;

Stream<List<int>> readTransferFile(String path) async* {
  final file = await File(path).open();
  try {
    while (true) {
      final bytes = await file.read(transferBufferBytes);
      if (bytes.isEmpty) break;
      yield bytes;
    }
  } finally {
    await file.close();
  }
}

Future<String> hashTransferFile(String path) async {
  final digest = TransferDigest();
  try {
    await for (final bytes in readTransferFile(path)) {
      digest.addBytes(bytes);
    }
    return digest.finish();
  } finally {
    digest.closeNative();
  }
}

// Keep this closure outside service state so only the path crosses isolates.
Future<String> hashTransferFileInBackground(String path) =>
    Isolate.run(() => hashTransferFile(path));

class TransferDigest implements Sink<Digest> {
  TransferDigest() {
    _native = WindowsSha256.tryCreate();
    if (_native == null) _input = sha256.startChunkedConversion(this);
  }
  ByteConversionSink? _input;
  WindowsSha256? _native;
  Digest? _digest;
  String get implementation => _native == null ? 'dart' : 'windows-cng';
  void addBytes(List<int> bytes) =>
      _native == null ? _input!.add(bytes) : _native!.add(bytes);
  String finish() {
    if (_native != null) return _native!.finish();
    _input!.close();
    return _digest!.toString();
  }

  void closeNative() => _native?.close();

  @override
  void add(Digest data) => _digest = data;
  @override
  void close() {}
}
