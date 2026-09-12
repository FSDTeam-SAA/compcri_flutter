import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'api_client.dart';

const purple = Color(0xff7040ff),
    lilac = Color(0xffcd96ff),
    muted = Color(0xff85858b);
const violetGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xff6740ff), Color(0xff974bfa)],
);
final appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: purple,
    primary: purple,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: Colors.transparent,
  fontFamily: 'Inter',
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 14, color: Color(0xff151518)),
    bodyLarge: TextStyle(fontSize: 16, color: Color(0xff151518)),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      color: Color(0xff151518),
      fontWeight: FontWeight.w500,
    ),
    iconTheme: IconThemeData(color: muted, size: 22),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white.withValues(alpha: .85),
    hintStyle: const TextStyle(color: Color(0xffb9b8bd), fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: lilac, width: .8),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: lilac, width: .8),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: purple, width: 1.3),
    ),
  ),
  dividerTheme: const DividerThemeData(color: Color(0xffeeeaf7), thickness: 1),
);

/// Pushes [route]. Awaiting the result lets a caller refresh once the pushed
/// screen pops.
Future<void> go(BuildContext context, String route, [Object? arguments]) =>
    Navigator.of(context).pushNamed<void>(route, arguments: arguments);
void home(BuildContext context) =>
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child, this.auth = false});
  final Widget child;
  final bool auth;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        stops: auth ? [0, .32, .65] : [0, .42, .72, 1],
        colors: auth
            ? [const Color(0xffe1d3ff), const Color(0xfff3fdff), Colors.white]
            : [
                const Color(0xffddfaff),
                Colors.white,
                const Color(0xfffdfbff),
                const Color(0xfff2eaff),
              ],
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: Image.asset(
                  'assets/artwork/pastel_shapes.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  opacity: AlwaysStoppedAnimation(auth ? .16 : .10),
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

class CreateEventButton extends StatelessWidget {
  const CreateEventButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: const Color(0xff5b28c8).withValues(alpha: .3),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff8b5cf6), Color(0xff6427d6)],
          ),
        ),
        child: IconButton(
          tooltip: 'Create Event',
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(width: 58, height: 58),
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 29),
        ),
      ),
    ),
  );
}

class AmbientPainter extends CustomPainter {
  AmbientPainter(this.auth);
  final bool auth;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    if (auth) {
      p.color = const Color(0xffdfe6ff).withValues(alpha: .7);
      for (var i = 0; i < 21; i++) {
        canvas.drawCircle(
          Offset((i * 37 % 108).toDouble(), size.height - (i * 29 % 150)),
          (3 + i % 3).toDouble(),
          p,
        );
      }
      return;
    }
    p.color = const Color(0xffe8e5ff).withValues(alpha: .26);
    for (final r in [
      const Rect.fromLTWH(.1, .23, .14, .08),
      const Rect.fromLTWH(.18, .37, .49, .11),
      const Rect.fromLTWH(.46, .32, .40, .13),
      const Rect.fromLTWH(.48, .45, .43, .13),
      const Rect.fromLTWH(.37, .76, .18, .05),
      const Rect.fromLTWH(.49, .86, .46, .13),
    ]) {
      canvas.save();
      canvas.translate(
        (r.left + r.width / 2) * size.width,
        (r.top + r.height / 2) * size.height,
      );
      canvas.rotate(-.55);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: r.width * size.width,
          height: r.height * size.height,
        ),
        p,
      );
      canvas.restore();
    }
    for (var i = 0; i < 8; i++) {
      canvas.drawCircle(
        Offset(
          (i * 97 % 380) / 393 * size.width,
          (.26 + i * .085) * size.height,
        ),
        (10 + (i % 3) * 9).toDouble(),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(AmbientPainter oldDelegate) => auth != oldDelegate.auth;
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.bottom,
    this.auth = false,
    this.scroll = true,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool auth, scroll;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Backdrop(
    auth: auth,
    child: Scaffold(
      appBar: title == null
          ? null
          : AppBar(title: Text(title!), actions: actions),
      body: SafeArea(
        child: scroll
            ? SingleChildScrollView(padding: padding, child: child)
            : Padding(padding: padding, child: child),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: bottom!,
            ),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
    this.outline = false,
    this.danger = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outline, danger;
  @override
  Widget build(BuildContext context) => PressFeedback(
    enabled: onPressed != null,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: outline || danger ? null : violetGradient,
        color: danger && !outline ? const Color(0xffff4e2c) : null,
        borderRadius: BorderRadius.circular(10),
        border: outline
            ? Border.all(color: danger ? const Color(0xffff8e8e) : lilac)
            : null,
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: outline
              ? (danger ? const Color(0xffff4e2c) : purple)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 19),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class PressFeedback extends StatefulWidget {
  const PressFeedback({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      if (widget.enabled) setState(() => pressed = true);
    },
    onPointerUp: (_) => setState(() => pressed = false),
    onPointerCancel: (_) => setState(() => pressed = false),
    child: AnimatedScale(
      scale: pressed && !MediaQuery.disableAnimationsOf(context) ? .975 : 1,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

class AppField extends StatefulWidget {
  const AppField(
    this.label, {
    super.key,
    this.hint,
    this.controller,
    this.password = false,
    this.lines = 1,
    this.keyboard,
    this.validator,
    this.onTap,
    this.icon,
    this.readOnly = false,
  });
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool password, readOnly;
  final int lines;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(widget.label, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 10),
        ],
        TextFormField(
          controller: widget.controller,
          obscureText: widget.password && hidden,
          maxLines: widget.lines,
          keyboardType: widget.keyboard,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          validator: widget.validator,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: widget.hint ?? widget.label,
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: lilac,
                      size: 22,
                    ),
                  )
                : widget.icon == null
                ? null
                : Icon(widget.icon, color: lilac, size: 21),
          ),
        ),
      ],
    ),
  );
}

