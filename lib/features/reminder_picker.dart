import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart' hide Text;

import '../core/design.dart';
import '../core/i18n.dart';
import '../core/time.dart';

const maxReminderMinutes = 525600;

enum ReminderUnit {
  minutes(1, 'minutes'),
  hours(60, 'hours'),
  days(1440, 'days');

  const ReminderUnit(this.multiplier, this.label);
  final int multiplier;
  final String label;
  int get maximum => maxReminderMinutes ~/ multiplier;
}

String reminderChoiceLabel(List<int> minutes) {
  if (minutes.isEmpty) return tr('None');
  final advance = minutes.where((value) => value > 0).toSet().toList()..sort();
  if (advance.isEmpty) return tr('At event time');
  if (advance.length > 1) {
    return tr('{count} reminders', {'count': advance.length + 1});
  }
  final value = advance.single;
  if (value % 1440 == 0) {
    return trCount(value ~/ 1440, '{count} day before', '{count} days before');
  }
  if (value % 60 == 0) {
    return trCount(value ~/ 60, '{count} hour before', '{count} hours before');
  }
  return tr('{minutes} min before', {'minutes': value});
}

String reminderInstant(DateTime instant, DateTime startsAt) =>
    DateUtils.isSameDay(instant, startsAt)
    ? formatClockAt(instant)
    : '${formatShortDay(instant)}, ${formatClockAt(instant)}';

String reminderAlerts(List<int> minutes, DateTime startsAt) {
  if (minutes.isEmpty) return tr('Reminders are off for this event.');
  final offsets = {0, ...minutes}.toList()..sort((a, b) => b.compareTo(a));
  final times = offsets
      .map(
        (value) => reminderInstant(
          startsAt.subtract(Duration(minutes: value)),
          startsAt,
        ),
      )
      .toList();
  final text = times.length == 1
      ? times.single
      : tr('{earlier} and {last}', {
          'earlier': times.take(times.length - 1).join(', '),
          'last': times.last,
        });
  return tr('Alerts: {times}', {'times': text});
}

Future<List<int>?> showReminderPicker(
  BuildContext context, {
  required DateTime startsAt,
  required List<int> initial,
}) => showModalBottomSheet<List<int>>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppPalette.of(context).surface,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .92,
  ),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
  ),
  builder: (_) => ReminderPickerSheet(startsAt: startsAt, initial: initial),
);

class ReminderPickerSheet extends StatefulWidget {
  const ReminderPickerSheet({
    super.key,
    required this.startsAt,
    required this.initial,
  });
  final DateTime startsAt;
  final List<int> initial;

  @override
  State<ReminderPickerSheet> createState() => _ReminderPickerSheetState();
}

class _ReminderPickerSheetState extends State<ReminderPickerSheet> {
  late bool before = widget.initial.any((value) => value > 0);
  late bool off = widget.initial.isEmpty;
  late ReminderUnit unit;
  late int amount;
  late final FixedExtentScrollController amountWheel;
  late final FixedExtentScrollController unitWheel;
  bool changed = false;

  @override
  void initState() {
    super.initState();
    final advance = widget.initial.where((value) => value > 0);
    final minutes = advance.isEmpty ? 15 : advance.first;
    unit = minutes % 1440 == 0
        ? ReminderUnit.days
        : minutes % 60 == 0
        ? ReminderUnit.hours
        : ReminderUnit.minutes;
    amount = (minutes ~/ unit.multiplier).clamp(1, unit.maximum);
    amountWheel = FixedExtentScrollController(initialItem: amount - 1);
    unitWheel = FixedExtentScrollController(initialItem: unit.index);
  }

  @override
  void dispose() {
    amountWheel.dispose();
    unitWheel.dispose();
    super.dispose();
  }

  List<int> get selection => !changed
      ? widget.initial
      : off
      ? const []
      : before
      ? [0, amount * unit.multiplier]
      : const [0];

