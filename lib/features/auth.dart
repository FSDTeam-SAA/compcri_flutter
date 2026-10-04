import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';

import '../core/api_client.dart';
import '../core/federated_auth.dart';
import '../core/design.dart';
import '../core/store.dart';
import '../core/i18n.dart';
export 'onboarding.dart' show OnboardingScreen;

/// Waits for the session restore in [AppStore.bootstrap] and routes onwards.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool routed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (!store.booted || routed || store.bootstrapError != null) return;
    routed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = store.isSignedIn
          ? '/home'
          : store.onboarded
          ? '/login'
          : '/onboarding';
      Navigator.pushReplacementNamed(context, target);
    });
  }

  /// Repeats the native launch screen exactly — same logo, same 96 logical
  /// pixels, same white — so the hand-off from Android/iOS to Flutter is
  /// invisible and the user sees one splash rather than two.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.of(context).surface,
    // Without the expand the stack shrinks to the logo and parks it in the
    // top-left corner instead of the middle of the screen.
    body: SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/icon/splash_logo.png',
            width: 96,
            filterQuality: FilterQuality.medium,
          ),
          // A session restore slow enough to outlast the splash shows this.
          if (StoreScope.of(context).bootstrapError != null)
            Positioned(
              bottom: 64,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  const Text(
                    'Could not connect. Your saved sign-in is safe.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  AsyncButton(
                    'Try Again',
                    onPressed: () => StoreScope.read(context).bootstrap(),
                  ),
                ],
              ),
            )
          else
            const Positioned(
              bottom: 96,
              child: _DelayedSpinner(delay: Duration(milliseconds: 1200)),
            ),
        ],
      ),
    ),
  );
}

class _DelayedSpinner extends StatefulWidget {
  const _DelayedSpinner({required this.delay});
  final Duration delay;
  @override
  State<_DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<_DelayedSpinner> {
  bool visible = false;
  late final Timer timer;

  @override
  void initState() {
    super.initState();
    timer = Timer(widget.delay, () => setState(() => visible = true));
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 300),
    child: const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.2),
    ),
  );
}

