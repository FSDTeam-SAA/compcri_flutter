import 'dart:convert';
import 'dart:io';
import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // The voice screen restores the remembered voice/hands-free settings.
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      'com.llfbandit.record/messages',
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
  });
  for (final failFirst in [false, true]) {
    testWidgets(
      failFirst
          ? 'a failed voice upload keeps the recording for retry'
          : 'voice transcript replaces the pending message in the same screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final temp = Directory.systemTemp.createTempSync('voice-ui-test-');
        final recording = File('${temp.path}/message.m4a')
          ..writeAsBytesSync([1, 2, 3, 4]);
        addTearDown(() {
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });
        var attempts = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/voice-messages')) {
            attempts++;
            if (failFirst && attempts == 1) {
              return http.Response(
                jsonEncode({
                  'success': false,
                  'message': 'Please try again',
                  'error': {
                    'code': 'AI_UNAVAILABLE',
                    'message': 'Please try again',
                  },
                }),
                503,
              );
            }
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'message': {
                    '_id': 'reply',
                    'role': 'ASSISTANT',
                    'content': 'What time works for you?',
                  },
                  'transcription': {
                    'text': 'Schedule a meeting with Ana tomorrow.',
                  },
                  'audio': {'available': false},
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                '_id': 'thread',
                'title': 'Planning with Aria',
                'calendarId': 'calendar',
                'messages': [],
              },
            }),
            200,
          );
        });
        final store = AppStore(api: Api(ApiClient(client: client)));
        await tester.pumpWidget(
          StoreScope(
            notifier: store,
            child: MaterialApp(
              theme: appTheme,
              home: ConversationScreen(
                conversationId: 'thread',
                voiceMode: true,
                audioPath: recording.path,
              ),
            ),
          ),
        );
        Future<void> finishUpload() async {
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pumpAndSettle();
            if (find.text('Retry send').evaluate().isNotEmpty ||
                find
                    .text('Schedule a meeting with Ana tomorrow.')
                    .evaluate()
                    .isNotEmpty) {
              break;
            }
          }
        }

        await finishUpload();
        if (failFirst) {
          expect(recording.existsSync(), isTrue);
          expect(find.text('Retry send'), findsOneWidget);
          await tester.tap(find.text('Retry send'));
          await finishUpload();
        }
        expect(attempts, failFirst ? 2 : 1);
        expect(
          find.text('Schedule a meeting with Ana tomorrow.'),
          findsOneWidget,
        );
        expect(find.text('You said'), findsOneWidget);
        expect(find.text('What time works for you?'), findsOneWidget);
        expect(find.text('Transcribing your voice message…'), findsNothing);
        expect(find.text('Voice with Aria'), findsOneWidget);
        expect(recording.existsSync(), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'the chosen voice and remaining allowance reach the voice screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      // A voice remembered from a previous run must be sent with the next turn.
      SharedPreferences.setMockInitialValues({'ai.voice': 'nova'});

      final temp = Directory.systemTemp.createTempSync('voice-prefs-test-');
      final recording = File('${temp.path}/message.m4a')
        ..writeAsBytesSync([1, 2, 3, 4]);
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      String? uploadBody;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/voice-messages')) {
          uploadBody = request.body;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'message': {
                  '_id': 'reply',
                  'role': 'ASSISTANT',
                  'content': 'Booked for Tuesday.',
                },
                'transcription': {'text': 'Book Tuesday.'},
                'audio': {'available': false},
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/ai/quota')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'used': 18, 'limit': 20, 'remaining': 2},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              '_id': 'thread',
              'title': 'Planning with Aria',
              'calendarId': 'calendar',
              'messages': [],
            },
          }),
          200,
        );
      });

      final store = AppStore(api: Api(ApiClient(client: client)))
        // The quota call is skipped without a calendar, as on a cold start.
        ..calendar = const CalendarInfo(
          id: 'calendar',
          name: 'Personal',
          timeZone: 'UTC',
        );

      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            home: ConversationScreen(
              conversationId: 'thread',
              voiceMode: true,
              audioPath: recording.path,
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        if (find.text('Booked for Tuesday.').evaluate().isNotEmpty) break;
      }

      expect(uploadBody, isNotNull);
      expect(uploadBody, contains('name="voice"'));
      expect(uploadBody, contains('nova'));
      // The picker reflects the stored choice rather than a generic label.
      expect(find.text('Nova'), findsOneWidget);
      expect(find.text('Hands-free off'), findsOneWidget);
      // The allowance rides at the top of the transcript, which the new turn
      // has just scrolled past.
      await tester.drag(find.byType(ListView).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.text('2 LEFT TODAY'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
