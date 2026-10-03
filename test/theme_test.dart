import 'dart:io';
import 'dart:ui' as ui;

import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/markdown.dart';
import 'package:compcri_flutter/features/settings.dart';
import 'package:compcri_flutter/features/dashboard.dart';
import 'package:compcri_flutter/features/time_picker.dart';
import 'package:compcri_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' show FakeBackend, bootedStore, pumpApp;

Brightness brightnessAt(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder.first)).brightness;

double contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return ((first > second ? first : second) + .05) /
      ((first < second ? first : second) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
  });
  setUp(() {
    AppAppearance.reset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });
  tearDown(() {
    AppAppearance.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          null,
        );
  });

  test('appearance defaults to system and restores saved choices', () async {
    SharedPreferences.setMockInitialValues({});
    await AppAppearance.restore();
    expect(AppAppearance.mode, ThemeMode.system);
    for (final mode in ThemeMode.values) {
      await AppAppearance.apply(mode);
      AppAppearance.reset();
      await AppAppearance.restore();
      expect(AppAppearance.mode, mode);
    }
    SharedPreferences.setMockInitialValues({
      AppAppearance.storageKey: 'invalid',
    });
    await AppAppearance.restore();
    expect(AppAppearance.mode, ThemeMode.system);
  });

  test('text and accent colors meet normal text contrast on both palettes', () {
    for (final palette in [AppPalette.light, AppPalette.night]) {
      for (final foreground in [palette.ink, palette.muted, palette.accent]) {
        expect(
          contrast(foreground, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('filled buttons and semantic colors have legible foregrounds', () {
    for (final color in violetGradient.colors) {
      expect(contrast(Colors.white, color), greaterThanOrEqualTo(4.5));
    }
    for (final theme in [appTheme, darkAppTheme]) {
      final scheme = theme.colorScheme;
      expect(contrast(scheme.onError, scheme.error), greaterThanOrEqualTo(4.5));
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('Markdown links and quotes follow the active palette', (
    tester,
  ) async {
    for (final theme in [darkAppTheme, appTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: MarkdownText('[Link](https://example.com)\n\n> Quote'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final colors = <Color>[];
      void collect(InlineSpan span) {
        if (span.style?.color != null) colors.add(span.style!.color!);
        if (span is TextSpan) {
          for (final child in span.children ?? <InlineSpan>[]) {
            collect(child);
          }
        }
      }

      for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
        collect(text.text);
      }
      final palette = theme.extension<AppPalette>()!;
      expect(colors, contains(palette.accent));
      expect(colors, contains(palette.muted));
    }
  });

  testWidgets(
    'appearance switches foregrounds and backgrounds on the first frame',
    (tester) async {
      final store = await bootedStore(tester, FakeBackend());
      await pumpApp(tester, store);
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        await tester.runAsync(() => AppAppearance.apply(mode));
        await tester.pump();
        final colors = AppPalette.of(
          tester.element(find.byType(CreateEventButton)),
        );
        expect(colors.dark, mode == ThemeMode.dark);
        expect(contrast(colors.ink, colors.surface), greaterThanOrEqualTo(4.5));
      }
    },
  );

  testWidgets('appearance changes the current screen and survives navigation', (
    tester,
  ) async {
    final store = await bootedStore(tester, FakeBackend());
    await pumpApp(tester, store);
    navigatorKey.currentState!.pushNamed('/appearance');
    await tester.pumpAndSettle();
    expect(find.text('Follow System'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(AppAppearance.mode, ThemeMode.dark);
    expect(
      brightnessAt(tester, find.byType(AppearanceScreen)),
      Brightness.dark,
    );
    final colors = AppPalette.of(tester.element(find.byType(AppearanceScreen)));
    final card = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(Surface),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (card.decoration! as BoxDecoration).color!.computeLuminance(),
      lessThan(.1),
    );
    final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(overlay.value.statusBarIconBrightness, Brightness.light);
    expect(overlay.value.systemNavigationBarColor, colors.canvas);
    await tester.runAsync(() async {
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppAppearance.storageKey,
        ),
        'dark',
      );
    });
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(
      brightnessAt(tester, find.byType(CreateEventButton)),
      Brightness.dark,
    );
    navigatorKey.currentState!.pushNamed('/appearance');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(
      brightnessAt(tester, find.byType(AppearanceScreen)),
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('follow system responds live; explicit choices override device', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = await bootedStore(tester, FakeBackend());
    await pumpApp(tester, store);
    expect(
      brightnessAt(tester, find.byType(CreateEventButton)),
      Brightness.light,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      brightnessAt(tester, find.byType(CreateEventButton)),
      Brightness.dark,
    );
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.light));
    await tester.pumpAndSettle();
    expect(
      brightnessAt(tester, find.byType(CreateEventButton)),
      Brightness.light,
    );
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.dark));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      brightnessAt(tester, find.byType(CreateEventButton)),
      Brightness.dark,
    );
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.system));
    await tester.pumpAndSettle();
    expect(
      brightnessAt(tester, find.byType(CreateEventButton)),
      Brightness.light,
    );
  });

  testWidgets('main tabs and event fields render in dark mode', (tester) async {
    final backend = FakeBackend()
      ..conversations = [
        {
          '_id': 'chat-1',
          'title': 'Plan my day',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];
    final store = await bootedStore(tester, backend);
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.dark));
    await pumpApp(tester, store);
    for (final tab in ['Home', 'AI Chat', 'Calendar', 'Network']) {
      await tester.tap(find.byTooltip(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
      final backdrop = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(Backdrop),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final gradient =
          (backdrop.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(
        gradient.colors.every((color) => color.computeLuminance() < .1),
        isTrue,
      );
      await capture(tester, tab);
    }
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.light));
    await tester.pumpAndSettle();
    for (final tab in ['Home', 'AI Chat', 'Calendar', 'Network']) {
      await tester.tap(find.byTooltip(tab));
      await tester.pumpAndSettle();
      expect(brightnessAt(tester, find.byType(Scaffold)), Brightness.light);
      expect(tester.takeException(), isNull, reason: tab);
      await capture(tester, tab);
    }
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create Event'));
    await tester.pumpAndSettle();
    final field = tester.element(find.byType(TextFormField).first);
    expect(
      Theme.of(field).inputDecorationTheme.fillColor!.computeLuminance(),
      lessThan(.1),
    );
    expect(
      Theme.of(field).textTheme.bodyLarge!.color!.computeLuminance(),
      greaterThan(.7),
    );
    expect(tester.takeException(), isNull);
    await capture(tester, 'Event');
    final context = tester.element(find.byType(PageFrame).first);
    final result = confirm(context, 'Confirm', 'Dark dialog');
    await tester.pumpAndSettle();
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor!.computeLuminance(), lessThan(.1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('custom clock picker uses dark fields and a dark sheet', (
    tester,
  ) async {
    final store = await bootedStore(tester, FakeBackend());
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.dark));
    await pumpApp(tester, store);
    final context = tester.element(find.byType(CreateEventButton));
    final result = showClockPicker(
      context,
      title: 'Start time',
      date: DateTime.now(),
      initial: const TimeOfDay(hour: 15, minute: 30),
    );
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor!.computeLuminance(), lessThan(.1));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.style!.color!.computeLuminance(), greaterThan(.7));
      expect(field.decoration!.fillColor!.computeLuminance(), lessThan(.1));
    }
    expect(tester.takeException(), isNull);
    await capture(tester, 'clock', find.byType(BottomSheet));
    await tester.runAsync(() => AppAppearance.apply(ThemeMode.light));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BottomSheet>(find.byType(BottomSheet))
          .backgroundColor!
          .computeLuminance(),
      greaterThan(.7),
    );
    expect(
      tester
          .widget<TextField>(find.byType(TextField).first)
          .style!
          .color!
          .computeLuminance(),
      lessThan(.1),
    );
    await tester.tap(find.text('Confirm time'));
    await tester.pumpAndSettle();
    expect(await result, const TimeOfDay(hour: 15, minute: 30));
  });

  testWidgets('an open contact dialog follows live system appearance', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = await bootedStore(tester, FakeBackend());
    await pumpApp(tester, store);
    await tester.tap(find.byTooltip('Network'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add Contact'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AlertDialog>(find.byType(AlertDialog))
          .backgroundColor!
          .computeLuminance(),
      greaterThan(.7),
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AlertDialog>(find.byType(AlertDialog))
          .backgroundColor!
          .computeLuminance(),
      lessThan(.1),
    );
    expect(tester.takeException(), isNull);
    await capture(tester, 'contact-dialog', find.byType(AlertDialog));
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
  });

  for (final voiceMode in [false, true]) {
    testWidgets('conversation renders in dark mode (voice: $voiceMode)', (
      tester,
    ) async {
      final store = await bootedStore(tester, FakeBackend());
      await tester.runAsync(() => AppAppearance.apply(ThemeMode.dark));
      await pumpApp(tester, store);
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(voiceMode: voiceMode),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        brightnessAt(tester, find.byType(ConversationScreen)),
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      for (final button in tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      )) {
        final background = button.style?.backgroundColor?.resolve({});
        if (background != null && background.computeLuminance() < .2) {
          expect(button.style!.foregroundColor!.resolve({}), Colors.white);
        }
      }
      await capture(tester, voiceMode ? 'voice' : 'conversation');
    });
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final route in [
      '/login',
      '/onboarding',
      '/appearance',
      '/notifications',
      '/notes',
      '/subscription',
      '/profile',
      '/profile/edit',
      '/general',
      '/password',
      '/delete',
      '/notification-settings',
      '/language',
      '/time-format',
      '/assistants',
      '/assistant/add',
      '/summary',
      '/contact-us',
      '/terms',
      '/privacy',
      '/signup',
      '/forgot',
      '/requests',
    ]) {
      testWidgets('$route renders in ${mode.name} mode without layout errors', (
        tester,
      ) async {
        final store = await bootedStore(tester, FakeBackend());
        await tester.runAsync(() => AppAppearance.apply(mode));
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(MyApp(store: store, initialRoute: route));
        await tester.pumpAndSettle();
        expect(
          brightnessAt(tester, find.byType(Scaffold)),
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, route.substring(1));
      });
    }
  }
}

/// Optional screenshots for local visual review, without golden-file coupling.
Future<void> capture(WidgetTester tester, String name, [Finder? target]) async {
  if (!const bool.fromEnvironment('CAPTURE_THEME')) return;
  final element = tester.element((target ?? find.byType(Scaffold)).first);
  RenderObject? object = element.findRenderObject();
  while (object != null && object is! RenderRepaintBoundary) {
    object = object.parent;
  }
  await tester.runAsync(() async {
    final picture = await (object! as RenderRepaintBoundary).toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('/tmp/compcri-theme-preview');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/${AppAppearance.mode.name}-${name.replaceAll('/', '-')}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
