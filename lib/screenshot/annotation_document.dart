import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum CaptureTool { select, rectangle, ellipse, arrow, pen, text }

class CaptureMark {
  CaptureMark({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    this.text = '',
    this.fontSize = 22,
    this.textWidth = 300,
    this.autoTextWidth = true,
  });
  final CaptureTool tool;
  final Color color;
  final double width;
  final List<Offset> points;
  final String text;
  final double fontSize;
  final double textWidth;
  final bool autoTextWidth;

  TextStyle get textStyle => TextStyle(
    inherit: false,
    textBaseline: TextBaseline.alphabetic,
    fontFamily: 'Microsoft YaHei UI',
    fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI'],
    color: color,
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    wordSpacing: 0,
    height: 1.3,
  );

  TextPainter textPainter() => TextPainter(
    text: TextSpan(text: text, style: textStyle),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1, textWidth));

  Rect get textBounds {
    final painter = textPainter();
    final bounds =
        points.first & Size(math.max(12, painter.width), painter.height);
    painter.dispose();
    return bounds;
  }

  void paint(Canvas canvas) {
    if (points.isEmpty) return;
    final brush = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final first = points.first;
    final last = points.last;
    final bounds = Rect.fromPoints(first, last);
    switch (tool) {
      case CaptureTool.rectangle:
        canvas.drawRect(bounds, brush);
      case CaptureTool.ellipse:
        canvas.drawOval(bounds, brush);
      case CaptureTool.arrow:
        canvas.drawLine(first, last, brush);
        final angle = math.atan2(last.dy - first.dy, last.dx - first.dx);
        final length = math.min((last - first).distance / 2, width * 4 + 8);
        for (final delta in [-.5, .5]) {
          canvas.drawLine(
            last,
            last -
                Offset(math.cos(angle + delta), math.sin(angle + delta)) *
                    length,
            brush,
          );
        }
      case CaptureTool.pen:
        if (points.length == 1) {
          canvas.drawCircle(
            first,
            width / 2,
            brush..style = PaintingStyle.fill,
          );
        } else {
          final path = Path()..moveTo(first.dx, first.dy);
          for (final point in points.skip(1)) {
            path.lineTo(point.dx, point.dy);
          }
          canvas.drawPath(path, brush);
        }
      case CaptureTool.text:
        final painter = textPainter();
        painter.paint(canvas, first);
        painter.dispose();
      case CaptureTool.select:
        break;
    }
  }
}

class AnnotationDocument {
  Rect? selection;
  final List<CaptureMark> marks = [];
  final List<List<CaptureMark>> _history = [];
  final List<List<CaptureMark>> undone = [];
  bool get canUndo => _history.isNotEmpty;

  void add(CaptureMark mark) {
    _history.add(List.of(marks));
    marks.add(mark);
    undone.clear();
  }

  void undo() {
    if (_history.isEmpty) return;
    undone.add(List.of(marks));
    marks
      ..clear()
      ..addAll(_history.removeLast());
  }

  void redo() {
    if (undone.isEmpty) return;
    _history.add(List.of(marks));
    marks
      ..clear()
      ..addAll(undone.removeLast());
  }

  void replace(int index, CaptureMark? mark) {
    final old = marks[index];
    if (mark != null &&
        old.text == mark.text &&
        old.points.first == mark.points.first &&
        old.fontSize == mark.fontSize &&
        old.color == mark.color &&
        old.textWidth == mark.textWidth &&
        old.autoTextWidth == mark.autoTextWidth) {
      return;
    }
    _history.add(List.of(marks));
    if (mark == null) {
      marks.removeAt(index);
    } else {
      marks[index] = mark;
    }
    undone.clear();
  }

  void reset() {
    selection = null;
    marks.clear();
    _history.clear();
    undone.clear();
  }

  void paintMarks(Canvas canvas, {CaptureMark? pending, int? hiddenIndex}) {
    if (selection == null) return;
    canvas.save();
    canvas.clipRect(selection!);
    for (var i = 0; i < marks.length; i++) {
      if (i != hiddenIndex) marks[i].paint(canvas);
    }
    pending?.paint(canvas);
    canvas.restore();
  }

  // Export only source pixels and committed marks; no editor widgets or mask.
  Future<Uint8List> exportPng(ui.Image image) async {
    final selected = selection?.intersect(
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    );
    if (selected == null || selected.width < 2 || selected.height < 2) {
      throw const FormatException('请先框选截图区域');
    }
    final left = selected.left.floor();
    final top = selected.top.floor();
    final width = selected.right.ceil() - left;
    final height = selected.bottom.ceil() - top;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-left.toDouble(), -top.toDouble());
    canvas.drawImage(image, Offset.zero, Paint());
    paintMarks(canvas);
    final picture = recorder.endRecording();
    final output = await picture.toImage(width, height);
    try {
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw const FormatException('截图编码失败，请重试');
      return bytes.buffer.asUint8List();
    } finally {
      output.dispose();
      picture.dispose();
    }
  }
}
