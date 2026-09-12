import 'dart:async';
import 'dart:convert';

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

/// A conversation whose turn is streamed back one frame at a time, each one
/// released only when the test says so — which is what lets the assertions land
/// mid-answer rather than after it.
MockClient streamingBackend(Stream<String> frames) => MockClient.streaming((
  request,
  body,
) async {
  if (request.url.path.endsWith('/messages/stream')) {
    return http.StreamedResponse(
      frames.map(utf8.encode),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
  return http.StreamedResponse(
    Stream.value(
      utf8.encode(
        jsonEncode({
          'success': true,
          'data': {
            '_id': 'thread',
            'title': 'Planning',
            'calendarId': 'calendar',
            'messages': [],
          },
        }),
      ),
    ),
    200,
    headers: {'content-type': 'application/json'},
  );
});

/// Lets the HTTP stream and the widget's own async work run for real, then
/// rebuilds. The screen never settles on its own — the idle voice orb animates
/// forever — so the test pumps deliberately instead of waiting for quiet.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

/// Writes one server-sent event. It has to go out from inside [runAsync]: the
/// listener lives on the real event loop, and a frame added from the test's
/// fake-async zone would never be delivered.
Future<void> emit(
  WidgetTester tester,
  StreamController<String> frames,
  Map<String, Object?> payload,
) async {
  await tester.runAsync(() async {
    frames.add('data: ${jsonEncode(payload)}\n\n');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
}

Future<StreamController<String>> pumpChat(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  final frames = StreamController<String>();
  await tester.pumpWidget(
    StoreScope(
      notifier: AppStore(api: Api(ApiClient(client: streamingBackend(frames.stream)))),
      child: MaterialApp(
        theme: appTheme,
        home: const ConversationScreen(conversationId: 'thread'),
      ),
    ),
  );
  await settle(tester);

  await tester.enterText(find.byType(TextField).first, 'Book my interview');
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await settle(tester);
  return frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The chat screen owns a player and a recorder for the voice turns it can
    // also take; neither has a platform side in a widget test.
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

  testWidgets('an answer appears as it streams and settles on the saved turn', (
    tester,
  ) async {
    final frames = await pumpChat(tester);

    // Nothing from the model yet: the wait sits where the answer will land.
    expect(find.byType(TypingDots), findsOneWidget);

    await emit(tester, frames, {
      'type': 'tools',
      'names': ['list_events'],
    });
    expect(
      find.text('Checking your calendar'),
      findsOneWidget,
      reason: 'the tool the model ran should be named in plain language',
    );

    // Thinking aloud before a tool call is retracted, not stitched on.
    await emit(tester, frames, {'type': 'delta', 'text': 'Let me check'});
    await emit(tester, frames, {'type': 'reset'});
    expect(find.textContaining('Let me check'), findsNothing);

    // Half-typed syntax must never reach the screen.
    await emit(tester, frames, {'type': 'delta', 'text': '**Inter'});
    expect(find.textContaining('**'), findsNothing);

    await emit(tester, frames, {'type': 'delta', 'text': 'view** is booked.'});
    expect(find.textContaining('Interview is booked.'), findsOneWidget);

    await emit(tester, frames, {
      'type': 'done',
      'message': {
        '_id': '0123456789abcdef01234567',
        'role': 'ASSISTANT',
        'content': '**Interview** is booked.',
      },
      'pendingActions': <Object?>[],
    });
    await tester.runAsync(frames.close);
    await settle(tester);

    // The caret is gone, the bubble holds the saved message, the wait is over.
    expect(find.textContaining('▍'), findsNothing);
    expect(find.byType(TypingDots), findsNothing);
    expect(find.textContaining('Interview is booked.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an error mid-stream restores the message for another try', (
    tester,
  ) async {
    final frames = await pumpChat(tester);

    await emit(tester, frames, {'type': 'delta', 'text': 'Half an ans'});
    expect(find.textContaining('Half an ans'), findsOneWidget);

    await emit(tester, frames, {
      'type': 'error',
      'code': 'AI_UNAVAILABLE',
      'message': 'AI assistant is temporarily unavailable',
    });
    await tester.runAsync(frames.close);
    await settle(tester);

    // The half-written answer is gone and the prompt is back in the box, so the
    // turn can be sent again without retyping it.
    expect(find.textContaining('Half an ans'), findsNothing);
    expect(find.byType(TypingDots), findsNothing);
    expect(find.text('Book my interview'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
