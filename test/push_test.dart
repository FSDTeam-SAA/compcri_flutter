import 'dart:async';
import 'dart:convert';

import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/push.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakePush implements PushTransport {
  AuthorizationStatus authorization = AuthorizationStatus.authorized;
  String? currentToken = 'device-token-that-is-long-enough';
  bool failToken = false;
  int requests = 0;
  final refreshed = StreamController<String>.broadcast();
  final incoming = StreamController<RemoteMessage>.broadcast();
  final presentationValues = <bool>[];
  @override
  Future<AuthorizationStatus> permission({required bool request}) async {
    if (request) requests++;
    return authorization;
  }

  @override
  Future<String?> token() async {
    if (failToken) throw StateError('APNs token not ready');
    return currentToken;
  }

  @override
  Future<void> presentation({required bool enabled}) async =>
      presentationValues.add(enabled);
  @override
  Future<void> deleteToken() async {}
  @override
  Stream<String> get tokenRefresh => refreshed.stream;
  @override
  Stream<RemoteMessage> get messages => incoming.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePush transport;
  late PushMessaging push;
  late AppStore store;
  late List<http.Request> requests;
  bool failRegistration = false;

  setUp(() {
    transport = FakePush();
    push = PushMessaging.forTest(transport);
    requests = [];
    failRegistration = false;
    store = AppStore(
      api: Api(
        ApiClient(
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/devices') && failRegistration) {
              return http.Response(
                jsonEncode({
                  'success': false,
                  'error': {'message': 'Offline'},
                }),
                503,
              );
            }
            return http.Response(
              jsonEncode({
                'success': true,
                'data': request.url.path.endsWith('/notifications') ? [] : {},
              }),
              200,
            );
          }),
        ),
      ),
    );
  });
  tearDown(() async {
    await push.stop(store.api);
    await transport.refreshed.close();
    await transport.incoming.close();
    push.dispose();
    store.dispose();
  });

  testWidgets('permission denial is visible and does not register a token', (
    tester,
  ) async {
    transport.authorization = AuthorizationStatus.denied;
    await push.start(store);
    expect(push.status, PushStatus.denied);
    expect(transport.requests, 1);
    expect(requests, isEmpty);
    expect(transport.presentationValues, [false]);
  });

  testWidgets(
    'APNs delay retries registration without asking for permission again',
    (tester) async {
      transport.currentToken = null;
      await push.start(store);
      expect(push.status, PushStatus.retrying);
      transport.currentToken = 'eventual-device-token-long-enough';
      await tester.pump(const Duration(seconds: 30));
      expect(push.status, PushStatus.ready);
      expect(transport.requests, 1);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  testWidgets('failed token lookup still installs the token refresh listener', (
    tester,
  ) async {
    transport.failToken = true;
    await push.start(store);
    expect(push.status, PushStatus.retrying);
    transport.refreshed.add('refreshed-device-token-long-enough');
    await tester.pump();
    expect(push.status, PushStatus.ready);
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  testWidgets(
    'registration failure is retried on resume and foreground messages refresh inbox',
    (tester) async {
      failRegistration = true;
      await push.start(store);
      expect(push.status, PushStatus.retrying);
      failRegistration = false;
      push.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(push.status, PushStatus.ready);
      transport.incoming.add(const RemoteMessage());
      await tester.pump();
      expect(
        requests.any((r) => r.url.path.endsWith('/notifications')),
        isTrue,
      );
      expect(transport.requests, 1);
    },
  );

  testWidgets(
    'sign-out cancels registration retry and token/message listeners',
    (tester) async {
      transport.currentToken = null;
      await push.start(store);
      await tester.runAsync(() => push.stop(store.api));
      transport.refreshed.add('another-device-token-long-enough');
      await tester.pump(const Duration(seconds: 30));
      expect(requests, isEmpty);
    },
  );
}