/// Arguments carried between the password-recovery steps.
class ResetFlow {
  const ResetFlow({required this.email, this.resetToken});
  final String email;
  final String? resetToken;
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.mode, this.arguments});
  final String mode;
  final Object? arguments;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController(),
      displayName = TextEditingController();

  /// The API sends a six-digit reset code.
  final codes = List.generate(6, (_) => TextEditingController());
  final codeNodes = List.generate(6, (_) => FocusNode());

  bool agreed = false, busy = false;

  ResetFlow? get flow =>
      widget.arguments is ResetFlow ? widget.arguments as ResetFlow : null;

  @override
  void initState() {
    super.initState();
    final incoming = flow;
    if (incoming != null) email.text = incoming.email;
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    repeat.dispose();
    displayName.dispose();
    for (final controller in codes) {
      controller.dispose();
    }
    for (final node in codeNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    switch (widget.mode) {
      case '/otp':
        await _verifyOtp();
      case '/signup':
        await _register();
      case '/forgot':
        await _requestReset();
      case '/reset':
        await _resetPassword();
      default:
        await _signIn();
    }
  }

  Future<void> _guard(Future<void> Function() task) async {
    setState(() => busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!form.currentState!.validate()) return;
    final store = StoreScope.of(context);
    await _guard(() async {
      final ok = await runAction(
        context,
        () => store.signIn(email.text.trim(), password.text),
        onError: _onSignInError,
      );
      if (ok && mounted) home(context);
    });
  }

  /// Google and Apple both end in the same place: a provider token the API
  /// exchanges for a session. A dismissed sheet returns null and is ignored.
  Future<void> _signInWithGoogle() async {
    final store = StoreScope.of(context);
    await _guard(() async {
      final String? token;
      try {
        token = await FederatedAuth.googleIdToken();
      } on FederatedAuthException catch (error) {
        if (mounted) toastError(context, error.message);
        return;
      }
      if (token == null || !mounted) return;
      final ok = await runAction(context, () => store.signInWithGoogle(token!));
      if (ok && mounted) home(context);
    });
  }

  Future<void> _signInWithApple() async {
    final store = StoreScope.of(context);
    await _guard(() async {
      final AppleIdentity? identity;
      try {
        identity = await FederatedAuth.apple();
      } on FederatedAuthException catch (error) {
        if (mounted) toastError(context, error.message);
        return;
      }
      if (identity == null || !mounted) return;
      final ok = await runAction(
        context,
        () => store.signInWithApple(
          identityToken: identity!.identityToken,
          fullName: identity.fullName,
        ),
      );
      if (ok && mounted) home(context);
    });
  }

  /// A deleted-but-recoverable account can be restored with the same password.
  void _onSignInError(ApiException error) {
    if (error.code != 'ACCOUNT_PENDING_DELETION') {
      toastError(context, error.message);
      return;
    }
    final store = StoreScope.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppPalette.of(dialogContext).surface,
        title: const Text('Account scheduled for deletion'),
        content: const Text(
          'This account is in its recovery window. Restore it now to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final restored = await runAction(
                context,
                () => store.restoreDeletedAccount(
                  email.text.trim(),
                  password.text,
                ),
                success: 'Welcome back — your account is active again.',
              );
              if (restored && mounted) home(context);
            },
            child: const Text('Restore account'),
          ),
        ],
      ),
    );
  }

  Future<void> _register() async {
    if (!form.currentState!.validate()) return;
    if (!agreed) {
      toast(context, 'Please agree to the Terms & Conditions.');
      return;
    }
    final store = StoreScope.of(context);
    await _guard(() async {
      final ok = await runAction(
        context,
        () => store.register(
          email: email.text.trim(),
          password: password.text,
          displayName: displayName.text.trim(),
        ),
      );
      if (!ok || !mounted) return;
      await _showAccountReady(store.user?.contactCode ?? '');
      if (mounted) go(context, '/setup');
    });
  }

  Future<void> _showAccountReady(String code) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppPalette.of(dialogContext).surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: violetGradient,
            ),
            child: const Icon(
              Icons.verified_user,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Your account is ready',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Surface(
            color: AppPalette.of(context).wash(const Color(0xffdef5fa)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your unique account code',
                  style: TextStyle(
                    color: AppPalette.of(context).muted,
                    fontSize: 11,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        code,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Copy account code'),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: code)),
                      icon: const Icon(Icons.copy, size: 16),
                    ),
                  ],
                ),
                Text(
                  'Share this code so contacts can find you in the app',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppPalette.of(context).muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            'Continue',
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    ),
  );

  Future<void> _requestReset() async {
    if (!form.currentState!.validate()) return;
    final store = StoreScope.of(context);
    final address = email.text.trim();
    await _guard(() async {
      final ok = await runAction(
        context,
        () => store.api.auth.forgotPassword(address),
        success: 'If that account exists, a six-digit code is on its way.',
      );
      if (ok && mounted) {
        go(context, '/otp', ResetFlow(email: address));
      }
    });
  }

  Future<void> _verifyOtp() async {
    final code = codes.map((controller) => controller.text).join();
    if (code.length != 6) {
      toast(context, 'Enter all six digits.');
      return;
    }
    final store = StoreScope.of(context);
    final address = flow?.email ?? email.text.trim();
    await _guard(() async {
      final token = await runTask(
        context,
        () => store.api.auth.verifyResetOtp(address, code),
      );
      if (token != null && mounted) {
        go(context, '/reset', ResetFlow(email: address, resetToken: token));
      }
    });
  }

  Future<void> _resetPassword() async {
    if (!form.currentState!.validate()) return;
    final token = flow?.resetToken;
    if (token == null) {
      toast(context, 'Start again from Forgot Password.');
      return;
    }
    final store = StoreScope.of(context);
    await _guard(() async {
      final ok = await runAction(
        context,
        () => store.api.auth.resetPassword(token, password.text),
        success: 'Password updated. Sign in with your new password.',
      );
      if (ok && mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final login = widget.mode == '/login',
        signup = widget.mode == '/signup',
        otp = widget.mode == '/otp',
        reset = widget.mode == '/reset';
    final title = login
        ? 'Welcome back'
        : signup
        ? 'Sign Up'
        : otp
        ? 'OTP'
        : reset
        ? 'Create New Password'
        : 'Forgot Password';
    return PageFrame(
      auth: true,
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: login || signup
                  ? 40
                  : MediaQuery.sizeOf(context).height * .22,
            ),
            const Center(child: Brand()),
            const SizedBox(height: 38),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 12),
            if (!reset)
              Text(
                login
                    ? 'Please enter your email & password to access\nyour account.'
                    : signup
                    ? 'Complete your information below.'
                    : otp
                    ? tr('Enter the 6-digit code sent to {email}', {
                        'email': flow?.email ?? tr('your email'),
                      })
                    : "Enter your email and we'll send you a code to\nreset your password",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 18),
            if (signup)
              AppField(
                'Full Name',
                hint: 'Enter your name',
                controller: displayName,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter your name' : null,
              ),
            if (!otp && !reset)
              AppField(
                'Email',
                hint: 'Enter your email',
                controller: email,
                keyboard: TextInputType.emailAddress,
                validator: (v) =>
                    v != null &&
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
                    ? null
                    : 'Enter a valid email',
              ),
            if (login)
              AppField(
                'Password',
                hint: '********',
                controller: password,
                password: true,
                validator: (v) =>
                    (v?.isNotEmpty ?? false) ? null : 'Enter your password',
              ),
            if (signup || reset)
              AppField(
                reset ? 'New Password' : 'Password',
                hint: '********',
                controller: password,
                password: true,
                validator: (v) => (v?.length ?? 0) >= 10
                    ? null
                    : 'Use at least 10 characters',
              ),
            if (signup || reset)
              AppField(
                'Confirm Password',
                hint: '********',
                controller: repeat,
                password: true,
                validator: (v) =>
                    v == password.text ? null : 'Passwords do not match',
              ),
            if (otp)
              Row(
                children: List.generate(
                  6,
                  (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i == 5 ? 0 : 8,
                        bottom: 24,
                      ),
                      child: TextField(
                        controller: codes[i],
                        focusNode: codeNodes[i],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: TextStyle(
                          fontSize: 21,
                          color: AppPalette.of(context).accent,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (v) {
                          if (v.isNotEmpty && i < 5) {
                            codeNodes[i + 1].requestFocus();
                          } else if (v.isEmpty && i > 0) {
                            codeNodes[i - 1].requestFocus();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            if (login)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => go(context, '/forgot'),
                  child: const Text(
                    'Forgot Password',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            if (otp)
              Center(
                child: TextButton(
                  onPressed: () async {
                    final store = StoreScope.of(context);
                    await runAction(
                      context,
                      () => store.api.auth.forgotPassword(
                        flow?.email ?? email.text.trim(),
                      ),
                      success: 'A new code is on its way.',
                    );
                  },
                  child: const Text('Resend code'),
                ),
              ),
            if (signup)
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: agreed,
                      onChanged: (v) => setState(() => agreed = v!),
                    ),
                  ),
                  const Text(' Agree with ', style: TextStyle(fontSize: 11)),
                  TextButton(
                    onPressed: () => go(context, '/terms'),
                    child: const Text(
                      'Terms & Conditions',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            PrimaryButton(
              login
                  ? 'Sign In'
                  : signup
                  ? 'Sign Up'
                  : otp
                  ? 'Verify'
                  : 'Next',
              onPressed: busy ? null : submit,
            ),
            if (login || signup) ...[
              const SizedBox(height: 24),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Or continue with',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 22),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppPalette.of(
                    context,
                  ).wash(const Color(0xfff4f5ff)),
                  foregroundColor: AppPalette.of(context).ink,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: busy ? null : _signInWithGoogle,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'G',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff4285f4),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('Google', style: TextStyle(fontSize: 17)),
                  ],
                ),
              ),
              // App Review guideline 4.8: an app offering a third-party login
              // has to offer Sign in with Apple beside it on Apple platforms.
              if (Platform.isIOS || Platform.isMacOS) ...[
                const SizedBox(height: 12),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: busy ? null : _signInWithApple,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.apple, size: 26, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Apple',
                        style: TextStyle(fontSize: 17, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
            ],
            if (!otp)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      login
                          ? "Don't have an account?"
                          : signup
                          ? 'Already have an account?'
                          : 'Remember Password?',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton(
                    onPressed: () => go(context, login ? '/signup' : '/login'),
                    child: Text(
                      login ? 'Sign Up' : 'Sign In',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
