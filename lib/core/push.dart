import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'store.dart';

/// Kept separate from Firebase so permission and token failures can be tested.
abstract class PushTransport {
  Future<AuthorizationStatus> permission({required bool request});
  Future<String?> token();
  Future<void> presentation({required bool enabled});
  Future<void> deleteToken();
  Stream<String> get tokenRefresh;
  Stream<RemoteMessage> get messages;

  /// Notifications tapped while the app was in the background.
  Stream<RemoteMessage> get opened;

  /// The notification whose tap launched the app, once.
  Future<RemoteMessage?> launchedBy();
}

class FirebasePushTransport implements PushTransport {
  FirebaseMessaging get messaging => FirebaseMessaging.instance;
  @override
  Future<AuthorizationStatus> permission({required bool request}) async =>
      (request
              ? await messaging.requestPermission()
              : await messaging.getNotificationSettings())
          .authorizationStatus;
  @override
  Future<String?> token() async {
    // iOS can grant permission before APNs has finished registering. Retrying
    // later is essential; getToken throws until the APNs token is available.
    if (Platform.isIOS && await messaging.getAPNSToken() == null) return null;
    return messaging.getToken();
  }

  @override
  Future<void> presentation({required bool enabled}) =>
      messaging.setForegroundNotificationPresentationOptions(
        alert: enabled,
        badge: enabled,
        sound: enabled,
      );
  @override
  Future<void> deleteToken() => messaging.deleteToken();
  @override
  Stream<String> get tokenRefresh => messaging.onTokenRefresh;
  @override
  Stream<RemoteMessage> get messages => FirebaseMessaging.onMessage;
  @override
  Stream<RemoteMessage> get opened => FirebaseMessaging.onMessageOpenedApp;
  @override
  Future<RemoteMessage?> launchedBy() => messaging.getInitialMessage();
}

enum PushStatus { unavailable, checking, notRequested, denied, retrying, ready }

/// Registers push tokens and presents reminders even while the app is open.
class PushMessaging extends ChangeNotifier with WidgetsBindingObserver {
  PushMessaging._() : _transport = FirebasePushTransport();
  @visibleForTesting
  PushMessaging.forTest(PushTransport transport)
    : _transport = transport,
      _available = true;

  static final PushMessaging instance = PushMessaging._();
  static const _native = MethodChannel('com.auroxday.app/notifications');
  final PushTransport _transport;
  bool _available = false, _observing = false, _starting = false;
  int _session = 0;
  String? _registered;
  AppStore? _store;
  Timer? _retry;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _openedSub;
  bool _checkedLaunch = false;
  PushStatus status = PushStatus.unavailable;

  /// Opens what a tapped notification is about. Set by the app shell; a tap
  /// that arrives before it is set, or before sign-in, waits in [_pendingOpen].
  Future<void> Function(Map<String, String> data)? _onOpen;
  Map<String, String>? _pendingOpen;

  set onOpen(Future<void> Function(Map<String, String> data)? handler) {
    _onOpen = handler;
    _flushOpen();
  }

  void _opened(Map<String, dynamic> data) {
    _pendingOpen = data.map((key, value) => MapEntry(key, '$value'));
    _flushOpen();
  }

  void _flushOpen() {
    final data = _pendingOpen, handler = _onOpen;
    // [_store] is set by start(), which runs once signed in, and cleared by
    // stop() on sign-out, so a tap never opens anything for a signed-out user.
    if (data == null || handler == null || _store == null) return;
    _pendingOpen = null;
    unawaited(handler(data));
  }

  void _setStatus(PushStatus value) {
    if (status == value) return;
    status = value;
    notifyListeners();
  }

  Future<bool> enable() async {
    if (_available) return true;
    try {
      await Firebase.initializeApp();
      _available = true;
      _setStatus(PushStatus.checking);
    } catch (_) {
      _setStatus(PushStatus.unavailable);
    }
    return _available;
  }

