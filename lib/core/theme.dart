import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device-local preference, restored before the first frame.
class AppAppearance {
  const AppAppearance._();
  static const storageKey = 'app.themeMode';
  static final _mode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static ValueListenable<ThemeMode> get listenable => _mode;
  static ThemeMode get mode => _mode.value;

  static Future<void> restore() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        storageKey,
      );
      _mode.value = ThemeMode.values.firstWhere(
        (mode) => mode.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      _mode.value = ThemeMode.system;
    }
  }

  static Future<void> apply(ThemeMode mode) async {
    _mode.value = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(
        storageKey,
        mode.name,
      );
    } catch (_) {
      // The active theme still changes if storage is unavailable.
    }
  }

  @visibleForTesting
  static void reset() => _mode.value = ThemeMode.system;
}

/// Semantic colors shared by custom controls and Material components.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.dark,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.border,
    required this.accent,
    required this.tint,
    required this.canvas,
  });
  final bool dark;
  final Color surface, ink, muted, border, accent, tint, canvas;

  static const light = AppPalette(
    dark: false,
    surface: Colors.white,
    ink: Color(0xff151518),
    muted: Color(0xff6f6688),
    border: Color(0xffe5ddef),
    accent: Color(0xff7040ff),
    tint: Color(0xfff3edff),
    canvas: Color(0xffeeeaf8),
  );
  static const night = AppPalette(
    dark: true,
    surface: Color(0xff22232e),
    ink: Color(0xfff3efff),
    muted: Color(0xffbeb7cf),
    border: Color(0xff3e3b50),
    accent: Color(0xffc084fc),
    tint: Color(0xff302443),
    canvas: Color(0xff111219),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      (Theme.of(context).brightness == Brightness.dark ? night : light);

  /// Keeps a tinted light surface's hue while lowering its night luminance.
  Color wash(Color lightColor) => dark
      ? HSLColor.fromColor(
          lightColor,
        ).withSaturation(.22).withLightness(.17).toColor()
      : lightColor;

  /// Keeps semantic warning/success hues legible on a dark surface.
  Color foreground(Color lightColor) => dark
      ? HSLColor.fromColor(lightColor).withLightness(.73).toColor()
      : lightColor;

  @override
  AppPalette copyWith({
    bool? dark,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? border,
    Color? accent,
    Color? tint,
    Color? canvas,
  }) => AppPalette(
    dark: dark ?? this.dark,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    accent: accent ?? this.accent,
    tint: tint ?? this.tint,
    canvas: canvas ?? this.canvas,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) => other == null
      ? this
      : AppPalette(
          dark: t < .5 ? dark : other.dark,
          surface: Color.lerp(surface, other.surface, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          border: Color.lerp(border, other.border, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          tint: Color.lerp(tint, other.tint, t)!,
          canvas: Color.lerp(canvas, other.canvas, t)!,
        );
}

SystemUiOverlayStyle appOverlayStyle(AppPalette colors) =>
    (colors.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: colors.canvas,
          systemNavigationBarIconBrightness: colors.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        );

ThemeData buildAppTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? AppPalette.night
      : AppPalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff7040ff),
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.dark ? const Color(0xff221332) : Colors.white,
    surface: colors.surface,
    onSurface: colors.ink,
    onSurfaceVariant: colors.muted,
    outline: colors.border,
    error: colors.dark ? const Color(0xffff9aab) : const Color(0xffb3261e),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: colors.border, width: .8),
  );
  return base.copyWith(
    extensions: [colors],
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: base.textTheme.apply(
      bodyColor: colors.ink,
      displayColor: colors.ink,
    ),
    iconTheme: IconThemeData(color: colors.muted, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: colors.ink,
      systemOverlayStyle: appOverlayStyle(colors),
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        color: colors.ink,
        fontWeight: FontWeight.w500,
      ),
      iconTheme: IconThemeData(color: colors.muted, size: 22),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface.withValues(alpha: .85),
      hintStyle: TextStyle(color: colors.muted, fontSize: 12),
      labelStyle: TextStyle(color: colors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.accent, width: 1.3),
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: colors.surface,
      side: BorderSide(color: colors.border),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accent.withValues(alpha: .25),
      selectionHandleColor: colors.accent,
    ),
  );
}
