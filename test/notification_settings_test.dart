import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows unavailable device delivery and explicit reminder opt-out on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore();
      store.user = AppUser.fromJson({
        '_id': 'user',
        'email': 'test@example.com',
        'displayName': 'Test',
        'notificationPreferences': {'reminders': false},
      });
      await tester.pumpWidget(
        StoreScope(
          notifier: store,
          child: MaterialApp(
            theme: appTheme,
            home: const NotificationSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Device notifications are unavailable. Reminders appear in your inbox.',
        ),
        findsOneWidget,
      );
      expect(find.text('Event reminders are turned off.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
