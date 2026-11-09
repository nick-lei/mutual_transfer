import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_transfer/android/android_host.dart';

import 'ui_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nearlink/android-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('launch notification waits until the workspace is ready', () async {
    final service = UiFixtureService(populated: false);
    final calls = <(String, String)>[];
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'paths' => {'backgroundEnabled': false},
        'ready' => [],
        'initializeNotifications' => [
          {'id': 'chat:laptop', 'action': 'open'},
        ],
        _ => null,
      },
    );
    final host = AndroidHost(service, channel: channel);
    await host.initialize();
    final platform = AndroidNotificationPlatform(host);
    await platform.initialize((id, action) => calls.add((id, action)));
    expect(calls, isEmpty);
    await host.ready();
    expect(calls, [('chat:laptop', 'open')]);
    await host.ready();
    expect(calls, hasLength(1));
    await host.close();
    await service.close();
  });

  test(
    'denied notification permission does not enable the foreground service',
    () async {
      final service = UiFixtureService(populated: false);
      var granted = false;
      final changes = <bool>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'paths') return {'backgroundEnabled': false};
        if (call.method == 'requestNotifications') return granted;
        if (call.method == 'setBackground') {
          changes.add((call.arguments as Map)['enabled'] as bool);
        }
        return null;
      });
      final host = AndroidHost(service, channel: channel);
      await host.initialize();
      await host.setBackground(true);
      expect(host.backgroundEnabled, isFalse);
      expect(host.error, contains('允许邻传通知'));
      expect(changes, isEmpty);
      granted = true;
      await host.setBackground(true);
      expect(host.backgroundEnabled, isTrue);
      expect(host.error, isNull);
      await host.setBackground(false);
      expect(changes, [true, false]);
      await host.close();
      await service.close();
    },
  );
}
