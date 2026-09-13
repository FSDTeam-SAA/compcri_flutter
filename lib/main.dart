import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/design.dart';
import 'core/i18n.dart';
import 'core/store.dart';
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
  runApp(const MyApp());
}

/// Lets any layer push a route without a [BuildContext] — used when the
/// session expires and the app has to return to sign-in.
final navigatorKey = GlobalKey<NavigatorState>();

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
    if (widget.store == null) store.bootstrap();
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
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StoreScope(
    notifier: store,
    // Changing language rebuilds the app with the new locale; every screen
    // translates itself through it, including ones already open.
    child: ValueListenableBuilder<String>(
      valueListenable: I18n.listenable,
      builder: (context, locale, _) => MaterialApp(
        title: 'Aurox Day',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: appTheme,
        locale: Locale(locale),
        supportedLocales: [for (final code in I18n.supported) Locale(code)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        initialRoute: widget.initialRoute,
        builder: (context, child) => ColoredBox(
          color: const Color(0xffeeeaf8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: child!,
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
    page = EventForm(event: arguments as CalendarEvent?);
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