class SelectField extends StatelessWidget {
  const SelectField(
    this.label, {
    super.key,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String label, value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[Text(label), const SizedBox(height: 10)],
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: lilac),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          style: const TextStyle(fontSize: 12, color: muted),
          items: values
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    ),
  );
}

/// Only decorative regions of supplied exports are displayed. All controls are native.
class ReferenceArt extends StatelessWidget {
  const ReferenceArt(
    this.file,
    this.region, {
    super.key,
    required this.width,
    required this.height,
    this.feather = false,
  });
  final String file;
  final Rect region;
  final double width, height;
  final bool feather;
  @override
  Widget build(BuildContext context) =>
      feather ? FeatheredArt(child: artwork()) : artwork();
  Widget artwork() => SizedBox(
    width: width,
    height: height,
    child: ClipRect(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: region.width,
          height: region.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -region.left,
                top: -region.top,
                width: 393,
                height: 852,
                child: Image.asset(
                  'assets/references/$file',
                  width: 393,
                  height: 852,
                  fit: BoxFit.fill,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FeatheredArt extends StatelessWidget {
  const FeatheredArt({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.white,
        Colors.white,
        Colors.transparent,
      ],
      stops: [0, .08, .86, 1],
    ).createShader(bounds),
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0, .08, .92, 1],
      ).createShader(bounds),
      child: child,
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 72, this.wordmark = false});
  final double size;
  final bool wordmark;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: BrandPainter()),
      ),
      if (wordmark) ...[
        const SizedBox(width: 10),
        const Text(
          'AUROX ',
          style: TextStyle(
            fontSize: 25,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Text('DAY', style: TextStyle(fontSize: 25, color: purple)),
      ],
    ],
  );
}

class BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 72, size.height / 72);
    final p = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xff005aff), Color(0xff7624ff)],
      ).createShader(const Rect.fromLTWH(0, 0, 72, 72));
    canvas.drawPath(
      Path()
        ..moveTo(5, 65)
        ..lineTo(31, 12)
        ..lineTo(44, 12)
        ..lineTo(20, 65)
        ..close(),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(36, 38)
        ..lineTo(44, 23)
        ..lineTo(66, 65)
        ..lineTo(52, 65)
        ..close(),
      p,
    );
    canvas.drawCircle(const Offset(35, 52), 5, p);
    for (var i = 0; i < 7; i++) {
      final s = 6 - i * .5;
      canvas.drawRect(
        Rect.fromLTWH(47 + (i % 2) * 8 + i * 1.6, 18 - i * 2.6, s, s),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(BrandPainter oldDelegate) => false;
}

class VoiceOrb extends StatefulWidget {
  const VoiceOrb({super.key, this.size = 160, this.onTap, this.active = false});
  final double size;
  final VoidCallback? onTap;
  final bool active;
  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  /// Ripples only run while recording, so an idle orb still costs one ticker.
  late final AnimationController ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _stillFrames => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stillFrames) {
      controller.stop();
      controller.value = 0;
      ripple.stop();
      ripple.value = 0;
      return;
    }
    if (!controller.isAnimating) controller.repeat(reverse: true);
    _syncRipple();
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _syncRipple();
  }

  void _syncRipple() {
    if (widget.active && !_stillFrames) {
      if (!ripple.isAnimating) ripple.repeat();
    } else {
      ripple.stop();
      ripple.value = 0;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.active ? 'Recording. Tap to send.' : 'Tap and say it',
    child: GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        // The rings paint past the orb without enlarging what the column lays
        // out, so starting a recording never reflows the screen.
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (widget.active)
              IgnorePointer(
                child: OverflowBox(
                  maxWidth: widget.size * _rippleExtent,
                  maxHeight: widget.size * _rippleExtent,
                  child: AnimatedBuilder(
                    animation: ripple,
                    builder: (context, _) => CustomPaint(
                      size: Size.square(widget.size * _rippleExtent),
                      painter: _RipplePainter(ripple.value),
                    ),
                  ),
                ),
              ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                final v = _stillFrames ? 0.0 : controller.value;
                return Transform.translate(
                  offset: Offset(0, math.sin(v * math.pi) * -5),
                  child: Transform.scale(
                    scale: 1 + v * (widget.active ? .07 : .02),
                    child: child,
                  ),
                );
              },
              child: RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: widget.size * .72,
                      height: widget.size * .72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xffb79aff,
                            ).withValues(alpha: .24),
                            blurRadius: widget.size * .18,
                            offset: Offset(0, widget.size * .08),
                          ),
                        ],
                      ),
                    ),
                    Image.asset(
                      'assets/artwork/glass_orb.png',
                      width: widget.size,
                      height: widget.size,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                    AnimatedSwitcher(
                      duration: _stillFrames
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      child: widget.active
                          ? Container(
                              key: const ValueKey('recording'),
                              width: widget.size * .34,
                              height: widget.size * .34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: .65),
                                border: Border.all(color: Colors.white70),
                              ),
                              child: Icon(
                                Icons.stop_rounded,
                                color: const Color(0xff9858eb),
                                size: widget.size * .19,
                              ),
                            )
                          : Image.asset(
                              'assets/artwork/microphone.png',
                              key: const ValueKey('microphone'),
                              width: widget.size * .38,
                              height: widget.size * .38,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              excludeFromSemantics: true,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// How far the outermost ripple travels, as a multiple of the orb diameter.
const _rippleExtent = 1.45;

/// Three rings spaced a third of a cycle apart, each expanding from the orb's
/// edge and fading out — the "we are listening" cue while recording.
class _RipplePainter extends CustomPainter {
  const _RipplePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final start = size.width / (2 * _rippleExtent);
    final end = size.width / 2;
    for (var ring = 0; ring < 3; ring += 1) {
      final t = (progress + ring / 3) % 1;
      final fade = 1 - t;
      canvas.drawCircle(
        center,
        start + (end - start) * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * fade
          ..color = lilac.withValues(alpha: .5 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.index = 0,
    this.size = 42,
    this.profile = false,
    this.url,
  });
  final int index;
  final double size;
  final bool profile;

  /// Uploaded avatar. Falls back to the bundled placeholder when absent.
  final String? url;

  @override
  Widget build(BuildContext context) {
    final source = url;
    if (source != null && source.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          source,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, _, _) => _placeholder(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _placeholder(),
        ),
      );
    }
    return ClipOval(child: _placeholder());
  }

  Widget _placeholder() => ReferenceArt(
    profile ? 'Main profile.png' : 'Contact and Group.png',
    profile
        ? const Rect.fromLTWH(151, 100, 86, 86)
        : Rect.fromLTWH(29, 308 + (index % 6) * 74, 48, 48),
    width: size,
    height: size,
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .84),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xfff0eafa)),
    ),
    child: child,
  );
}

