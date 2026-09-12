import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final skip in [false, true]) {
    testWidgets(
      skip
          ? 'skip completes onboarding'
          : 'onboarding advances and completes on a small screen',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final store = AppStore();
        await tester.pumpWidget(
          StoreScope(
            notifier: store,
            child: MaterialApp(
              theme: appTheme,
              home: const OnboardingScreen(),
              routes: {
                '/login': (_) =>
                    const Scaffold(body: Text('Login destination')),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (skip) {
          await tester.tap(find.text('Skip'));
        } else {
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          expect(find.text('Say it.\nLet Aria help.'), findsOneWidget);
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Get started'));
        }
        await tester.pumpAndSettle();
        expect(store.onboarded, isTrue);
        expect(find.text('Login destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
