import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/time.dart';
import 'package:compcri_flutter/features/reminder_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2030, 10, 3, 10, 30);
  Future<void> open(
    WidgetTester tester,
    List<int> initial,
    ValueChanged<List<int>?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => onResult(
                await showReminderPicker(
                  context,
                  startsAt: start,
                  initial: initial,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final unit in ReminderUnit.values) {
    testWidgets(
      'saves a custom amount in ${unit.label} with an event-time alert',
      (tester) async {
        List<int>? saved;
        await open(tester, [0], (value) => saved = value);
        await tester.tap(find.byKey(const ValueKey('reminder-before')));
        await tester.pumpAndSettle();
        tester
            .widget<CupertinoPicker>(
              find.byKey(const ValueKey('reminder-amount')),
            )
            .scrollController!
            .jumpToItem(1);
        tester
            .widget<CupertinoPicker>(
              find.byKey(const ValueKey('reminder-unit')),
            )
            .scrollController!
            .jumpToItem(unit.index);
        await tester.pumpAndSettle();
        expect(find.textContaining('Event-time alert at'), findsOneWidget);
        if (unit == ReminderUnit.days) {
          expect(find.textContaining('Oct 1, 2030'), findsOneWidget);
        }
        await tester.tap(find.byKey(const ValueKey('reminder-apply')));
        await tester.pumpAndSettle();
        expect(saved, [0, 2 * unit.multiplier]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('opening and applying keeps every existing custom reminder', (
    tester,
  ) async {
    List<int>? saved;
    await open(tester, [0, 17, 45], (value) => saved = value);
    await tester.tap(find.byKey(const ValueKey('reminder-apply')));
    await tester.pumpAndSettle();
    expect(saved, [0, 17, 45]);
  });

  testWidgets('dismissing an edited picker does not apply it', (tester) async {
    List<int>? saved = [0, 45];
    await open(tester, [0, 45], (value) {
      if (value != null) saved = value;
    });
    await tester.tap(find.byKey(const ValueKey('reminder-at-time')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ReminderPickerSheet))).pop();
    await tester.pumpAndSettle();
    expect(saved, [0, 45]);
  });

  testWidgets('switching units clamps a large amount to the API limit', (
    tester,
  ) async {
    List<int>? saved;
    await open(tester, [0, 500000], (value) => saved = value);
    tester
        .widget<CupertinoPicker>(find.byKey(const ValueKey('reminder-unit')))
        .scrollController!
        .jumpToItem(ReminderUnit.days.index);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-apply')));
    await tester.pumpAndSettle();
    expect(saved, [0, 525600]);
    expect(tester.takeException(), isNull);
  });

  test(
    'summary displays both notification times and the earlier date for days',
    () {
      ClockFormat.debugDeviceUses24Hour = false;
      addTearDown(ClockFormat.reset);
      expect(reminderAlerts([0, 15], start), 'Alerts: 10:15 AM and 10:30 AM');
      expect(
        reminderAlerts([0, 1440], start),
        'Alerts: Oct 2, 2030, 10:30 AM and 10:30 AM',
      );
      expect(reminderChoiceLabel([0, 120]), '2 hours before');
      expect(reminderChoiceLabel([0, 2880]), '2 days before');
      expect(reminderAlerts([], start), 'Reminders are off for this event.');
    },
  );
}
