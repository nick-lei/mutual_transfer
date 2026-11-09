import 'dart:async';

import 'package:mutual_transfer/desktop/desktop_notifications.dart';
import 'package:mutual_transfer/lan_service.dart';
import 'package:mutual_transfer/models.dart';

class FakeNotificationPlatform implements NotificationPlatform {
  void Function(String, String)? onAction;
  bool allowed = true, fails = false, disposed = false;
  bool dismissFails = false;
  int tests = 0;
  int messageSounds = 0;
  final messageNotifications = <({String peerId, int count, bool sound})>[];
  final messageNames = <String>[];
  final messagePreviews = <String>[];
  final shown = <String>[];
  final sounds = <bool>[];
  final dismissed = <String>[];
  final completions = <({TransferCompletion completion, bool sound})>[];
  Completer<void>? showGate;

  @override
  Future<void> initialize(void Function(String, String) callback) async {
    if (fails) throw StateError('Notification service unavailable');
    onAction = callback;
  }

  @override
  Future<bool> isAllowed() async => allowed;

  @override
  Future<void> showOffer(IncomingOffer offer, {required bool sound}) async {
    shown.add(offer.id);
    sounds.add(sound);
    await showGate?.future;
  }

  @override
  Future<void> showTest({required bool sound}) async {
    tests++;
  }

  @override
  Future<void> showCompletion(
    TransferCompletion completion, {
    required bool sound,
  }) async {
    completions.add((completion: completion, sound: sound));
  }

  @override
  Future<void> showMessages(
    String peerId,
    String name,
    int count,
    String preview, {
    required bool sound,
  }) async {
    messageNotifications.add((peerId: peerId, count: count, sound: sound));
    messageNames.add(name);
    messagePreviews.add(preview);
  }

  @override
  Future<void> playMessageSound() async {
    messageSounds++;
  }

  @override
  Future<void> dismiss(String id) async {
    dismissed.add(id);
    if (dismissFails) throw StateError('Notification cleanup unavailable');
  }

  @override
  Future<void> openSettings() async {}

  @override
  void dispose() {
    disposed = true;
  }
}
