import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'i18n.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device's IANA time zone, resolved once and cached.
///
/// The API validates this against `Intl.DateTimeFormat`, so an abbreviation
/// like `EST` from `DateTime.timeZoneName` would be rejected — we need the
/// full identifier, e.g. `America/New_York`.
class DeviceTimeZone {
  const DeviceTimeZone._();

  static String _cached = 'UTC';
  static bool _resolved = false;

  static String get current => _cached;

  static Future<String> resolve() async {
    if (_resolved) return _cached;
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (info.identifier.trim().isNotEmpty) _cached = info.identifier;
    } catch (_) {
      // Unsupported platform or plugin failure: UTC is a safe default.
    }
    _resolved = true;
    return _cached;
  }
}

/// Formats an instant the way the API expects: ISO 8601 with an offset.
/// UTC with a trailing `Z` satisfies the server's `datetime({ offset: true })`.
String isoUtc(DateTime value) => value.toUtc().toIso8601String();

/// Combines a picked calendar day and wall-clock time into a local instant.
DateTime combine(DateTime day, TimeOfDay time) =>
    DateTime(day.year, day.month, day.day, time.hour, time.minute);

/// Inclusive start of the day, in local time.
DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Today stays editable for the whole day; only earlier dates are locked.
bool isPastDay(DateTime value, {DateTime? now}) =>
    startOfDay(value).isBefore(startOfDay(now ?? DateTime.now()));

DateTime endOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

/// The Sunday-anchored week containing [value].
DateTime startOfWeek(DateTime value) =>
    startOfDay(value).subtract(Duration(days: value.weekday % 7));

/// A generous window used when loading the calendar, so month navigation and
/// "today" both have data without a refetch per tap.
({DateTime from, DateTime to}) monthWindow(DateTime anchor) => (
  from: DateTime(anchor.year, anchor.month - 1, 1),
  to: DateTime(anchor.year, anchor.month + 2, 1),
);

/// The month's name in the app's language.
String monthName(int month) =>
    DateFormat.MMMM(I18n.dateLocale).format(DateTime(2000, month));

/// A full date the way the app's language writes it: "September 14, 2026",
/// "14 de setembro de 2026", "14 de septiembre de 2026".
String formatDay(DateTime value) =>
    DateFormat.yMMMMd(I18n.dateLocale).format(value);

/// Where a new event starts by default: the next full hour today, so a fresh
/// form never opens on a time that has already gone. Late in the evening it
/// stays on today rather than quietly moving to tomorrow.
DateTime upcomingStart(DateTime now) {
  final next = DateTime(now.year, now.month, now.day, now.hour + 1);
  if (DateUtils.isSameDay(next, now)) return next;
  final minutes = ((now.hour * 60 + now.minute) ~/ 5 + 1) * 5;
  return DateTime(
    now.year,
    now.month,
    now.day,
    0,
    minutes.clamp(0, 23 * 60 + 55),
  );
}

/// A date with its weekday: "Fri, Oct 2, 2026", "sex., 2 de out. de 2026".
String formatWeekdayDay(DateTime value) =>
    DateFormat.yMMMEd(I18n.dateLocale).format(value);

/// A short date: "Oct 2, 2026", "2 de out. de 2026".
String formatShortDay(DateTime value) =>
    DateFormat.yMMMd(I18n.dateLocale).format(value);

/// Short relative stamp for notification rows.
String relativeTime(DateTime? value) {
  if (value == null) return '';
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return tr('just now');
  if (difference.inMinutes < 60) {
    return tr('{minutes}m ago', {'minutes': difference.inMinutes});
  }
  if (difference.inHours < 24) {
    return tr('{hours}h ago', {'hours': difference.inHours});
  }
  if (difference.inDays < 7) {
    return tr('{days}d ago', {'days': difference.inDays});
  }
  return formatDay(value);
}

/// Greeting used on the home header.
String greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return tr('Good morning');
  if (hour < 17) return tr('Good afternoon');
  return tr('Good evening');
}

/// How clock times are written. The server stores the same three values.
enum TimeFormat {
  auto('AUTO', 'Automatic'),
  h12('H12', '12-hour (AM/PM)'),
  h24('H24', '24-hour');

