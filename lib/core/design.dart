import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'theme.dart';
export 'theme.dart';

import 'api_client.dart';

const purple = Color(0xff7040ff),
    lilac = Color(0xffcd96ff),
    muted = Color(0xff85858b);
const violetGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xff6740ff), Color(0xff8b3ae8)],
);
final appTheme = buildAppTheme(Brightness.light);
final darkAppTheme = buildAppTheme(Brightness.dark);

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
        stops: auth && !AppPalette.of(context).dark
            ? [0, .32, .65]
            : [0, .42, .72, 1],
        colors: AppPalette.of(context).dark
            ? [
                const Color(0xff191a25),
                const Color(0xff14151d),
                const Color(0xff1b1828),
                const Color(0xff15161e),
              ]
            : auth
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
                  opacity: AlwaysStoppedAnimation(
                    AppPalette.of(context).dark ? .025 : (auth ? .16 : .10),
                  ),
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
          tooltip: tr('Create Event'),
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
        color: danger && !outline ? const Color(0xffb3261e) : null,
        borderRadius: BorderRadius.circular(10),
        border: outline
            ? Border.all(color: danger ? const Color(0xffff8e8e) : lilac)
            : null,
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: outline
              ? (danger
                    ? Theme.of(context).colorScheme.error
                    : AppPalette.of(context).accent)
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
    this.minLines,
    this.compact = false,
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
  final int? minLines;
  final bool compact;
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
    padding: EdgeInsets.only(bottom: widget.compact ? 12 : 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(widget.label, style: const TextStyle(fontSize: 14)),
          SizedBox(height: widget.compact ? 6 : 10),
        ],
        TextFormField(
          controller: widget.controller,
          obscureText: widget.password && hidden,
          maxLines: widget.lines,
          minLines: widget.minLines,
          keyboardType: widget.keyboard,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          // Validation messages render inside the field, outside any Text
          // this app controls, so they are translated on the way out.
          validator: widget.validator == null
              ? null
              : (value) {
                  final message = widget.validator!(value);
                  return message == null ? null : tr(message);
                },
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: widget.compact ? true : null,
            contentPadding: widget.compact
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
                : null,
            hintText: tr(widget.hint ?? widget.label),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: tr(hidden ? 'Show password' : 'Hide password'),
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppPalette.of(context).accent,
                      size: 22,
                    ),
                  )
                : widget.icon == null
                ? null
                : Icon(
                    widget.icon,
                    color: AppPalette.of(context).accent,
                    size: 21,
                  ),
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
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: 12,
            color: AppPalette.of(context).ink,
          ),
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

