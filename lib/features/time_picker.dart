import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../core/design.dart';
import '../core/i18n.dart';
import '../core/time.dart';

/// Asks for a clock time with large, typeable hour and minute fields, an
/// AM/PM switch in 12-hour mode, and a preview of exactly what will be saved.
///
/// [note] adds a line under the preview for the time being picked — the end
/// picker uses it to say when an event runs into the next day.
Future<TimeOfDay?> showClockPicker(
  BuildContext context, {
  required String title,
  required DateTime date,
  required TimeOfDay initial,
  String? Function(TimeOfDay time)? note,
}) => showModalBottomSheet<TimeOfDay>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) =>
      ClockPickerSheet(title: title, date: date, initial: initial, note: note),
);

class ClockPickerSheet extends StatefulWidget {
  const ClockPickerSheet({
    super.key,
    required this.title,
    required this.date,
    required this.initial,
    this.note,
  });

  final String title;
  final DateTime date;
  final TimeOfDay initial;
  final String? Function(TimeOfDay time)? note;

  @override
  State<ClockPickerSheet> createState() => _ClockPickerSheetState();
}

class _ClockPickerSheetState extends State<ClockPickerSheet> {
  // Read once: the sheet keeps the format it opened with even if the setting
  // changes underneath it.
  final bool use24 = ClockFormat.use24;
  late final TextEditingController hour = TextEditingController(
    text: use24
        ? widget.initial.hour.toString().padLeft(2, '0')
        : '${hour12Of(widget.initial)}',
  );
  late final TextEditingController minute = TextEditingController(
    text: widget.initial.minute.toString().padLeft(2, '0'),
  );
  late DayPeriod period = widget.initial.period;
  final hourFocus = FocusNode(), minuteFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Typing replaces the number rather than appending to it.
    for (final (focus, controller) in [
      (hourFocus, hour),
      (minuteFocus, minute),
    ]) {
      focus.addListener(() {
        if (focus.hasFocus) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        } else {
          _tidy();
        }
      });
    }
  }

  @override
  void dispose() {
    hour.dispose();
    minute.dispose();
    hourFocus.dispose();
    minuteFocus.dispose();
    super.dispose();
  }

  int? get _hourValue => int.tryParse(hour.text);
  int? get _minuteValue => int.tryParse(minute.text);

  /// What the fields say, or null while they do not make a time.
  TimeOfDay? get value {
    final h = _hourValue, m = _minuteValue;
    if (h == null || m == null || m < 0 || m > 59) return null;
    if (use24) {
      return h >= 0 && h <= 23 ? TimeOfDay(hour: h, minute: m) : null;
    }
    if (h < 1 || h > 12) return null;
    final base = h == 12 ? 0 : h;
    return TimeOfDay(hour: base + (period == DayPeriod.pm ? 12 : 0), minute: m);
  }

  String? get _problem {
    final h = _hourValue, m = _minuteValue;
    if (h == null || (use24 ? h > 23 : h < 1 || h > 12)) {
      return use24
          ? tr('Enter an hour from 0 to 23')
          : tr('Enter an hour from 1 to 12');
    }
    if (m == null || m > 59) return tr('Enter minutes from 0 to 59');
    return null;
  }

  void _onHourChanged(String text) {
    final h = int.tryParse(text);
    // Someone used to 15:00 typing "15" in 12-hour mode means 3 PM — take it
    // that way instead of refusing it, or worse, showing "15 PM".
    if (!use24 && h != null && h >= 13 && h <= 23) {
      hour.text = '${h - 12}';
      period = DayPeriod.pm;
    } else if (!use24 && h == 0 && text.length == 2) {
      hour.text = '12';
      period = DayPeriod.am;
    }
    setState(() {});
    // Move on once no further digit could follow.
    final done = text.length == 2 || (h != null && h > (use24 ? 2 : 1));
    if (done) minuteFocus.requestFocus();
  }

  /// Pads the fields once the user leaves them: "5" minutes reads "05".
  void _tidy() {
    final m = _minuteValue;
    if (m != null && m <= 59) minute.text = m.toString().padLeft(2, '0');
    final h = _hourValue;
    if (use24 && h != null && h <= 23) hour.text = h.toString().padLeft(2, '0');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final time = value;
    final note = time == null ? null : widget.note?.call(time);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
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
                    color: AppPalette.of(context).border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatShortDay(widget.date),
                style: TextStyle(
                  fontSize: 15,
                  color: AppPalette.of(context).muted,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _NumberField(
                      key: const ValueKey('clock-hour'),
                      controller: hour,
                      focus: hourFocus,
                      label: 'Hour',
                      values: use24
                          ? [for (var h = 0; h < 24; h++) h]
                          : [12, for (var h = 1; h < 12; h++) h],
                      pad: use24,
                      onChanged: _onHourChanged,
                      onScrolled: () => setState(() {}),
                      onSubmitted: (_) => minuteFocus.requestFocus(),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 52, 8, 0),
                    child: Text(
                      ':',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _NumberField(
                      key: const ValueKey('clock-minute'),
                      controller: minute,
                      focus: minuteFocus,
                      label: 'Minute',
                      values: [for (var m = 0; m < 60; m++) m],
                      pad: true,
                      onChanged: (_) => setState(() {}),
                      onScrolled: () => setState(() {}),
                      onSubmitted: (_) => minuteFocus.unfocus(),
                    ),
                  ),
                  if (!use24) ...[
                    const SizedBox(width: 12),
                    _PeriodSwitch(
                      value: period,
                      onChanged: (next) => setState(() => period = next),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'Scroll, or tap a number to type.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppPalette.of(context).muted,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Preview(time: time, problem: _problem, note: note),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      'Cancel',
                      outline: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: PrimaryButton(
                      'Confirm time',
                      onPressed: time == null
                          ? null
                          : () => Navigator.pop(context, time),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number on a looping wheel you can flick through, which turns into a
/// text field when tapped so it can also be typed.
///
/// The field stays in the tree, invisible, while the wheel shows: that keeps
/// its focus node live, so typing the hour can hand straight on to the
/// minute, and leaving the field turns the wheel to whatever was typed.
class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.focus,
    required this.label,
    required this.values,
    required this.pad,
    required this.onChanged,
    required this.onScrolled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String label;

  /// The wheel's numbers, in order: 0–23, 12 then 1–11, or 0–59.
  final List<int> values;

  /// Whether numbers read "05" rather than "5".
  final bool pad;
  final ValueChanged<String> onChanged;
  final VoidCallback onScrolled;
  final ValueChanged<String> onSubmitted;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  static const _rowHeight = 52.0;

  late final FixedExtentScrollController wheel = FixedExtentScrollController(
    initialItem: _indexOf(int.tryParse(widget.controller.text)) ?? 0,
  );
  bool typing = false;

  String _text(int value) =>
      widget.pad ? value.toString().padLeft(2, '0') : '$value';

  int? _indexOf(int? value) {
    final index = value == null ? -1 : widget.values.indexOf(value);
    return index == -1 ? null : index;
  }

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    wheel.dispose();
    super.dispose();
  }

  void _onFocus() {
    final focused = widget.focus.hasFocus;
    if (focused == typing) return;
    setState(() => typing = focused);
    if (!focused) _turnTo(int.tryParse(widget.controller.text));
  }

  /// Turns the wheel to [value] by the shortest way round.
  void _turnTo(int? value) {
    final target = _indexOf(value);
    if (target == null || !wheel.hasClients) return;
    final length = widget.values.length;
    final current = wheel.selectedItem;
    var delta = (target - current) % length;
    if (delta > length / 2) delta -= length;
    if (delta != 0) wheel.jumpToItem(current + delta);
  }

  void _onWheel(int index) {
    if (typing) return;
    final text = _text(widget.values[index % widget.values.length]);
    if (widget.controller.text == text) return;
    widget.controller.text = text;
    HapticFeedback.selectionClick();
    widget.onScrolled();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    const height = _rowHeight * 3;
    final numberStyle = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      height: 1.1,
      color: palette.ink,
    );
    return Column(
      children: [
        Semantics(
          label: tr(widget.label),
          value: widget.controller.text,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: palette.tint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: typing ? palette.accent : Colors.transparent,
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // The band the chosen number sits in.
                Center(
                  child: Container(
                    height: _rowHeight,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: typing ? 0 : .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Opacity(
                  opacity: typing ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: typing,
                    child: GestureDetector(
                      // A tap types; a drag spins the wheel.
                      onTap: widget.focus.requestFocus,
                      child: ListWheelScrollView.useDelegate(
                        controller: wheel,
                        itemExtent: _rowHeight,
                        physics: const FixedExtentScrollPhysics(),
                        diameterRatio: 1.5,
                        perspective: .004,
                        overAndUnderCenterOpacity: .32,
                        useMagnifier: true,
                        magnification: 1.18,
                        onSelectedItemChanged: _onWheel,
                        childDelegate: ListWheelChildLoopingListDelegate(
                          children: [
                            for (final value in widget.values)
                              Center(
                                child: Text(_text(value), style: numberStyle),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: typing ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !typing,
                    child: Center(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focus,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        style: numberStyle.copyWith(fontSize: 48),
                        decoration: InputDecoration(
                          // The box's own tint, so the field reads the same
                          // in either theme while typing.
                          filled: true,
                          fillColor: palette.tint,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: widget.onChanged,
                        onSubmitted: widget.onSubmitted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}

/// AM above PM, the chosen one filled and ticked.
class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.value, required this.onChanged});

  final DayPeriod value;
  final ValueChanged<DayPeriod> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    decoration: BoxDecoration(
      color: AppPalette.of(context).tint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        for (final (period, label) in [
          (DayPeriod.am, 'AM'),
          (DayPeriod.pm, 'PM'),
        ])
          Semantics(
            button: true,
            selected: value == period,
            child: Material(
              color: value == period ? purple : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: ValueKey('clock-$label'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(period),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: value == period
                              ? Colors.white
                              : AppPalette.of(context).ink,
                        ),
                      ),
                      if (value == period) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check, size: 16, color: Colors.white),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The time exactly as it will be saved, and roughly when in the day it is.
class _Preview extends StatelessWidget {
  const _Preview({required this.time, required this.problem, this.note});

  final TimeOfDay? time;
  final String? problem;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final time = this.time;
    final daytime = time != null && time.hour >= 6 && time.hour < 18;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.of(context).wash(const Color(0xfff7f3ff)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppPalette.of(context).wash(const Color(0xffe9e0ff)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              time == null
                  ? Icons.error_outline
                  : daytime
                  ? Icons.wb_sunny_rounded
                  : Icons.nightlight_round,
              color: AppPalette.of(context).accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time == null ? '--:--' : formatClock(time),
                  key: const ValueKey('clock-preview'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  time == null ? problem ?? '' : dayPeriodLabel(time),
                  style: TextStyle(
                    fontSize: 13,
                    color: time == null
                        ? AppPalette.of(
                            context,
                          ).foreground(const Color(0xffb3261e))
                        : AppPalette.of(context).muted,
                  ),
                ),
                if (note != null)
                  Text(
                    note!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.of(context).accent,
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
