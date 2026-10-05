import 'dart:convert';

import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'app_test.dart' show FakeBackend, bootedStore, calendarId;

http.Response ok(Object body) => http.Response(
  jsonEncode({'success': true, 'data': body}),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  for (final legacy in [false, true]) {
    testWidgets(
      'a moved daily event can be edited again (${legacy ? 'older' : 'current'} API)',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final original = DateTime(
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          9,
        );
        final moved = DateTime(
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          10,
          30,
        );
        String iso(DateTime time) => time.toUtc().toIso8601String();
        const id = '65b1f77bcf86cd7994390111';
        final series = <String, dynamic>{
          '_id': id,
          'calendarId': calendarId,
          'title': 'Daily appointment',
          'description': 'Series notes',
          'location': 'Office',
          'startsAt': iso(original),
          'endsAt': iso(original.add(const Duration(hours: 1))),
          'timeZone': 'America/Sao_Paulo',
          'recurrenceRrule': 'FREQ=DAILY;COUNT=3',
          'reminderMinutes': [0],
          '__v': 1,
          'recurrenceExceptions': [
            {
              'originalStartAt': iso(original),
              'overrides': {
                'startsAt': iso(moved),
                'endsAt': iso(moved.add(const Duration(hours: 1))),
                'title': 'Moved appointment',
                'description': 'Occurrence notes',
              },
            },
          ],
        };
        final row = <String, dynamic>{
          ...series,
          'title': 'Moved appointment',
          'description': 'Occurrence notes',
          if (legacy) 'startsAt': iso(moved),
          if (legacy) 'endsAt': iso(moved.add(const Duration(hours: 1))),
          'occurrenceStartAt': iso(moved),
          'occurrenceEndAt': iso(moved.add(const Duration(hours: 1))),
          if (!legacy) 'occurrenceOriginalStartAt': iso(original),
        };
        final writes = <Map<String, dynamic>>[];
        final backend = FakeBackend()
          ..handler = (request) async {
            if (request.url.path.endsWith('/recurrence-exception')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              writes.add(body);
              return ok({
                'event': {...series, '__v': 2},
                'conflicts': [],
              });
            }
            if (request.url.path.endsWith('/events/$id')) {
              return ok({
                'event': series,
                'permissions': {'edit': true, 'delete': true},
              });
            }
            if (request.url.path.endsWith('/conflicts')) {
              return ok({'conflicts': [], 'suggestions': []});
            }
            if (request.url.path.endsWith('/calendars/$calendarId/events') &&
                request.method == 'GET') {
              return ok([row]);
            }
            return null;
          };
        final store = await bootedStore(tester, backend);
        final event = store.events.single;
        await tester.pumpWidget(
          StoreScope(
            notifier: store,
            child: MaterialApp(
              theme: appTheme,
              routes: {
                '/event/edit': (context) => EventForm(
                  event:
                      ModalRoute.of(context)!.settings.arguments
                          as CalendarEvent,
                ),
              },
              home: EventDetails(event: event),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Moved appointment'), findsOneWidget);
        expect(find.text('Occurrence notes'), findsOneWidget);
        final edit = find.widgetWithText(TextButton, 'Edit Event');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Add a title'),
          'Edited again',
        );
        final reminder = find.byKey(const ValueKey('event-reminder'));
        await tester.ensureVisible(reminder);
        await tester.tap(reminder);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reminder-before')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reminder-apply')));
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final save = find.widgetWithText(TextButton, 'Save Changes');
        await tester.ensureVisible(save);
        await tester.tap(save);
        // The save button stays busy while the scope dialog awaits a choice.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(TextButton, 'This event'));
        await tester.pumpAndSettle();
        expect(writes, hasLength(1));
        expect(writes.single['originalStartAt'], iso(original));
        expect(writes.single['version'], 1);
        final overrides = writes.single['overrides'] as Map;
        expect(overrides['startsAt'], iso(moved));
        expect(overrides['endsAt'], iso(moved.add(const Duration(hours: 1))));
        expect(overrides['title'], 'Edited again');
        expect(overrides['description'], 'Occurrence notes');
        expect(overrides['reminderMinutes'], [0, 15]);
        expect(find.byType(EventForm), findsNothing);
        expect(tester.takeException(), isNull);
        // Cancelling also addresses the original slot, not the moved clock time.
        await tester.runAsync(() => store.cancelOccurrence(event));
        expect(writes.last['cancelled'], isTrue);
        expect(writes.last['originalStartAt'], iso(original));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'after the whole series moves 9:00 → 9:30, "this event" can still be edited',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      DateTime at(int hour, int minute) =>
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute);
      String iso(DateTime time) => time.toUtc().toIso8601String();
      const id = '65b1f77bcf86cd7994390222';
      // The series as the server now has it, after its time was changed.
      final series = <String, dynamic>{
        '_id': id,
        'calendarId': calendarId,
        'title': 'Daily check-in',
        'startsAt': iso(at(9, 30)),
        'endsAt': iso(at(10, 30)),
        'timeZone': 'America/New_York',
        'recurrenceRrule': 'RRULE:FREQ=DAILY',
        'reminderMinutes': [0],
        '__v': 1,
        'recurrenceExceptions': [],
      };
      final writes = <Map<String, dynamic>>[];
      final backend = FakeBackend()
        ..handler = (request) async {
          if (request.url.path.endsWith('/recurrence-exception')) {
            writes.add(jsonDecode(request.body) as Map<String, dynamic>);
            return ok({
              'event': {...series, '__v': 2},
              'conflicts': [],
            });
          }
          if (request.url.path.endsWith('/events/$id')) {
            return ok({
              'event': series,
              'permissions': {'edit': true, 'delete': true},
            });
          }
          if (request.url.path.endsWith('/conflicts')) {
            return ok({'conflicts': [], 'suggestions': []});
          }
          if (request.url.path.endsWith('/calendars/$calendarId/events') &&
              request.method == 'GET') {
            return ok([
              {
                ...series,
                'occurrenceStartAt': iso(at(9, 30)),
                'occurrenceEndAt': iso(at(10, 30)),
                'occurrenceOriginalStartAt': iso(at(9, 30)),
              },
            ]);
          }
          return null;
        };
      final store = await bootedStore(tester, backend);
      // The screen still holds the row from before the series moved.
      final stale = CalendarEvent.fromJson({
        ...series,
        'startsAt': iso(at(9, 0)),
        'endsAt': iso(at(10, 0)),
        '__v': 0,
        'occurrenceStartAt': iso(at(9, 0)),
        'occurrenceEndAt': iso(at(10, 0)),
        'occurrenceOriginalStartAt': iso(at(9, 0)),
      });
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            routes: {
              '/event/edit': (context) => EventForm(
                event:
                    ModalRoute.of(context)!.settings.arguments as CalendarEvent,
              ),
            },
            home: EventDetails(event: stale),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final edit = find.widgetWithText(TextButton, 'Edit Event');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Add a title'),
        'Moved check-in',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'Save Changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(TextButton, 'This event'));
      await tester.pumpAndSettle();

      // The slot the series really has now, and the current version.
      expect(writes, hasLength(1));
      expect(writes.single['originalStartAt'], iso(at(9, 30)));
      expect(writes.single['version'], 1);
      expect(find.byType(EventForm), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a reminder for a repeating event opens the day it names', (
    tester,
  ) async {
    final first = DateTime.now().add(const Duration(days: 1));
    DateTime day(int offset) =>
        DateTime(first.year, first.month, first.day + offset, 9, 30);
    String iso(DateTime time) => time.toUtc().toIso8601String();
    const id = '65b1f77bcf86cd7994390333';
    final series = <String, dynamic>{
      '_id': id,
      'calendarId': calendarId,
      'title': 'Daily check-in',
      'startsAt': iso(day(0)),
      'endsAt': iso(day(0).add(const Duration(hours: 1))),
      'timeZone': 'America/New_York',
      'recurrenceRrule': 'RRULE:FREQ=DAILY',
      '__v': 1,
    };
    final backend = FakeBackend()
      ..handler = (request) async {
        if (request.url.path.endsWith('/events/$id')) {
          return ok({
            'event': series,
            'permissions': {'edit': true, 'delete': true},
          });
        }
        return null;
      };
    final store = await bootedStore(tester, backend);
    // Three days in: not loaded in the store, so it comes from the server.
    final event = await tester.runAsync(
      () => store.eventForNotification({
        'eventId': id,
        'occurrenceStartAt': iso(day(3)),
        'occurrenceOriginalStartAt': iso(day(3)),
      }),
    );
    expect(event!.occurrenceStartAt, day(3));
    expect(event.occurrenceEndAt, day(3).add(const Duration(hours: 1)));
    expect(event.occurrenceOriginalStartAt, day(3));
    // An older notification without the occurrence still opens the event.
    final plain = await tester.runAsync(
      () => store.eventForNotification({'eventId': id}),
    );
    expect(plain!.id, id);
    expect(await store.eventForNotification({'title': 'no event'}), isNull);
  });
}