  void _mode(bool next) => setState(() {
    before = next;
    off = false;
    changed = true;
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final selected = selection;
    final advance = selected.where((value) => value > 0).toList();
    final previewMinutes = advance.isEmpty
        ? amount * unit.multiplier
        : advance.first;
    final reminderAt = widget.startsAt.subtract(
      Duration(minutes: previewMinutes),
    );
    Widget tab(String label, bool value, Key key) => Expanded(
      child: Container(
        decoration: BoxDecoration(
          gradient: !off && before == value ? violetGradient : null,
          borderRadius: BorderRadius.circular(11),
        ),
        child: TextButton(
          key: key,
          onPressed: () => _mode(value),
          style: TextButton.styleFrom(
            foregroundColor: !off && before == value
                ? Colors.white
                : palette.ink,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: palette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Remind me',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        tab(
                          'At event time',
                          false,
                          const ValueKey('reminder-at-time'),
                        ),
                        tab(
                          'Before event',
                          true,
                          const ValueKey('reminder-before'),
                        ),
                      ],
                    ),
                  ),
                  if (before && !off) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Choose how long before the event.',
                      style: TextStyle(color: palette.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Amount',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Unit',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.muted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 190,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: palette.wash(const Color(0xfff1ebff)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoPicker.builder(
                                  key: const ValueKey('reminder-amount'),
                                  scrollController: amountWheel,
                                  itemExtent: 44,
                                  childCount: unit.maximum,
                                  selectionOverlay: const SizedBox.shrink(),
                                  onSelectedItemChanged: (index) =>
                                      setState(() {
                                        amount = index + 1;
                                        changed = true;
                                      }),
                                  itemBuilder: (_, index) => Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontFamily: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.fontFamily,
                                          fontSize: index + 1 == amount
                                              ? 26
                                              : 20,
                                          fontWeight: index + 1 == amount
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: index + 1 == amount
                                              ? palette.accent
                                              : palette.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 1,
                                height: 44,
                                child: ColoredBox(color: palette.border),
                              ),
                              Expanded(
                                child: CupertinoPicker(
                                  key: const ValueKey('reminder-unit'),
                                  scrollController: unitWheel,
                                  itemExtent: 44,
                                  selectionOverlay: const SizedBox.shrink(),
                                  onSelectedItemChanged: (index) {
                                    final next = ReminderUnit.values[index];
                                    if (amount > next.maximum) {
                                      amountWheel.jumpToItem(next.maximum - 1);
                                    }
                                    setState(() {
                                      unit = next;
                                      amount = amount.clamp(1, next.maximum);
                                      changed = true;
                                    });
                                  },
                                  children: [
                                    for (final item in ReminderUnit.values)
                                      Center(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            item.label,
                                            style: TextStyle(
                                              fontFamily: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.fontFamily,
                                              fontSize: item == unit ? 23 : 18,
                                              fontWeight: item == unit
                                                  ? FontWeight.w700
                                                  : FontWeight.w400,
                                              color: item == unit
                                                  ? palette.accent
                                                  : palette.muted,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Surface(
                    color: palette.wash(const Color(0xfff5efff)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          off
                              ? 'Reminders are off for this event.'
                              : before
                              ? tr('Reminder at {time}', {
                                  'time': reminderInstant(
                                    reminderAt,
                                    widget.startsAt,
                                  ),
                                })
                              : tr('Alert at {time}', {
                                  'time': formatClockAt(widget.startsAt),
                                }),
                          key: const ValueKey('reminder-preview'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!off && before) ...[
                          const SizedBox(height: 6),
                          Text(
                            tr('Event-time alert at {time} is included.', {
                              'time': formatClockAt(widget.startsAt),
                            }),
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 13,
                            ),
                          ),
                          if (!reminderAt.isAfter(DateTime.now())) ...[
                            const SizedBox(height: 6),
                            Text(
                              'The advance reminder time has passed. You will still be notified when the event starts.',
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (!changed && advance.length > 1) ...[
                            const SizedBox(height: 6),
                            Text(
                              reminderAlerts(selected, widget.startsAt),
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrimaryButton(
                  'Apply reminder',
                  key: const ValueKey('reminder-apply'),
                  onPressed: () =>
                      Navigator.pop(context, List<int>.of(selection)),
                ),
                TextButton(
                  key: const ValueKey('reminder-off'),
                  onPressed: () => setState(() {
                    off = true;
                    changed = true;
                  }),
                  child: Text(
                    'Turn off reminders',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
