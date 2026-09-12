import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/dashboard.dart';
import 'package:compcri_flutter/features/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeBackend, bootedStore, pumpApp;

/// Renders [child] the way the app does, at a phone size.
Future<void> pumpScreen(
  WidgetTester tester,
  AppStore store,
  Widget child, {
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    StoreScope(
      notifier: store,
      child: MaterialApp(
        theme: appTheme,
        home: Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _iso(DateTime value) => value.toUtc().toIso8601String();

List<Map<String, dynamic>> _chats(int count) => [
  for (var i = 0; i < count; i++)
    {
      '_id': 'chat-$i',
      'title': i.isEven
          ? 'I have an interview tomorrow at three, can you move the gym block?'
          : 'Hello',
      'updatedAt': _iso(DateTime.now().subtract(Duration(hours: i))),
    },
];

Map<String, dynamic> _notification({
  required String id,
  required String category,
  required bool read,
  required Duration age,
}) => {
  '_id': id,
  'title': 'Interview starts in two hours',
  'body':
      'Your interview with the design team begins at 11:00 AM on Google Meet. '
      'Tap to open the event and review the guest list.',
  'category': category,
  if (read) 'readAt': _iso(DateTime.now()),
  'createdAt': _iso(DateTime.now().subtract(age)),
};

/// The screens under test refetch on mount, so fixtures are served by the
/// fake backend rather than assigned onto the store.
Future<AppStore> storeWith(
  WidgetTester tester, {
  List<Map<String, dynamic>>? chats,
  List<Map<String, dynamic>>? notifications,
}) {
  final backend = FakeBackend()
    ..conversations = chats
    ..notifications = notifications;
  return bootedStore(tester, backend);
}

/// The starter-prompt strip is the only horizontal list on the chat tab.
final _horizontalList = find.byWidgetPredicate(
  (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
);

void main() {
  group('chat tab', () {
    testWidgets('lays out a full chat list without overflow', (tester) async {
      final store = await storeWith(tester, chats: _chats(7));
      await pumpScreen(tester, store, const ChatTab());

      expect(store.conversations, hasLength(7));
      expect(find.text('Recent chats'), findsOneWidget);
      expect(find.widgetWithText(PrimaryButton, 'New chat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the starter prompts fully inside their strip', (
      tester,
    ) async {
      final store = await storeWith(tester, chats: _chats(7));
      await pumpScreen(tester, store, const ChatTab());

      // A chip taller than the strip is silently clipped at the baseline,
      // which is what the fixed-height ActionChip layout used to do.
      expect(_horizontalList, findsOneWidget);
      final stripRect = tester.getRect(_horizontalList);
      final chip = find.text("What's on my schedule today?");
      expect(chip, findsOneWidget);
      final chipRect = tester.getRect(chip);
      expect(stripRect.top, lessThanOrEqualTo(chipRect.top));
      expect(stripRect.bottom, greaterThanOrEqualTo(chipRect.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a narrow screen', (tester) async {
      final store = await storeWith(tester, chats: _chats(5));
      await pumpScreen(
        tester,
        store,
        const ChatTab(),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the event button so it cannot sit on "New chat"', (
      tester,
    ) async {
      final store = await storeWith(tester, chats: _chats(3));
      await pumpApp(tester, store);

      expect(find.byType(CreateEventButton), findsOneWidget);
      await tester.tap(find.byTooltip('AI Chat'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(PrimaryButton, 'New chat'), findsOneWidget);
      expect(find.byType(CreateEventButton), findsNothing);
    });
  });

  group('notifications', () {
    testWidgets('groups by day and marks unread rows', (tester) async {
      final store = await storeWith(
        tester,
        notifications: [
          _notification(
            id: 'n1',
            category: 'REMINDER',
            read: false,
            age: const Duration(minutes: 5),
          ),
          _notification(
            id: 'n2',
            category: 'INVITATION',
            read: true,
            age: const Duration(days: 1, hours: 2),
          ),
          _notification(
            id: 'n3',
            category: 'SECURITY',
            read: true,
            age: const Duration(days: 20),
          ),
        ],
      );
      await pumpScreen(tester, store, const NotificationsScreen());

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Unread'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filters to unread only', (tester) async {
      final store = await storeWith(
        tester,
        notifications: [
          _notification(
            id: 'n1',
            category: 'REMINDER',
            read: false,
            age: const Duration(minutes: 5),
          ),
          _notification(
            id: 'n2',
            category: 'INVITATION',
            read: true,
            age: const Duration(hours: 3),
          ),
        ],
      );
      await pumpScreen(tester, store, const NotificationsScreen());
      expect(find.byType(Dismissible), findsNWidgets(2));

      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(find.byType(Dismissible), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders long bodies on a narrow screen', (tester) async {
      final store = await storeWith(
        tester,
        notifications: [
          for (var i = 0; i < 4; i++)
            _notification(
              id: 'n$i',
              category: 'GROUP_UPDATE',
              read: i.isEven,
              age: Duration(hours: i),
            ),
        ],
      );
      await pumpScreen(
        tester,
        store,
        const NotificationsScreen(),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('calendar strip', () {
    testWidgets('scrolls horizontally to reach other days', (tester) async {
      final store = await bootedStore(tester, FakeBackend());
      await pumpScreen(tester, store, const CalendarTab());
      expect(_horizontalList, findsOneWidget);

      final controller = tester.widget<ListView>(_horizontalList).controller!;
      final before = controller.position.pixels;
      await tester.drag(_horizontalList, const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(controller.position.pixels, greaterThan(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Today" brings the strip back to the current day', (
      tester,
    ) async {
      final store = await bootedStore(tester, FakeBackend());
      await pumpScreen(tester, store, const CalendarTab());

      final controller = tester.widget<ListView>(_horizontalList).controller!;
      final centred = controller.position.pixels;

      await tester.drag(_horizontalList, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(controller.position.pixels, isNot(closeTo(centred, 1)));

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(controller.position.pixels, closeTo(centred, 1));
      expect(tester.takeException(), isNull);
    });
  });
}
