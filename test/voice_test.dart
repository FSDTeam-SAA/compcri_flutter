import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
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
  setUpAll(() async {
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
    // The process-wide initializer must not retain a widget test's fake zone.
    await AudioPlayer.global.ensureInitialized();
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  final audioCalls = <MethodCall>[];
  setUp(() {
    audioCalls.clear();
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
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        audioCalls.add(call);
        if (call.method == 'setSourceUrl') {
          final id = (call.arguments as Map)['playerId'];
          await messenger.handlePlatformMessage(
            'xyz.luan/audioplayers/events/$id',
            const StandardMethodCodec().encodeSuccessEnvelope({
              'event': 'audio.onPrepared',
              'value': true,
            }),
            null,
          );
        }
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
  Future<void> settleIO(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'voice preview uses a typed MP3 file and reapplies playback before resuming',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final store = AppStore(
        api: Api(
          ApiClient(
            client: MockClient(
              (request) async => http.Response(
                jsonEncode({
                  'success': true,
                  'data': {
                    'base64': base64Encode([73, 68, 51, 1, 2, 3]),
                    'contentType': 'audio/mpeg',
                  },
                }),
                200,
              ),
            ),
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
      await tester.tap(find.text('Voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play sample').first);
      await settleIO(tester);
      final source =
          audioCalls
                  .singleWhere((call) => call.method == 'setSourceUrl')
                  .arguments
              as Map;
      expect(source['url'], endsWith('.mp3'));
      expect(source['mimeType'], 'audio/mpeg');
      expect(source['isLocal'], true);
      final contextIndex = audioCalls.indexWhere(
        (call) => call.method == 'setAudioContext',
      );
      final sourceIndex = audioCalls.indexWhere(
        (call) => call.method == 'setSourceUrl',
      );
      final resumeIndex = audioCalls.indexWhere(
        (call) => call.method == 'resume',
      );
      expect(contextIndex, greaterThanOrEqualTo(0));
      expect(sourceIndex, greaterThan(contextIndex));
      expect(resumeIndex, greaterThan(sourceIndex));
      final context = audioCalls[contextIndex].arguments as Map;
      expect(context['category'], 'playback');
      expect(File(source['url'] as String).existsSync(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await settleIO(tester);
      expect(File(source['url'] as String).existsSync(), isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'hands-free has a minimal orb screen and typing keeps the same conversation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async => call.method == 'hasPermission' ? false : null,
      );
      final posted = <String>[];
      final store = AppStore(
        api: Api(
          ApiClient(
            client: MockClient((request) async {
              if (request.method == 'POST') {
                posted.add(request.url.path);
                return _events([
                  {
                    'type': 'done',
                    'message': {
                      '_id': 'reply',
                      'role': 'ASSISTANT',
                      'content': 'Your meeting is at noon.',
                    },
                    'pendingActions': [],
                  },
                  {'type': 'audio_error', 'message': 'Sample unavailable'},
                ]);
              }
              return http.Response(
                jsonEncode({
                  'success': true,
                  'data': {
                    '_id': 'thread',
                    'title': 'Schedule',
                    'messages': [],
                  },
                }),
                200,
              );
            }),
          ),
        ),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: darkAppTheme,
            home: RepaintBoundary(
              key: boundary,
              child: const ConversationScreen(
                conversationId: 'thread',
                voiceMode: true,
              ),
            ),
          ),
        ),
      );
      await settleIO(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hands-free off'));
      await tester.tap(find.text('Hands-free off'));
      await settleIO(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hands-free-text')), findsOneWidget);
      expect(find.byTooltip('End call'), findsOneWidget);
      expect(find.text('Hands-free off'), findsNothing);
      expect(find.byType(VoiceOrb), findsOneWidget);
      final orb = tester.widget<VoiceOrb>(find.byType(VoiceOrb));
      expect(orb.size, greaterThan(200));
      final rendering =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final picture = await rendering.toImage();
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'design_review/rendered/hands_free_oct6.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        picture.dispose();
      });
      await tester.enterText(
        find.byKey(const ValueKey('hands-free-text')),
        'What is on my calendar today?',
      );
      final sendButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Send',
      );
      expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Send'));
      await settleIO(tester);
      expect(posted, ['/api/v1/ai/conversations/thread/messages/stream']);
      await tester.tap(find.byTooltip('Show conversation'));
      await tester.pumpAndSettle();
      expect(find.text('What is on my calendar today?'), findsOneWidget);
      expect(find.text('Your meeting is at noon.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
          if (request.url.path.endsWith('/voice-messages/stream')) {
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
            return _events([
              {
                'type': 'transcript',
                'transcription': {
                  'text': 'Schedule a meeting with Ana tomorrow.',
                },
              },
              {'type': 'delta', 'text': 'What time '},
              {'type': 'delta', 'text': 'works for you?'},
              {
                'type': 'done',
                'message': {
                  '_id': 'reply',
                  'role': 'ASSISTANT',
                  'content': 'What time works for you?',
                },
                'pendingActions': [],
                'transcription': {
                  'text': 'Schedule a meeting with Ana tomorrow.',
                },
              },
              {
                'type': 'audio_error',
                'code': 'AI_AUDIO_UNAVAILABLE',
                'message': 'Voice service is temporarily unavailable',
              },
            ]);
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
            // The transcript now lands before the answer, so wait for the
            // answer and the clean-up that follows it.
            if (find.text('Retry send').evaluate().isNotEmpty ||
                (find.text('What time works for you?').evaluate().isNotEmpty &&
                    !recording.existsSync())) {
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
        // The assistant is named by the account, so the title follows the
        // app's default when nobody has renamed it.
        expect(
          find.text('Voice with ${AppStore.defaultAssistantName}'),
          findsOneWidget,
        );
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
        if (request.url.path.endsWith('/voice-messages/stream')) {
          uploadBody = request.body;
          return _events([
            {
              'type': 'transcript',
              'transcription': {'text': 'Book Tuesday.'},
            },
            {
              'type': 'done',
              'message': {
                '_id': 'reply',
                'role': 'ASSISTANT',
                'content': 'Booked for Tuesday.',
              },
              'pendingActions': [],
              'transcription': {'text': 'Book Tuesday.'},
            },
          ]);
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
      expect(uploadBody, contains('name="speak"'));
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

/// A server-sent event stream, the way the voice route answers.
http.Response _events(List<Map<String, Object?>> events) => http.Response(
  events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
  200,
  headers: {'content-type': 'text/event-stream'},
);
