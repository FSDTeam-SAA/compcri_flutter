import 'dart:convert';

import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const userId = '65b1f77bcf86cd7994390001';
const calendarId = '65b1f77bcf86cd7994390100';

String _iso(DateTime value) => value.toUtc().toIso8601String();

Map<String, dynamic> get _user => {
  '_id': userId,
  'email': 'smith@example.com',
  'displayName': 'Smith Josh',
  'contactCode': 'JOHN-456-FA',
  'plan': 'FREE',
  'phone': '+1 555 0100',
  'interests': ['Business'],
  'notificationPreferences': {'pushEnabled': true, 'reminders': false},
};

Map<String, dynamic> _event({
  required String id,
  required String title,
  required DateTime startsAt,
}) => {
  '_id': id,
  'calendarId': calendarId,
  'createdById': userId,
  'title': title,
  'startsAt': _iso(startsAt),
  'endsAt': _iso(startsAt.add(const Duration(hours: 1))),
  'timeZone': 'UTC',
  'reminderMinutes': const <int>[],
  '__v': 0,
};

/// Records every request so tests can assert on what the app sent.
class FakeBackend {
  FakeBackend();

  final requests = <http.BaseRequest>[];
  final createdEvents = <Map<String, dynamic>>[];
  final createdNotes = <Map<String, dynamic>>[];

  /// Set these to serve a fixture instead of the default payload — screens
  /// that refetch on mount would otherwise overwrite a store set by hand.
  List<Map<String, dynamic>>? notifications;
  List<Map<String, dynamic>>? conversations;

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    final method = request.method;

    Object? body;
    if (request.body.isNotEmpty) {
      body = jsonDecode(request.body);
    }

    if (path == '/auth/login') {
      return _ok({
        'user': _user,
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'refreshTokenExpiresAt': _iso(
          DateTime.now().add(const Duration(days: 30)),
        ),
      });
    }
    if (path == '/legal') {
      return _ok([
        {'type': 'TERMS', 'version': '1.0', 'title': 'Terms', 'content': 'x'},
        {
          'type': 'PRIVACY',
          'version': '1.0',
          'title': 'Privacy',
          'content': 'x',
        },
      ]);
    }
    if (path == '/users/me') {
      return _ok({
        'user': _user,
        'primaryCalendar': {
          '_id': calendarId,
          'name': 'My Calendar',
          'timeZone': 'UTC',
          'ownerId': userId,
        },
      });
    }
    if (path == '/users/me/calendars') {
      return _ok({
        'owned': [
          {
            'calendar': {
              '_id': calendarId,
              'name': 'My Calendar',
              'timeZone': 'UTC',
              'ownerId': userId,
            },
            'preset': 'OWNER',
          },
        ],
        'delegated': const [],
      });
    }
    if (path == '/subscriptions/me') {
      return _ok({
        'plan': 'FREE',
        'subscription': {'status': 'FREE'},
      });
    }
    if (path == '/calendars/$calendarId/events' && method == 'GET') {
      final now = DateTime.now();
      return _ok([
        _event(
          id: '65b1f77bcf86cd7994390101',
          title: 'Lunch with Ana',
          startsAt: DateTime(now.year, now.month, now.day, 12),
        ),
      ]);
    }
    if (path == '/calendars/$calendarId/events' && method == 'POST') {
      final payload = (body! as Map).cast<String, dynamic>();
      createdEvents.add(payload);
      return _ok({
        'event': _event(
          id: '65b1f77bcf86cd7994390109',
          title: '${payload['title']}',
          startsAt: DateTime.now(),
        ),
        'conflicts': const [],
      }, 201);
    }
    if (path == '/events/shared') return _ok(const []);
    if (path.endsWith('/completion')) {
      // Mirrors the real endpoint: the stored series document, with no
      // expanded occurrence fields.
      final completed = (body! as Map)['completed'] == true;
      return _ok({
        '_id': '65b1f77bcf86cd7994390111',
        'calendarId': calendarId,
        'title': 'Standup',
        'startsAt': '2026-01-05T09:00:00.000Z',
        'endsAt': '2026-01-05T09:15:00.000Z',
        'recurrenceRrule': 'RRULE:FREQ=WEEKLY',
        'completedAt': completed ? _iso(DateTime.now()) : null,
        '__v': 5,
      });
    }
    if (path == '/contacts') {
      return _ok([
        {
          'user': {
            '_id': '65b1f77bcf86cd7994390010',
            'displayName': 'Sarah Martinez',
            'email': 'sarah@example.com',
          },
          'relation': 'Coworker',
        },
      ]);
    }
    if (path == '/contact-requests') return _ok(const []);
    if (path == '/groups') return _ok(const []);
    if (path == '/group-invitations') return _ok(const []);
    if (path == '/notifications') {
      return _ok(
        notifications ??
            [
              {
                '_id': '65b1f77bcf86cd7994390300',
                'title': 'Upcoming event',
                'body': 'Lunch with Ana starts soon',
                'category': 'REMINDER',
                'createdAt': _iso(DateTime.now()),
              },
            ],
      );
    }
    if (path == '/ai/conversations') return _ok(conversations ?? const []);
    if (path == '/notes' && method == 'GET') {
      return _ok([
        {
          '_id': '65b1f77bcf86cd7994390400',
          'title': 'Ask Ana to move the review',
          'body': 'Ask Ana to move the review to Monday morning.',
          'source': 'VOICE',
          'pinned': false,
          'voice': {'durationSeconds': 14},
          'createdAt': _iso(DateTime.now()),
          'updatedAt': _iso(DateTime.now()),
        },
      ]);
    }
    if (path == '/notes' && method == 'POST') {
      final payload = (body! as Map).cast<String, dynamic>();
      createdNotes.add(payload);
      return _ok({
        '_id': '65b1f77bcf86cd7994390401',
        'title': payload['title'] ?? 'Untitled',
        'body': payload['body'],
        'source': 'TEXT',
        'pinned': payload['pinned'] == true,
        'createdAt': _iso(DateTime.now()),
        'updatedAt': _iso(DateTime.now()),
      }, 201);
    }

