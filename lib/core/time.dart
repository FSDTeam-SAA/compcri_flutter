import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

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

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String monthName(int month) => monthNames[(month - 1) % 12];

String formatDay(DateTime value) =>
    '${monthName(value.month)} ${value.day}, ${value.year}';

/// Short relative stamp for notification rows.
String relativeTime(DateTime? value) {
  if (value == null) return '';
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return formatDay(value);
}

/// Greeting used on the home header.
String greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
