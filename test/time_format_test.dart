import 'package:compcri_flutter/core/i18n.dart' hide Text;
import 'package:compcri_flutter/core/time.dart';
import 'package:compcri_flutter/features/past_time.dart';
import 'package:compcri_flutter/features/time_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.reset();
    ClockFormat.reset();
  });

  group('formatClock', () {
    const noon = TimeOfDay(hour: 12, minute: 0);
    const midnight = TimeOfDay(hour: 0, minute: 0);
    const afternoon = TimeOfDay(hour: 15, minute: 0);
    const evening = TimeOfDay(hour: 22, minute: 5);

    test('12-hour writes AM/PM and never an hour above 12', () {
      expect(formatClock(noon, use24: false), '12:00 PM');
      expect(formatClock(midnight, use24: false), '12:00 AM');
      expect(formatClock(afternoon, use24: false), '3:00 PM');
      expect(formatClock(evening, use24: false), '10:05 PM');
      for (var hour = 0; hour < 24; hour++) {
        final text = formatClock(
          TimeOfDay(hour: hour, minute: 0),
          use24: false,
        );
        expect(text, isNot(matches(RegExp(r'^(1[3-9]|2\d|0)\D'))));
      }
    });

    test('24-hour has no AM/PM', () {
      expect(formatClock(noon, use24: true), '12:00');
      expect(formatClock(midnight, use24: true), '00:00');
      expect(formatClock(afternoon, use24: true), '15:00');
      expect(formatClock(evening, use24: true), '22:05');
    });

    test('Automatic follows the phone; a choice overrides it', () async {
      ClockFormat.debugDeviceUses24Hour = true;
      expect(formatClock(afternoon), '15:00');
      ClockFormat.debugDeviceUses24Hour = false;
      expect(formatClock(afternoon), '3:00 PM');
      await ClockFormat.apply(TimeFormat.h24);
      expect(formatClock(afternoon), '15:00');
      await ClockFormat.apply(TimeFormat.h12);
      ClockFormat.debugDeviceUses24Hour = true;
      expect(formatClock(afternoon), '3:00 PM');
    });

    test('changing the format never changes the time itself', () async {
      final at = DateTime(2026, 10, 2, 21, 45);
      await ClockFormat.apply(TimeFormat.h12);
      expect(formatClockAt(at), '9:45 PM');
      await ClockFormat.apply(TimeFormat.h24);
      expect(formatClockAt(at), '21:45');
      expect(at, DateTime(2026, 10, 2, 21, 45));
    });

    test('hour axis labels', () async {
      await ClockFormat.apply(TimeFormat.h12);
      expect([0, 12, 15].map(formatHour), ['12 AM', '12 PM', '3 PM']);
      await ClockFormat.apply(TimeFormat.h24);
      expect([0, 12, 15].map(formatHour), ['00:00', '12:00', '15:00']);
    });
  });

  test('durations, including an event ending the next day', () {
    expect(formatDuration(const Duration(hours: 1)), '1 hour');
    expect(formatDuration(const Duration(minutes: 45)), '45 minutes');
    expect(formatDuration(const Duration(minutes: 90)), '1 hour 30 minutes');
    final overnight = DateTime(
      2026,
      10,
      3,
      1,
    ).difference(DateTime(2026, 10, 2, 23));
    expect(formatDuration(overnight), '2 hours');
  });

  test('a new event opens on the next full hour, never on tomorrow', () {
    expect(
      upcomingStart(DateTime(2026, 10, 2, 14, 20)),
      DateTime(2026, 10, 2, 15),
    );
    final late = upcomingStart(DateTime(2026, 10, 2, 23, 31));
    expect(DateUtils.isSameDay(late, DateTime(2026, 10, 2)), isTrue);
    expect(late.isAfter(DateTime(2026, 10, 2, 23, 31)), isTrue);
  });

  group('clock picker', () {
    Future<TimeOfDay? Function()> open(
      WidgetTester tester,
      TimeOfDay initial,
    ) async {
      TimeOfDay? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showClockPicker(
                context,
                title: 'Start time',
                date: DateTime(2026, 10, 2),
                initial: initial,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    Finder preview() => find.byKey(const ValueKey('clock-preview'));
    String previewText(WidgetTester tester) =>
        (tester.widget(
                  find
                      .descendant(
                        of: preview(),
                        matching: find.byType(RichText),
                      )
                      .first,
                )
                as RichText)
            .text
            .toPlainText();

    testWidgets('12-hour: typing 15 means 3 PM, not "15 PM"', (tester) async {
      await tester.runAsync(() => ClockFormat.apply(TimeFormat.h12));
      final result = await open(tester, const TimeOfDay(hour: 9, minute: 0));
      expect(find.byKey(const ValueKey('clock-AM')), findsOneWidget);
      expect(find.byKey(const ValueKey('clock-PM')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('clock-hour')), '15');
      await tester.enterText(find.byKey(const ValueKey('clock-minute')), '45');
      await tester.pump();
      expect(previewText(tester), '3:45 PM');
      expect(find.textContaining('15 PM'), findsNothing);

      await tester.tap(find.text('Confirm time'));
      await tester.pumpAndSettle();
      expect(result(), const TimeOfDay(hour: 15, minute: 45));
    });

    testWidgets('12-hour: noon and midnight', (tester) async {
      await tester.runAsync(() => ClockFormat.apply(TimeFormat.h12));
      var result = await open(tester, const TimeOfDay(hour: 9, minute: 0));
      await tester.enterText(find.byKey(const ValueKey('clock-hour')), '12');
      await tester.enterText(find.byKey(const ValueKey('clock-minute')), '00');
      await tester.tap(find.byKey(const ValueKey('clock-PM')));
      await tester.pump();
      expect(previewText(tester), '12:00 PM');
      await tester.tap(find.text('Confirm time'));
      await tester.pumpAndSettle();
      expect(result(), const TimeOfDay(hour: 12, minute: 0));

      result = await open(tester, const TimeOfDay(hour: 21, minute: 0));
      await tester.enterText(find.byKey(const ValueKey('clock-hour')), '12');
      await tester.enterText(find.byKey(const ValueKey('clock-minute')), '00');
      await tester.tap(find.byKey(const ValueKey('clock-AM')));
      await tester.pump();
      expect(previewText(tester), '12:00 AM');
      await tester.tap(find.text('Confirm time'));
      await tester.pumpAndSettle();
      expect(result(), const TimeOfDay(hour: 0, minute: 0));
    });

    testWidgets('the wheels scroll to a time, and a tap still types', (
      tester,
    ) async {
      await ClockFormat.apply(TimeFormat.h24);
      final result = await open(tester, const TimeOfDay(hour: 16, minute: 0));
      expect(previewText(tester), '16:00');

      // Two rows up on the hour wheel, one on the minutes: 18:01.
      final hourWheel = find.descendant(
        of: find.byKey(const ValueKey('clock-hour')),
        matching: find.byType(ListWheelScrollView),
      );
      final minuteWheel = find.descendant(
        of: find.byKey(const ValueKey('clock-minute')),
        matching: find.byType(ListWheelScrollView),
      );
      await tester.drag(hourWheel, const Offset(0, -104));
      await tester.pumpAndSettle();
      await tester.drag(minuteWheel, const Offset(0, -52));
      await tester.pumpAndSettle();
      expect(previewText(tester), '18:01');

      // Hours wrap round: twenty rows down from 18:00 is 22:00.
      await tester.drag(hourWheel, const Offset(0, 52 * 20));
      await tester.pumpAndSettle();
      expect(previewText(tester), '22:01');

      // Tapping the minutes switches them to typing.
      await tester.tap(minuteWheel);
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('clock-minute')), '30');
      await tester.pump();
      expect(previewText(tester), '22:30');

      await tester.tap(find.text('Confirm time'));
      await tester.pumpAndSettle();
      expect(result(), const TimeOfDay(hour: 22, minute: 30));
    });

    testWidgets('24-hour hides AM/PM and rejects impossible hours', (
      tester,
    ) async {
      await tester.runAsync(() => ClockFormat.apply(TimeFormat.h24));
      final result = await open(tester, const TimeOfDay(hour: 22, minute: 0));
      expect(find.byKey(const ValueKey('clock-AM')), findsNothing);
      expect(find.byKey(const ValueKey('clock-PM')), findsNothing);
      expect(previewText(tester), '22:00');

      await tester.enterText(find.byKey(const ValueKey('clock-hour')), '25');
      await tester.pump();
      expect(find.text('Enter an hour from 0 to 23'), findsOneWidget);
      await tester.tap(find.text('Confirm time'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm time'), findsOneWidget, reason: 'stays open');

      await tester.enterText(find.byKey(const ValueKey('clock-hour')), '00');
      await tester.pump();
      expect(previewText(tester), '00:00');
      await tester.tap(find.text('Confirm time'));
      await tester.pumpAndSettle();
      expect(result(), const TimeOfDay(hour: 0, minute: 0));
    });
  });

  testWidgets('a past start says what was picked and what time it is', (
    tester,
  ) async {
    await tester.runAsync(() => ClockFormat.apply(TimeFormat.h12));
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    PastTimeChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showPastTimeSheet(
              context,
              startsAt: today.add(const Duration(hours: 21)),
              endsAt: today.add(const Duration(hours: 22)),
              now: today.add(const Duration(hours: 23, minutes: 31)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('This time has already passed'), findsOneWidget);
    expect(find.text('You selected today at 9:00 PM.'), findsOneWidget);
    expect(find.text('It is already 11:31 PM.'), findsOneWidget);
    expect(find.text('9:00 PM – 10:00 PM'), findsOneWidget);

    await tester.tap(find.text('Save as past event'));
    await tester.pumpAndSettle();
    expect(choice, PastTimeChoice.savePast);
  });
}