/// Shows a failure message in the app's error styling.
void toastError(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xffb3261e),
      ),
    );

/// Runs a request that returns a value, behind a modal spinner.
///
/// Returns the value, or `null` when the call failed — call sites branch on
/// the result rather than repeating try/catch around every request.
Future<T?> runTask<T extends Object>(
  BuildContext context,
  Future<T> Function() task, {
  String? success,
  bool showSpinner = true,
  void Function(ApiException error)? onError,
}) => _run<T>(
  context,
  task,
  success: success,
  showSpinner: showSpinner,
  onError: onError,
);

/// Runs a request that returns nothing. `true` means it succeeded.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() task, {
  String? success,
  bool showSpinner = true,
  void Function(ApiException error)? onError,
}) async {
  final outcome = await _run<bool>(
    context,
    () async {
      await task();
      return true;
    },
    success: success,
    showSpinner: showSpinner,
    onError: onError,
  );
  return outcome ?? false;
}

Future<T?> _run<T extends Object>(
  BuildContext context,
  Future<T> Function() task, {
  String? success,
  bool showSpinner = true,
  void Function(ApiException error)? onError,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  var spinning = false;
  if (showSpinner) {
    spinning = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => const Center(
        child: SizedBox(
          width: 42,
          height: 42,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }

  void dismiss() {
    if (spinning && navigator.canPop()) navigator.pop();
    spinning = false;
  }

  try {
    final result = await task();
    dismiss();
    if (success != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(success), behavior: SnackBarBehavior.floating),
      );
    }
    return result;
  } on ApiException catch (error) {
    dismiss();
    if (onError != null) {
      onError(error);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xffb3261e),
        ),
      );
    }
    return null;
  } catch (error) {
    dismiss();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Something went wrong: $error'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xffb3261e),
      ),
    );
    return null;
  }
}

/// Placeholder shown when a list has loaded and come back empty.
class EmptyState extends StatelessWidget {
  const EmptyState(
    this.message, {
    super.key,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    child: Column(
      children: [
        Icon(icon, size: 38, color: lilac),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.4),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

/// Centred spinner sized for inline list placeholders.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 140});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    ),
  );
}

/// Three dots rolling over while a turn is in flight. It sits where the reply
/// will land, so the wait reads as an answer being written rather than as a
/// screen that has stopped responding.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color = purple, this.size = 7});
  final Color color;
  final double size;
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// Each dot trails the one before it, and rests for the back half of the
  /// cycle so the row breathes instead of shimmering.
  double _lift(int index) {
    final phase = (_wave.value - index * .16) % 1;
    return phase < .5 ? math.sin(phase * 2 * math.pi) : 0.0;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _wave,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
            child: Transform.translate(
              offset: Offset(0, -3 * _lift(i)),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: .3 + .6 * _lift(i)),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A button that shows a spinner while its action is in flight.
class AsyncButton extends StatefulWidget {
  const AsyncButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
    this.outline = false,
    this.danger = false,
  });
  final String label;
  final Future<void> Function() onPressed;
  final IconData? icon;
  final bool outline, danger;
  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => busy
      ? const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        )
      : PrimaryButton(
          widget.label,
          icon: widget.icon,
          outline: widget.outline,
          danger: widget.danger,
          onPressed: () async {
            setState(() => busy = true);
            try {
              await widget.onPressed();
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
        );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Continue',
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              action,
              style: TextStyle(color: danger ? Colors.red : purple),
            ),
          ),
        ],
      ),
    ) ??
    false;
