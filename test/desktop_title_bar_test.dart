import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/ui/desktop_title_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  var maximized = false;

  setUp(() {
    calls = [];
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'isFullScreen':
              return false;
            case 'maximize':
              maximized = true;
            case 'unmaximize':
              maximized = false;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Future<void> showTitleBar(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DesktopTitleBar(
                leadingWidth: 218,
                compactBrand: false,
                actions: [],
                child: Row(children: [Text('文件传输')]),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'caption commands minimize, maximize, restore and request graceful close',
    (tester) async {
      await showTitleBar(tester);
      await tester.tap(find.byTooltip('最小化'));
      await tester.pumpAndSettle();
      expect(calls, contains('minimize'));
      await tester.tap(find.byTooltip('最大化'));
      await tester.pumpAndSettle();
      expect(calls, contains('maximize'));
      expect(find.byTooltip('还原'), findsOneWidget);
      await tester.tap(find.byTooltip('还原'));
      await tester.pumpAndSettle();
      expect(calls, contains('unmaximize'));
      expect(find.byTooltip('最大化'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(calls, contains('close'));
      expect(calls, isNot(contains('destroy')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'title area drags and double-clicks without turning the tools into drag regions',
    (tester) async {
      await showTitleBar(tester);
      final dragArea = find.byKey(const ValueKey('title-drag-region'));
      await tester.drag(dragArea, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(calls, contains('startDragging'));
      calls.clear();
      await tester.tap(dragArea);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(dragArea);
      await tester.pumpAndSettle();
      expect(calls, contains('maximize'));
      calls.clear();
      await tester.tap(find.byTooltip('最小化'));
      await tester.pumpAndSettle();
      expect(calls, contains('minimize'));
      expect(calls, isNot(contains('startDragging')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('native maximize events update the restore button', (
    tester,
  ) async {
    await showTitleBar(tester);
    tester.binding.channelBuffers.push(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onEvent', {'eventName': 'maximize'}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('还原'), findsOneWidget);
    tester.binding.channelBuffers.push(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onEvent', {'eventName': 'unmaximize'}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('最大化'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
