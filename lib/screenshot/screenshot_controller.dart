import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../logging/app_log.dart';

@immutable
class CaptureHotkey {
  const CaptureHotkey({this.modifiers = 3, this.key = 65});
  final int modifiers; // Windows MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4.
  final int key;

  bool get valid =>
      modifiers & 3 != 0 &&
      modifiers & ~7 == 0 &&
      ((key >= 65 && key <= 90) ||
          (key >= 48 && key <= 57) ||
          (key >= 112 && key <= 135));

  String get label => [
    if (modifiers & 2 != 0) 'Ctrl',
    if (modifiers & 1 != 0) 'Alt',
    if (modifiers & 4 != 0) 'Shift',
    key >= 112 && key <= 135 ? 'F${key - 111}' : String.fromCharCode(key),
  ].join(' + ');

  Map<String, int> toJson() => {'modifiers': modifiers, 'key': key};

  static CaptureHotkey? fromEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed) return null;
    final logical = event.logicalKey;
    int? key;
    if (logical.keyId >= LogicalKeyboardKey.keyA.keyId &&
        logical.keyId <= LogicalKeyboardKey.keyZ.keyId) {
      key = logical.keyId - LogicalKeyboardKey.keyA.keyId + 65;
    } else if (logical.keyId >= LogicalKeyboardKey.digit0.keyId &&
        logical.keyId <= LogicalKeyboardKey.digit9.keyId) {
      key = logical.keyId - LogicalKeyboardKey.digit0.keyId + 48;
    } else if (logical.keyId >= LogicalKeyboardKey.f1.keyId &&
        logical.keyId <= LogicalKeyboardKey.f24.keyId) {
      key = logical.keyId - LogicalKeyboardKey.f1.keyId + 112;
    }
    if (key == null) return null;
    final candidate = CaptureHotkey(
      modifiers:
          (keyboard.isAltPressed ? 1 : 0) |
          (keyboard.isControlPressed ? 2 : 0) |
          (keyboard.isShiftPressed ? 4 : 0),
      key: key,
    );
    return candidate.valid ? candidate : null;
  }
}

class ScreenshotController extends ChangeNotifier {
  ScreenshotController(this.dataDirectory, {this.log});
  static const channel = MethodChannel('nearlink/screenshot');
  final Directory dataDirectory;
  final AppLog? log;
  CaptureHotkey hotkey = const CaptureHotkey();
  bool enabled = true;
  bool hideWindowOnCapture = true;
  bool registered = false;
  bool ready = false;
  bool capturing = false;
  bool updating = false;
  bool recordingHotkey = false;
  String? hotkeyError;
  String? captureSettingsError;
  ValueChanged<CaptureHotkey>? onRecordedHotkey;
  Future<void> Function()? onCapture;
  VoidCallback? onCancel;
  final stagedFiles = StreamController<String>.broadcast();

