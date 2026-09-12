import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/design.dart';
import '../core/store.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final pages = PageController();
  late final AnimationController float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  int page = 0;
  bool finishing = false;
  bool get reduce => MediaQuery.disableAnimationsOf(context);
  static const violet = Color(0xff7c3aed);
  static const slides = [
    (
      asset: 'plan',
      label: 'A LITTLE MORE CLARITY',
      title: 'Your day,\nbeautifully planned.',
      body:
          'Make room for what matters. Keep your events, reminders, and ideas together.',
      chip: 'One calm place for your day',
      icon: Icons.calendar_month_outlined,
    ),
    (
      asset: 'voice',
      label: 'LESS TYPING. MORE LIVING.',
      title: 'Say it.\nLet Aria help.',
      body:
          'Speak naturally or send a message. Turn a thought into a plan, one conversation at a time.',
      chip: 'Talk it through with Aria',
      icon: Icons.mic_none_rounded,
    ),
    (
      asset: 'share',
      label: 'BETTER TOGETHER',
      title: 'Good plans\nbring us together.',
      body:
          'Share events with your people, coordinate schedules, and make time for each other.',
      chip: 'Keep everyone in the loop',
      icon: Icons.people_outline_rounded,
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduce) {
      float.stop();
      float.value = 0;
    } else if (!float.isAnimating) {
      float.repeat();
    }
  }

  @override
  void dispose() {
    pages.dispose();
    float.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    if (finishing) return;
    setState(() => finishing = true);
    try {
      await StoreScope.read(context).markOnboarded();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    } catch (_) {
      if (mounted) {
        setState(() => finishing = false);
        toastError(context, 'Could not continue. Please try again.');
      }
    }
  }

  void select(int index) {
    if (reduce) {
      pages.jumpToPage(index);
    } else {
      pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 440),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff7f5ff),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: violet,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 9),
                const Text(
                  'compcri',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                    color: Color(0xff251c39),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: finishing ? null : finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Color(0xff796b90), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: pages,
              itemCount: slides.length,
              onPageChanged: (index) => setState(() => page = index),
              itemBuilder: (context, index) {
                final slide = slides[index];
                return LayoutBuilder(
                  builder: (context, bounds) {
                    final artSize = math
                        .min(bounds.maxWidth, bounds.maxHeight * .59)
                        .clamp(180.0, 420.0);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: Listenable.merge([pages, float]),
                            child: RepaintBoundary(
                              child: Image.asset(
                                'assets/artwork/onboarding_${slide.asset}.png',
                                width: artSize,
                                height: artSize,
                                fit: BoxFit.contain,
                                cacheWidth: 1000,
                                filterQuality: FilterQuality.high,
                                excludeFromSemantics: true,
                              ),
                            ),
                            builder: (context, child) {
                              final position =
                                  pages.hasClients &&
                                      pages.position.hasContentDimensions
                                  ? pages.page ?? page.toDouble()
                                  : page.toDouble();
                              final distance = (position - index).clamp(
                                -1.0,
                                1.0,
                              );
                              return Transform.translate(
                                offset: Offset(
                                  reduce ? 0 : distance * 35,
                                  reduce
                                      ? 0
                                      : math.sin(float.value * math.pi * 2) * 5,
                                ),
                                child: Transform.scale(
                                  scale: reduce ? 1 : 1 - distance.abs() * .07,
                                  child: Opacity(
                                    opacity: 1 - distance.abs() * .35,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              children: [
                                Text(
                                  slide.label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: violet,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  slide.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 31,
                                    height: 1.13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.1,
                                    color: Color(0xff251c39),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  slide.body,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.7,
                                    color: Color(0xff796b90),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .85),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: violet.withValues(alpha: .08),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(slide.icon, size: 16, color: violet),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          slide.chip,
                                          style: const TextStyle(
                                            color: Color(0xff62537c),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 6, 28, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    slides.length,
                    (i) => Semantics(
                      button: true,
                      selected: page == i,
                      label: 'Page ${i + 1} of ${slides.length}',
                      child: InkWell(
                        onTap: finishing ? null : () => select(i),
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 17,
                          ),
                          child: AnimatedContainer(
                            duration: reduce
                                ? Duration.zero
                                : const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            height: 6,
                            width: page == i ? 30 : 7,
                            decoration: BoxDecoration(
                              color: page == i
                                  ? violet
                                  : const Color(0xffddd4ef),
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: violet,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: finishing
                        ? null
                        : () => page == 2 ? finish() : select(page + 1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: reduce
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          child: Text(
                            finishing
                                ? 'One moment…'
                                : page == 2
                                ? 'Get started'
                                : 'Continue',
                            key: ValueKey(page == 2),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A little more time for you.',
                  style: TextStyle(color: Color(0xff9a8eac), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
