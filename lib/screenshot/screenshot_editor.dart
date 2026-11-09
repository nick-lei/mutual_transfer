import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui/app_theme.dart';
import 'annotation_document.dart';

enum CaptureOutput { copy, save, stage }

class ScreenshotEditor extends StatefulWidget {
  const ScreenshotEditor({
    super.key,
    required this.image,
    required this.onCancel,
    required this.onOutput,
  });
  final ui.Image image;
  final VoidCallback onCancel;
  final Future<void> Function(CaptureOutput action, Uint8List png) onOutput;

  @override
  State<ScreenshotEditor> createState() => _ScreenshotEditorState();
}

class _ScreenshotEditorState extends State<ScreenshotEditor> {
  final document = AnnotationDocument();
  final _focus = FocusNode();
  final _textFocus = FocusNode();
  final _text = TextEditingController();
  CaptureTool _tool = CaptureTool.select;
  Color _color = const Color(0xFFF04452);
  double _stroke = 4;
  double _fontSize = 22;
  Size _view = Size.zero;
  Offset? _origin, _textAnchor;
  Rect? _originalSelection;
  int? _resizeHandle;
  int? _editingText;
  double? _textWidth;
  CaptureMark? _pending;
  bool _selecting = false, _moving = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(_refreshText);
  }

  void _refreshText() {
    if (mounted && _textAnchor != null) setState(() {});
  }

  double get _scale => widget.image.width / math.max(1, _view.width);
  Rect get _imageBounds => Rect.fromLTWH(
    0,
    0,
    widget.image.width.toDouble(),
    widget.image.height.toDouble(),
  );

  @override
  void dispose() {
    _focus.dispose();
    _textFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  Offset _point(Offset local) => Offset(
    (local.dx * widget.image.width / _view.width).clamp(
      0,
      widget.image.width.toDouble(),
    ),
    (local.dy * widget.image.height / _view.height).clamp(
      0,
      widget.image.height.toDouble(),
    ),
  );
  Offset _local(Offset point) =>
      Offset(point.dx / _scale, point.dy * _view.height / widget.image.height);
  Rect _localRect(Rect rect) =>
      Rect.fromPoints(_local(rect.topLeft), _local(rect.bottomRight));
  List<Offset> _handles(Rect r) => [
    r.topLeft,
    r.topCenter,
    r.topRight,
    r.centerRight,
    r.bottomRight,
    r.bottomCenter,
    r.bottomLeft,
    r.centerLeft,
  ];

  void _start(DragStartDetails details) {
    if (_textAnchor != null) _commitText();
    if (_busy ||
        _textAnchor != null ||
        _tool == CaptureTool.text && document.selection != null) {
      return;
    }
    _focus.requestFocus();
    final point = _point(details.localPosition);
    final selection = document.selection;
    setState(() {
      _error = null;
      _origin = point;
      _originalSelection = selection;
      _resizeHandle = null;
      _moving = false;
      if (_tool == CaptureTool.select || selection == null) {
        if (selection != null) {
          final handles = _handles(selection);
          for (var i = 0; i < handles.length; i++) {
            if ((point - handles[i]).distance < 12 * _scale) {
              _resizeHandle = i;
              break;
            }
          }
          _moving = _resizeHandle == null && selection.contains(point);
          // Existing annotations stay attached to source pixels while cropping.
          if (!_moving && _resizeHandle == null) document.reset();
        }
        _selecting = !_moving && _resizeHandle == null;
        if (_selecting) document.selection = Rect.fromPoints(point, point);
      } else if (selection.contains(point)) {
        _pending = CaptureMark(
          tool: _tool,
          color: _color,
          width: _stroke * _scale,
          points: [point],
        );
      }
    });
  }

  void _update(DragUpdateDetails details) {
    if (_origin == null || _busy) return;
    final point = _point(details.localPosition);
    setState(() {
      if (_selecting) {
        document.selection = Rect.fromPoints(_origin!, point);
      } else if (_moving) {
        final rect = _originalSelection!;
        final delta = point - _origin!;
        document.selection = rect.shift(
          Offset(
            delta.dx.clamp(-rect.left, _imageBounds.right - rect.right),
            delta.dy.clamp(-rect.top, _imageBounds.bottom - rect.bottom),
          ),
        );
      } else if (_resizeHandle != null) {
        final rect = _originalSelection!;
        final h = _resizeHandle!;
        final left = [0, 6, 7].contains(h)
            ? math.min(point.dx, rect.right - 2)
            : rect.left;
        final right = [2, 3, 4].contains(h)
            ? math.max(point.dx, rect.left + 2)
            : rect.right;
        final top = [0, 1, 2].contains(h)
            ? math.min(point.dy, rect.bottom - 2)
            : rect.top;
        final bottom = [4, 5, 6].contains(h)
            ? math.max(point.dy, rect.top + 2)
            : rect.bottom;
        document.selection = Rect.fromLTRB(
          left,
          top,
          right,
          bottom,
        ).intersect(_imageBounds);
      } else if (_pending != null) {
        final selection = document.selection!;
        final clamped = Offset(
          point.dx.clamp(selection.left, selection.right),
          point.dy.clamp(selection.top, selection.bottom),
        );
        if (_pending!.tool == CaptureTool.pen) {
          _pending!.points.add(clamped);
        } else {
          if (_pending!.points.length > 1) _pending!.points.removeLast();
          _pending!.points.add(clamped);
        }
      }
    });
  }

  void _end([DragEndDetails? details]) {
    setState(() {
      if (_pending != null) {
        final mark = _pending!;
        if (mark.tool == CaptureTool.pen ||
            (mark.points.last - mark.points.first).distance >= 2) {
          document.add(mark);
        }
      }
      if (document.selection != null &&
          (document.selection!.width < 2 || document.selection!.height < 2)) {
        document.selection = null;
      }
      _pending = null;
      _origin = null;
      _selecting = false;
      _moving = false;
      _resizeHandle = null;
    });
  }

  void _tap(TapUpDetails details) {
    if (_busy) return;
    if (_textAnchor != null) {
      _commitText();
      return;
    }
    if (_tool != CaptureTool.text) return;
    final point = _point(details.localPosition);
    if (document.selection?.contains(point) != true) return;
    int? index;
    for (var i = document.marks.length - 1; i >= 0; i--) {
      final mark = document.marks[i];
      if (mark.tool == CaptureTool.text &&
          mark.textBounds.inflate(6 * _scale).contains(point)) {
        index = i;
        break;
      }
    }
    final mark = index == null ? null : document.marks[index];
    setState(() {
      _editingText = index;
      _textAnchor =
          mark?.points.first ??
          Offset(
            point.dx.clamp(
              document.selection!.left,
              math.max(
                document.selection!.left,
                document.selection!.right - 40 * _scale,
              ),
            ),
            point.dy.clamp(
              document.selection!.top,
              math.max(
                document.selection!.top,
                document.selection!.bottom - _fontSize * 1.3 * _scale,
              ),
            ),
          );
      _textWidth = mark?.autoTextWidth == false ? mark!.textWidth : null;
      if (mark != null) {
        _color = mark.color;
        _fontSize = mark.fontSize / _scale;
      }
      _text.text = mark?.text ?? '';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
    _textFocus.requestFocus();
  }

  CaptureMark _draftText() => CaptureMark(
    tool: CaptureTool.text,
    color: _color,
    width: _stroke * _scale,
    points: [_textAnchor!],
    text: _text.text,
    fontSize: _fontSize * _scale,
    autoTextWidth: _textWidth == null,
    textWidth: math.min(
      _textWidth ?? double.infinity,
      document.selection!.right - _textAnchor!.dx,
    ),
  );

  void _cancelText() {
    setState(() {
      _textAnchor = null;
      _editingText = null;
      _textWidth = null;
      _text.clear();
    });
    _focus.requestFocus();
  }

  void _setTool(CaptureTool tool) {
    if (_textAnchor != null) _commitText();
    setState(() => _tool = tool);
  }

  void _commitText() {
    if (_textAnchor == null) return;
    setState(() {
      final mark = _text.text.trim().isEmpty ? null : _draftText();
      if (_editingText != null) {
        document.replace(_editingText!, mark);
      } else if (mark != null) {
        document.add(mark);
      }
      _textAnchor = null;
      _editingText = null;
      _textWidth = null;
      _text.clear();
    });
    _focus.requestFocus();
  }

  Future<void> _output(CaptureOutput action) async {
    if (_busy || document.selection == null) return;
    _commitText();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final png = await document.exportPng(widget.image);
      await widget.onOutput(action, png);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is PlatformException
              ? e.message ?? '操作失败，请重试'
              : '未能完成操作，请重试或选择其他保存方式。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _busy) return KeyEventResult.ignored;
    if (_textAnchor != null) {
      if (_text.value.composing.isValid && !_text.value.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelText();
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        _commitText();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        setState(
          HardwareKeyboard.instance.isShiftPressed
              ? document.redo
              : document.undo,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY) {
        setState(document.redo);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        _output(CaptureOutput.copy);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyS) {
        _output(CaptureOutput.save);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black,
    child: Focus(
      autofocus: true,
      focusNode: _focus,
      onKeyEvent: _key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _view = constraints.biggest;
          final selection = document.selection;
          final local = selection == null ? null : _localRect(selection);
          final toolbarWidth = math.min(492.0, _view.width - 24);
          final mainHeight = toolbarWidth < 492 ? 88.0 : 48.0;
          final hasOptions = _tool != CaptureTool.select;
          final totalHeight = mainHeight + (hasOptions ? 48 : 0);
          final left = local == null
              ? 12.0
              : (local.right - toolbarWidth).clamp(
                  12.0,
                  math.max(12.0, _view.width - toolbarWidth - 12),
                );
          final top = local == null
              ? 12.0
              : (local.bottom + totalHeight + 18 <= _view.height
                        ? local.bottom + 10
                        : local.top >= totalHeight + 34
                        ? local.top - totalHeight - 34
                        : _view.height - totalHeight - 12)
                    .clamp(
                      12.0,
                      math.max(12.0, _view.height - totalHeight - 12),
                    );
          final optionsWidth = math.min(306.0, toolbarWidth);
          final optionsLeft = (left + 8 + _tool.index * 38 - optionsWidth / 2)
              .clamp(12.0, math.max(12.0, _view.width - optionsWidth - 12));
          return Stack(
            children: [
              Positioned.fill(
                child: MouseRegion(
                  cursor: _tool == CaptureTool.text
                      ? SystemMouseCursors.text
                      : SystemMouseCursors.precise,
                  child: GestureDetector(
                    key: const ValueKey('capture-canvas'),
                    dragStartBehavior: DragStartBehavior.down,
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _start,
                    onPanUpdate: _update,
                    onPanEnd: _end,
                    onPanCancel: _end,
                    onTapUp: _tap,
                    child: CustomPaint(
                      painter: _CapturePainter(
                        widget.image,
                        document,
                        _pending,
                        showHandles: _tool == CaptureTool.select,
                        hiddenIndex: _editingText,
                      ),
                    ),
                  ),
                ),
              ),
              if (selection == null)
                Positioned(
                  top: 28,
                  left: 24,
                  right: 24,
                  child: Center(
                    child: _panel(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 10, right: 12),
                            child: Icon(LucideIcons.scan, size: 20, color: ink),
                          ),
                          const Flexible(
                            child: Text(
                              '拖动鼠标框选区域 · Esc 取消',
                              style: TextStyle(color: ink, fontSize: 13),
                            ),
                          ),
                          _button(
                            '取消截图',
                            LucideIcons.x,
                            widget.onCancel,
                            color: danger,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (local != null)
                Positioned(
                  left: local.left.clamp(4.0, math.max(4.0, _view.width - 134)),
                  top: local.top >= 28 ? local.top - 26 : local.top + 7,
                  child: IgnorePointer(
                    child: Container(
                      key: const ValueKey('capture-dimensions'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC17233A),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${selection!.right.ceil() - selection.left.floor()} × ${selection.bottom.ceil() - selection.top.floor()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_textAnchor != null) _inlineText(),
              if (local != null && _origin == null) ...[
                Positioned(
                  left: left.toDouble(),
                  top: top.toDouble(),
                  width: toolbarWidth,
                  child: _toolbar(),
                ),
                if (hasOptions)
                  Positioned(
                    left: optionsLeft.toDouble(),
                    top: top + mainHeight + 6,
                    width: optionsWidth,
                    child: _options(),
                  ),
                if (_error != null)
                  Positioned(
                    left: left.toDouble(),
                    top: math.max(8, top - 44),
                    width: toolbarWidth,
                    child: _panel(
                      Text(
                        _error!,
                        style: const TextStyle(color: danger, fontSize: 12),
                      ),
                    ),
                  ),
              ],
              if (_busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _inlineText() {
    final anchor = _local(_textAnchor!);
    final selection = _localRect(document.selection!);
    final maxBodyWidth = math.max(1.0, selection.right - anchor.dx);
    final style = _draftText().textStyle.copyWith(fontSize: _fontSize);
    final painter =
        TextPainter(
          text: TextSpan(
            text: _text.text.isEmpty ? ' ' : _text.text,
            style: style,
          ),
          textDirection: TextDirection.ltr,
        )..layout(
          maxWidth: math.min(
            _textWidth == null ? maxBodyWidth : _textWidth! / _scale,
            maxBodyWidth,
          ),
        );
    final bodyWidth = math.min(
      maxBodyWidth,
      _textWidth == null
          ? math.max(44.0, painter.width + 4)
          : _textWidth! / _scale,
    );
    painter.layout(maxWidth: bodyWidth);
    final bodyHeight = math.min(
      math.max(_fontSize * 1.3, painter.height),
      math.max(1.0, selection.bottom - anchor.dy),
    );
    painter.dispose();
    final frameWidth = bodyWidth + 12;
    final frameHeight = bodyHeight + 12;
    void move(DragUpdateDetails details) {
      final bounds = document.selection!;
      setState(() {
        _textAnchor = Offset(
          (_textAnchor!.dx + details.delta.dx * _scale).clamp(
            bounds.left,
            math.max(bounds.left, bounds.right - bodyWidth * _scale),
          ),
          (_textAnchor!.dy +
                  details.delta.dy * widget.image.height / _view.height)
              .clamp(
                bounds.top,
                math.max(bounds.top, bounds.bottom - bodyHeight * _scale),
              ),
        );
      });
    }

    void resize(DragUpdateDetails details) {
      setState(
        () => _textWidth = ((bodyWidth + details.delta.dx) * _scale).clamp(
          math.min(24 * _scale, maxBodyWidth * _scale),
          maxBodyWidth * _scale,
        ),
      );
    }

    return Positioned(
      left: anchor.dx - 6,
      top: anchor.dy - 6,
      width: frameWidth,
      height: frameHeight,
      child: CustomPaint(
        key: const ValueKey('capture-text-frame'),
        foregroundPainter: const _TextFramePainter(),
        child: Stack(
          children: [
            Positioned(
              left: 6,
              top: 6,
              width: bodyWidth,
              height: bodyHeight,
              child: MediaQuery.withNoTextScaling(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): () {
                      if (!_text.value.composing.isValid ||
                          _text.value.composing.isCollapsed) {
                        _commitText();
                      }
                    },
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _cancelText,
                  },
                  child: TextField(
                    key: const ValueKey('capture-text'),
                    controller: _text,
                    focusNode: _textFocus,
                    style: style,
                    cursorColor: _color,
                    cursorWidth: 1.5,
                    minLines: 1,
                    maxLines: null,
                    maxLength: 1000,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    decoration: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    scrollPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: move,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 6,
              bottom: 0,
              width: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: move,
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: resize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(Widget child, {Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: const Color(0xFFFCFCFD),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
      ],
    ),
    child: child,
  );

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool selected = false,
    Color? color,
    Key? key,
  }) => SizedBox(
    width: 36,
    height: 36,
    child: IconButton(
      key: key ?? ValueKey('capture-$label'),
      tooltip: label,
      onPressed: _busy ? null : onPressed,
      style: IconButton.styleFrom(
        foregroundColor: selected ? blue : color ?? ink,
        disabledForegroundColor: const Color(0xFFABB2BD),
        backgroundColor: selected ? blueTint : Colors.transparent,
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      icon: Icon(icon, size: 19),
    ),
  );

  Widget _divider() => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: line,
  );

  void _undo() {
    if (_textAnchor != null) _commitText();
    setState(document.undo);
  }

  Widget _toolbar() => _panel(
    key: const ValueKey('capture-toolbar'),
    Wrap(
      spacing: 2,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final item in [
          (CaptureTool.select, '调整选区', LucideIcons.move),
          (CaptureTool.rectangle, '矩形', LucideIcons.square),
          (CaptureTool.ellipse, '椭圆', LucideIcons.circle),
          (CaptureTool.arrow, '箭头', LucideIcons.moveUpRight),
          (CaptureTool.pen, '画笔', LucideIcons.pencil),
          (CaptureTool.text, '文字', LucideIcons.type),
        ])
          _button(
            item.$2,
            item.$3,
            () => _setTool(item.$1),
            selected: _tool == item.$1,
          ),
        _divider(),
        _button(
          '撤销 Ctrl+Z',
          LucideIcons.undo2,
          document.canUndo || _textAnchor != null ? _undo : null,
        ),
        _button(
          '重做 Ctrl+Y',
          LucideIcons.redo2,
          document.undone.isEmpty ? null : () => setState(document.redo),
        ),
        _divider(),
        _button(
          '另存为 PNG',
          LucideIcons.download,
          () => _output(CaptureOutput.save),
        ),
        _button(
          '加入待发送',
          LucideIcons.forward,
          () => _output(CaptureOutput.stage),
        ),
        _button('取消截图', LucideIcons.x, widget.onCancel, color: danger),
        _button(
          '完成并复制 Ctrl+C',
          LucideIcons.check,
          () => _output(CaptureOutput.copy),
          color: green,
          key: const ValueKey('capture-copy'),
        ),
      ],
    ),
  );

  void _keepTextFocus() {
    if (_textAnchor != null) _textFocus.requestFocus();
  }

  Widget _option(
    String label,
    Widget child,
    bool selected,
    VoidCallback action,
  ) => SizedBox(
    width: 30,
    height: 30,
    child: IconButton(
      tooltip: label,
      onPressed: () {
        action();
        _keepTextFocus();
      },
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(5),
        minimumSize: const Size(30, 30),
        backgroundColor: selected ? blueTint : Colors.transparent,
        foregroundColor: selected ? blue : muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: child,
    ),
  );

  Widget _options() => _panel(
    key: const ValueKey('capture-options'),
    Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_tool == CaptureTool.text)
          for (final value in [(16.0, '小号文字'), (22.0, '中号文字'), (32.0, '大号文字')])
            _option(
              value.$2,
              Icon(
                LucideIcons.type,
                size: value.$1 == 16
                    ? 14
                    : value.$1 == 22
                    ? 18
                    : 22,
              ),
              _fontSize == value.$1,
              () => setState(() => _fontSize = value.$1),
            )
        else
          for (final width in [2.0, 4.0, 7.0])
            _option(
              '线宽 ${width.toInt()}',
              Center(
                child: Container(
                  width: width + 2,
                  height: width + 2,
                  decoration: const BoxDecoration(
                    color: ink,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              _stroke == width,
              () => setState(() => _stroke = width),
            ),
        const SizedBox(width: 2),
        for (final value in const [
          (Color(0xFFF04452), '红色'),
          (Color(0xFFFFCD45), '黄色'),
          (Color(0xFF34D399), '绿色'),
          (Color(0xFF54A5FF), '蓝色'),
          (Colors.white, '白色'),
          (Colors.black, '黑色'),
        ])
          _option(
            value.$2,
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value.$1,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: _color == value.$1 ? blue : line,
                  width: _color == value.$1 ? 2 : 1,
                ),
              ),
            ),
            _color == value.$1,
            () => setState(() => _color = value.$1),
          ),
      ],
    ),
  );
}

class _TextFramePainter extends CustomPainter {
  const _TextFramePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = const Color(0xFF6F7783)
      ..strokeWidth = 1;
    final rect = Rect.fromLTWH(
      3,
      3,
      math.max(0, size.width - 6),
      math.max(0, size.height - 6),
    );
    for (double x = rect.left; x < rect.right; x += 7) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(math.min(x + 4, rect.right), rect.top),
        border,
      );
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(math.min(x + 4, rect.right), rect.bottom),
        border,
      );
    }
    for (double y = rect.top; y < rect.bottom; y += 7) {
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.left, math.min(y + 4, rect.bottom)),
        border,
      );
      canvas.drawLine(
        Offset(rect.right, y),
        Offset(rect.right, math.min(y + 4, rect.bottom)),
        border,
      );
    }
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(point, 3, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3, border..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TextFramePainter oldDelegate) => false;
}

class _CapturePainter extends CustomPainter {
  _CapturePainter(
    this.image,
    this.document,
    this.pending, {
    required this.showHandles,
    this.hiddenIndex,
  });
  final ui.Image image;
  final AnnotationDocument document;
  final CaptureMark? pending;
  final bool showHandles;
  final int? hiddenIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / image.width;
    final scaleY = size.height / image.height;
    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawImage(image, Offset.zero, Paint());
    document.paintMarks(canvas, pending: pending, hiddenIndex: hiddenIndex);
    final bounds = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final selection = document.selection;
    final dim = Path()..addRect(bounds);
    if (selection != null) dim.addRect(selection);
    dim.fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: .52));
    if (selection != null) {
      canvas.drawRect(
        selection,
        Paint()
          ..color = const Color(0xFF65A5FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scaleX,
      );
      if (showHandles) {
        for (final point in [
          selection.topLeft,
          selection.topCenter,
          selection.topRight,
          selection.centerRight,
          selection.bottomRight,
          selection.bottomCenter,
          selection.bottomLeft,
          selection.centerLeft,
        ]) {
          canvas.drawRect(
            Rect.fromCenter(
              center: point,
              width: 7 / scaleX,
              height: 7 / scaleY,
            ),
            Paint()..color = Colors.white,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CapturePainter oldDelegate) => true;
}
