import 'dart:async';
import 'dart:convert';

import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/events.dart';
import 'package:compcri_flutter/features/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart'
    show FakeBackend, bootedStore, pumpApp, calendarId, userId;

http.Response ok(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);
http.Response failure(int status) => http.Response(
  jsonEncode({
    'success': false,
    'error': {'code': 'TEMPORARILY_UNAVAILABLE', 'message': 'Try again'},
  }),
  status,
);
Map<String, dynamic> row(
  String id,
  DateTime at, {
  String calendar = calendarId,
  String? permission,
  String? rsvp,
}) => {
  '_id': id,
  'calendarId': calendar,
  'title': id,
  'createdById': userId,
  'startsAt': at.toUtc().toIso8601String(),
  'endsAt': at.add(const Duration(hours: 1)).toUtc().toIso8601String(),
  'sharePermission': ?permission,
  'rsvpStatus': ?rsvp,
};
const delegatedId = '65b1f77bcf86cd7994390999';
Map<String, dynamic> accessible(String preset) => {
  'owned': [
    {
      'calendar': {
        '_id': calendarId,
        'name': 'My Calendar',
        'ownerId': userId,
        'timeZone': 'UTC',
      },
    },
  ],
  'delegated': [
    {
      'calendar': {
        '_id': delegatedId,
        'name': 'Owner Calendar',
        'ownerId': {'_id': 'owner', 'displayName': 'Calendar Owner'},
        'timeZone': 'America/New_York',
      },
      'preset': preset,
      'delegationId': 'delegation',
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final choice in ['This event', 'Cancel']) {
    testWidgets('recurring tile deletion asks scope and honors $choice', (tester) async {
      final original = DateTime.now().add(const Duration(days: 2));
      final event = CalendarEvent(id: 'repeating-tile', calendarId: calendarId, title: 'Daily event', startsAt: original.subtract(const Duration(days: 1)), endsAt: original.subtract(const Duration(days: 1)).add(const Duration(hours: 1)), occurrenceStartAt: original, occurrenceEndAt: original.add(const Duration(hours: 1)), occurrenceOriginalStartAt: original, recurrenceRrule: 'FREQ=DAILY;COUNT=3');
      final writes = <Map<String, dynamic>>[];
      final backend = FakeBackend()..handler = (request) async {
        if (request.url.path.endsWith('/recurrence-exception')) {
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          return ok({'event': row(event.id, event.startsAt), 'conflicts': []});
        }
        return null;
      };
      final store = await bootedStore(tester, backend);
      await tester.pumpWidget(StoreScope(notifier: store, child: MaterialApp(theme: appTheme, home: Scaffold(body: EventTile(event: event)))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete repeating event'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(writes.length, choice == 'Cancel' ? 0 : 1);
      if (writes.isNotEmpty) {
        expect(writes.single['cancelled'], isTrue);
        expect(writes.single['originalStartAt'], original.toUtc().toIso8601String());
      }
      expect(backend.requests.any((request) => request.method == 'DELETE' && request.url.path.contains('repeating-tile')), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in [503, 429]) {
    test(
      'refresh $status preserves the saved session and reports the temporary error',
      () async {
        SharedPreferences.setMockInitialValues({});
        var bounced = false;
        final client = ApiClient(
          client: MockClient(
            (request) async => request.url.path.endsWith('/auth/refresh')
                ? failure(status)
                : failure(401),
          ),
        )..onUnauthorized = () => bounced = true;
        await client.setSession(
          const Session(accessToken: 'old', refreshToken: 'old-refresh'),
        );
        await expectLater(
          client.get('/users/me'),
          throwsA(
            isA<ApiException>().having(
              (error) => error.status,
              'status',
              status,
            ),
          ),
        );
        expect(client.isAuthenticated, isTrue);
        expect((await client.store.read())?.refreshToken, 'old-refresh');
        expect(bounced, isFalse);
      },
    );
  }

  test(
    'a refresh finishing after sign-out cannot restore the old login',
    () async {
      SharedPreferences.setMockInitialValues({});
      final response = Completer<http.Response>();
      final refreshing = Completer<void>();
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshing.complete();
            return response.future;
          }
          return failure(401);
        }),
      );
      await client.setSession(
        const Session(accessToken: 'old', refreshToken: 'old-refresh'),
      );
      final pending = client.get('/users/me');
      final failed = expectLater(pending, throwsA(isA<ApiException>()));
      await refreshing.future;
      await client.clearSession();
      response.complete(
        ok({'accessToken': 'renewed', 'refreshToken': 'renewed-refresh'}),
      );
      await failed;
      expect(client.isAuthenticated, isFalse);
      expect(await client.store.read(), isNull);
    },
  );

  testWidgets(
    'offline startup retains login and offers a retry that opens the dashboard',
    (tester) async {
      var offline = true;
      final backend = FakeBackend()
        ..handler = (request) async {
          if (offline && request.url.path.endsWith('/users/me'))
            throw http.ClientException('offline');
          return null;
        };
      final store = await bootedStore(tester, backend);
      expect(store.bootstrapError?.isNetworkError, isTrue);
      expect(store.api.client.isAuthenticated, isTrue);
      await pumpApp(tester, store);
      expect(
        find.text('Could not connect. Your saved sign-in is safe.'),
        findsOneWidget,
      );
      offline = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('Lunch with Ana'), findsWidgets);
      expect(store.bootstrapError, isNull);
    },
  );

  testWidgets(
    'successful sign-in remains successful when a secondary list is down',
    (tester) async {
      final backend = FakeBackend()..failEvents = true;
      final store = await bootedStore(tester, backend, signedIn: false);
      await tester.runAsync(
        () => store.signIn('smith@example.com', 'password'),
      );
      expect(store.isSignedIn, isTrue);
      expect(store.hasEventsFor(DateTime.now()), isFalse);
      await pumpApp(tester, store);
      expect(find.text('Could not load events.'), findsWidgets);
      expect(find.text('A fresh start'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final preset in ['ADD_EDIT', 'VIEW_OWN']) {
    testWidgets(
      'selecting a secretary calendar uses its events and respects $preset permissions',
      (tester) async {
        final backend = FakeBackend()
          ..handler = (request) async {
            if (request.url.path.endsWith('/users/me/calendars'))
              return ok(accessible(preset));
            if (request.url.path.endsWith('/calendars/$delegatedId/events'))
              return ok([
                row(
                  'Delegated appointment',
                  DateTime.now(),
                  calendar: delegatedId,
                ),
              ]);
            return null;
          };
        final store = await bootedStore(tester, backend);
        await tester.runAsync(store.refreshCalendars);
        await pumpApp(tester, store);
        await tester.tap(find.byKey(const ValueKey('calendar-switcher')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('calendar-choice-$delegatedId')),
        );
        await tester.pumpAndSettle();
        expect(store.calendarId, delegatedId);
        expect(store.events.single.title, 'Delegated appointment');
        expect(store.sharedEvents, isEmpty);
        expect(
          find.byType(CreateEventButton),
          preset == 'ADD_EDIT' ? findsOneWidget : findsNothing,
        );
        await tester.runAsync(store.loadProfile);
        expect(
          store.calendarId,
          delegatedId,
          reason: 'profile refresh must keep the selected calendar',
        );
        expect(
          store.calendar?.timeZone,
          'America/New_York',
          reason: 'the secretary must not change the owner time zone',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'revoked secretary access returns to the owned calendar and clears old rows',
    (tester) async {
      var granted = true;
      final backend = FakeBackend()
        ..handler = (request) async {
          if (request.url.path.endsWith('/users/me/calendars') && granted)
            return ok(accessible('ADD_EDIT'));
          if (request.url.path.endsWith('/calendars/$delegatedId/events'))
            return ok([
              row(
                'Private delegated row',
                DateTime.now(),
                calendar: delegatedId,
              ),
            ]);
          return null;
        };
      final store = await bootedStore(tester, backend);
      await tester.runAsync(store.refreshCalendars);
      await tester.runAsync(() => store.selectCalendar(store.calendars.last));
      granted = false;
      await tester.runAsync(store.refreshCalendars);
      expect(store.calendarId, calendarId);
      expect(
        store.events.any((event) => event.title == 'Private delegated row'),
        isFalse,
      );
    },
  );

  testWidgets(
    'an old calendar response cannot replace the latest selected month',
    (tester) async {
      final backend = FakeBackend();
      final store = await bootedStore(tester, backend);
      final old = Completer<http.Response>();
      backend.handler = (request) async {
        if (!request.url.path.endsWith('/calendars/$calendarId/events'))
          return null;
        if (request.url.queryParameters['from']!.startsWith('2026-10'))
          return old.future;
        return ok([row('Latest month', DateTime(2027, 2, 2))]);
      };
      await tester.runAsync(() async {
        final previous = store.loadEvents(anchor: DateTime(2026, 11, 2));
        await store.loadEvents(anchor: DateTime(2027, 2, 2));
        old.complete(ok([row('Old month', DateTime(2026, 11, 2))]));
        await previous;
      });
      expect(store.events.single.title, 'Latest month');
      expect(store.hasEventsFor(DateTime(2027, 2, 2)), isTrue);
      expect(store.hasEventsFor(DateTime(2026, 11, 2)), isFalse);
    },
  );

  test(
    'a delayed contact response cannot repopulate the store after logout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final old = Completer<http.Response>();
      final started = Completer<void>();
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/contacts')) {
            started.complete();
            return old.future;
          }
          return ok([]);
        }),
      );
      await client.setSession(
        const Session(accessToken: 'access', refreshToken: 'refresh'),
      );
      final store = AppStore(api: Api(client));
      final pending = store.loadNetwork();
      await started.future;
      await store.signOut(callServer: false);
      old.complete(
        ok([
          {
            'user': {'_id': 'old-person', 'displayName': 'Old private contact'},
          },
        ]),
      );
      await pending;
      expect(store.contacts, isEmpty);
      expect(store.isSignedIn, isFalse);
    },
  );

  testWidgets(
    'declined invitations are hidden and a midnight event appears on both dates once',
    (tester) async {
      final store = await bootedStore(tester, FakeBackend());
      final start = DateTime(2026, 11, 2, 23, 30);
      final overnight = CalendarEvent(
        id: 'overnight',
        calendarId: calendarId,
        title: 'Overnight',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 2)),
      );
      store.events = [overnight];
      store.sharedEvents = [
        overnight,
        CalendarEvent.fromJson(
          row(
            'Declined',
            DateTime(2026, 11, 3, 9),
            permission: 'RESPOND',
            rsvp: 'DECLINED',
          ),
        ),
      ];
      expect(store.eventsOn(DateTime(2026, 11, 2)).map((event) => event.id), [
        'overnight',
      ]);
      expect(store.eventsOn(DateTime(2026, 11, 3)).map((event) => event.id), [
        'overnight',
      ]);
    },
  );

  for (final permission in ['VIEW_ONLY', 'RESPOND', 'EDIT']) {
    testWidgets(
      'shared $permission detail retains the invitation and displays only permitted actions',
      (tester) async {
        final json = row(
          'shared',
          DateTime.now(),
          permission: permission,
          rsvp: 'PENDING',
        );
        final backend = FakeBackend();
        // Use a distinct id because /events/shared is also the list endpoint.
        json['_id'] = 'shared-event';
        backend.handler = (request) async {
          if (request.url.path.endsWith('/events/shared')) return ok([json]);
          if (request.url.path.endsWith('/events/shared-event'))
            return ok({
              'event': json,
              'permissions': {
                'edit': permission == 'EDIT',
                'delete': false,
                'respond': permission != 'VIEW_ONLY',
                'share': false,
              },
            });
          return null;
        };
        final store = await bootedStore(tester, backend);
        expect(store.sharedEvents.single.invited, permission != 'VIEW_ONLY');
        await tester.pumpWidget(
          StoreScope(
            notifier: store,
            child: MaterialApp(
              theme: appTheme,
              home: EventDetails(event: store.sharedEvents.single),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Share Event'), findsNothing);
        expect(find.text('Delete Event'), findsNothing);
        expect(
          find.text('Accept'),
          permission == 'VIEW_ONLY' ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Edit Event'),
          permission == 'EDIT' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'changing the secretary email discards the previous lookup and links the newly checked account',
    (tester) async {
      final backend = FakeBackend()
        ..handler = (request) async {
          if (request.url.path.endsWith('/delegations/lookup')) {
            final email = (jsonDecode(request.body) as Map)['email'];
            return ok({
              'exists': true,
              'user': {
                '_id': email == 'one@example.com' ? 'one' : 'two',
                'displayName': 'Secretary',
              },
            });
          }
          if (request.url.path.endsWith('/delegations'))
            return ok(request.method == 'GET' ? [] : {});
          return null;
        };
      final store = await bootedStore(tester, backend);
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(theme: appTheme, home: const AssistantForm()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter their email'),
        'one@example.com',
      );
      await tester.tap(find.text('Check this email'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This email already has an account. Their existing sign-in keeps working.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter their email'),
        'two@example.com',
      );
      await tester.pump();
      expect(
        find.text(
          'This email already has an account. Their existing sign-in keeps working.',
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      final submit = find.text('Add Assistant / Secretary');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final sent =
          backend.requests
                  .where(
                    (request) =>
                        request.method == 'POST' &&
                        request.url.path.endsWith('/delegations'),
                  )
                  .single
              as http.Request;
      expect((jsonDecode(sent.body) as Map)['userId'], 'two');
    },
  );
}