  Future<void> start(AppStore store, {bool requestPermission = true}) async {
    _store = store;
    if (!_available || _starting) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _starting = true;
    final session = _session;
    try {
      // Install listeners first: a missing APNs token must not prevent us from
      // receiving the token when registration eventually completes.
      _refresh ??= _transport.tokenRefresh.listen((token) async {
        final current = _store;
        if (current == null) return;
        try {
          final session = _session;
          final permission = await _transport.permission(request: false);
          if (session != _session) return;
          if (permission != AuthorizationStatus.authorized &&
              permission != AuthorizationStatus.provisional) {
            _setStatus(
              permission == AuthorizationStatus.denied
                  ? PushStatus.denied
                  : PushStatus.notRequested,
            );
            return;
          }
          await _send(current.api, token, session);
          if (session != _session) return;
          _retry?.cancel();
          _setStatus(PushStatus.ready);
        } catch (_) {
          _scheduleRetry();
        }
      });
      _foreground ??= _transport.messages.listen((message) {
        final current = _store;
        if (current != null) unawaited(_receive(current, message));
      });
      // A tapped notification opens what it is about: from the background,
      // from a closed app, or from the banner Android shows while open.
      _openedSub ??= _transport.opened.listen(
        (message) => _opened(message.data),
      );
      if (!_checkedLaunch) {
        _checkedLaunch = true;
        final launched = await _transport.launchedBy();
        if (launched != null) _opened(launched.data);
        if (Platform.isAndroid) {
          _native.setMethodCallHandler((call) async {
            if (call.method == 'opened' && call.arguments is Map) {
              _opened(Map<String, dynamic>.from(call.arguments as Map));
            }
          });
          final banner = await _native.invokeMethod<Map<Object?, Object?>>(
            'takeOpened',
          );
          if (banner != null) {
            _opened(banner.map((key, value) => MapEntry('$key', value)));
          }
        }
      }
      _flushOpen();
      final permission = await _transport.permission(
        request:
            requestPermission &&
            store.user?.notificationPreferences.pushEnabled != false,
      );
      if (session != _session) return;
      final allowed =
          permission == AuthorizationStatus.authorized ||
          permission == AuthorizationStatus.provisional;
      await _transport.presentation(
        enabled:
            allowed && store.user?.notificationPreferences.pushEnabled != false,
      );
      if (!allowed) {
        _retry?.cancel();
        _setStatus(
          permission == AuthorizationStatus.denied
              ? PushStatus.denied
              : PushStatus.notRequested,
        );
        return;
      }
      if (Platform.isAndroid &&
          await _native.invokeMethod<bool>('notificationsEnabled', {
                'alarm':
                    store.user?.notificationPreferences.alarmReminders == true,
              }) ==
              false) {
        _setStatus(PushStatus.denied);
        return;
      }
      final token = await _transport.token();
      if (session != _session) return;
      if (token == null || token.length < 20) {
        _scheduleRetry();
        return;
      }
      await _send(store.api, token, session);
      _retry?.cancel();
      _setStatus(PushStatus.ready);
    } catch (_) {
      if (session == _session) _scheduleRetry();
    } finally {
      _starting = false;
    }
  }

  void _scheduleRetry() {
    _setStatus(PushStatus.retrying);
    _retry?.cancel();
    if (_store == null) return;
    _retry = Timer(const Duration(seconds: 30), () {
      final store = _store;
      if (store != null) unawaited(start(store, requestPermission: false));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final store = _store;
    if (state == AppLifecycleState.resumed && store != null) {
      unawaited(start(store, requestPermission: false));
    }
  }

  Future<void> openSettings() async {
    if (Platform.isAndroid) {
      await _native.invokeMethod<void>('openSettings');
    } else if (Platform.isIOS) {
      await launchUrl(Uri.parse('app-settings:'));
    }
  }

  Future<void> stop(Api api) async {
    ++_session;
    _store = null;
    _retry?.cancel();
    await _refresh?.cancel();
    await _foreground?.cancel();
    await _openedSub?.cancel();
    _refresh = null;
    _foreground = null;
    _openedSub = null;
    _pendingOpen = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _observing = false;
    final token = _registered;
    _registered = null;
    if (token != null) {
      try {
        await api.notifications.unregisterDevice(token);
      } catch (_) {}
    }
    if (_available) {
      try {
        await _transport.deleteToken();
      } catch (_) {}
    }
  }

  Future<void> _send(Api api, String? token, int session) async {
    if (session != _session ||
        token == null ||
        token.length < 20 ||
        token == _registered) {
      return;
    }
    await api.notifications.registerDevice(
      token: token,
      platform: Platform.isIOS ? 'IOS' : 'ANDROID',
    );
    if (session == _session) _registered = token;
  }

  Future<void> _receive(AppStore store, RemoteMessage message) async {
    try {
      final prefs = store.user?.notificationPreferences;
      if (Platform.isAndroid &&
          message.notification != null &&
          prefs?.pushEnabled != false &&
          (message.data['category'] != 'REMINDER' ||
              prefs?.reminders != false)) {
        await _native.invokeMethod<void>('show', {
          'id': message.data['notificationId'] ?? message.messageId ?? '',
          'data': message.data,
          'title': message.notification?.title,
          'body': message.notification?.body,
          'alarm':
              message.data['alarm'] == 'true' && prefs?.alarmReminders == true,
        });
      }
    } catch (_) {
      // The inbox remains useful if native presentation fails.
    }
    try {
      await store.loadNotifications();
    } catch (_) {}
  }
}
