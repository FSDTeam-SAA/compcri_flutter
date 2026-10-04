import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/i18n.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/core/time.dart';
import 'package:compcri_flutter/features/events.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';

import 'app_test.dart' show FakeBackend, bootedStore, calendarId;

http.Response ok(Object body) => http.Response(
  jsonEncode({'success': true, 'data': body}),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting();
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  tearDown(() {
    I18n.reset();
    ClockFormat.reset();
  });

  final eventJson = <String, dynamic>{
    '_id': '65b1f77bcf86cd7994390102',
    'calendarId': calendarId,
    'title': 'Property viewing',
    'startsAt': DateTime(2030, 10, 3, 10, 30).toUtc().toIso8601String(),
    'endsAt': DateTime(2030, 10, 3, 11, 30).toUtc().toIso8601String(),
    'reminderMinutes': [0, 15],
    'timeZone': 'America/Sao_Paulo',
    '__v': 0,
  };

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_EDITOR')) return;
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('/tmp/compcri-editor-preview');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  for (final language in ['en', 'pt', 'es']) {
    for (final dark in [false, true]) {
      testWidgets(
        'compact editor and reminder sheet fit in $language ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = const Size(393, 852);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = await bootedStore(tester, FakeBackend());
          await tester.runAsync(() => I18n.apply(language));
          ClockFormat.debugDeviceUses24Hour = false;
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: StoreScope(
                notifier: store,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(language),
                  supportedLocales: [
                    for (final code in I18n.supported) Locale(code),
                  ],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: dark ? darkAppTheme : appTheme,
                  initialRoute: '/editor',
                  home: const Scaffold(),
                  routes: {
                    '/editor': (_) =>
                        EventForm(event: CalendarEvent.fromJson(eventJson)),
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final save = find.widgetWithText(TextButton, tr('Save Changes'));
          expect(save.hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('event-reminder')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('event-repeat')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            boundary,
            'editor-$language-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.byKey(const ValueKey('event-reminder')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('reminder-apply')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            boundary,
            'reminder-$language-${dark ? 'dark' : 'light'}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'save and apply remain reachable with large text on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await bootedStore(tester, FakeBackend());
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: EventForm(event: CalendarEvent.fromJson(eventJson)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextButton, 'Save Changes').hitTestable(),
        findsOneWidget,
      );
      final reminder = find.byKey(const ValueKey('event-reminder'));
      await tester.ensureVisible(reminder);
      await tester.tap(reminder);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reminder-apply')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final changeRepeat in [false, true]) {
    testWidgets(
      'series save ${changeRepeat ? 'applies the new repeat choice' : 'preserves the existing recurrence rule'}',
      (tester) async {
        final row = {...eventJson, 'recurrenceRrule': 'FREQ=DAILY;COUNT=3'};
        Map<String, dynamic>? written;
        final backend = FakeBackend()
          ..handler = (request) async {
            if (request.method == 'PATCH' &&
                request.url.path.endsWith('/events/${row['_id']}')) {
              written = jsonDecode(request.body) as Map<String, dynamic>;
              return ok({'event': row, 'conflicts': []});
            }
            return null;
          };
        final store = await bootedStore(tester, backend);
        await tester.pumpWidget(
          StoreScope(
            notifier: store,
            child: MaterialApp(
              theme: appTheme,
              home: EventForm(event: CalendarEvent.fromJson(row)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (changeRepeat) {
          await tester.tap(find.byKey(const ValueKey('event-repeat')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Weekly'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.widgetWithText(TextButton, 'Save Changes'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (changeRepeat) expect(find.text('This event'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'All events'));
        await tester.pumpAndSettle();
        expect(written?['reminderMinutes'], [0, 15]);
        expect(
          written?['recurrenceRrule'],
          changeRepeat ? 'RRULE:FREQ=WEEKLY' : 'FREQ=DAILY;COUNT=3',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
