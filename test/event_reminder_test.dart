import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeBackend, bootedStore;

const explanation =
    'Event-time notification is included. Choose an advance reminder for an extra notification before the event.';
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
      final reminder = find.byWidgetPredicate(
        (widget) => widget is SelectField && widget.label == 'Reminder',
      );
      expect(tester.widget<SelectField>(reminder).value, 'At event time');
      expect(find.text(explanation), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Add a title'),
        'Two-minute event',
      );
      if (choice != 'At event time') {
        await tester.ensureVisible(reminder);
        await tester.pumpAndSettle();
        final dropdown = find.descendant(
          of: reminder,
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice).last);
        await tester.pumpAndSettle();
      }
      if (choice == '10 Minutes') expect(find.text(passedTime), findsOneWidget);
      if (choice == 'None') {
        expect(find.text('Reminders are off for this event.'), findsOneWidget);
      }
      final submit = find.widgetWithText(TextButton, 'Create Event');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        submit,
        250,
        scrollable: find
            .ancestor(of: submit, matching: find.byType(Scrollable))
            .first,
      );
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