/// Softens the light-backed onboarding artwork for comfortable night viewing.
class ThemedArtwork extends StatelessWidget {
  const ThemedArtwork({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!AppPalette.of(context).dark) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const RadialGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, .5, 1],
      ).createShader(bounds),
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0xff79688c),
          BlendMode.modulate,
        ),
        child: child,
      ),
    );
  }
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
        Text(
          'DAY',
          style: TextStyle(fontSize: 25, color: AppPalette.of(context).accent),
        ),
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
  const VoiceOrb({
    super.key,
    this.size = 160,
    this.onTap,
    this.active = false,
    this.halo = false,
    this.speaking = false,
    this.thinking = false,
    this.level = 0,
  });
  final double size;
  final VoidCallback? onTap;
  final bool active;

  /// The full orbital treatment used by the immersive call screen.
  final bool halo;
  final bool speaking, thinking;

  /// Normalized microphone energy; eased locally to avoid meter jitter.
  final double level;
  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

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
    _syncMotion();
    _syncRipple();
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.halo != oldWidget.halo) {
      controller.stop();
      _syncMotion();
    }
    if (widget.active != oldWidget.active || widget.halo != oldWidget.halo) {
      _syncRipple();
    }
  }

  void _syncMotion() {
    if (_stillFrames) return;
    controller.duration = widget.halo
        ? const Duration(seconds: 20)
        : const Duration(milliseconds: 2400);
    if (!controller.isAnimating) controller.repeat(reverse: !widget.halo);
  }

  void _syncRipple() {
    if (widget.active && !widget.halo && !_stillFrames) {
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
  Widget build(BuildContext context) {
    if (widget.halo) return _halo();
    return Semantics(
      button: true,
      label: tr(widget.active ? 'Recording. Tap to send.' : 'Tap and say it'),
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

  Widget _halo() => Semantics(
    button: widget.onTap != null,
    label: tr(
      widget.speaking
          ? 'Stop reply'
          : widget.active
          ? 'Recording. Tap to send.'
          : 'Tap and say it',
    ),
    child: GestureDetector(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.active ? widget.level.clamp(0.0, 1.0) : 0),
          duration: _stillFrames
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, energy, _) => SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(
              painter: _OrbitPainter(
                motion: controller,
                energy: energy,
                active: widget.active,
                speaking: widget.speaking,
                thinking: widget.thinking,
                still: _stillFrames,
              ),
              child: Center(
                child: AnimatedBuilder(
                  animation: controller,
                  child: RepaintBoundary(
                    child: Image.asset(
                      'assets/artwork/glass_orb.png',
                      width: widget.size * .72,
                      height: widget.size * .72,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                  ),
                  builder: (context, child) {
                    final phase = _stillFrames
                        ? 0.0
                        : controller.value * math.pi * 2;
                    final breath = math.sin(phase * 4);
                    final scale =
                        1 +
                        breath * (widget.active ? .012 + energy * .018 : .008);
                    return Transform.scale(
                      scale: scale,
                      child: CustomPaint(
                        foregroundPainter: _GlassFlowPainter(
                          motion: controller,
                          energy: energy,
                          active: widget.active,
                          speaking: widget.speaking,
                          thinking: widget.thinking,
                          still: _stillFrames,
                        ),
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One continuous clock drives the orbits, light and voice response. Canvas
/// repainting stays inside the orb's boundary, away from the conversation UI.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.motion,
    required this.energy,
    required this.active,
    required this.speaking,
    required this.thinking,
    required this.still,
  }) : super(repaint: motion);
  final Animation<double> motion;
  final double energy;
  final bool active, speaking, thinking, still;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * .475;
    final phase = still ? 0.0 : motion.value * math.pi * 2;
    final breath = (math.sin(phase * 4) + 1) / 2;
    final intensity = speaking
        ? .75
        : active
        ? .24 + energy * .65
        : .12;
    final bounds = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xffa466ff).withValues(alpha: .10 + intensity * .08),
            const Color(0xff7131f4).withValues(alpha: .15 + breath * .04),
            const Color(0xff6335dd).withValues(alpha: 0),
          ],
          stops: const [.38, .7, 1],
        ).createShader(bounds),
    );

    // Fine circular tracks keep the glow crisp instead of washing out the glass.
    for (final fraction in [1.0, .75]) {
      final radius = r * fraction;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(
            0xff7c3aff,
          ).withValues(alpha: .18 + intensity * .1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .65
          ..shader = SweepGradient(
          transform: GradientRotation(-phase),
            colors: const [
              Color(0x257b4cf5),
              Color(0xffb897ff),
              Color(0x607f46ff),
              Color(0xff8049ed),
              Color(0x257b4cf5),
            ],
            stops: const [0, .24, .48, .75, 1],
          ).createShader(bounds),
      );
    }

    // Two liquid contours gently respond to real microphone energy. Playback
    // uses a separate rhythm because it has no microphone meter.
    for (var ring = 0; ring < 2; ring++) {
      final path = Path();
      for (var step = 0; step <= 144; step++) {
        final a = step * math.pi * 2 / 144;
        final swell =
            math.sin(a * 3 + phase * 8 + ring * math.pi) * .012 +
            math.sin(a * 5 - phase * 6) * .007;
        final radius = r * (.815 + ring * .035 + swell * (.3 + intensity));
        final point = c + Offset(math.cos(a), math.sin(a)) * radius;
        if (step == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 0 ? 1.1 : .6
          ..color =
              (ring == 0 ? const Color(0xffc2a0ff) : const Color(0xff81dfff))
                  .withValues(alpha: .13 + intensity * .32),
      );
    }

    for (var i = 0; i < 64; i++) {
      final angle = i * math.pi / 32 - math.pi / 2 + phase;
      final point = c + Offset(math.cos(angle), math.sin(angle)) * r * .9;
      final marker = i % 8 == 0;
      final shimmer = .6 + .4 * math.sin(phase * 6 + i * .7);
      final color = i % 16 == 0
          ? const Color(0xffb9eeff)
          : const Color(0xffdec7ff);
      if (marker) {
        canvas.drawCircle(
          point,
          r * .023,
          Paint()
            ..color = const Color(
              0xff9749ff,
            ).withValues(alpha: .65 + shimmer * .2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(
        point,
        r * (marker ? .011 : .0038),
        Paint()
          ..color = color.withValues(
            alpha: marker ? .85 + shimmer * .15 : .25 + shimmer * .4,
          ),
      );
    }

    // Counter-rotating highlights travel around the perimeter, with soft tails.
    for (var i = 0; i < 2; i++) {
      final angle = (i == 0 ? phase : -phase + math.pi);
      final orbit = r * (i == 0 ? 1 : .75);
      final color = i == 0 ? const Color(0xffcfb6ff) : const Color(0xffa2eeff);
      final rect = Rect.fromCircle(center: c, radius: orbit);
      canvas.drawArc(
        rect,
        angle - .32,
        .32,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.3
          ..color = color.withValues(alpha: .6),
      );
      final point = c + Offset(math.cos(angle), math.sin(angle)) * orbit;
      canvas.drawCircle(
        point,
        r * .025,
        Paint()
          ..color = color.withValues(alpha: .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        point,
        r * .009,
        Paint()..color = const Color(0xfff7edff),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      energy != old.energy ||
      active != old.active ||
      speaking != old.speaking ||
      thinking != old.thinking ||
      still != old.still;
}

/// Translucent moving colour inside the glass, with a small illuminated voice
/// waveform replacing the opaque disc that used to cover its centre.
class _GlassFlowPainter extends CustomPainter {
  _GlassFlowPainter({
    required this.motion,
    required this.energy,
    required this.active,
    required this.speaking,
    required this.thinking,
    required this.still,
  }) : super(repaint: motion);
  final Animation<double> motion;
  final double energy;
  final bool active, speaking, thinking, still;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * .405;
    final phase = still ? 0.0 : motion.value * math.pi * 2;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    for (var i = 0; i < 3; i++) {
      final angle = phase * (i == 1 ? -2 : 2) + i * math.pi * 2 / 3;
      final point =
          c + Offset(math.cos(angle) * .52, math.sin(angle) * .42) * r;
      final color = [
        const Color(0xff81f4ff),
        const Color(0xfffa9dde),
        const Color(0xffb49aff),
      ][i];
      final bounds = Rect.fromCircle(center: point, radius: r * .86);
      canvas.drawCircle(
        point,
        r * .86,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: .27), color.withValues(alpha: 0)],
          ).createShader(bounds),
      );
    }
    // Caustic ribbons drift through the surface like light through crystal.
    for (var i = 0; i < 2; i++) {
      final shift = math.sin(phase * 3 + i * 2) * r * .24;
      final ribbon = Path()
        ..moveTo(c.dx - r, c.dy + shift - r * .1)
        ..cubicTo(
          c.dx - r * .3,
          c.dy - r * .68 + shift,
          c.dx + r * .15,
          c.dy + r * .62,
          c.dx + r,
          c.dy - r * .32 + shift,
        );
      canvas.drawPath(
        ribbon,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .055
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .045)
          ..color = (i == 0 ? const Color(0xffb4f7ff) : const Color(0xffffd4f5))
              .withValues(alpha: .32)
          ..blendMode = BlendMode.screen,
      );
    }
    canvas.restore();

    final core = Rect.fromCircle(center: c, radius: r * .42);
    canvas.drawCircle(
      c,
      r * .42,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xff7648ce).withValues(alpha: .24),
            const Color(0xffa572e3).withValues(alpha: 0),
          ],
        ).createShader(core),
    );
    if (thinking) {
      for (var i = 0; i < 3; i++) {
        final a = phase * 14 + i * math.pi * 2 / 3;
        final point = c + Offset(math.cos(a), math.sin(a)) * r * .1;
        canvas.drawCircle(
          point,
          r * .021,
          Paint()..color = const Color(0xfff9f1ff),
        );
      }
    } else {
      final intensity = speaking
          ? .85
          : active
          ? .18 + energy * .82
          : .08;
      for (var i = 0; i < 5; i++) {
        final rhythm = still
            ? .45
            : (math.sin(phase * (speaking ? 34 : 20) + i * 1.4) + 1) / 2;
        final envelope = 1 - (i - 2).abs() * .22;
        final height = r * (.035 + intensity * (.06 + rhythm * .20) * envelope);
        final x = c.dx + (i - 2) * r * .065;
        final start = Offset(x, c.dy - height / 2);
        final end = Offset(x, c.dy + height / 2);
        canvas.drawLine(
          start,
          end,
          Paint()
            ..color = const Color(0xffad72ff).withValues(alpha: .6)
            ..strokeWidth = r * .05
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawLine(
          start,
          end,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xffffffff), Color(0xffe4d3ff)],
            ).createShader(core)
            ..strokeWidth = r * .019
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GlassFlowPainter old) =>
      energy != old.energy ||
      active != old.active ||
      speaking != old.speaking ||
      thinking != old.thinking ||
      still != old.still;
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
    this.name,
  });
  final int index;
  final double size;
  final bool profile;

  /// Uploaded avatar. Falls back to the initials placeholder when absent.
  final String? url;

  /// Whose avatar this is, used for the initials placeholder.
  final String? name;

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

  /// Initials on a tinted disc.
  ///
  /// This used to crop a face out of the bundled reference art, and picked a
  /// different sheet on the profile screen than in member lists — so one
  /// account appeared as two different people (QA P06). Initials are neutral
  /// and identical wherever the same person is shown.
  Widget _placeholder() {
    final letters = _initials(name);
    final tint =
        _tints[(letters.isEmpty ? index : letters.codeUnitAt(0)) %
            _tints.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: tint,
      child: letters.isEmpty
          ? Icon(Icons.person, size: size * .55, color: Colors.white)
          : Text(
              letters,
              style: TextStyle(
                fontSize: size * .38,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
    );
  }

  static const _tints = [
    Color(0xff7c5cd6),
    Color(0xff3867b6),
    Color(0xff287b70),
    Color(0xff966121),
    Color(0xffa34665),
    Color(0xff5961b2),
  ];

  /// Up to two initials from the first and last word of [value].
  static String _initials(String? value) {
    final words = (value ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final first = words.first.characters.first.toUpperCase();
    if (words.length == 1) return first;
    return first + words.last.characters.first.toUpperCase();
  }
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: (color ?? AppPalette.of(context).surface).withValues(alpha: .84),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.of(context).border),
    ),
    // A tile inside the card paints its ink on the nearest Material, which
    // would otherwise be behind this decoration and invisible.
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// Shows a failure message in the app's error styling.
void toastError(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(color: Colors.white)),
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
          content: Text(
            error.message,
            style: const TextStyle(color: Colors.white),
          ),
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
        content: Text(
          tr('Something went wrong: {error}', {'error': error}),
          style: const TextStyle(color: Colors.white),
        ),
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
          style: TextStyle(
            color: AppPalette.of(context).muted,
            fontSize: 13,
            height: 1.4,
          ),
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
  const TypingDots({super.key, this.color, this.size = 7});
  final Color? color;
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
                  color: (widget.color ?? AppPalette.of(context).accent)
                      .withValues(alpha: .3 + .6 * _lift(i)),
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
        backgroundColor: AppPalette.of(context).surface,
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
              style: TextStyle(
                color: danger
                    ? Theme.of(context).colorScheme.error
                    : AppPalette.of(context).accent,
              ),
            ),
          ),
        ],
      ),
    ) ??
    false;
