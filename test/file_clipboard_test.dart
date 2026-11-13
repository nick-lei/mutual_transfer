import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/desktop/file_clipboard.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late File file;
  late List<MethodCall> calls;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nearlink-clipboard-');
    file = await File(
      p.join(directory.path, '项目 文件.txt'),
    ).writeAsString('clipboard fixture');
    calls = [];
    messenger.setMockMethodCallHandler(WindowsFileClipboard.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(WindowsFileClipboard.channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'copies the existing Unicode file through the Windows file clipboard method',
    () async {
      await WindowsFileClipboard.copyFile(file.path);
      expect(calls.single.method, 'copyFilesToClipboard');
      expect(calls.single.arguments, {
        'paths': [p.normalize(p.absolute(file.path))],
      });
    },
  );

  test('missing or malformed files never replace the clipboard', () async {
    await file.delete();
    for (final path in [file.path, '', '${directory.path}\u0000bad']) {
      await expectLater(
        WindowsFileClipboard.copyFile(path),
        throwsFormatException,
      );
    }
    expect(calls, isEmpty);
  });

  test(
    'a busy clipboard retries asynchronously with a bounded limit',
    () async {
      messenger.setMockMethodCallHandler(WindowsFileClipboard.channel, (
        call,
      ) async {
        calls.add(call);
        if (calls.length < 3) throw PlatformException(code: 'clipboard_busy');
        return null;
      });
      await WindowsFileClipboard.copyFile(file.path);
      expect(calls, hasLength(3));
    },
  );

  test(
    'persistent clipboard errors produce a recovery message after three attempts',
    () async {
      messenger.setMockMethodCallHandler(WindowsFileClipboard.channel, (
        call,
      ) async {
        calls.add(call);
        throw PlatformException(code: 'clipboard_busy');
      });
      await expectLater(
        WindowsFileClipboard.copyFile(file.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            '剪贴板暂时不可用，请稍后重试',
          ),
        ),
      );
      expect(calls, hasLength(3));
    },
  );

  test(
    'native revalidation catches a file removed after the Dart check',
    () async {
      messenger.setMockMethodCallHandler(WindowsFileClipboard.channel, (
        call,
      ) async {
        calls.add(call);
        throw PlatformException(code: 'file_unavailable');
      });
      await expectLater(
        WindowsFileClipboard.copyFile(file.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            '文件已被移动或删除，无法复制',
          ),
        ),
      );
      expect(calls, hasLength(1));
    },
  );
}
