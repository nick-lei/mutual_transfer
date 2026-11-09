import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screenshot_controller.dart';
import 'screenshot_editor.dart';

class ScreenshotHost extends StatefulWidget {
  const ScreenshotHost({
    super.key,
    required this.controller,
    required this.child,
  });
  final ScreenshotController controller;
  final Widget child;

  @override
  State<ScreenshotHost> createState() => _ScreenshotHostState();
}

class _ScreenshotHostState extends State<ScreenshotHost> {
  ui.Image? _image;
  Completer<void>? _session;
  bool _closing = false;
  bool _preparing = false;
  bool _cancelPreparation = false;

  @override
  void initState() {
    super.initState();
    widget.controller.onCapture = _capture;
    widget.controller.onCancel = _cancel;
  }

  void _cancel() {
    if (_preparing) {
      _cancelPreparation = true;
    } else {
      unawaited(_finish(activate: false));
    }
  }

  Future<void> _capture() async {
    _session = Completer<void>();
    _preparing = true;
    _cancelPreparation = false;
    try {
      await ScreenshotController.channel.invokeMethod<void>(
        'beginCapture',
        widget.controller.hideWindowOnCapture,
      );
      // Let the compositor settle before freezing the chosen desktop state.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final bytes = await ScreenshotController.channel.invokeMethod<Uint8List>(
        'captureDesktop',
      );
      if (bytes == null) throw const FormatException('无法获取桌面图像');
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || _cancelPreparation) {
        frame.image.dispose();
        _preparing = false;
        await _finish(activate: false);
        return;
      }
      setState(() => _image = frame.image);
      // Paint the editor before showing the desktop-sized native window.
      await WidgetsBinding.instance.endOfFrame;
      await ScreenshotController.channel.invokeMethod<void>('showOverlay');
      _preparing = false;
      if (_cancelPreparation) await _finish(activate: false);
      await _session!.future;
    } catch (e, stack) {
      widget.controller.log?.warning(
        'screenshot',
        'capture_failed',
        '截图失败',
        error: e,
        stack: stack,
      );
      _preparing = false;
      await _finish(activate: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PlatformException ? e.message ?? '截图失败，请重试' : '截图失败，请重试。',
            ),
          ),
        );
      }
    }
  }

  Future<void> _finish({required bool activate}) async {
    if (_closing) return;
    _closing = true;
    final image = _image;
    try {
      // Keep capture pixels off the restored application window.
      if (mounted) setState(() => _image = null);
      await ScreenshotController.channel.invokeMethod<void>(
        'restoreWindow',
        activate,
      );
    } finally {
      if (mounted) await WidgetsBinding.instance.endOfFrame;
      image?.dispose();
      if (_session?.isCompleted == false) _session!.complete();
      _closing = false;
    }
  }

  Future<void> _output(CaptureOutput action, Uint8List png) async {
    switch (action) {
      case CaptureOutput.copy:
        await widget.controller.copyImage(png);
        await _finish(activate: false);
      case CaptureOutput.save:
        final date = DateTime.now();
        final stamp =
            '${date.year}${date.month.toString().padLeft(2, '0')}'
            '${date.day.toString().padLeft(2, '0')}_${date.hour.toString().padLeft(2, '0')}'
            '${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}';
        String? path;
        // The system file dialog is a separate non-topmost window on Windows.
        // Let it appear above the capture overlay, then restore editing on cancel.
        await ScreenshotController.channel.invokeMethod<void>(
          'setOverlayTopmost',
          false,
        );
        try {
          path = await FilePicker.saveFile(
            dialogTitle: '保存截图',
            fileName: '邻传截图_$stamp.png',
            type: FileType.custom,
            allowedExtensions: ['png'],
          );
        } finally {
          await ScreenshotController.channel.invokeMethod<void>(
            'setOverlayTopmost',
            true,
          );
        }
        if (path == null) return;
        // The native save dialog owns overwrite confirmation for its returned path.
        await File(path).writeAsBytes(png, flush: true);
        await _finish(activate: false);
      case CaptureOutput.stage:
        await widget.controller.stageImage(png);
        await _finish(activate: true);
    }
  }

  @override
  void dispose() {
    widget.controller.onCapture = null;
    widget.controller.onCancel = null;
    _image?.dispose();
    if (_session?.isCompleted == false) _session!.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Offstage(
        offstage: _image != null,
        child: ExcludeFocus(excluding: _image != null, child: widget.child),
      ),
      if (_image != null)
        Positioned.fill(
          child: HeroControllerScope.none(
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (context, animation, secondaryAnimation) =>
                    ScreenshotEditor(
                      image: _image!,
                      onCancel: _cancel,
                      onOutput: _output,
                    ),
              ),
            ),
          ),
        ),
    ],
  );
}
