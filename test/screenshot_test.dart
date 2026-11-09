import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/screenshot/annotation_document.dart';
import 'package:mutual_transfer/screenshot/screenshot_controller.dart';
import 'package:mutual_transfer/screenshot/screenshot_editor.dart';
import 'package:mutual_transfer/screenshot/screenshot_host.dart';
import 'package:mutual_transfer/screenshot/screenshot_settings.dart';
import 'package:mutual_transfer/ui/app_theme.dart';

Future<ui.Image> sampleImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!Platform.isWindows) return;
    for (final font in {
      'Microsoft YaHei UI': r'C:\Windows\Fonts\msyh.ttc',
      'Segoe UI': r'C:\Windows\Fonts\segoeui.ttf',
    }.entries) {
      await (FontLoader(
            font.key,
          )..addFont(File(font.value).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
  });

  test('editing and deleting text preserve layers and undo history', () {
    CaptureMark mark(String text) => CaptureMark(
      tool: CaptureTool.text,
      color: Colors.red,
      width: 2,
      points: [const Offset(20, 30)],
      text: text,
    );
    final document = AnnotationDocument();
    final original = mark('原文');
    final edited = mark('修改');
    final top = mark('上层');
    document.add(original);
    document.add(top);
    document.replace(0, edited);
    expect(document.marks, [edited, top]);
    document.undo();
    expect(document.marks, [original, top]);
    document.redo();
    expect(document.marks, [edited, top]);
    document.replace(0, null);
    expect(document.marks, [top]);
    document.undo();
    expect(document.marks, [edited, top]);
  });

  test(
    'crop exports source pixels and marks without editor mask; undo/redo is reversible',
    () async {
      final image = await sampleImage(100, 80);
      final document = AnnotationDocument()
        ..selection = const Rect.fromLTWH(40, 10, 30, 20);
      final mark = CaptureMark(
        tool: CaptureTool.rectangle,
        color: Colors.red,
        width: 2,
        points: [const Offset(52, 12), const Offset(65, 25)],
      );
      document.add(mark);
      document.undo();
      expect(document.marks, isEmpty);
      document.redo();
      expect(document.marks.single, same(mark));
      final png = await document.exportPng(image);
      final codec = await ui.instantiateImageCodec(png);
      final output = (await codec.getNextFrame()).image;
      expect(output.width, 30);
      expect(output.height, 20);
      final rgba = (await output.toByteData())!;
      // Unannotated white remains white: no dark mask, blue selection or toolbar.
      final whitePixel = (18 * output.width + 28) * 4;
      expect(rgba.getUint8(whitePixel), 255);
      expect(rgba.getUint8(whitePixel + 1), 255);
      expect(rgba.getUint8(whitePixel + 2), 255);
      final redPixel = (8 * output.width + 12) * 4;
      expect(rgba.getUint8(redPixel), greaterThan(200));
      expect(rgba.getUint8(redPixel + 1), lessThan(100));
      document.undo();
      document.add(
        CaptureMark(
          tool: CaptureTool.pen,
          color: Colors.black,
          width: 2,
          points: [const Offset(55, 15)],
        ),
      );
      expect(document.undone, isEmpty);
      output.dispose();
      codec.dispose();
      image.dispose();
    },
  );

  test(
    'export clips reversed drag result to image bounds and rejects empty crop',
    () async {
      final image = await sampleImage(100, 80);
      final document = AnnotationDocument()
        ..selection = const Rect.fromLTRB(-20, -10, 110, 90);
      final codec = await ui.instantiateImageCodec(
        await document.exportPng(image),
      );
      final output = (await codec.getNextFrame()).image;
      expect(output.width, 100);
      expect(output.height, 80);
      document.selection = Rect.zero;
      await expectLater(document.exportPng(image), throwsFormatException);
      output.dispose();
      codec.dispose();
      image.dispose();
    },
  );

  test(
    'hotkey conflict preserves active binding and persisted settings',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'nearlink-capture-test-',
      );
      final calls = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScreenshotController.channel, (call) async {
            if (call.method == 'registerHotkey') {
              final args = call.arguments as Map;
              calls.add(args);
              if (args['key'] == 66) {
                throw PlatformException(
                  code: 'hotkey_conflict',
                  message: '快捷键已被占用',
                );
              }
            }
            return null;
          });
      final controller = ScreenshotController(directory);
      try {
        await controller.initialize();
        await controller.updateHotkey(
          const CaptureHotkey(key: 67),
          enable: true,
        );
        final before = File(
          '${directory.path}/screenshot.json',
        ).readAsStringSync();
        await expectLater(
          controller.updateHotkey(const CaptureHotkey(key: 66), enable: true),
          throwsA(isA<PlatformException>()),
        );
        expect(controller.hotkey.key, 67);
        expect(controller.registered, isTrue);
        expect(
          File('${directory.path}/screenshot.json').readAsStringSync(),
          before,
        );
        expect(controller.hotkeyError, contains('占用'));
        await controller.updateHotkey(controller.hotkey, enable: false);
        expect(controller.registered, isFalse);
        expect(calls.last['key'], 0);
        final restored = ScreenshotController(directory);
        await restored.initialize();
        expect(restored.hotkey.key, 67);
        expect(restored.enabled, isFalse);
        restored.dispose();
      } finally {
        controller.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotController.channel, null);
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'capture visibility is persisted alongside hotkeys and defaults for old settings',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'nearlink-capture-visibility-',
      );
      final file = File('${directory.path}/screenshot.json');
      await file.writeAsString(
        jsonEncode({'modifiers': 3, 'key': 67, 'enabled': false}),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            ScreenshotController.channel,
            (_) async => null,
          );
      final controller = ScreenshotController(directory);
      ScreenshotController? restored;
      try {
        await controller.initialize();
        expect(controller.hideWindowOnCapture, isTrue);
        await controller.updateHideWindowOnCapture(false);
        expect(controller.enabled, isFalse);
        expect(controller.hotkey.key, 67);
        await controller.updateHotkey(
          const CaptureHotkey(key: 68),
          enable: true,
        );
        restored = ScreenshotController(directory);
        await restored.initialize();
        expect(restored.hideWindowOnCapture, isFalse);
        expect(restored.hotkey.key, 68);
        expect(restored.enabled, isTrue);
        await restored.updateHideWindowOnCapture(true);
        expect(
          (jsonDecode(await file.readAsString()) as Map)['hideWindowOnCapture'],
          isTrue,
        );
      } finally {
        controller.dispose();
        restored?.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotController.channel, null);
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'a capture visibility save failure retains the active preference',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'nearlink-capture-save-failure-',
      );
      final blocker = File('${directory.path}/not-a-directory')
        ..writeAsStringSync('test');
      final controller = ScreenshotController(Directory(blocker.path));
      try {
        await expectLater(
          controller.updateHideWindowOnCapture(false),
          throwsA(isA<FileSystemException>()),
        );
        expect(controller.hideWindowOnCapture, isTrue);
        expect(controller.updating, isFalse);
        expect(controller.captureSettingsError, contains('无法保存截图设置'));
      } finally {
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  testWidgets('capture visibility switch saves and updates its state', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'nearlink-capture-switch-',
    );
    final controller = ScreenshotController(directory)..ready = true;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: nearLinkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenshotSettings(controller: controller),
            ),
          ),
        ),
      );
      final toggle = find.byKey(const ValueKey('capture-hide-window'));
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.ensureVisible(toggle);
      await tester.runAsync(() async {
        await tester.tap(toggle);
        for (var i = 0; controller.updating && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(controller.hideWindowOnCapture, isFalse);
      await tester.pumpWidget(const SizedBox());
    } finally {
      controller.dispose();
      directory.deleteSync(recursive: true);
    }
  });

  for (final enabled in [true, false]) {
    testWidgets(
      'inline hotkey recorder saves on release and preserves enabled=$enabled',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'nearlink-inline-hotkey-',
        );
        final registrations = <Object?>[];
        final recordingStates = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotController.channel, (
              call,
            ) async {
              if (call.method == 'registerHotkey') {
                registrations.add(call.arguments);
              } else if (call.method == 'setHotkeyRecording') {
                recordingStates.add(call.arguments);
              }
              return null;
            });
        final controller = ScreenshotController(directory);
        var captures = 0;
        try {
          await tester.runAsync(() async {
            await controller.initialize();
            await controller.updateHotkey(controller.hotkey, enable: enabled);
          });
          controller.onCapture = () async {
            captures++;
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: nearLinkTheme(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ScreenshotSettings(controller: controller),
                ),
              ),
            ),
          );
          expect(find.text('修改快捷键'), findsNothing);
          expect(find.text('快捷键已生效'), findsNothing);
          expect(find.textContaining('框选后可添加'), findsNothing);
          expect(find.textContaining('截图中：'), findsNothing);
          final field = find.byKey(const ValueKey('capture-hotkey-field'));
          await tester.tap(field);
          await tester.pump();
          expect(find.text('按下组合键'), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(controller.recordingHotkey, isTrue);
          await controller.capture();
          expect(captures, 0);
          final before = registrations.length;
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(find.text('Ctrl'), findsOneWidget);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          await tester.pump();
          expect(find.text('Ctrl + Alt'), findsOneWidget);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
          await tester.pump();
          expect(find.text('Ctrl + Alt + K'), findsOneWidget);
          expect(registrations.length, before);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
          await tester.pump();
          expect(find.text('Ctrl + Alt + K'), findsOneWidget);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          expect(registrations.length, before);
          await tester.runAsync(() async {
            await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
            for (var i = 0; controller.updating && i < 100; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pump();
          await tester.pump();
          expect(controller.hotkey.key, 75);
          expect(controller.enabled, enabled);
          expect(controller.recordingHotkey, isFalse);
          expect(recordingStates, [true, false]);
          expect(find.text('Ctrl + Alt + K'), findsOneWidget);
          final saved =
              jsonDecode(
                    File(
                      '${directory.path}/screenshot.json',
                    ).readAsStringSync(),
                  )
                  as Map;
          expect(saved['key'], 75);
          expect(saved['enabled'], enabled);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(ScreenshotController.channel, null);
          directory.deleteSync(recursive: true);
        }
      },
    );
  }

  testWidgets(
    'hotkey preview shows partial and invalid chords without resizing',
    (tester) async {
      final controller = ScreenshotController(Directory.systemTemp)
        ..ready = true;
      final captureKey = GlobalKey();
      final recordingStates = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScreenshotController.channel, (call) async {
            if (call.method == 'setHotkeyRecording') {
              recordingStates.add(call.arguments);
            }
            return null;
          });
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              theme: nearLinkTheme(),
              home: Scaffold(body: ScreenshotSettings(controller: controller)),
            ),
          ),
        );
        final field = find.byKey(const ValueKey('capture-hotkey-field'));
        final fieldSize = tester.getSize(field);
        await tester.tap(field);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(find.text('Shift'), findsOneWidget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
        await tester.pump();
        expect(find.text('Shift + K'), findsOneWidget);
        expect(find.textContaining('请使用 Ctrl 或 Alt'), findsOneWidget);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(find.text('Shift + K'), findsOneWidget);
        expect(controller.hotkey.label, 'Ctrl + Alt + A');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(find.text('Ctrl'), findsOneWidget);
        expect(find.textContaining('请使用 Ctrl 或 Alt'), findsNothing);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(find.text('Ctrl + Alt + Shift'), findsOneWidget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
        await tester.pump();
        expect(find.text('Ctrl + Alt + Shift + F12'), findsOneWidget);
        expect(tester.getSize(field), fieldSize);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          await tester.runAsync(() async {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final rendered = await boundary.toImage();
            final bytes = (await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
            final file = File('outputs/hotkey-live-preview.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes);
            rendered.dispose();
          });
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(controller.recordingHotkey, isFalse);
        expect(controller.onRecordedHotkey, isNull);
        expect(find.text('Ctrl + Alt + A'), findsOneWidget);

        await tester.tap(field);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(find.text('Ctrl'), findsOneWidget);
        await tester.tapAt(const Offset(700, 500));
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(controller.recordingHotkey, isFalse);
        expect(controller.onRecordedHotkey, isNull);
        expect(controller.hotkey.label, 'Ctrl + Alt + A');
        await tester.tap(field);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(controller.recordingHotkey, isFalse);
        expect(recordingStates, [true, false, true, false, true, false]);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotController.channel, null);
      }
    },
  );

  for (final delayed in [false, true]) {
    testWidgets(
      'the registered hotkey is previewed instead of capturing; delayed=$delayed',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'nearlink-hotkey-echo-',
        );
        final controller = ScreenshotController(directory);
        var captures = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              ScreenshotController.channel,
              (_) async => null,
            );
        try {
          await tester.runAsync(() async {
            await controller.initialize();
            await controller.updateHotkey(
              const CaptureHotkey(modifiers: 1),
              enable: true,
            );
          });
          controller.onCapture = () async {
            captures++;
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: nearLinkTheme(),
              home: Scaffold(body: ScreenshotSettings(controller: controller)),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('capture-hotkey-field')));
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          await tester.pump();
          expect(find.text('Alt'), findsOneWidget);
          if (delayed) {
            await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          }
          await tester.runAsync(() async {
            tester.binding.channelBuffers.push(
              ScreenshotController.channel.name,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('captureRequested'),
              ),
              (_) {},
            );
            for (var i = 0; controller.updating && i < 100; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pump();
          expect(find.text('Alt + A'), findsOneWidget);
          expect(captures, 0);
          if (!delayed) {
            expect(controller.recordingHotkey, isTrue);
            await tester.runAsync(() async {
              await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
              for (var i = 0; controller.updating && i < 100; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
            });
          }
          await tester.pump();
          await tester.pump();
          expect(controller.recordingHotkey, isFalse);
          expect(controller.onRecordedHotkey, isNull);
          expect(controller.hotkey.label, 'Alt + A');
          expect(controller.registered, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(ScreenshotController.channel, null);
          directory.deleteSync(recursive: true);
        }
      },
    );
  }

  testWidgets(
    'inline hotkey conflicts keep the old binding and Escape ends recording',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'nearlink-inline-conflict-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScreenshotController.channel, (call) async {
            if (call.method == 'registerHotkey' &&
                (call.arguments as Map)['key'] == 66) {
              throw PlatformException(
                code: 'hotkey_conflict',
                message: '快捷键已被占用',
              );
            }
            return null;
          });
      final controller = ScreenshotController(directory);
      try {
        await tester.runAsync(() async {
          await controller.initialize();
          await controller.updateHotkey(controller.hotkey, enable: true);
        });
        final file = File('${directory.path}/screenshot.json');
        final before = file.readAsStringSync();
        await tester.pumpWidget(
          MaterialApp(
            theme: nearLinkTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenshotSettings(controller: controller),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('capture-hotkey-field')));
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pump();
        expect(controller.hotkey.key, 65);
        expect(controller.registered, isTrue);
        expect(file.readAsStringSync(), before);
        expect(find.text('快捷键已被占用'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(controller.recordingHotkey, isFalse);
        expect(find.text('Ctrl + Alt + A'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotController.channel, null);
        directory.deleteSync(recursive: true);
      }
    },
  );

  for (final hideWindow in [true, false]) {
    testWidgets(
      'capture host passes hideWindow=$hideWindow and Escape restores window',
      (tester) async {
        final image = (await tester.runAsync(() => sampleImage(800, 600)))!;
        final png = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        ))!.buffer.asUint8List();
        image.dispose();
        final calls = <String>[];
        Object? captureArgument;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotController.channel, (
              call,
            ) async {
              calls.add(call.method);
              if (call.method == 'beginCapture') {
                captureArgument = call.arguments;
              }
              return call.method == 'captureDesktop' ? png : null;
            });
        final controller = ScreenshotController(Directory.systemTemp)
          ..ready = true
          ..hideWindowOnCapture = hideWindow;
        await tester.pumpWidget(
          MaterialApp(
            theme: nearLinkTheme(),
            builder: (context, child) =>
                ScreenshotHost(controller: controller, child: child!),
            home: const Scaffold(body: TextField(autofocus: true)),
          ),
        );
        await tester.pump();
        final capture = controller.capture();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump();
        await tester.pump();
        expect(find.text('拖动鼠标框选区域 · Esc 取消'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(calls, contains('showOverlay'));
        expect(captureArgument, hideWindow);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        await capture;
        expect(calls.last, 'restoreWindow');
        expect(controller.capturing, isFalse);
        expect(find.byType(ScreenshotEditor), findsNothing);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotController.channel, null);
      },
    );
  }

  for (final size in [
    const Size(1280, 800),
    const Size(520, 720),
    const Size(440, 720),
  ]) {
    testWidgets('select, annotate, undo and copy at ${size.width} width', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final image = (await tester.runAsync(
        () => sampleImage(size.width.toInt(), size.height.toInt()),
      ))!;
      Uint8List? copied;
      var cancelled = false;
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            theme: nearLinkTheme(),
            home: ScreenshotEditor(
              image: image,
              onCancel: () => cancelled = true,
              onOutput: (action, bytes) async {
                expect(action, CaptureOutput.copy);
                copied = bytes;
              },
            ),
          ),
        ),
      );
      final canvas = find.byKey(const ValueKey('capture-canvas'));
      final gesture = await tester.startGesture(const Offset(50, 70));
      await gesture.moveTo(const Offset(350, 290));
      await tester.pump();
      expect(find.text('300 × 220'), findsOneWidget);
      final dimensions = tester.getRect(
        find.byKey(const ValueKey('capture-dimensions')),
      );
      expect(dimensions.left, 50);
      expect(dimensions.bottom, lessThan(70));
      await gesture.up();
      await tester.pump();
      expect(find.text('300 × 220'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('capture-矩形')));
      await tester.pump();
      final draw = await tester.startGesture(const Offset(100, 120));
      await draw.moveTo(const Offset(250, 200));
      await draw.up();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('capture-撤销 Ctrl+Z')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('capture-重做 Ctrl+Y')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('capture-文字')));
      await tester.pump();
      await tester.tapAt(const Offset(130, 150));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('capture-text')),
        '中文批注',
      );
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('capture-text'))),
        const Offset(130, 150),
      );
      expect(find.byKey(const ValueKey('capture-text-frame')), findsOneWidget);
      await tester.tap(find.byTooltip('大号文字'));
      await tester.pump();
      await tester.tap(find.byTooltip('蓝色'));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('capture-text')),
      );
      expect(field.style!.fontSize, 32);
      expect(field.style!.color, const Color(0xFF54A5FF));
      final originalTextFrame = tester.getSize(
        find.byKey(const ValueKey('capture-text-frame')),
      );
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(
        editable
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
            )
            .length,
        1,
        reason: 'All four Chinese characters must remain on one visible line',
      );
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('capture-toolbar')),
      );
      final options = tester.getRect(
        find.byKey(const ValueKey('capture-options')),
      );
      expect(options.top, greaterThanOrEqualTo(toolbar.bottom));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('capture-toolbar')),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.pump(const Duration(milliseconds: 700));
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final rendered = await boundary.toImage();
          final bytes = (await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          final file = File(
            'outputs/screenshot-inline-${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          rendered.dispose();
        });
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byKey(const ValueKey('capture-text')), findsNothing);
      await tester.tapAt(const Offset(140, 160));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('capture-text-frame'))),
        originalTextFrame,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('capture-text')))
            .controller!
            .text,
        '中文批注',
      );
      await tester.enterText(
        find.byKey(const ValueKey('capture-text')),
        '修改内容',
      );
      await tester.tapAt(const Offset(320, 260));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('capture-撤销 Ctrl+Z')));
      await tester.pump();
      await tester.tapAt(const Offset(140, 160));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('capture-text')))
            .controller!
            .text,
        '中文批注',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, isFalse);
      expect(canvas, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('capture-copy')));
        await tester.pump();
        // Wait for the real raster encoder without blocking fake widget time.
        for (var i = 0; copied == null && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(copied, isNotNull);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, isTrue);
      await tester.pumpWidget(const SizedBox());
      image.dispose();
    });
  }
}
