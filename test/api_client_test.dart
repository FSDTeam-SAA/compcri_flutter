import 'dart:convert';

import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String ok(Object data) => jsonEncode({'success': true, 'data': data});

String errorBody(String code, String message) => jsonEncode({
  'success': false,
  'error': {'code': code, 'message': message, 'requestId': 'test'},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unwraps the success envelope', () async {
    final client = ApiClient(
      client: MockClient((_) async => http.Response(ok({'plan': 'FREE'}), 200)),
    );

    expect(await client.get('/users/me'), {'plan': 'FREE'});
  });

  test('raises the server error code and message', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async =>
            http.Response(errorBody('INVALID_CREDENTIALS', 'Email or password is incorrect'), 401),
      ),
    );

    await expectLater(
      client.post('/auth/login', auth: false, body: {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'INVALID_CREDENTIALS')
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', 'Email or password is incorrect'),
      ),
    );
  });

  test('carries error details through for conflict handling', () async {
    final body = jsonEncode({
      'success': false,
      'error': {
        'code': 'EVENT_CONFLICT',
        'message': 'Event overlaps with existing events',
        'details': {
          'conflicts': [
            {
              'title': 'Standup',
              'startsAt': '2026-09-10T09:00:00.000Z',
              'endsAt': '2026-09-10T09:30:00.000Z',
            },
          ],
          'alternatives': [
            {
              'startsAt': '2026-09-10T11:00:00.000Z',
              'endsAt': '2026-09-10T11:30:00.000Z',
            },
          ],
        },
      },
    });
    final client = ApiClient(
      client: MockClient((_) async => http.Response(body, 409)),
    );

    try {
      await client.post('/calendars/abc/events', body: {});
      fail('expected a conflict');
    } on ApiException catch (error) {
      expect(error.isConflict, isTrue);
      final details = error.details as Map;
      expect((details['conflicts'] as List), hasLength(1));
      expect((details['alternatives'] as List), hasLength(1));
    }
  });

  test('refreshes once on 401 and replays the original request', () async {
    final calls = <String>[];
    var refreshed = false;

    final client = ApiClient(
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshed = true;
          return http.Response(
            ok({
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
              'refreshTokenExpiresAt': DateTime.now()
                  .add(const Duration(days: 30))
                  .toIso8601String(),
            }),
            200,
          );
        }
        if (!refreshed) {
          return http.Response(errorBody('INVALID_TOKEN', 'expired'), 401);
        }
        expect(request.headers['Authorization'], 'Bearer new-access');
        return http.Response(ok({'ok': true}), 200);
      }),
    );

    await client.setSession(
      const Session(accessToken: 'old', refreshToken: 'old-refresh'),
    );

    expect(await client.get('/users/me'), {'ok': true});
    expect(calls, [
      '/api/v1/users/me',
      '/api/v1/auth/refresh',
      '/api/v1/users/me',
    ]);
    expect(client.session?.accessToken, 'new-access');
  });

  test('clears the session and notifies when the refresh is rejected', () async {
    var signedOut = false;
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return http.Response(errorBody('REFRESH_TOKEN_EXPIRED', 'expired'), 401);
        }
        return http.Response(errorBody('INVALID_TOKEN', 'expired'), 401);
      }),
    )..onUnauthorized = () => signedOut = true;

    await client.setSession(
      const Session(accessToken: 'old', refreshToken: 'old-refresh'),
    );

    await expectLater(client.get('/users/me'), throwsA(isA<ApiException>()));
    expect(signedOut, isTrue);
    expect(client.isAuthenticated, isFalse);
  });

  test('shares one refresh between concurrent requests', () async {
    var refreshCalls = 0;
    var refreshed = false;

    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls += 1;
          refreshed = true;
          return http.Response(
            ok({'accessToken': 'a2', 'refreshToken': 'r2'}),
            200,
          );
        }
        return refreshed
            ? http.Response(ok({'ok': true}), 200)
            : http.Response(errorBody('INVALID_TOKEN', 'expired'), 401);
      }),
    );
    await client.setSession(
      const Session(accessToken: 'a1', refreshToken: 'r1'),
    );

    await Future.wait([
      client.get('/users/me'),
      client.get('/contacts'),
      client.get('/groups'),
    ]);

    expect(refreshCalls, 1);
  });

  test('drops an expired refresh token on restore', () async {
    SharedPreferences.setMockInitialValues({
      'auth.accessToken': 'a',
      'auth.refreshToken': 'r',
      'auth.refreshExpiresAt': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
    });
    final client = ApiClient(
      client: MockClient((_) async => http.Response(ok({}), 200)),
    );

    expect(await client.restore(), isNull);
    expect(client.isAuthenticated, isFalse);
  });

  test('sends range queries as UTC ISO timestamps', () async {
    late Uri captured;
    final api = Api(
      ApiClient(
        client: MockClient((request) async {
          captured = request.url;
          return http.Response(ok(const []), 200);
        }),
      ),
    );

    await api.events.list(
      calendarId: '65b1f77bcf86cd7994390100',
      from: DateTime.utc(2026, 9, 1),
      to: DateTime.utc(2026, 10, 1),
    );

    expect(captured.path, '/api/v1/calendars/65b1f77bcf86cd7994390100/events');
    expect(captured.queryParameters['from'], '2026-09-01T00:00:00.000Z');
    expect(captured.queryParameters['to'], '2026-10-01T00:00:00.000Z');
  });

  test('deletes an event with the optimistic-concurrency version', () async {
    late Uri captured;
    late String method;
    final api = Api(
      ApiClient(
        client: MockClient((request) async {
          captured = request.url;
          method = request.method;
          return http.Response(ok({}), 200);
        }),
      ),
    );

    await api.events.delete('65b1f77bcf86cd7994390101', 3);

    expect(method, 'DELETE');
    expect(captured.queryParameters['version'], '3');
  });
}
