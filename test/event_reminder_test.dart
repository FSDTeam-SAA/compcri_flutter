import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeBackend, bootedStore;

const passedTime =
    'The advance reminder time has passed. You will still be notified when the event starts.';

void main() {
  for (final choice in ['At event time', '10 Minutes', 'None']) {
    testWidgets('two-minute event saves $choice and explains its reminders', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeBackend();
      final store = await bootedStore(tester, backend);
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            home: EventForm(
              initialStart: DateTime.now().add(const Duration(minutes: 2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reminder = find.byKey(const ValueKey('event-reminder'));
      expect(find.text('At event time'), findsOneWidget);
      expect(find.textContaining('Alerts:'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Add a title'),
        'Two-minute event',
      );
      if (choice != 'At event time') {
        await tester.ensureVisible(reminder);
        await tester.pumpAndSettle();
        await tester.tap(reminder);
        await tester.pumpAndSettle();
        if (choice == 'None') {
          await tester.tap(find.byKey(const ValueKey('reminder-off')));
        } else {
          await tester.tap(find.byKey(const ValueKey('reminder-before')));
          await tester.pumpAndSettle();
          tester
              .widget<CupertinoPicker>(
                find.byKey(const ValueKey('reminder-amount')),
              )
              .scrollController!
              .jumpToItem(9);
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reminder-apply')));
        await tester.pumpAndSettle();
      }
      if (choice == '10 Minutes') expect(find.text(passedTime), findsOneWidget);
      if (choice == 'None') {
        expect(find.text('Reminders are off for this event.'), findsOneWidget);
      }
      final submit = find.widgetWithText(TextButton, 'Create Event');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(backend.createdEvents, hasLength(1));
      expect(backend.createdEvents.single['reminderMinutes'], switch (choice) {
        '10 Minutes' => [0, 10],
        'None' => <int>[],
        _ => [0],
      });
      expect(tester.takeException(), isNull);
    });
  }
}
