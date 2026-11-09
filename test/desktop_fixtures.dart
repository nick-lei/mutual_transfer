import 'package:mutual_transfer/desktop/desktop_controller.dart';

class FakeStartupRegistration implements StartupRegistration {
  bool enabled = false;
  bool fail = false;
  final changes = <bool>[];

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async {
    if (fail) throw StateError('Registration denied');
    changes.add(value);
    enabled = value;
  }
}