  Future<void> initialize() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'captureRequested' && !capturing && !updating) {
        if (recordingHotkey) {
          // Windows consumes the active global chord before Flutter sees it.
          onRecordedHotkey?.call(hotkey);
        } else {
          await capture();
        }
      } else if (call.method == 'cancelRequested') {
        onCancel?.call();
      }
    });
    final file = File(p.join(dataDirectory.path, 'screenshot.json'));
    try {
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final saved = CaptureHotkey(
          modifiers: json['modifiers'] as int,
          key: json['key'] as int,
        );
        if (!saved.valid) throw const FormatException('无效的快捷键');
        hotkey = saved;
        enabled = json['enabled'] as bool;
        hideWindowOnCapture = json['hideWindowOnCapture'] as bool? ?? true;
      }
    } catch (error, stack) {
      log?.warning(
        'screenshot',
        'preferences_read_failed',
        '截图设置读取失败',
        error: error,
        stack: stack,
      );
      hotkeyError = '快捷键设置读取失败，已使用默认组合。';
    }
    try {
      await _register(hotkey, enabled);
      registered = enabled;
    } on PlatformException catch (e) {
      log?.warning(
        'screenshot',
        'hotkey_registration_failed',
        '截图快捷键注册失败',
        error: e,
      );
      hotkeyError = e.message ?? '快捷键注册失败，可在设置中重新绑定。';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _register(CaptureHotkey value, bool enable) =>
      channel.invokeMethod<void>(
        'registerHotkey',
        enable ? value.toJson() : {'modifiers': 0, 'key': 0},
      );

  Future<void> setRecordingHotkey(bool recording) async {
    if (recordingHotkey == recording) return;
    recordingHotkey = recording;
    await channel.invokeMethod<void>('setHotkeyRecording', recording);
  }

  Future<void> _saveSettings({
    required CaptureHotkey hotkey,
    required bool enabled,
    required bool hideWindowOnCapture,
  }) async {
    await dataDirectory.create(recursive: true);
    final temporary = File(p.join(dataDirectory.path, 'screenshot.json.tmp'));
    await temporary.writeAsString(
      jsonEncode({
        ...hotkey.toJson(),
        'enabled': enabled,
        'hideWindowOnCapture': hideWindowOnCapture,
      }),
      flush: true,
    );
    await temporary.rename(p.join(dataDirectory.path, 'screenshot.json'));
  }

  Future<void> updateHideWindowOnCapture(bool hideWindow) async {
    if (updating || capturing) return;
    updating = true;
    captureSettingsError = null;
    notifyListeners();
    try {
      await _saveSettings(
        hotkey: hotkey,
        enabled: enabled,
        hideWindowOnCapture: hideWindow,
      );
      hideWindowOnCapture = hideWindow;
    } catch (_) {
      captureSettingsError = '无法保存截图设置，请检查本机配置目录后重试。';
      rethrow;
    } finally {
      updating = false;
      notifyListeners();
    }
  }

  Future<void> updateHotkey(CaptureHotkey value, {required bool enable}) async {
    if (updating) return;
    if (!value.valid) throw const FormatException('请使用 Ctrl 或 Alt 搭配字母、数字或功能键');
    updating = true;
    notifyListeners();
    final wasRegistered = registered;
    var changed = false;
    try {
      await _register(value, enable);
      changed = true;
      await _saveSettings(
        hotkey: value,
        enabled: enable,
        hideWindowOnCapture: hideWindowOnCapture,
      );
      hotkey = value;
      enabled = enable;
      registered = enable;
      hotkeyError = null;
    } catch (e) {
      log?.warning('screenshot', 'hotkey_update_failed', '截图快捷键更新失败', error: e);
      if (changed) {
        try {
          await _register(hotkey, wasRegistered);
          registered = wasRegistered;
        } catch (_) {
          registered = false;
        }
      }
      hotkeyError = e is PlatformException
          ? e.message ?? '快捷键注册失败'
          : '无法保存快捷键设置，请检查本机配置目录。';
      rethrow;
    } finally {
      updating = false;
      notifyListeners();
    }
  }

  Future<void> capture() async {
    if (!ready ||
        capturing ||
        updating ||
        recordingHotkey ||
        onCapture == null) {
      return;
    }
    capturing = true;
    notifyListeners();
    try {
      log?.info(
        'screenshot',
        'capture_started',
        '开始截图',
        fields: {'hideWindow': hideWindowOnCapture},
      );
      await onCapture!();
    } finally {
      capturing = false;
      notifyListeners();
    }
  }

  Future<void> copyImage(Uint8List png) =>
      channel.invokeMethod<void>('copyImage', png);

  Future<String> stageImage(Uint8List png) async {
    final directory = Directory(p.join(dataDirectory.path, 'screenshots'));
    await directory.create(recursive: true);
    final file = File(
      p.join(directory.path, '截图_${DateTime.now().microsecondsSinceEpoch}.png'),
    );
    await file.writeAsBytes(png, flush: true);
    stagedFiles.add(file.path);
    return file.path;
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    unawaited(stagedFiles.close());
    super.dispose();
  }
}