  const TimeFormat(this.server, this.label);
  final String server;
  final String label;

  static TimeFormat fromServer(String? value) => values.firstWhere(
    (format) => format.server == value,
    orElse: () => TimeFormat.auto,
  );
}

/// The clock format the whole app writes times in: 3:00 PM or 15:00.
///
/// Automatic follows the phone's own 12/24-hour setting, so an American phone
/// reads 3:00 PM and a Brazilian one 15:00 without anyone choosing. Only how a
/// time is written changes — never the time an event is stored at.
class ClockFormat {
  const ClockFormat._();

  static const _key = 'app.timeFormat';
  static final ValueNotifier<TimeFormat> _preference = ValueNotifier(
    TimeFormat.auto,
  );

  /// Rebuilds the app shell whenever the format changes.
  static ValueListenable<TimeFormat> get listenable => _preference;
  static TimeFormat get preference => _preference.value;

  /// Stands in for the phone's setting in tests.
  @visibleForTesting
  static bool? debugDeviceUses24Hour;

  /// The phone's own 12/24-hour setting.
  static bool get deviceUses24Hour =>
      debugDeviceUses24Hour ??
      PlatformDispatcher.instance.alwaysUse24HourFormat;

  static bool get use24 => switch (preference) {
    TimeFormat.h24 => true,
    TimeFormat.h12 => false,
    TimeFormat.auto => deviceUses24Hour,
  };

  /// Opens in the format chosen last time on this phone.
  static Future<void> restore() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      _preference.value = TimeFormat.fromServer(saved);
    } catch (_) {
      // No storage: Automatic is the right default anyway.
    }
  }

  /// Switches every time on screen to [format] and remembers it.
  static Future<void> apply(TimeFormat format) async {
    _preference.value = format;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        format.server,
      );
    } catch (_) {
      // Remembering is a convenience; the switch itself already happened.
    }
  }

  /// For tests: back to Automatic without touching storage.
  @visibleForTesting
  static void reset() {
    _preference.value = TimeFormat.auto;
    debugDeviceUses24Hour = null;
  }
}

/// A clock time in the chosen format: "3:00 PM" or "15:00". Noon is 12:00 PM
/// and midnight 12:00 AM; an hour past 12 never carries AM or PM.
String formatClock(TimeOfDay time, {bool? use24}) {
  final minute = time.minute.toString().padLeft(2, '0');
  if (use24 ?? ClockFormat.use24) {
    return '${time.hour.toString().padLeft(2, '0')}:$minute';
  }
  return '${hour12Of(time)}:$minute ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
}

/// The clock time of an instant, in the chosen format.
String formatClockAt(DateTime value, {bool? use24}) =>
    formatClock(TimeOfDay.fromDateTime(value), use24: use24);

/// "9:00 AM – 10:00 AM" / "09:00 – 10:00".
String formatClockRange(DateTime startsAt, DateTime endsAt) =>
    '${formatClockAt(startsAt)} – ${formatClockAt(endsAt)}';

/// An hour on its own, for time axes: "3 PM" or "15:00".
String formatHour(int hour) {
  hour %= 24; // The line closing a day view is midnight, not "12 PM".
  if (ClockFormat.use24) return '${hour.toString().padLeft(2, '0')}:00';
  final time = TimeOfDay(hour: hour, minute: 0);
  return '${hour12Of(time)} ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
}

/// The hour on a 12-hour dial: 12, 1, 2 … 11.
int hour12Of(TimeOfDay time) => time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;

/// "1 hour", "45 minutes", "1 hour 30 minutes".
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final parts = [
    if (hours == 1) tr('1 hour'),
    if (hours > 1) tr('{count} hours', {'count': hours}),
    if (minutes == 1) tr('1 minute'),
    if (minutes > 1) tr('{count} minutes', {'count': minutes}),
  ];
  return parts.isEmpty ? tr('{count} minutes', {'count': 0}) : parts.join(' ');
}

/// The part of the day a time falls in, as people say it.
String dayPeriodLabel(TimeOfDay time) => switch (time.hour) {
  >= 5 && < 12 => tr('Morning'),
  >= 12 && < 17 => tr('Afternoon'),
  >= 17 && < 21 => tr('Evening'),
  _ => tr('Night'),
};
