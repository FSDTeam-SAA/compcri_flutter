import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';
import 'api_client.dart';
import 'store.dart';

/// Delivery of the backend's reminders and invitations to the device.
///
/// The in-app inbox works without any of this, so every call here is optional:
/// [start] is a no-op until [enable] has reported a live Firebase app, which
/// keeps widget tests — and any build without the Firebase config files — on
/// the pure-HTTP path.
class PushMessaging {
  PushMessaging._();

  static final PushMessaging instance = PushMessaging._();

  bool _available = false;
  String? _registered;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;

  /// Boots Firebase. Returns false when the platform has no configuration, so
  /// the app keeps running rather than failing to start.
  Future<bool> enable() async {
    if (_available) return true;
    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// Hands the device's FCM token to the API and keeps it current. Safe to
  /// call on every sign-in; the backend treats a repeat token as one device.
  Future<void> start(AppStore store) async {
    if (!_available) return;
    final messaging = FirebaseMessaging.instance;
    try {
      // iOS shows the system prompt here; Android 13+ needs it as well.
      await messaging.requestPermission();
      final token = await messaging.getToken();
      await _send(store.api, token);

      // A token can rotate at any time — an app restore, a reinstall, or when
      // Firebase decides to. A stale token silently stops delivering.
      _refresh ??= messaging.onTokenRefresh.listen(
        (value) => _send(store.api, value),
      );

      // A notification that arrives while the app is open is not shown by the
      // system, so the inbox is what the user sees; keep it in step.
      _foreground ??= FirebaseMessaging.onMessage.listen(
        (_) => unawaited(_reload(store)),
      );
    } catch (_) {
      // Push is a convenience; never block sign-in on it.
    }
  }

  /// Drops the token server-side so a signed-out phone stops receiving another
  /// person's reminders. Called while the session is still valid.
  Future<void> stop(Api api) async {
    final token = _registered;
    _registered = null;
    if (!_available || token == null) return;
    try {
      await api.notifications.unregisterDevice(token);
      await FirebaseMessaging.instance.deleteToken();
    } on ApiException {
      // Signing out locally matters more than the server round trip.
    } catch (_) {}
  }

  Future<void> _send(Api api, String? token) async {
    if (token == null || token.length < 20 || token == _registered) return;
    try {
      await api.notifications.registerDevice(
        token: token,
        platform: Platform.isIOS ? 'IOS' : 'ANDROID',
      );
      _registered = token;
    } on ApiException {
      // A rejected token is retried on the next sign-in or refresh.
    }
  }

  Future<void> _reload(AppStore store) async {
    try {
      await store.loadNotifications();
    } on ApiException {
      // The next screen that opens reloads anyway.
    }
  }
}
