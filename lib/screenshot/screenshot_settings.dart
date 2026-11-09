import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui/components.dart';
import 'screenshot_controller.dart';

class ScreenshotSettings extends StatelessWidget {
  const ScreenshotSettings({super.key, required this.controller});
  final ScreenshotController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('截图与快捷键'),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '全局截图快捷键',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '邻传运行时，在其他程序中也能唤起截图。',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: controller.enabled,
                    onChanged: controller.ready && !controller.updating
                        ? (enable) async {
                            try {
                              await controller.updateHotkey(
                                controller.hotkey,
                                enable: enable,
                              );
                            } catch (_) {
                              /* The persistent inline error explains recovery. */
                            }
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _HotkeyField(controller: controller),
                  TextButton.icon(
                    onPressed: controller.ready && !controller.capturing
                        ? controller.capture
                        : null,
                    icon: const Icon(LucideIcons.scan, size: 18),
                    label: const Text('立即截图'),
                  ),
                ],
              ),
              if (controller.hotkeyError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    controller.hotkeyError!,
                    style: const TextStyle(fontSize: 13, color: danger),
                  ),
                ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '截图时隐藏邻传',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Semantics(
                    label: '截图时隐藏邻传',
                    child: Switch(
                      key: const ValueKey('capture-hide-window'),
                      value: controller.hideWindowOnCapture,
                      onChanged:
                          controller.ready &&
                              !controller.updating &&
                              !controller.capturing
                          ? (hideWindow) async {
                              try {
                                await controller.updateHideWindowOnCapture(
                                  hideWindow,
                                );
                              } catch (_) {
                                // Keep the current value and show the save error below.
                              }
                            }
                          : null,
                    ),
                  ),
                ],
              ),
              if (controller.captureSettingsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    controller.captureSettingsError!,
                    style: const TextStyle(fontSize: 13, color: danger),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HotkeyField extends StatefulWidget {
  const _HotkeyField({required this.controller});
  final ScreenshotController controller;
  @override
  State<_HotkeyField> createState() => _HotkeyFieldState();
}

class _HotkeyFieldState extends State<_HotkeyField>
    with WidgetsBindingObserver {
  CaptureHotkey? _candidate;
  String? _preview;
  bool _busy = false;
  String? _error;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _focus.unfocus();
  }

  Future<void> _setRecording(bool recording) async {
    try {
      await widget.controller.setRecordingHotkey(recording);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '快捷键录入暂不可用，请重新点击输入框');
      }
    }
  }

  static final _modifiers = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  String get _label => _focus.hasFocus
      ? _candidate?.label ?? _preview ?? '按下组合键'
      : widget.controller.hotkey.label;

  String? _pressedLabel() {
    final keyboard = HardwareKeyboard.instance;
    final labels = [
      if (keyboard.isControlPressed) 'Ctrl',
      if (keyboard.isAltPressed) 'Alt',
      if (keyboard.isShiftPressed) 'Shift',
      if (keyboard.isMetaPressed) 'Win',
      for (final key in keyboard.logicalKeysPressed)
        if (!_modifiers.contains(key))
          key == LogicalKeyboardKey.space
              ? 'Space'
              : key.keyLabel.toUpperCase(),
    ];
    return labels.isEmpty ? null : labels.join(' + ');
  }

  void _recordedHotkey(CaptureHotkey hotkey) {
    if (!mounted || !_focus.hasFocus || _busy) return;
    setState(() {
      _candidate = hotkey;
      _preview = hotkey.label;
      _error = null;
    });
    if (HardwareKeyboard.instance.logicalKeysPressed.isEmpty) {
      unawaited(_save());
    }
  }

  bool get _enabled =>
      widget.controller.ready &&
      !widget.controller.updating &&
      !widget.controller.capturing;

  void _focusChanged(bool focused) {
    unawaited(_setRecording(focused));
    widget.controller.onRecordedHotkey = focused ? _recordedHotkey : null;
    setState(() {
      _candidate = null;
      _preview = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_setRecording(false));
    widget.controller.onRecordedHotkey = null;
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final candidate = _candidate;
    if (candidate == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.updateHotkey(
        candidate,
        enable: widget.controller.enabled,
      );
      if (mounted) _focus.unfocus();
    } catch (_) {
      // Registration and persistence errors are shown by the settings section.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _candidate = null;
        });
      }
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_busy || !_enabled) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      final candidate = CaptureHotkey.fromEvent(event);
      final isModifier = _modifiers.contains(event.logicalKey);
      setState(() {
        _preview = _pressedLabel();
        if (candidate != null) {
          _candidate = candidate;
          _error = null;
        } else if (!isModifier) {
          _candidate = null;
          _error = '请使用 Ctrl 或 Alt 搭配字母、数字或功能键';
        } else if (_candidate == null) {
          _error = null;
        }
      });
    }
    // Register after release so the new global shortcut cannot trigger a capture
    // while this same chord is still being entered.
    if (event is KeyUpEvent &&
        _candidate != null &&
        HardwareKeyboard.instance.logicalKeysPressed.isEmpty) {
      unawaited(_save());
    } else if (event is KeyUpEvent && _candidate == null && _error == null) {
      setState(() => _preview = _pressedLabel());
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 248,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TapRegion(
          onTapOutside: (_) => _focus.unfocus(),
          child: Focus(
            focusNode: _focus,
            canRequestFocus: _enabled || _busy,
            onFocusChange: _focusChanged,
            onKeyEvent: _key,
            child: Semantics(
              label: '截图快捷键',
              value: _label,
              textField: true,
              readOnly: true,
              enabled: _enabled,
              focused: _focus.hasFocus,
              onTap: _enabled ? _focus.requestFocus : null,
              child: MouseRegion(
                cursor: _enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  key: const ValueKey('capture-hotkey-field'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _enabled ? _focus.requestFocus : null,
                  child: SizedBox(
                    height: 48,
                    child: InputDecorator(
                      isFocused: _focus.hasFocus,
                      decoration: InputDecoration(
                        enabled: _enabled,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        suffixIconConstraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        suffixIcon: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                LucideIcons.keyboard,
                                size: 18,
                                color: _focus.hasFocus ? blue : muted,
                              ),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _focus.hasFocus ? blue : ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: danger),
            ),
          ),
      ],
    ),
  );
}
