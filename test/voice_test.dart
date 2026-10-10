import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/speech_monitor.dart';
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
    // VoiceOrb animates continuously; motion is disabled for deterministic pumps.

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

  Future<List<String>> mockRecorder({
    Completer<bool>? permission,
    Completer<void>? start,
    Completer<void>? stop,
    bool silent = false,
    double Function()? decibels,
  }) async {
    final calls = <String>[];
    fakeProbability = () => (decibels?.call() ?? -160) >= -20 ? .95 : .01;
    String? path;
    var recording = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'create') {
          final id = (call.arguments as Map)['recorderId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('com.llfbandit.record/events/$id'),
            (_) async => null,
          );
        }
        if (call.method == 'hasPermission') {
          return permission?.future ?? Future.value(true);
        }
        if (call.method == 'start') {
          recording = true;
          path = (call.arguments as Map)['path'] as String;
          await File(path!).writeAsBytes([1, 2, 3, 4]);
          if (start != null) await start.future;
        }
        if (call.method == 'stop') {
          recording = false;
          if (stop != null) await stop.future;
          return path;
        }
        if (call.method == 'cancel' && path != null) {
          recording = false;
          await File(path!).delete().catchError((_) => File(path!));
        }
        if ((silent || decibels != null) && call.method == 'isRecording') {
          return recording;
        }
        if ((silent || decibels != null) && call.method == 'getAmplitude') {
          final level = decibels?.call() ?? -160.0;
          return {'current': level, 'max': level};
        }
        return null;
      },
    );
    return calls;
  }

  Future<void> pumpHandsFree(
    WidgetTester tester,
    http.Client client, {
    bool muted = false,
    SpeechMonitorFactory monitorFactory = fakeSpeechMonitor,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleIO(tester);
    });
    SharedPreferences.setMockInitialValues({'ai.muted': muted});
    final store = AppStore(api: Api(ApiClient(client: client)));
    await tester.pumpWidget(
      StoreScope(
        notifier: store,
        child: MaterialApp(
          theme: appTheme,
          home: ConversationScreen(
            speechMonitorFactory: monitorFactory,
            conversationId: 'thread',
            voiceMode: true,
          ),
        ),
      ),
    );
    await settleIO(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hands-free off'));
    await tester.tap(find.text('Hands-free off'));
    await settleIO(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleIO(tester);
  }

  http.Response emptyThread() => http.Response(
    jsonEncode({
      'success': true,
      'data': {'_id': 'thread', 'title': 'Voice', 'messages': []},
    }),
    200,
  );

  testWidgets('a silent hands-free turn pauses the microphone and can resume', (
    tester,
  ) async {
    final calls = await mockRecorder(silent: true);
    var uploads = 0;
    await pumpHandsFree(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') uploads++;
        return emptyThread();
      }),
    );
    expect(find.text('Listening to you'), findsOneWidget);
    for (var i = 0; i < 130; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settleIO(tester);
    expect(calls, contains('cancel'));
    expect(uploads, 0);
    expect(find.byTooltip('Resume hands-free'), findsOneWidget);
    await tester.tap(find.byType(VoiceOrb));
    await settleIO(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settleIO(tester);
    expect(calls.where((method) => method == 'start'), hasLength(2));
    expect(find.text('Listening to you'), findsOneWidget);
    expect(find.byTooltip('Mute microphone'), findsOneWidget);
  });
  testWidgets(
    'an unavailable speech model pauses hands-free and keeps typing usable',
    (tester) async {
      final calls = await mockRecorder();
      await pumpHandsFree(
        tester,
        MockClient((_) async => emptyThread()),
        monitorFactory: () async =>
            throw StateError('native model unavailable'),
      );
      expect(calls, isNot(contains('start')));
      expect(find.byTooltip('Resume hands-free'), findsOneWidget);
      expect(
        find.text(
          'Could not start speech detection. Please try again, or type below.',
        ),
        findsOneWidget,
      );
      final field = find.byKey(const ValueKey('hands-free-text'));
      await tester.enterText(field, 'Hello');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Send'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  List<Map<String, Object?>> voiceReply({
    bool audio = false,
    bool audioError = false,
  }) => [
    {
      'type': 'transcript',
      'transcription': {'text': 'What is on my calendar today?'},
    },
    {
      'type': 'done',
      'message': {
        '_id': 'reply',
        'role': 'ASSISTANT',
        'content': 'No meetings today.',
      },
      'pendingActions': [],
      'transcription': {'text': 'What is on my calendar today?'},
    },
    if (audio)
      {
        'type': 'audio',
        'base64': base64Encode([73, 68, 51]),
        'index': 0,
        'last': true,
      },
    if (audioError) {'type': 'audio_error', 'message': 'Speech unavailable'},
  ];

  testWidgets(
    'hands-free sends after speech returns to noisy room levels without a tap',
    (tester) async {
      var level = -32.0;
      final calls = await mockRecorder(decibels: () => level);
      var uploads = 0;
      await pumpHandsFree(
        tester,
        MockClient((request) async {
          if (request.method == 'POST') {
            uploads++;
            expect(request.url.path, endsWith('/voice-messages/stream'));
            return _events(voiceReply());
          }
          return emptyThread();
        }),
        muted: true,
      );
      expect(find.text('Listening to you'), findsOneWidget);
      for (var turn = 1; turn <= 3; turn++) {
        level = -12;
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        level = -32;
        for (var i = 0; i < 22; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await settleIO(tester);
        expect(uploads, turn);
        expect(calls.where((method) => method == 'stop'), hasLength(turn));
        await tester.pump(const Duration(milliseconds: 500));
        await settleIO(tester);
        await tester.pump(const Duration(milliseconds: 600));
        await settleIO(tester);
        expect(find.text('Listening to you'), findsOneWidget);
        expect(calls.where((method) => method == 'start'), hasLength(turn + 1));
      }
      await tester.tap(find.byTooltip('End call'));
      await settleIO(tester);
    },
  );

  for (final muted in [true, false]) {
    testWidgets(
      muted
          ? 'hands-free resumes after a muted spoken turn'
          : 'hands-free resumes when reply audio fails',
      (tester) async {
        final calls = await mockRecorder();
        var uploads = 0;
        await pumpHandsFree(
          tester,
          MockClient((request) async {
            if (request.method == 'POST') {
              uploads++;
              return _events(voiceReply(audioError: !muted));
            }
            return emptyThread();
          }),
          muted: muted,
        );
        expect(
          calls.where((method) => method == 'start'),
          hasLength(1),
          reason: tester.allWidgets
              .whereType<RichText>()
              .map((widget) => widget.text.toPlainText())
              .join(' | '),
        );
        await tester.tap(find.byType(VoiceOrb));
        await settleIO(tester);
        await tester.pump(const Duration(milliseconds: 500));
        await settleIO(tester);
        await tester.pump(const Duration(milliseconds: 600));
        await settleIO(tester);
        expect(uploads, 1);
        expect(
          calls.where((method) => method == 'start'),
          hasLength(2),
          reason: 'The next hands-free turn must start without another tap',
        );
        expect(find.text('Listening to you'), findsOneWidget);
        await tester.tap(find.byTooltip('End call'));
        await settleIO(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('ending a call suppresses late reply audio', (tester) async {
    await mockRecorder();
    final response = Completer<http.Response>();
    var uploads = 0;
    await pumpHandsFree(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          uploads++;
          return response.future;
        }
        return emptyThread();
      }),
    );
    await tester.tap(find.byType(VoiceOrb));
    await settleIO(tester);
    expect(uploads, 1);
    await tester.tap(find.byTooltip('End call'));
    await settleIO(tester);
    response.complete(_events(voiceReply(audio: true)));
    await settleIO(tester);
    expect(
      audioCalls.where((call) => call.method == 'resume'),
      isEmpty,
      reason: 'End call must apply to audio still arriving',
    );
    expect(audioCalls.where((call) => call.method == 'setSourceUrl'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ending a call cancels a microphone still starting', (
    tester,
  ) async {
    final permission = Completer<bool>();
    addTearDown(() {
      if (!permission.isCompleted) permission.complete(true);
    });
    final calls = await mockRecorder(permission: permission);
    await pumpHandsFree(tester, MockClient((_) async => emptyThread()));
    expect(calls, contains('hasPermission'));
    await tester.tap(find.byTooltip('End call'));
    await settleIO(tester);
    permission.complete(true);
    await settleIO(tester);
    expect(find.text('Listening to you'), findsNothing);
    expect(
      calls.contains('start') && !calls.contains('cancel'),
      isFalse,
      reason: 'A pending start must not keep recording after End call',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ending a call cancels a pending native recording start', (
    tester,
  ) async {
    final start = Completer<void>();
    addTearDown(() {
      if (!start.isCompleted) start.complete();
    });
    final calls = await mockRecorder(start: start);
    await pumpHandsFree(tester, MockClient((_) async => emptyThread()));
    expect(calls, contains('start'));
    await tester.tap(find.byTooltip('End call'));
    await settleIO(tester);
    start.complete();
    await settleIO(tester);
    expect(calls, contains('cancel'));
    expect(find.text('Listening to you'), findsNothing);
  });

  for (final typeInstead in [false, true]) {
    testWidgets(
      typeInstead
          ? 'typing can cancel a pending microphone permission request'
          : 'muting the microphone can cancel a pending permission request',
      (tester) async {
        final permission = Completer<bool>();
        addTearDown(() {
          if (!permission.isCompleted) permission.complete(true);
        });
        final calls = await mockRecorder(permission: permission);
        var typedUploads = 0;
        await pumpHandsFree(
          tester,
          MockClient((request) async {
            if (request.method == 'POST') {
              expect(request.url.path, endsWith('/messages/stream'));
              typedUploads++;
              return _events(voiceReply());
            }
            return emptyThread();
          }),
          muted: true,
        );
        expect(calls, contains('hasPermission'));
        if (typeInstead) {
          await tester.enterText(
            find.byKey(const ValueKey('hands-free-text')),
            'What is on my calendar today?',
          );
          await tester.pump();
          await tester.tap(find.byTooltip('Send'));
        } else {
          await tester.tap(find.byTooltip('Mute microphone'));
        }
        await settleIO(tester);
        permission.complete(true);
        await settleIO(tester);
        expect(calls, isNot(contains('start')));
        expect(find.byTooltip('Resume hands-free'), findsOneWidget);
        expect(typedUploads, typeInstead ? 1 : 0);
        if (typeInstead) {
          await tester.pumpAndSettle();
          expect(find.text('No meetings today.'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('ending a call while recording stops discards the turn', (
    tester,
  ) async {
    final stop = Completer<void>();
    addTearDown(() {
      if (!stop.isCompleted) stop.complete();
    });
    final calls = await mockRecorder(stop: stop);
    var uploads = 0;
    await pumpHandsFree(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          uploads++;
          return _events(voiceReply(audio: true));
        }
        return emptyThread();
      }),
    );
    await tester.tap(find.byType(VoiceOrb));
    await settleIO(tester);
    expect(calls, contains('stop'));
    await tester.tap(find.byTooltip('End call'));
    await settleIO(tester);
    stop.complete();
    await settleIO(tester);
    expect(uploads, 0);
    expect(find.text('Listening to you'), findsNothing);
    expect(audioCalls.where((call) => call.method == 'resume'), isEmpty);
  });

  testWidgets(
    'rapid typed sends upload only one message while playback stops',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      SharedPreferences.setMockInitialValues({'ai.muted': true});
      var uploads = 0;
      final store = AppStore(
        api: Api(
          ApiClient(
            client: MockClient((request) async {
              if (request.method == 'POST') {
                uploads++;
                return _events(voiceReply());
              }
              return emptyThread();
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
              speechMonitorFactory: fakeSpeechMonitor,
              conversationId: 'thread',
              voiceMode: true,
            ),
          ),
        ),
      );
      await settleIO(tester);
      final stop = Completer<void>();
      addTearDown(() {
        if (!stop.isCompleted) stop.complete();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers'),
            (call) async {
              if (call.method == 'stop') await stop.future;
              return null;
            },
          );
      await tester.enterText(
        find.byType(TextField).last,
        'What is on my calendar today?',
      );
      await tester.pump();
      final send = tester
          .widget<TextField>(find.byType(TextField).last)
          .onSubmitted!;
      send('What is on my calendar today?');
      send('What is on my calendar today?');
      await settleIO(tester);
      expect(uploads, 0);
      stop.complete();
      await settleIO(tester);
      expect(uploads, 1);
      expect(find.text('What is on my calendar today?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await settleIO(tester);
    },
  );

  testWidgets('four voices preserve the choice when the picker is dismissed', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({'ai.voice': 'marin'});
    final store = AppStore(
      api: Api(
        ApiClient(client: MockClient((_) async => http.Response('{}', 200))),
      ),
    );
    await tester.pumpWidget(
      StoreScope(
        notifier: store,
        child: MaterialApp(
          theme: appTheme,
          home: const ConversationScreen(
            speechMonitorFactory: fakeSpeechMonitor,
            voiceMode: true,
          ),
        ),
      ),
    );
    await settleIO(tester);
    expect(find.text('Shimmer'), findsOneWidget);
    await tester.tap(find.text('Shimmer'));
    await settleIO(tester);
    await tester.pumpAndSettle();
    expect(find.byType(RadioListTile<String>), findsNWidgets(4));
    expect(find.text('App default'), findsNothing);
    expect(find.text('Marin'), findsNothing);
    await tester.tap(find.text('Onyx'));
    await settleIO(tester);
    await tester.pumpAndSettle();
    expect((await store.api.client.store.voicePrefs()).voice, 'onyx');
    await tester.tap(find.text('Onyx'));
    await settleIO(tester);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await settleIO(tester);
    await tester.pumpAndSettle();
    expect(find.text('Onyx'), findsOneWidget);
    expect((await store.api.client.store.voicePrefs()).voice, 'onyx');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a late preview cannot change the audio session after the mic starts',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final response = Completer<http.Response>();
      final store = AppStore(
        api: Api(ApiClient(client: MockClient((_) => response.future))),
      );
      final recordCalls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async {
          recordCalls.add(call.method);
          if (call.method == 'create') {
            final id = (call.arguments as Map)['recorderId'];
            messenger.setMockMethodCallHandler(
              MethodChannel('com.llfbandit.record/events/$id'),
              (_) async => null,
            );
          }
          return call.method == 'hasPermission' ? true : null;
        },
      );
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            home: const ConversationScreen(
              speechMonitorFactory: fakeSpeechMonitor,
              voiceMode: true,
            ),
          ),
        ),
      );
      await settleIO(tester);
      await tester.tap(find.text('Nova'));
      await settleIO(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play sample').first);
      await settleIO(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settleIO(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(VoiceOrb).first);
      await settleIO(tester);
      expect(recordCalls, contains('start'));
      final sourcesBefore = audioCalls
          .where((call) => call.method == 'setSourceUrl')
          .length;
      response.complete(
        http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'base64': base64Encode([73, 68, 51]),
            },
          }),
          200,
        ),
      );
      await settleIO(tester);
      expect(
        audioCalls.where((call) => call.method == 'setSourceUrl').length,
        sourcesBefore,
      );
      expect(
        audioCalls.where((call) => call.method == 'setAudioContext'),
        isEmpty,
      );
      expect(find.text('Listening to you'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await settleIO(tester);
    },
  );

  testWidgets(
    'a silent voice turn lets the user record again without retrying silence',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final temp = Directory.systemTemp.createTempSync('silent-voice-');
      final recording = File('${temp.path}/message.m4a')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => temp.deleteSync(recursive: true));
      final store = AppStore(
        api: Api(
          ApiClient(
            client: MockClient((request) async {
              if (request.url.path.endsWith('/voice-messages/stream')) {
                return http.Response(
                  jsonEncode({
                    'success': false,
                    'error': {
                      'code': 'AUDIO_NO_SPEECH',
                      'message': 'No speech was detected in the audio',
                    },
                  }),
                  422,
                );
              }
              return http.Response(
                jsonEncode({
                  'success': true,
                  'data': {'_id': 'thread', 'title': 'Voice', 'messages': []},
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
            home: ConversationScreen(
              speechMonitorFactory: fakeSpeechMonitor,
              conversationId: 'thread',
              voiceMode: true,
              audioPath: recording.path,
            ),
          ),
        ),
      );
      await settleIO(tester);
      await tester.pumpAndSettle();
      expect(find.text('Retry send'), findsNothing);
      expect(
        find.text(
          'I did not hear any speech. Tap the mic, wait for Listening, then speak.',
        ),
        findsOneWidget,
      );
      expect(recording.existsSync(), isFalse);
      final orb = tester.widget<VoiceOrb>(find.byType(VoiceOrb));
      expect(orb.onTap, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
            home: const ConversationScreen(
              speechMonitorFactory: fakeSpeechMonitor,
              voiceMode: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nova'));
      await settleIO(tester);
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
                speechMonitorFactory: fakeSpeechMonitor,
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
      await tester.pump();
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

  for (final recovery in ['success', 'retry', 'typing']) {
    final failFirst = recovery != 'success';
    testWidgets(
      recovery == 'typing'
          ? 'a failed recording can be replaced by typing with the keyboard open'
          : failFirst
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
        var typedAttempts = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/messages/stream')) {
            typedAttempts++;
            expect(
              request.body,
              contains('Schedule a meeting with Ana tomorrow.'),
            );
            return _events(voiceReply());
          }
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
        final retryBoundary = GlobalKey();
        await tester.pumpWidget(
          StoreScope(
            notifier: store,
            child: MaterialApp(
              theme: appTheme,
              home: RepaintBoundary(
                key: retryBoundary,
                child: ConversationScreen(
                  speechMonitorFactory: fakeSpeechMonitor,
                  conversationId: 'thread',
                  voiceMode: true,
                  audioPath: recording.path,
                ),
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
          if (recovery == 'typing') {
            expect(find.byType(TextField), findsOneWidget);
            tester.view.physicalSize = const Size(320, 640);
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.enterText(
              find.byType(TextField),
              'Schedule a meeting with Ana tomorrow.',
            );
            await tester.pump();
            await tester.runAsync(() async {
              final rendering =
                  retryBoundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final picture = await rendering.toImage();
              final png = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'design_review/rendered/voice_retry_keyboard_oct10.png',
              ).writeAsBytes(png!.buffer.asUint8List());
              picture.dispose();
            });
            expect(
              recording.existsSync(),
              isTrue,
              reason: 'Typing a draft must retain the recording until Send',
            );
            await tester.tap(find.byTooltip('Send message'));
            await settleIO(tester);
            await tester.pumpAndSettle();
            expect(typedAttempts, 1);
            expect(attempts, 1);
            expect(recording.existsSync(), isFalse);
            expect(find.text('No meetings today.'), findsOneWidget);
            expect(find.text('Retry send'), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await settleIO(tester);
            return;
          } else {
            await tester.tap(find.text('Retry send'));
            await finishUpload();
          }
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
              speechMonitorFactory: fakeSpeechMonitor,
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

// Model probability is injected here; native inference is checked on Android.
double Function() fakeProbability = () => .01;
Future<SpeechMonitor> fakeSpeechMonitor() async => _FakeSpeechMonitor();

class _FakeSpeechMonitor implements SpeechMonitor {
  Timer? timer;
  @override
  Future<void> start(
    String path,
    SpeechFrame onFrame,
    void Function() onError,
  ) async {
    await stop();
    var elapsed = Duration.zero;
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed += const Duration(milliseconds: 100);
      onFrame(fakeProbability(), elapsed);
    });
  }

  @override
  Future<void> stop() async {
    timer?.cancel();
    timer = null;
  }

  @override
  Future<void> dispose() => stop();
}
