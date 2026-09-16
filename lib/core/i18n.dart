import 'dart:ui' show PlatformDispatcher, TextHeightBehavior;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart' hide Text;
import 'package:intl/intl.dart' show Intl;
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

/// The language the app speaks.
///
/// English is written inline throughout the code and doubles as the lookup
/// key: the other languages translate those English strings in
/// [translations]. Anything without a translation stays as written, so user
/// content — event titles, names, notes — passes through untouched.
class I18n {
  const I18n._();

  static const supported = ['en', 'pt', 'es'];
  static const _localeKey = 'app.locale';

  static final ValueNotifier<String> _locale = ValueNotifier('en');

  /// Rebuilds the app shell whenever the language changes.
  static ValueListenable<String> get listenable => _locale;
  static String get locale => _locale.value;

  /// The locale date formatting uses. English maps to `en_US`, the one set of
  /// month and weekday names intl ships without loading anything first.
  static String get dateLocale => locale == 'en' ? 'en_US' : locale;

  static String _supportedOr(String? code) =>
      supported.contains(code) ? code! : 'en';

  /// Opens in the language chosen last time, or the device's language when it
  /// is one the app speaks.
  static Future<void> restore() async {
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_localeKey);
    } catch (_) {
      // No storage (tests, a locked-down device): fall back to the device.
    }
    _set(saved ?? PlatformDispatcher.instance.locale.languageCode);
  }

  /// Switches the whole app — its own text, dates, pickers — to [code], and
  /// remembers it for the next launch.
  static Future<void> apply(String code) async {
    _set(code);
    try {
      await (await SharedPreferences.getInstance()).setString(
        _localeKey,
        locale,
      );
    } catch (_) {
      // Remembering is a convenience; the switch itself already happened.
    }
  }

  static void _set(String code) {
    final next = _supportedOr(code);
    _locale.value = next;
    Intl.defaultLocale = dateLocale;
  }

  /// For tests: back to English without touching storage.
  @visibleForTesting
  static void reset() => _set('en');
}

/// [text] in the current language, with `{name}` placeholders filled in from
/// [args].
///
/// A key may be written as `context|Text` when one English word needs
/// different translations in different places — "All" is masculine for
/// contacts but feminine for notifications in Portuguese. Only the full key is
/// looked up; English falls back to the part after the bar, so the source
/// language is unaffected.
String tr(String text, [Map<String, Object?> args = const {}]) {
  final bar = text.indexOf('|');
  var result =
      translations[I18n.locale]?[text] ??
      (bar == -1 ? text : text.substring(bar + 1));
  args.forEach((key, value) => result = result.replaceAll('{$key}', '$value'));
  return result;
}

/// The singular or plural form for [count], with `{count}` filled in.
String trCount(int count, String one, String other) =>
    tr(count == 1 ? one : other, {'count': count});

/// Drop-in for Flutter's `Text` that shows its string in the current language.
///
/// Screens import this in place of the material `Text`, so a literal like
/// `Text('Save')` translates itself without every call site changing. It
/// depends on the app's [Localizations], so switching language rebuilds it
/// even when it was built as a `const`.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    Localizations.maybeLocaleOf(context);
    return material.Text(
      tr(data),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null ? null : tr(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
