import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/design.dart';
import 'core/i18n.dart';
import 'core/purchases.dart';
import 'core/push.dart';
import 'core/store.dart';
import 'core/time.dart';
import 'features/auth.dart';
import 'features/dashboard.dart';
import 'features/events.dart';
import 'features/network.dart';
import 'features/notes.dart';
import 'features/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Month and weekday names for every language the app speaks, then the
  // language itself, so the first frame is already in the right one.
  await initializeDateFormatting();
  await I18n.restore();
  await ClockFormat.restore();
  await AppAppearance.restore();
  // Optional: a build without the Firebase config files still runs, it just
  // keeps notifications inside the app.
  await PushMessaging.instance.enable();
  // Likewise optional: a platform with no store key shows the plans without
  // prices rather than refusing to start.
  await StorePurchases.instance.enable();
  runApp(const MyApp());
}

/// Lets any layer push a route without a [BuildContext] — used when the
/// session expires and the app has to return to sign-in.
final navigatorKey = GlobalKey<NavigatorState>();

/// The name of the route on top, so a notification tap can wait for the
/// splash screen to hand over before opening anything.
class _TopRoute extends NavigatorObserver {
  String? name;
  void _set(Route<dynamic>? route) => name = route?.settings.name;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);
}

final _topRoute = _TopRoute();

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.initialRoute = '/', this.store});
  final String initialRoute;

  /// Injected by widget tests; production builds create their own.
  final AppStore? store;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppStore store = widget.store ?? AppStore();
  bool _bouncing = false;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStoreChanged);
    PushMessaging.instance.onOpen = _openNotification;
    if (widget.store == null) store.bootstrap();
  }

  /// A tapped notification opens the event it is about, or the inbox when it
  /// is not about an event — never just the app's front page.
  Future<void> _openNotification(Map<String, String> data) async {
    final id = data['notificationId'];
    if (id != null && id.isNotEmpty) {
      unawaited(store.markNotificationIdRead(id).catchError((Object _) {}));
    }
    // A cold start delivers the tap during the splash, which then replaces
    // whatever is on top with the home screen. Open only once it has.
    for (var i = 0; i < 50 && (_topRoute.name ?? '/') == '/'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    CalendarEvent? event;
    try {
      event = await store.eventForNotification(data);
    } catch (_) {
      // Deleted or no longer shared: the inbox still explains it.
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null || !mounted) return;
    if (event != null) {
      unawaited(navigator.pushNamed('/event', arguments: event));
    } else {
      unawaited(navigator.pushNamed('/notifications'));
    }
  }

  /// A refresh token that the server rejected drops the user at sign-in.
  void _onStoreChanged() {
    if (!store.signedOutRemotely || _bouncing) return;
    _bouncing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      store.signedOutRemotely = false;
      _bouncing = false;
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (_) => false,
      );
    });
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    PushMessaging.instance.onOpen = null;
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StoreScope(
    notifier: store,
    // Appearance, language, and clock changes update every route, including
    // screens and dialogs that are already open.
    child: ListenableBuilder(
      listenable: Listenable.merge([
        I18n.listenable,
        ClockFormat.listenable,
        AppAppearance.listenable,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'Aurox Day',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        navigatorObservers: [_topRoute],
        theme: appTheme,
        darkTheme: darkAppTheme,
        themeMode: AppAppearance.mode,
        // Apply foregrounds and custom surfaces together during a switch.
        themeAnimationDuration: Duration.zero,
        locale: Locale(I18n.locale),
        supportedLocales: [for (final code in I18n.supported) Locale(code)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        initialRoute: widget.initialRoute,
        // Material's own pickers and TimeOfDay.format follow the same
        // 12/24-hour choice as the rest of the app.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(alwaysUse24HourFormat: ClockFormat.use24),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: appOverlayStyle(AppPalette.of(context)),
            child: ColoredBox(
              color: AppPalette.of(context).canvas,
              // Flutter leaves the keyboard up until something takes focus away,
              // so on iOS — where tapping off a field is how everyone closes it —
              // ours looked stuck. One handler around the whole app rather than a
              // dozen screens remembering to add their own.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
        onGenerateInitialRoutes: (name) => [
          buildRoute(RouteSettings(name: name)),
        ],
        onGenerateRoute: buildRoute,
      ),
    ),
  );
}

Route<void> buildRoute(RouteSettings settings) {
  final name = settings.name ?? '/';
  final arguments = settings.arguments;
  final Widget page;
  if (name == '/') {
    page = const SplashScreen();
  } else if (name == '/onboarding') {
    page = const OnboardingScreen();
  } else if ([
    '/login',
    '/signup',
    '/forgot',
    '/otp',
    '/reset',
  ].contains(name)) {
    page = AuthScreen(mode: name, arguments: arguments);
  } else if (name == '/home') {
    page = const Dashboard();
  } else if (name == '/event/create' || name == '/event/edit') {
    // A String argument is a group id: the form was opened from inside a
    // group and the new event should belong to it (QA F05).
    page = EventForm(
      event: arguments is CalendarEvent ? arguments : null,
      groupId: arguments is String ? arguments : null,
    );
  } else if (name == '/event') {
    page = EventDetails(event: arguments as CalendarEvent);
  } else if (name == '/event/share') {
    page = ShareEventScreen(event: arguments as CalendarEvent);
  } else if (name == '/contact') {
    page = ContactDetails(contact: arguments as Person);
  } else if (name == '/group') {
    page = GroupDetails(group: arguments as Group);
  } else if (name == '/notes') {
    page = const NotesScreen();
  } else if (name == '/note') {
    page = NoteEditor(note: arguments as Note?);
  } else if (name == '/requests') {
    page = const RequestsScreen();
  } else {
    page = SettingsScreen(route: name, arguments: arguments);
  }
  return PageRouteBuilder<void>(
    settings: settings,
    pageBuilder: (_, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.045, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
}
