import 'package:flutter/material.dart' hide Text;

import '../core/design.dart';
import '../core/i18n.dart';
import '../core/time.dart';

enum PastTimeChoice { change, savePast }

/// "today", "yesterday", or the date, to drop into a sentence.
String _dayInSentence(DateTime value, DateTime now) {
  final days = DateUtils.dateOnly(
    value,
  ).difference(DateUtils.dateOnly(now)).inDays;
  return switch (days) {
    0 => tr('today'),
    -1 => tr('yesterday'),
    _ => formatShortDay(value),
  };
}

/// Stops a save whose start has already passed — nearly always today picked
/// when tomorrow was meant — and says so in plain words. Resolves to
/// [PastTimeChoice.change], [PastTimeChoice.savePast], or null if dismissed.
///
/// Nothing here moves the date on its own: guessing "tomorrow" would quietly
/// trade one wrong appointment for another.
Future<PastTimeChoice?> showPastTimeSheet(
  BuildContext context, {
  required DateTime startsAt,
  required DateTime endsAt,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  return showModalBottomSheet<PastTimeChoice>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.of(sheetContext).border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'This time has already passed',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              tr('You selected {day} at {time}.', {
                'day': _dayInSentence(startsAt, current),
                'time': formatClockAt(startsAt),
              }),
              key: const ValueKey('past-selected'),
              style: TextStyle(
                fontSize: 14,
                color: AppPalette.of(sheetContext).muted,
              ),
            ),
            Text(
              tr('It is already {time}.', {'time': formatClockAt(current)}),
              key: const ValueKey('past-now'),
              style: TextStyle(
                fontSize: 14,
                color: AppPalette.of(sheetContext).muted,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppPalette.of(
                  sheetContext,
                ).wash(const Color(0xfff7f3ff)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    color: AppPalette.of(sheetContext).accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatShortDay(startsAt),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          formatClockRange(startsAt, endsAt),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.of(sheetContext).muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Choose a future date or time, or save this as a past event without reminders.',
              style: TextStyle(
                fontSize: 13,
                color: AppPalette.of(sheetContext).muted,
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              'Change date or time',
              key: const ValueKey('past-change'),
              onPressed: () =>
                  Navigator.pop(sheetContext, PastTimeChoice.change),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              'Save as past event',
              key: const ValueKey('past-save'),
              outline: true,
              onPressed: () =>
                  Navigator.pop(sheetContext, PastTimeChoice.savePast),
            ),
          ],
        ),
      ),
    ),
  );
}
