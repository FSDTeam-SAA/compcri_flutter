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
}
