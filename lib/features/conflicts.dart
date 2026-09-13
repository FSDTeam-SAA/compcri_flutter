import 'package:flutter/material.dart' hide Text;

import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';
import '../core/i18n.dart';

const _amber = Color(0xffb87b00);
const _amberWash = Color(0xfffff4e0);
const _free = Color(0xff1f8a5b);

/// "Today", "Tomorrow", or the date.
String conflictDay(DateTime value) {
  final days = DateUtils.dateOnly(
    value,
  ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
  return switch (days) {
    0 => tr('Today'),
    1 => tr('Tomorrow'),
    -1 => tr('Yesterday'),
    _ => formatDay(value),
  };
}

String _clock(BuildContext context, DateTime value) =>
    TimeOfDay.fromDateTime(value).format(context);

String _span(BuildContext context, DateTime startsAt, DateTime endsAt) =>
    '${_clock(context, startsAt)} – ${_clock(context, endsAt)}';

/// How a person would describe a suggestion: "Right after", "Just before", or
/// the day it falls on.
String _headline(TimeSlot slot) => switch (slot.reason) {
  'AFTER_CONFLICT' => tr('Right after'),
  'BEFORE_CONFLICT' => tr('Just before'),
  _ => conflictDay(slot.startsAt),
};

/// The live verdict on the time being picked: checking, free, or what it runs
/// into — with the nearest free times one tap away.
class ConflictPanel extends StatelessWidget {
  const ConflictPanel({
    super.key,
    required this.report,
    required this.onPick,
    this.checking = false,
    this.suggestionsTitle = 'Free nearby — tap to switch',
    this.background = _amberWash,
  });

  final ConflictReport? report;
  final ValueChanged<TimeSlot> onPick;
  final bool checking;
  final String suggestionsTitle;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    final Widget child;
    if (report == null) {
      child = checking
          ? const _Status(
              key: ValueKey('checking'),
              icon: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: muted),
              ),
              text: 'Checking your calendar…',
              color: muted,
            )
          : const SizedBox.shrink();
    } else if (report.clear) {
      child = _Status(
        key: const ValueKey('free'),
        icon: checking
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: muted),
              )
            : const Icon(Icons.check_circle_rounded, size: 16, color: _free),
        text: checking ? 'Checking your calendar…' : 'You’re free at this time',
        color: checking ? muted : _free,
      );
    } else {
      child = Surface(
        key: const ValueKey('busy'),
        color: background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_busy_rounded, size: 18, color: _amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.conflicts.length == 1
                        ? 'This overlaps 1 event'
                        : tr('This overlaps {count} events', {
                            'count': report.conflicts.length,
                          }),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _amber,
                    ),
                  ),
                ),
                if (checking)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _amber,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final conflict in report.conflicts.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 26),
                    Expanded(
                      child: Text(
                        conflict.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _span(context, conflict.startsAt, conflict.endsAt),
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            if (report.conflicts.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  tr('+{count} more', {'count': report.conflicts.length - 3}),
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ),
            if (report.alternatives.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                suggestionsTitle,
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final slot in report.alternatives.take(4))
                    ActionChip(
                      avatar: const Icon(
                        Icons.event_available_rounded,
                        size: 16,
                        color: purple,
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xffd9ccff)),
                      label: Text(
                        '${_headline(slot)} · ${_clock(context, slot.startsAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => onPick(slot),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: child is SizedBox
            ? child
            : Padding(
                key: child.key,
                padding: const EdgeInsets.only(bottom: 16),
                child: child,
              ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final Widget icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      icon,
      const SizedBox(width: 8),
      Text(text, style: TextStyle(fontSize: 12, color: color)),
    ],
  );
}

/// What to do about a clash: move to a suggested free time, or keep both.
class ConflictDecision {
  const ConflictDecision._(this.slot, this.keepBoth);

  factory ConflictDecision.move(TimeSlot slot) =>
      ConflictDecision._(slot, false);
  static const keep = ConflictDecision._(null, true);

  final TimeSlot? slot;
  final bool keepBoth;
}

/// Asks what to do about a clash before it is saved. Resolves to a free time
/// to move to, [ConflictDecision.keep], or null when the user would rather
/// pick another time themselves.
Future<ConflictDecision?> showConflictSheet(
  BuildContext context,
  ConflictReport report, {
  String? title,
}) => showModalBottomSheet<ConflictDecision>(
  context: context,
  backgroundColor: Colors.white,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (sheetContext) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xffd9d3e6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: _amberWash,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.event_busy_rounded, color: _amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'That time is already taken',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title == null || title.isEmpty
                            ? 'It overlaps with:'
                            : tr('“{title}” overlaps with:', {'title': title}),
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final conflict in report.conflicts)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _amberWash,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: _amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        conflict.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _span(sheetContext, conflict.startsAt, conflict.endsAt),
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            if (report.alternatives.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Move it to a free time',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final slot in report.alternatives.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0xfff3edff),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(
                        sheetContext,
                        ConflictDecision.move(slot),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_available_rounded,
                              color: purple,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _headline(slot),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${conflictDay(slot.startsAt)} · ${_span(sheetContext, slot.startsAt, slot.endsAt)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: purple),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            PrimaryButton(
              'Keep both anyway',
              outline: true,
              onPressed: () =>
                  Navigator.pop(sheetContext, ConflictDecision.keep),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('I’ll pick another time'),
            ),
          ],
        ),
      ),
    ),
  ),
);
