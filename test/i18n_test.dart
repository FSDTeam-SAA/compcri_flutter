import 'dart:io';

import 'package:compcri_flutter/core/i18n.dart';
import 'package:compcri_flutter/core/translations.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(I18n.reset);

  test('Portuguese and Spanish cover exactly the same strings', () {
    final pt = translations['pt']!.keys.toSet();
    final es = translations['es']!.keys.toSet();
    expect(pt.difference(es), isEmpty, reason: 'missing in Spanish');
    expect(es.difference(pt), isEmpty, reason: 'missing in Portuguese');
  });

  test('every translation keeps the placeholders of its English text', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    Set<String> names(String text) =>
        placeholder.allMatches(text).map((match) => match.group(1)!).toSet();
    translations.forEach((language, strings) {
      strings.forEach((english, translated) {
        expect(
          names(translated),
          names(english),
          reason: '$language: $english',
        );
      });
    });
  });

  test('every literal a screen shows has a translation', () {
    // The two ways a screen shows words: a Text widget or a tr() call.
    final shown = RegExp(
      r"(?:\bText\(\s*|\btr\(\s*|\btrCount\([^,]+,\s*)'((?:[^'\\$]|\\.)*)'",
    );
    final missing = <String>{};
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              !file.path.endsWith('translations.dart') &&
              !file.path.endsWith('markdown.dart'),
        );
    for (final file in sources) {
      for (final match in shown.allMatches(file.readAsStringSync())) {
        final text = match.group(1)!.replaceAll(r'\n', '\n');
        if (!RegExp('[A-Za-z]').hasMatch(text)) continue;
        for (final language in ['pt', 'es']) {
          if (!translations[language]!.containsKey(text)) {
            missing.add('$language: $text');
          }
        }
      }
    }
    expect(missing, isEmpty);
  });

  test('placeholders and plurals are filled in the current language', () async {
    await I18n.apply('pt');
    expect(tr('{count} events', {'count': 3}), '3 eventos');
    expect(trCount(1, '{count} member', '{count} members'), '1 membro');
    await I18n.apply('es');
    expect(
      tr('Booked for {day} at {time}', {'day': 'Hoy', 'time': '10:00'}),
      'Programado para Hoy a las 10:00',
    );
    // Anything without a translation, such as user content, stays as written.
    expect(tr('Weekly sync with Ana'), 'Weekly sync with Ana');
    // Unsupported languages fall back to English.
    await I18n.apply('de');
    expect(I18n.locale, 'en');
  });

  testWidgets('switching language re-renders open screens in place', (
    tester,
  ) async {
    await initializeDateFormatting();
    await tester.pumpWidget(
      ValueListenableBuilder<String>(
        valueListenable: I18n.listenable,
        builder: (context, locale, _) => MaterialApp(
          locale: Locale(locale),
          supportedLocales: [for (final code in I18n.supported) Locale(code)],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(body: Text('Save Changes')),
        ),
      ),
    );
    expect(find.text('Save Changes'), findsOneWidget);

    await tester.runAsync(() => I18n.apply('pt'));
    await tester.pumpAndSettle();
    expect(find.text('Salvar alterações'), findsOneWidget);

    await tester.runAsync(() => I18n.apply('es'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar cambios'), findsOneWidget);
  });
}
