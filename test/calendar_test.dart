import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/calendar.dart';
import 'package:compcri_flutter/features/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeBackend, bootedStore;

void main() {
  testWidgets('calendar switches views and creates on the selected day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await bootedStore(tester, FakeBackend());
    await tester.pumpWidget(
      StoreScope(
        notifier: store,
        child: MaterialApp(
          theme: appTheme,
          home: const Scaffold(body: SafeArea(child: CalendarTab())),
        ),
      ),
    );
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Lunch with Ana'), findsOneWidget);
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('No events scheduled for this day.'), findsOneWidget);
    await tester.tap(find.byTooltip('Create Event'));
    await tester.pumpAndSettle();
    final form = tester.widget<EventForm>(find.byType(EventForm));
    final expected = DateTime.now().add(const Duration(days: 7));
    expect(DateUtils.isSameDay(form.initialStart, expected), isTrue);
    expect(form.initialStart!.hour, 9);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the month view shows every day and selects the one tapped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await bootedStore(tester, FakeBackend());
    await tester.pumpWidget(
      StoreScope(
        notifier: store,
        child: MaterialApp(
          theme: appTheme,
          home: const Scaffold(body: SafeArea(child: CalendarTab())),
        ),
      ),
    );

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    // Every day of this month has a cell, and the header names the month
    // rather than a single day.
    final today = DateTime.now();
    final days = DateUtils.getDaysInMonth(today.year, today.month);
    expect(find.text('$days'), findsWidgets);
    expect(find.byTooltip('Next month'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tapping a day carries the selection into the other views, so switching
    // lands where the user was looking rather than back on today.
    final target = today.day == 1 ? 2 : 1;
    // The date strip also contains this number, including off-screen cells.
    // Select the visible cell in the month grid.
    final cell = find.descendant(
      of: find.byType(GridView),
      matching: find.text('$target'),
    );
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create Event'));
    await tester.pumpAndSettle();
    final form = tester.widget<EventForm>(find.byType(EventForm));
    expect(form.initialStart!.day, target);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'overlapping and overnight events remain visible on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await bootedStore(tester, FakeBackend());
      final today = DateUtils.dateOnly(DateTime.now());
      CalendarEvent event(String title, DateTime start, DateTime end) =>
          CalendarEvent.fromJson({
            '_id': title,
            'title': title,
            'startsAt': start.toIso8601String(),
            'endsAt': end.toIso8601String(),
          });
      store.events = [
        event(
          'Overnight',
          today.subtract(const Duration(hours: 1)),
          today.add(const Duration(hours: 1)),
        ),
        event(
          'Early call',
          today.add(const Duration(minutes: 15)),
          today.add(const Duration(minutes: 45)),
        ),
      ];
      store.sharedEvents = [];
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            home: const Scaffold(body: SafeArea(child: CalendarTab())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Overnight'), findsOneWidget);
      expect(find.text('Early call'), findsOneWidget);
      final first = tester.getRect(find.text('Overnight'));
      final second = tester.getRect(find.text('Early call'));
      expect(first.overlaps(second), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<AppStore> pumpCalendar(
    WidgetTester tester,
    FakeBackend backend,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await bootedStore(tester, backend);
    await tester.pumpWidget(
      StoreScope(
        notifier: store,
        child: MaterialApp(
          theme: appTheme,
          home: const Scaffold(body: SafeArea(child: CalendarTab())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('tapping an empty slot opens the form on that day and time', (
    tester,
  ) async {
    await pumpCalendar(tester, FakeBackend());
    // A week ahead: nothing is booked, so the day view starts at 9:00.
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();

    final slots = find.byKey(const ValueKey('timeline-slots'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    // 80 px per hour from 9:00: 11:10 is 2h10m down, snapping to 11:00.
    await tester.tapAt(
      tester.getTopLeft(slots) + const Offset(40, 80 * 2 + 13),
    );
    await tester.pumpAndSettle();

    final form = tester.widget<EventForm>(find.byType(EventForm));
    final expected = DateTime.now().add(const Duration(days: 7));
    expect(DateUtils.isSameDay(form.initialStart, expected), isTrue);
    expect(form.initialStart!.hour, 11);
    expect(form.initialStart!.minute, 0);
    // Opened, not saved: nothing is created until the user confirms.
    expect(find.text('Duration: 1 hour'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed load offers a retry and never claims free time', (
    tester,
  ) async {
    final backend = FakeBackend()..failEvents = true;
    await pumpCalendar(tester, backend);

    expect(find.byKey(const ValueKey('calendar-retry')), findsOneWidget);
    expect(find.textContaining('free · tap to add'), findsNothing);

    backend.failEvents = false;
    await tester.tap(find.byKey(const ValueKey('calendar-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-retry')), findsNothing);
    expect(find.textContaining('free · tap to add'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
