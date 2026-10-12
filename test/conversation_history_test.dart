import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/conversation_history.dart';
import 'package:compcri_flutter/features/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response ok(Object data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class HistoryBackend {
  HistoryBackend({this.premium = false});
  final bool premium;
  bool failDelete = false;
  final deleted = <String>[];
  late final rows = <Map<String, dynamic>>[
    {
      '_id': 'thread',
      'title': 'My schedule today',
      'updatedAt': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    },
    {
      '_id': 'week',
      'title': 'Plan my week',
      'updatedAt': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    },
    if (premium)
      {
        '_id': 'ideas',
        'title': 'Ideas for my project',
        'updatedAt': DateTime.now()
            .subtract(const Duration(days: 12))
            .toIso8601String(),
        'savedAt': DateTime.now().toIso8601String(),
      },
    {
      '_id': 'appointments',
      'title': 'Organize my appointments',
      'updatedAt': DateTime.now()
          .subtract(Duration(days: premium ? 29 : 6))
          .toIso8601String(),
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 23))
          .toIso8601String(),
    },
  ];
  late final client = MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'DELETE') {
      deleted.add(path);
      if (failDelete) {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'TEMPORARILY_UNAVAILABLE',
              'message': 'Please try again',
            },
          }),
          503,
        );
      }
      if (path.endsWith('/conversations')) {
        rows.clear();
      } else {
        rows.removeWhere((row) => path.endsWith('/${row['_id']}'));
      }
      return ok({'deleted': true});
    }
    if (path.endsWith('/saved')) {
      final row = rows.firstWhere(
        (row) => path.endsWith('/${row['_id']}/saved'),
      );
      row['savedAt'] = (jsonDecode(request.body) as Map)['saved'] == true
          ? DateTime.now().toIso8601String()
          : null;
      return ok(row);
    }
    if (path.endsWith('/conversations')) return ok(rows);
    return ok({
      '_id': 'thread',
      'title': 'My schedule today',
      'messages': [
        {
          '_id': 'reply',
          'role': 'ASSISTANT',
          'content': 'Your meeting is at noon.',
        },
      ],
    });
  });
}

Future<(AppStore, GlobalKey)> pumpHistory(
  WidgetTester tester,
  HistoryBackend backend, {
  Size size = const Size(393, 852),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final store = AppStore(api: Api(ApiClient(client: backend.client)))
    ..user = AppUser(
      id: 'user',
      email: 'history@example.com',
      plan: backend.premium ? 'PREMIUM' : 'FREE',
    );
  final boundary = GlobalKey();
  await tester.pumpWidget(
    StoreScope(
      notifier: store,
      child: MaterialApp(
        theme: appTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundary,
          child: const ConversationScreen(
            conversationId: 'thread',
            showHistory: true,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return (store, boundary);
}

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
    await AudioPlayer.global.ensureInitialized();
    for (final font in [
      ('Inter', 'assets/fonts/Inter.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (_) async => null,
    );
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

  for (final premium in [false, true]) {
    testWidgets(
      '${premium ? 'Pro' : 'Free'} history matches the plan and filters search',
      (tester) async {
        final (_, boundary) = await pumpHistory(
          tester,
          HistoryBackend(premium: premium),
        );
        expect(find.text('Conversation history'), findsOneWidget);
        expect(
          find.text(premium ? '30-day history' : '7-day history'),
          findsOneWidget,
        );
        expect(
          find.byType(SegmentedButton<bool>),
          premium ? findsOneWidget : findsNothing,
        );
        expect(
          find.byTooltip('Save conversation'),
          premium ? findsWidgets : findsNothing,
        );
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final picture = await render.toImage(pixelRatio: 2);
          final png = await picture.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'design_review/rendered/history_${premium ? 'pro' : 'free'}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          picture.dispose();
        });
        final search = find.descendant(
          of: find.byType(ConversationHistory),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, 'appointments');
        await tester.pumpAndSettle();
        expect(find.text('Organize my appointments'), findsOneWidget);
        expect(find.text('Plan my week'), findsNothing);
        expect(find.textContaining('Will be deleted'), findsOneWidget);
        await tester.enterText(search, 'does not exist');
        await tester.pumpAndSettle();
        expect(find.text('No conversations found.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Pro bookmarks persist and Saved excludes unsaved chats', (
    tester,
  ) async {
    final backend = HistoryBackend(premium: true);
    await pumpHistory(tester, backend);
    await tester.tap(find.text('Saved').first);
    await tester.pumpAndSettle();
    expect(find.text('Ideas for my project'), findsOneWidget);
    expect(find.text('Plan my week'), findsNothing);
    await tester.tap(find.byTooltip('Unsave conversation'));
    await settle(tester);
    expect(find.text('No saved chats yet.'), findsOneWidget);
    expect(
      backend.rows.firstWhere((row) => row['_id'] == 'ideas')['savedAt'],
      isNull,
    );
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save conversation').first);
    await settle(tester);
    await tester.tap(find.text('Saved').first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ConversationHistory),
        matching: find.text('My schedule today'),
      ),
      findsOneWidget,
    );
    expect(find.text('Plan my week'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'individual deletion honors cancel and clears the active conversation',
    (tester) async {
      final backend = HistoryBackend();
      final (store, _) = await pumpHistory(tester, backend);
      await tester.tap(find.byTooltip('Delete conversation').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.deleted, isEmpty);
      await tester.tap(find.byTooltip('Delete conversation').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(backend.deleted.single, endsWith('/conversations/thread'));
      expect(store.conversations.any((item) => item.id == 'thread'), isFalse);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Your meeting is at noon.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'delete all ${fails ? 'failure preserves' : 'success removes'} history including saved',
      (tester) async {
        final backend = HistoryBackend(premium: true)..failDelete = fails;
        final (store, _) = await pumpHistory(tester, backend);
        await tester.scrollUntilVisible(
          find.text('Delete all history'),
          200,
          scrollable: find
              .descendant(
                of: find.descendant(
                  of: find.byType(ConversationHistory),
                  matching: find.byType(ListView),
                ),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Delete all history'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete all'));
        await settle(tester);
        expect(backend.deleted.single, endsWith('/ai/conversations'));
        expect(store.conversations.isEmpty, !fails);
        if (!fails) expect(backend.rows, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'small screens and larger text keep history scrollable without overflow',
    (tester) async {
      await pumpHistory(
        tester,
        HistoryBackend(premium: true),
        size: const Size(320, 700),
        scale: 1.5,
      );
      await tester.scrollUntilVisible(
        find.text('Delete all history'),
        200,
        scrollable: find
            .descendant(
              of: find.descendant(
                of: find.byType(ConversationHistory),
                matching: find.byType(ListView),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Delete all history').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'a history refresh started before deletion cannot restore deleted chats',
    () async {
      final response = Completer<http.Response>();
      final store = AppStore(
        api: Api(ApiClient(client: MockClient((_) => response.future))),
      );
      final loading = store.loadConversations();
      store.clearConversations();
      response.complete(
        ok([
          {'_id': 'deleted', 'title': 'Private history'},
        ]),
      );
      await loading;
      expect(store.conversations, isEmpty);
      store.dispose();
    },
  );
}
