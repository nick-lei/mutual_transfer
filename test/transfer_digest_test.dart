import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/transfer_stream.dart';

void main() {
  test('native SHA-256 matches standard vectors and chunk boundaries', () {
    for (final length in [
      0,
      3,
      55,
      56,
      63,
      64,
      65,
      1024 * 1024,
      2 * 1024 * 1024 + 17,
    ]) {
      final bytes = Uint8List.fromList(List.generate(length, (i) => i % 251));
      final digest = TransferDigest();
      try {
        expect(
          digest.implementation,
          Platform.isWindows ? 'windows-cng' : 'dart',
        );
        for (var offset = 0; offset < bytes.length; offset += 77777) {
          digest.addBytes(
            Uint8List.sublistView(
              bytes,
              offset,
              (offset + 77777).clamp(0, bytes.length),
            ),
          );
        }
        expect(
          digest.finish(),
          sha256.convert(bytes).toString(),
          reason: '$length bytes',
        );
      } finally {
        digest.closeNative();
      }
    }
    final known = TransferDigest();
    known.addBytes([97, 98, 99]);
    expect(
      known.finish(),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('abandoned digests release native state and reject further input', () {
    final digest = TransferDigest();
    digest.addBytes([1, 2]);
    digest.closeNative();
    digest.closeNative();
    if (Platform.isWindows) {
      expect(() => digest.addBytes([3]), throwsStateError);
    }
  });
}