    return _ok(const <String, dynamic>{});
  });

  http.Response _ok(Object data, [int status = 200]) => http.Response(
    jsonEncode({'success': true, 'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// Builds a store wired to [backend] and boots it before the first frame.
Future<AppStore> bootedStore(
  WidgetTester tester,
  FakeBackend backend, {
  bool signedIn = true,
}) async {
  SharedPreferences.setMockInitialValues(
    signedIn
        ? {
            'app.onboarded': true,
            'auth.accessToken': 'access-token',
            'auth.refreshToken': 'refresh-token',
            'auth.refreshExpiresAt': _iso(
              DateTime.now().add(const Duration(days: 30)),
            ),
          }
        : {'app.onboarded': true},
  );
  final store = AppStore(api: Api(ApiClient(client: backend.client)));
  // Bootstrap does real async I/O, which needs the real event loop rather
  // than the test binding's fake async clock.
  await tester.runAsync(store.bootstrap);

  return store;
}

Future<void> pumpApp(WidgetTester tester, AppStore store) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // The voice orb loops forever; without this pumpAndSettle would never
  // settle. The widgets already honour the platform "reduce motion" flag.
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(MyApp(store: store));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a restored session lands on the dashboard with live data', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);

    expect(store.isSignedIn, isTrue);
    expect(store.user?.name, 'Smith Josh');
    expect(store.calendarId, calendarId);
    expect(store.events, hasLength(1));

    await pumpApp(tester, store);

    expect(find.textContaining('Smith'), findsWidgets);
    expect(find.text('Lunch with Ana'), findsWidgets);
  });

  testWidgets('signing in calls the API and routes to the dashboard', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend, signedIn: false);

    expect(store.isSignedIn, isFalse);

    await pumpApp(tester, store);
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Enter your email'),
      'smith@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '********').first,
      'a-very-long-password',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(store.isSignedIn, isTrue);
    expect(
      backend.requests.any((r) => r.url.path.endsWith('/auth/login')),
      isTrue,
    );
    expect(find.text('Lunch with Ana'), findsWidgets);
  });

  testWidgets('the bell shows the unread notification count', (tester) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);
    await pumpApp(tester, store);

    expect(store.unreadNotifications, 1);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('the network tab renders contacts from the API', (tester) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);
    await pumpApp(tester, store);

    await tester.tap(find.byTooltip('Network'));
    await tester.pumpAndSettle();

    expect(find.text('Sarah Martinez'), findsOneWidget);
    expect(find.text('JOHN-456-FA'), findsWidgets);
  });

  testWidgets('creating an event posts UTC timestamps to the calendar', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);
    await pumpApp(tester, store);

    await tester.tap(find.byTooltip('Create Event'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Lunch with Ana'),
      'Dentist appointment',
    );
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(TextButton, 'Create Event');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(backend.createdEvents, hasLength(1));
    final payload = backend.createdEvents.single;
    expect(payload['title'], 'Dentist appointment');
    expect(payload['startsAt'], endsWith('Z'));
    expect(payload['endsAt'], endsWith('Z'));
    expect(payload['overrideConflicts'], isFalse);
  });

  testWidgets('completing a recurring occurrence keeps its own date', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);

    // A weekly series anchored in the past, shown as a much later occurrence.
    final occurrence = CalendarEvent.fromJson({
      '_id': '65b1f77bcf86cd7994390111',
      'calendarId': calendarId,
      'title': 'Standup',
      'startsAt': '2026-01-05T09:00:00.000Z',
      'endsAt': '2026-01-05T09:15:00.000Z',
      'occurrenceStartAt': '2026-09-21T09:00:00.000Z',
      'occurrenceEndAt': '2026-09-21T09:15:00.000Z',
      'recurrenceRrule': 'RRULE:FREQ=WEEKLY',
      '__v': 4,
    });
    store.events = [occurrence];

    // The completion endpoint answers with the stored series document only.
    await tester.runAsync(() => store.setEventCompleted(occurrence, true));

    final updated = store.events.single;
    expect(updated.completed, isTrue);
    expect(updated.occurrenceStartAt.toUtc().month, 9);
    expect(updated.occurrenceStartAt.toUtc().day, 21);
  });

  testWidgets('signing out clears the session and returns to sign-in', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);
    await pumpApp(tester, store);

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Logout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Logout').last);
    await tester.pumpAndSettle();

    expect(store.isSignedIn, isFalse);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('the home tab lists notes and opens the notes inbox', (
    tester,
  ) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);
    await tester.runAsync(() => store.loadNotes(silent: true));
    await pumpApp(tester, store);

    expect(store.notes, hasLength(1));
    expect(store.notes.single.durationLabel, '0:14');

    await tester.scrollUntilVisible(find.text('All notes'), 200);
    await tester.tap(find.text('All notes'));
    await tester.pumpAndSettle();

    expect(find.text('Ask Ana to move the review'), findsWidgets);
    expect(find.text('Write a note'), findsOneWidget);
  });

  testWidgets('writing a note posts it and caches it locally', (tester) async {
    final backend = FakeBackend();
    final store = await bootedStore(tester, backend);
    await pumpApp(tester, store);

    await tester.runAsync(
      () => store.createNote(body: 'Book the dentist', title: ''),
    );

    expect(backend.createdNotes, hasLength(1));
    expect(backend.createdNotes.single['body'], 'Book the dentist');
    expect(backend.createdNotes.single['calendarId'], calendarId);
    // An empty title is omitted so the server derives one from the body.
    expect(backend.createdNotes.single.containsKey('title'), isFalse);
    expect(store.notes.first.body, 'Book the dentist');
  });
}
