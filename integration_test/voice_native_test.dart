import 'dart:async';
import 'dart:convert';
import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/dashboard.dart';
import 'package:compcri_flutter/features/voice_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Samples come from scripts/verify-voice.js via --dart-define-from-file.
// The HTTP layer uses synthetic fixtures; platform playback and recording are real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int attempts = 100,
  }) async {
    for (var i = 0; i < attempts; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    expect(
      finder,
      findsOneWidget,
      reason: tester.allWidgets
          .whereType<RichText>()
          .map((widget) => widget.text.toPlainText())
          .join(' | '),
    );
  }

  testWidgets('native audio: four MP3 previews and recording after playback', (
    tester,
  ) async {
    const clips = {
      'echo': String.fromEnvironment('VOICE_QA_ECHO'),
      'onyx': String.fromEnvironment('VOICE_QA_ONYX'),
      'nova': String.fromEnvironment('VOICE_QA_NOVA'),
      'shimmer': String.fromEnvironment('VOICE_QA_SHIMMER'),
    };
    expect(
      clips.values.every((clip) => clip.isNotEmpty),
      isTrue,
      reason: 'Provide the live-provider MP3 fixtures',
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({});
    final requested = <String>[];
    final store = AppStore(
      api: Api(
        ApiClient(
          client: MockClient((request) async {
            final voice = request.url.path.split('/')[5];
            requested.add(voice);
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'base64': clips[voice], 'contentType': 'audio/mpeg'},
              }),
              200,
            );
          }),
        ),
      ),
    );
    await tester.pumpWidget(
      StoreScope(
        notifier: store,
        child: MaterialApp(
          theme: appTheme,
          home: const ConversationScreen(voiceMode: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final voice in ['Echo', 'Onyx', 'Nova', 'Shimmer']) {
      await tester.tap(find.text('Nova'));
      await tester.pumpAndSettle();
      expect(find.byType(VoicePicker), findsOneWidget);
      final row = find.ancestor(
        of: find.text(voice),
        matching: find.byType(RadioListTile<String>),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byTooltip('Play sample')),
      );
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .text('Aurox Day is speaking', skipOffstage: false)
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(
        find.text('Aurox Day is speaking', skipOffstage: false),
        findsOneWidget,
        reason: '$voice must start native playback',
      );
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .text('Aurox Day is speaking', skipOffstage: false)
            .evaluate()
            .isEmpty) {
          break;
        }
      }
      expect(
        find.text('Aurox Day is speaking', skipOffstage: false),
        findsNothing,
        reason: '$voice must finish playback',
      );
      expect(find.text('That sample could not be played.'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(VoiceOrb));
      // A fresh QA install needs its system microphone prompt accepted.
      await waitFor(tester, find.text('Listening to you'), attempts: 450);
      expect(
        find.text('Listening to you'),
        findsOneWidget,
        reason:
            'The mic must reclaim the session after $voice: ${tester.allWidgets.whereType<RichText>().map((widget) => widget.text.toPlainText()).join(' | ')}',
      );
      await tester.tap(find.byTooltip('Cancel recording'));
      await tester.pumpAndSettle();
    }
    expect(requested, ['echo', 'onyx', 'nova', 'shimmer']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets(
    'native audio: spoken turns, muted recovery and ending a pending reply',
    (tester) async {
      const clip = String.fromEnvironment('VOICE_QA_NOVA');
      expect(clip, isNotEmpty);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      SharedPreferences.setMockInitialValues({});
      final pending = Completer<http.Response>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(http.Response('', 500));
      });
      final uploadedTo = <String>[];
      http.Response reply({bool speak = true}) => http.Response(
        [
          {
            'type': 'transcript',
            'transcription': {'text': 'Olá'},
          },
          {
            'type': 'done',
            'message': {
              '_id': 'reply-${uploadedTo.length}',
              'role': 'ASSISTANT',
              'content': 'Olá, como posso ajudar?',
            },
            'pendingActions': [],
            'transcription': {'text': 'Olá'},
          },
          if (speak)
            {'type': 'audio', 'base64': clip, 'index': 0, 'last': true},
        ].map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
        200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
      final store = AppStore(
        api: Api(
          ApiClient(
            client: MockClient((request) async {
              if (request.method == 'POST') {
                uploadedTo.add(request.url.path);
                if (uploadedTo.length == 4) return pending.future;
                return reply(speak: uploadedTo.length != 3);
              }
              return http.Response(
                jsonEncode({
                  'success': true,
                  'data': {
                    '_id': 'thread',
                    'title': 'Native voice QA',
                    'messages': [],
                  },
                }),
                200,
              );
            }),
          ),
        ),
      );
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            home: const ConversationScreen(
              conversationId: 'thread',
              voiceMode: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hands-free off'));
      await tester.tap(find.text('Hands-free off'));
      await waitFor(tester, find.text('Listening to you'));
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byType(VoiceOrb));
        await waitFor(tester, find.text('Aurox Day is speaking'));
        await waitFor(tester, find.text('Listening to you'));
        expect(uploadedTo, hasLength(i + 1));
      }
      await tester.tap(find.byTooltip('End call'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mute spoken replies'));
      await tester.tap(find.text('Hands-free off'));
      await waitFor(tester, find.text('Listening to you'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byType(VoiceOrb));
      for (var i = 0; i < 100 && uploadedTo.length != 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(uploadedTo, hasLength(3));
      await waitFor(tester, find.text('Listening to you'));
      await tester.tap(find.byTooltip('End call'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Enable spoken replies'));
      await tester.tap(find.text('Hands-free off'));
      await waitFor(tester, find.text('Listening to you'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byType(VoiceOrb));
      for (var i = 0; i < 100 && uploadedTo.length != 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(uploadedTo, hasLength(4));
      await tester.tap(find.byTooltip('End call'));
      await tester.pumpAndSettle();
      pending.complete(reply());
      await tester.pumpAndSettle();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Aurox Day is speaking'), findsNothing);
        expect(find.text('Listening to you'), findsNothing);
      }
      expect(
        uploadedTo.toSet(),
        hasLength(1),
        reason: 'Every voice turn must use the same conversation',
      );
      expect(find.text('Olá, como posso ajudar?'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
