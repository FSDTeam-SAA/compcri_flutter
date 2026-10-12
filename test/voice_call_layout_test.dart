import 'dart:io';
import 'dart:ui' as ui;

import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/features/voice_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  for (final width in [320.0, 393.0]) {
    testWidgets(
      'call controls and orb stay usable at $width with the keyboard',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 24);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.reset);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final input = TextEditingController();
        final scroll = ScrollController();
        addTearDown(input.dispose);
        addTearDown(scroll.dispose);
        final sent = <String>[];
        var resumed = false;
        var closed = false;
        var pickedVoice = false;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: darkAppTheme,
            home: RepaintBoundary(
              key: boundary,
              child: VoiceCallBackdrop(
                child: Scaffold(
                  body: SafeArea(
                    child: Builder(
                      builder: (context) => VoiceExperience(
                        recording: false,
                        busy: false,
                        sending: false,
                        speaking: false,
                        muted: false,
                        seconds: 0,
                        level: 0,
                        hasMessages: false,
                        hasRetry: false,
                        retryIsEmpty: false,
                        canReplay: false,
                        onRecord: () {},
                        onCancel: () {},
                        onRetry: () {},
                        onDiscard: () {},
                        onMute: () {},
                        onReplay: () {},
                        onSend: sent.add,
                        assistantName: 'Aurox Day',
                        onHandsFree: (value) => resumed = value,
                        onPickVoice: () => pickedVoice = true,
                        handsFree: false,
                        voiceLabel: 'Aria',
                        controller: input,
                        scroll: scroll,
                        messages: const SizedBox.shrink(),
                        minimal: true,
                        keyboardOpen:
                            MediaQuery.viewInsetsOf(context).bottom > 0,
                        onClose: () => closed = true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/artwork/glass_orb.png'),
            tester.element(find.byType(VoiceOrb)),
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Voice'));
        expect(pickedVoice, isTrue);
        tester.view.viewInsets = const FakeViewPadding(bottom: 272);
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('hands-free-text'));
        final orb = find.byType(VoiceOrb);
        expect(orb.hitTestable(), findsOneWidget);
        expect(
          find.byTooltip('Resume hands-free').hitTestable(),
          findsOneWidget,
        );
        expect(find.byTooltip('End call').hitTestable(), findsOneWidget);
        expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(428));
        expect(
          tester.widget<TextField>(field).keyboardAppearance,
          Brightness.dark,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == 'Send',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        if (width == 393) {
          await tester.runAsync(() async {
            final rendering =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final picture = await rendering.toImage(pixelRatio: 2);
            final png = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'design_review/rendered/voice_call_reference.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.enterText(field, 'Plan my afternoon');
        await tester.pump();
        await tester.tap(find.byTooltip('Send'));
        expect(sent, ['Plan my afternoon']);
        await tester.tap(orb);
        expect(resumed, isTrue);
        await tester.tap(find.byTooltip('End call'));
        expect(closed, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
