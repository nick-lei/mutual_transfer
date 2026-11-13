import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class WindowsFileClipboard {
  static const channel = MethodChannel('nearlink/lifecycle');

  static Future<void> copyFile(String path) async {
    if (path.isEmpty || path.contains('\u0000') || !await File(path).exists()) {
      throw const FormatException('文件已被移动或删除，无法复制');
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await channel.invokeMethod<void>('copyFilesToClipboard', {
          'paths': [p.normalize(p.absolute(path))],
        });
        return;
      } on PlatformException catch (error) {
        if (error.code == 'clipboard_busy' && attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 50 * (attempt + 1)),
          );
          continue;
        }
        throw FormatException(
          error.code == 'file_unavailable'
              ? '文件已被移动或删除，无法复制'
              : '剪贴板暂时不可用，请稍后重试',
        );
      }
    }
  }
}
