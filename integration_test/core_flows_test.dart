import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/core/time.dart';
import 'package:compcri_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auxiliary accounts never overwrite the app account's saved login.
class MemorySessionStore extends SessionStore {
  Session? saved;
  @override
  Future<void> write(Session session) async => saved = session;
  @override
  Future<Session?> read() async => saved;
  @override
  Future<void> clear() async => saved = null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native app: login, event/reminder, family link, RSVP and secretary calendar',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await initializeDateFormatting();
      SharedPreferences.setMockInitialValues({'app.onboarded': true});
      await AppAppearance.apply(ThemeMode.light);
      final ownerApi = Api(ApiClient(store: MemorySessionStore()));
      final guestApi = Api(ApiClient(store: MemorySessionStore()));
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final ownerEmail = 'owner-$suffix@example.com',
          guestEmail = 'guest-$suffix@example.com';
      const password = 'SecurePassword123!';
      final owner = await ownerApi.auth.register(
        email: ownerEmail,
        password: password,
        displayName: 'QA Owner',
        termsVersion: 'v1',
        privacyVersion: 'v1',
      );
      final guest = await guestApi.auth.register(
        email: guestEmail,
        password: password,
        displayName: 'QA Family',
        termsVersion: 'v1',
        privacyVersion: 'v1',
      );
      await ownerApi.client.setSession(owner.session);
      await guestApi.client.setSession(guest.session);
      final ownerCalendar = (await ownerApi.users.me()).calendar!;
      final store = AppStore();
      await store.bootstrap();
      await tester.pumpWidget(MyApp(store: store, initialRoute: '/login'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter your email'),
        ownerEmail,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '********').first,
        password,
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(store.isSignedIn, isTrue);
      expect(store.user?.name, 'QA Owner');

      await tester.tap(find.byType(CreateEventButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Add a title'),
        'QA property viewing',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Add notes about your event...'),
        'Native API verification',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remind me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remind me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Before event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply reminder'));
      await tester.pumpAndSettle();
      // The page title reads the same as the button; tap the button.
      final createButton = find.widgetWithText(TextButton, 'Create Event');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      final event = store.events.singleWhere(
        (event) => event.title == 'QA property viewing',
      );
      expect(event.reminderMinutes, [0, 15]);
      expect(event.description, 'Native API verification');

      // Link actual accounts in both directions, then verify the app's Network tab.
      await store.sendContactRequest(
        guest.user.contactCode.toLowerCase(),
        'Family',
      );
      final request = (await guestApi.network.contactRequests()).single;
      await guestApi.network.respondToContactRequest(
        requestId: request.id,
        accept: true,
        relation: 'Family',
      );
      await store.loadNetwork();
      await tester.tap(find.byTooltip('Network'));
      await tester.pumpAndSettle();
      expect(find.text('QA Family'), findsOneWidget);
      expect(store.contacts.single.relation, 'Family');

      await store.shareEvent(
        event: event,
        targetType: 'USER',
        targetIds: [guest.user.id],
        permission: 'RESPOND',
      );
      await store.signOut();
      await store.signIn(guestEmail, password);
      navigatorKey.currentState!.pushNamedAndRemoveUntil('/home', (_) => false);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      final shared = store.sharedEvents.singleWhere(
        (row) => row.id == event.id,
      );
      expect(shared.invited, isTrue);
      navigatorKey.currentState!.pushNamed('/event', arguments: shared);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.text('Share Event'), findsNothing);
      await tester.ensureVisible(find.text('Accept'));
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect((await guestApi.events.get(event.id)).rsvpStatus, 'ACCEPTED');

      final delegation = await ownerApi.delegations.createForExistingAccount(
        userId: guest.user.id,
        preset: 'FULL_ACCESS',
      );
      await store.refreshCalendars();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('calendar-choice-${ownerCalendar.id}')),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(store.calendarId, ownerCalendar.id);
      expect(store.events.single.title, 'QA property viewing');
      await store.createEvent(
        title: 'QA secretary appointment',
        startsAt: event.occurrenceStartAt.add(const Duration(hours: 3)),
        endsAt: event.occurrenceEndAt.add(const Duration(hours: 3)),
      );
      final ownerRows = await ownerApi.events.list(
        calendarId: ownerCalendar.id,
        from: monthWindow(DateTime.now()).from,
        to: monthWindow(DateTime.now()).to,
      );
      expect(
        ownerRows.any((event) => event.title == 'QA secretary appointment'),
        isTrue,
      );
      await ownerApi.delegations.revoke(delegation.id);
      await store.refreshCalendars();
      await tester.pumpAndSettle();
      expect(store.calendar?.isOwned, isTrue);
      expect(
        store.events.any((event) => event.title == 'QA secretary appointment'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      ownerApi.client.close();
      guestApi.client.close();
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );
}
